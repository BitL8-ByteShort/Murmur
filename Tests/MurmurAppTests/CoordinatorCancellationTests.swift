import Foundation
import Testing
import MurmurCore
@testable import Murmur

private actor DelayedPreparation: SpeechBackend {
    private var report: (@Sendable (SpeechEvent) -> Void)?
    private var originalReport: (@Sendable (SpeechEvent) -> Void)?
    private var session = UUID()
    private var cleanup: CheckedContinuation<Void, Never>?
    private var released = false
    private(set) var waitingForCleanup = false
    private(set) var preparations = 0
    func prepare(sessionID: UUID, locale: String, report: @escaping @Sendable (SpeechEvent) -> Void) async throws {
        preparations += 1; session = sessionID; self.report = report; originalReport = report
        try await Task.sleep(for: .seconds(60))
    }
    func emitPartial() { report?(.utterance(.init(sessionID: session, id: UUID(), revision: 1, text: "Keep these words", isFinal: false))) }
    func emitLate() { originalReport?(.utterance(.init(sessionID: session, id: UUID(), revision: 2, text: "Late words", isFinal: true))) }
    func accept(_ packet: AudioPacket) throws { Issue.record("Capture should never start during preparation") }
    func flush() {}
    func finish() {}
    func suspend() async {
        guard !released else { report = nil; return }
        waitingForCleanup = true
        await withCheckedContinuation { cleanup = $0 }
        report = nil
    }
    func releaseCleanup() { released = true; cleanup?.resume(); cleanup = nil }
    func unload() {}
}

@Test @MainActor func cancelDuringPreviousCleanupCannotRestartCaptureOrLoseRecoveredWords() async {
    let backend = DelayedPreparation()
    let coordinator = DictationCoordinator(backendFactory: { _ in backend })
    var preferences = Preferences(); preferences.copyOnly = true
    let snapshot = preferences
    let first = Task { await coordinator.start(mode: .quickTalk, preferences: snapshot) }
    for _ in 0..<100 {
        if await backend.preparations == 1 { break }
        try? await Task.sleep(for: .milliseconds(5))
    }
    #expect(await backend.preparations == 1)
    await backend.emitPartial()
    for _ in 0..<100 where coordinator.partial.isEmpty { try? await Task.sleep(for: .milliseconds(5)) }
    #expect(coordinator.partial == "Keep these words")
    first.cancel(); coordinator.cancel()
    #expect(coordinator.transcript == "Keep these words")
    for _ in 0..<100 {
        if await backend.waitingForCleanup { break }
        try? await Task.sleep(for: .milliseconds(5))
    }
    #expect(await backend.waitingForCleanup)
    let second = Task { await coordinator.start(mode: .keepTalking, preferences: snapshot) }
    for _ in 0..<100 where coordinator.phase != .preparing { try? await Task.sleep(for: .milliseconds(5)) }
    #expect(coordinator.phase == .preparing)
    #expect(coordinator.recovery.entries.first?.text == "Keep these words")
    second.cancel(); coordinator.cancel()
    await backend.releaseCleanup()
    await first.value; await second.value
    await backend.emitLate()
    try? await Task.sleep(for: .milliseconds(20))
    #expect(coordinator.phase == .idle)
    #expect(coordinator.recoveryText.isEmpty)
    #expect(coordinator.recovery.entries.first?.text == "Keep these words")
    #expect(await backend.preparations == 1)
}
