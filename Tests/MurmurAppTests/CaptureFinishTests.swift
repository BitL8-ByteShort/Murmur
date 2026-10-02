import AppKit
import Testing
import MurmurCore
@testable import Murmur

/// Models the last audio callback arriving after key-up, while it is still
/// buffered by the capture device. No microphone or external app is touched.
@MainActor private final class BufferedEndingCapture: DictationCapture {
    var onMeter: ((MeterFrame) -> Void)?
    var onFailure: ((String) -> Void)?
    var onPreparing: ((String) -> Void)?
    var capturing = false
    var finishing = false
    private var session = UUID()
    private var inbox: AudioInbox?
    private var wake: AsyncStream<Void>.Continuation?
    private var drain: CheckedContinuation<Void, Never>?
    func start(sessionID: UUID, microphoneID: String, inbox: AudioInbox, wake: AsyncStream<Void>.Continuation) async throws {
        session = sessionID; self.inbox = inbox; self.wake = wake; capturing = true
        try inbox.enqueue(.init(sessionID: session, samples: [1]))
        wake.yield(())
    }
    func finish(tail: Duration) async throws {
        finishing = true
        await withCheckedContinuation { drain = $0 }
        try Task.checkCancellation()
        guard capturing else { throw CancellationError() }
        try inbox?.enqueue(.init(sessionID: session, samples: [2]))
        wake?.yield(())
        stop()
    }
    func releaseLastCallback() { drain?.resume(); drain = nil }
    func stop() { capturing = false }
}

private actor EndingBackend: SpeechBackend {
    private var report: (@Sendable (SpeechEvent) -> Void)?
    private var session = UUID()
    private var ending = false
    func prepare(sessionID: UUID, locale: String, report: @escaping @Sendable (SpeechEvent) -> Void) {
        session = sessionID; self.report = report
    }
    func accept(_ packet: AudioPacket) { if packet.samples == [2] { ending = true } }
    func flush() {}
    func finish() {
        report?(.utterance(.init(sessionID: session, id: UUID(), revision: 1,
            text: ending ? "Smooth operator." : "Smooth oper", isFinal: true)))
    }
    func suspend() { report = nil }
    func unload() {}
}

@Test @MainActor func releaseDrainsLastAudioCallbackBeforeFinalizingAndPasting() async {
    let capture = BufferedEndingCapture(), backend = EndingBackend()
    var words: [String] = []
    let coordinator = DictationCoordinator(backendFactory: { _ in backend }, capture: capture,
        writeText: { text, _ in #expect(!capture.capturing); words.append(text); return .verified })
    let target = TextInsertionService.Target(pid: 0, element: AXUIElementCreateApplication(0), terminal: false,
        remoteShortcut: nil, remoteWindowTitle: nil, appName: "Test editor")
    await coordinator.start(mode: .quickTalk, preferences: Preferences(),
        output: .init(destination: target, notice: nil), heldQuickTalk: true)
    let finishing = Task { await coordinator.finish() }
    for _ in 0..<100 where !capture.finishing && coordinator.phase == .listening { await Task.yield() }
    #expect(capture.finishing)
    #expect(coordinator.phase == .finalizing)
    #expect(words.isEmpty)
    capture.releaseLastCallback()
    await finishing.value
    #expect(words == ["Smooth operator."])
    #expect(!capture.capturing)
}

@Test @MainActor func cancellationWhileDrainingNeverPastesOrRestartsCapture() async {
    let capture = BufferedEndingCapture(), backend = EndingBackend()
    var words: [String] = []
    let coordinator = DictationCoordinator(backendFactory: { _ in backend }, capture: capture,
        writeText: { text, _ in words.append(text); return .verified })
    let target = TextInsertionService.Target(pid: 0, element: AXUIElementCreateApplication(0), terminal: false,
        remoteShortcut: nil, remoteWindowTitle: nil, appName: "Test editor")
    await coordinator.start(mode: .quickTalk, preferences: Preferences(),
        output: .init(destination: target, notice: nil), heldQuickTalk: true)
    let finishing = Task { await coordinator.finish() }
    for _ in 0..<100 where !capture.finishing && coordinator.phase == .listening { await Task.yield() }
    #expect(capture.finishing)
    coordinator.cancel()
    capture.releaseLastCallback()
    await finishing.value
    #expect(coordinator.phase == .idle)
    #expect(!capture.capturing)
    #expect(words.isEmpty)
}
