import AppKit
import Testing
import MurmurCore
@testable import Murmur

@MainActor private final class SilentCapture: DictationCapture {
    var onMeter: ((MeterFrame) -> Void)?
    var onFailure: ((String) -> Void)?
    var onPreparing: ((String) -> Void)?
    var capturing = false
    func start(sessionID: UUID, microphoneID: String, inbox: AudioInbox, wake: AsyncStream<Void>.Continuation) async throws {
        capturing = true
    }
    func stop() { capturing = false }
}

private actor ReleaseBackend: SpeechBackend {
    var report: (@Sendable (SpeechEvent) -> Void)?
    var session = UUID()
    var second = UUID()
    func prepare(sessionID: UUID, locale: String, report: @escaping @Sendable (SpeechEvent) -> Void) {
        session = sessionID; self.report = report
    }
    func speak() {
        report?(.utterance(.init(sessionID: session, id: UUID(), revision: 1, text: "First thought.", isFinal: true)))
        report?(.utterance(.init(sessionID: session, id: second, revision: 1, text: "Last word", isFinal: false)))
    }
    func accept(_ packet: AudioPacket) {}
    func flush() { Issue.record("A held shortcut must not wait for pause finalization") }
    func finish() {
        report?(.utterance(.init(sessionID: session, id: second, revision: 2, text: "Last words.", isFinal: true)))
    }
    func suspend() { report = nil }
    func unload() {}
}

@Test @MainActor func heldQuickTalkWritesAllFinalWordsOnceAtReleaseAndStopsCaptureFirst() async {
    let backend = ReleaseBackend(), capture = SilentCapture()
    var writes: [String] = []
    let coordinator = DictationCoordinator(backendFactory: { _ in backend }, capture: capture,
        writeText: { text, _ in
            #expect(!capture.capturing)
            writes.append(text)
            return .verified
        })
    let target = TextInsertionService.Target(pid: 0, element: AXUIElementCreateApplication(0), terminal: false,
        remoteShortcut: nil, remoteWindowTitle: nil, appName: "Test editor")
    await coordinator.start(mode: .quickTalk, preferences: Preferences(),
        output: .init(destination: target, notice: nil), heldQuickTalk: true)
    #expect(capture.capturing)
    await backend.speak()
    for _ in 0..<100 where coordinator.partial.isEmpty { await Task.yield() }
    #expect(coordinator.transcript == "First thought.")
    #expect(coordinator.partial == "Last word")
    #expect(writes.isEmpty)
    #expect(coordinator.phase == .listening)
    await coordinator.finish()
    #expect(!capture.capturing)
    #expect(writes == ["First thought. Last words."])
    #expect(coordinator.phase == .success)
    #expect(coordinator.status == "Inserted")
    #expect(coordinator.partial.isEmpty)
}

@Test @MainActor func keepTalkingStillWritesFinalWordsWhileListening() async {
    let backend = ReleaseBackend(), capture = SilentCapture()
    var writes: [String] = []
    let coordinator = DictationCoordinator(backendFactory: { _ in backend }, capture: capture,
        writeText: { text, _ in writes.append(text); return .verified })
    let target = TextInsertionService.Target(pid: 0, element: AXUIElementCreateApplication(0), terminal: false,
        remoteShortcut: nil, remoteWindowTitle: nil, appName: "Test editor")
    await coordinator.start(mode: .keepTalking, preferences: Preferences(), output: .init(destination: target, notice: nil))
    await backend.speak()
    for _ in 0..<100 where writes.isEmpty { await Task.yield() }
    #expect(writes == ["First thought."])
    #expect(capture.capturing)
    await coordinator.finish()
    #expect(writes == ["First thought.", "Last words."])
    #expect(!capture.capturing)
}
