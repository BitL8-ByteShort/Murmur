import Testing
@testable import MurmurCore

@Test func rollingAudioKeepsOnlyItsBoundedContextAndSkipsAlreadyRecognizedOverlap() {
    var window = DictationAudioWindow()
    for _ in 0..<120 { window.append(Array(repeating: 0.1, count: 1600)) }
    #expect(window.isBoundary)
    #expect(window.samples.count == 192_000)
    window.advance()
    #expect(window.samples.count == 32_000)
    #expect(window.skipBefore == 2)
    window.append(Array(repeating: 0, count: 10_400))
    #expect(window.isBoundary)
    window.advance()
    #expect(window.samples.isEmpty)
    #expect(!window.hasPendingSpeech)
    #expect(window.skipBefore == 0)
}
