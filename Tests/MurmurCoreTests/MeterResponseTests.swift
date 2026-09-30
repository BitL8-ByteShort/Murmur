import Testing
@testable import MurmurCore

@Test func ordinarySpeechGetsVisibleMovementWithoutAnimatingSilence() {
    let normalSpeech = AudioMeter.measure(Array(repeating: 0.02, count: 512))
    let nearSilence = AudioMeter.measure(Array(repeating: 0.0001, count: 512))
    #expect(normalSpeech.peaks.allSatisfy { $0 > 0.4 })
    #expect(normalSpeech.level > 0.5)
    #expect(nearSilence.peaks.allSatisfy { $0 == 0 })
    #expect(nearSilence.level == 0)
}
