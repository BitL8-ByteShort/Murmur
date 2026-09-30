import Testing
import Foundation
@testable import MurmurCore

@Test func quickTalkCompletesButContinuousReturnsToListening() {
    for mode in [CaptureMode.quickTalk, .keepTalking] {
        var session = SessionState()
        let id = session.begin(mode)
        session.prepared(sessionID: id)
        session.endpoint(sessionID: id)
        session.finalized(sessionID: id)
        session.inserted(sessionID: id)
        #expect(session.phase == (mode == .quickTalk ? .success : .listening))
    }
}

@Test func cancelledOrSupersededSessionsIgnoreLateCallbacks() {
    var session = SessionState()
    let old = session.begin(.quickTalk)
    session.cancel()
    session.prepared(sessionID: old)
    #expect(session.phase == .idle)
    let current = session.begin(.keepTalking)
    session.prepared(sessionID: old)
    #expect(session.phase == .preparing)
    session.prepared(sessionID: current)
    #expect(session.phase == .listening)
}

@Test func duplicateAndOutOfOrderCompletionsDoNotAdvance() {
    var session = SessionState()
    let id = session.begin(.quickTalk)
    session.inserted(sessionID: id)
    #expect(session.phase == .preparing)
    session.prepared(sessionID: id)
    session.endpoint(sessionID: id)
    session.finalized(sessionID: id)
    session.inserted(sessionID: id)
    session.finalized(sessionID: id)
    session.inserted(sessionID: id)
    #expect(session.phase == .success)
}

@Test func pinnedBarDoesNotMakeSessionActive() {
    let session = SessionState()
    #expect(OverlayPolicy.isVisible(pinned: true, manuallyOpened: false, phase: session.phase))
    #expect(!session.phase.isActive)
    #expect(!OverlayPolicy.isVisible(pinned: false, manuallyOpened: false, phase: .idle))
    #expect(OverlayPolicy.isVisible(pinned: false, manuallyOpened: true, phase: .idle))
    #expect(OverlayPolicy.isVisible(pinned: false, manuallyOpened: false, phase: .failed))
}

@Test func malformedAudioCannotBreakVisualizerBounds() {
    let frame = AudioMeter.measure([.nan, .infinity, -.infinity, 8, -8, 0], bins: 500)
    #expect(frame.level.isFinite && (0...1).contains(frame.level))
    #expect(frame.peaks.count == 128)
    #expect(frame.peaks.allSatisfy { $0.isFinite && (0...1).contains($0) })
    #expect(AudioMeter.measure([], bins: 0).peaks == [0])
}

@Test func silenceAndAudioProduceDifferentMeterFrames() {
    let silence = AudioMeter.measure(Array(repeating: 0, count: 1024))
    let audio = AudioMeter.measure(Array(repeating: 0.1, count: 1024))
    #expect(silence.level == 0)
    #expect(silence.peaks.allSatisfy { $0 == 0 })
    #expect(audio.level > silence.level)
    #expect(audio.peaks.count == 40)
}

@Test func preferencesRoundTripWithoutPersistingCapture() throws {
    var preferences = Preferences()
    preferences.style = .auraRing
    preferences.keepBarVisible = true
    let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
    #expect(restored == preferences)
    #expect(SessionState().phase == .idle)
}
