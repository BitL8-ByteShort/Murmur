import Foundation
import Testing
@testable import MurmurCore

@Test func transcriptPartialsReplaceAndFinalsCommitOnce() {
    let session = UUID(), utterance = UUID()
    var assembler = TranscriptAssembler(sessionID: session)
    #expect(assembler.update(.init(sessionID: session, id: utterance, revision: 1, text: "hello", isFinal: false)) == nil)
    #expect(assembler.update(.init(sessionID: session, id: utterance, revision: 2, text: "hello Chris", isFinal: false)) == nil)
    #expect(assembler.partialText == "hello Chris")
    #expect(assembler.update(.init(sessionID: session, id: utterance, revision: 1, text: "old", isFinal: false)) == nil)
    #expect(assembler.partialText == "hello Chris")
    let final = Utterance(sessionID: session, id: utterance, revision: 3, text: "Hello Chris.", isFinal: true)
    #expect(assembler.update(final) == "Hello Chris.")
    #expect(assembler.update(final) == nil)
    #expect(assembler.partialText.isEmpty)
    assembler.reset(sessionID: UUID())
    #expect(assembler.update(final) == nil)
}

@Test func emptyFinalDoesNotLoseRecoverablePartial() {
    let session = UUID(), id = UUID()
    var assembler = TranscriptAssembler(sessionID: session)
    _ = assembler.update(.init(sessionID: session, id: id, revision: 1, text: "keep this", isFinal: false))
    #expect(assembler.update(.init(sessionID: session, id: id, revision: 2, text: " ", isFinal: true)) == nil)
    #expect(assembler.partialText == "keep this")
}

@Test func audioQueueRefusesOverflowWithoutLosingPendingAudio() throws {
    let id = UUID()
    var queue = AudioQueue()
    try queue.enqueue(.init(sessionID: id, samples: Array(repeating: 0.1, count: 480_000), sampleRate: 16_000))
    #expect(throws: AudioQueueError.overflow) {
        try queue.enqueue(.init(sessionID: id, samples: [0.2], sampleRate: 16_000))
    }
    #expect(queue.pendingSamples == 480_000)
    #expect(queue.dequeue()?.samples.count == 480_000)
    #expect(queue.pendingSamples == 0)
    #expect(queue.dequeue() == nil)
}

@Test func quickTalkWaitsForSpeechThenEndsAfterPause() {
    var policy = EndpointPolicy(mode: .quickTalk, silenceSeconds: 1.2, inactivitySeconds: 300)
    #expect(policy.update(speechDetected: false, elapsedSeconds: 10) == .continueListening)
    #expect(policy.update(speechDetected: true, elapsedSeconds: 11) == .continueListening)
    #expect(policy.update(speechDetected: false, elapsedSeconds: 12) == .continueListening)
    #expect(policy.update(speechDetected: false, elapsedSeconds: 12.3) == .finalizeUtterance)
    #expect(policy.update(speechDetected: false, elapsedSeconds: 13) == .continueListening)
}

@Test func silenceTimeoutAndContinuousSpeechAreDifferent() {
    var quick = EndpointPolicy(mode: .quickTalk, silenceSeconds: 1.2, inactivitySeconds: 300)
    #expect(quick.update(speechDetected: false, elapsedSeconds: 15) == .noSpeechTimeout)
    var continuous = EndpointPolicy(mode: .keepTalking, silenceSeconds: 1.2, inactivitySeconds: 300)
    #expect(continuous.update(speechDetected: false, elapsedSeconds: 15) == .continueListening)
    _ = continuous.update(speechDetected: true, elapsedSeconds: 20)
    #expect(continuous.update(speechDetected: false, elapsedSeconds: 21.3) == .finalizeUtterance)
    _ = continuous.update(speechDetected: true, elapsedSeconds: 25)
    #expect(continuous.update(speechDetected: false, elapsedSeconds: 26.3) == .finalizeUtterance)
    #expect(continuous.update(speechDetected: false, elapsedSeconds: 325) == .inactivityTimeout)
}

@Test func heldQuickTalkKeepsListeningThroughPausesUntilRelease() {
    var held = EndpointPolicy(mode: .quickTalk, silenceSeconds: 0.7, inactivitySeconds: 60, finishQuickTalkOnPause: false)
    _ = held.update(speechDetected: true, elapsedSeconds: 1)
    #expect(held.update(speechDetected: false, elapsedSeconds: 2) == .continueListening)
    #expect(held.update(speechDetected: false, elapsedSeconds: 10) == .continueListening)
    _ = held.update(speechDetected: true, elapsedSeconds: 11)
    #expect(held.update(speechDetected: false, elapsedSeconds: 12) == .continueListening)
    var empty = EndpointPolicy(mode: .quickTalk, silenceSeconds: 0.7, inactivitySeconds: 60, finishQuickTalkOnPause: false)
    #expect(empty.update(speechDetected: false, elapsedSeconds: 15) == .noSpeechTimeout)
}

@Test func legacyPreferencesRetainAppearanceAndDefaultToMicOff() throws {
    let data = Data(#"{"version":1,"style":"auraRing","keepBarVisible":true,"reduceMotion":false}"#.utf8)
    let preferences = try JSONDecoder().decode(Preferences.self, from: data)
    #expect(preferences.style == .auraRing)
    #expect(preferences.engine == .apple)
    #expect(preferences.locale == "en_US")
    #expect(preferences.historyDays == 0)
    #expect(preferences.silenceSeconds == 1.2)
}
