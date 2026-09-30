import Foundation
import Testing
import MurmurCore

@Test func changingProvisionalTimestampsDoNotLeaveRepeatedWordsAfterFinalization() throws {
    let session = UUID()
    var tracker = ProgressiveUtteranceTracker(sessionID: session)
    var transcript = TranscriptAssembler(sessionID: session)
    let firstResult = tracker.update(text: "Hello Chris", start: 0, isFinal: false)
    let first = try #require(firstResult)
    transcript.update(first)
    let shiftedResult = tracker.update(text: "Hello, Chris.", start: 0.12, isFinal: false)
    let shifted = try #require(shiftedResult)
    transcript.update(shifted)
    #expect(transcript.partialText == "Hello, Chris.")
    #expect(first.id == shifted.id)
    let finalResult = tracker.update(text: "Hello, Chris.", start: 0.14, isFinal: true)
    let final = try #require(finalResult)
    let committed = transcript.update(final)
    #expect(committed == "Hello, Chris.")
    #expect(transcript.partialText.isEmpty)
    let duplicate = tracker.update(text: "Hello, Chris.", start: 0.14, isFinal: true)
    #expect(duplicate == nil)

    let nextResult = tracker.update(text: "Another thought", start: 2, isFinal: false)
    let next = try #require(nextResult)
    transcript.update(next)
    #expect(next.id != final.id)
    let revokedResult = tracker.update(text: "", start: 2.1, isFinal: false)
    let revoked = try #require(revokedResult)
    transcript.update(revoked)
    #expect(transcript.partialText.isEmpty)
    let repeatedResult = tracker.update(text: "Hello, Chris.", start: 2.2, isFinal: true)
    let repeated = try #require(repeatedResult)
    let repeatedText = transcript.update(repeated)
    #expect(repeatedText == "Hello, Chris.")
}
