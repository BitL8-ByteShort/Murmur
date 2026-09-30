import AVFoundation
import Testing
import MurmurCore
@testable import Murmur

private final class TapBox: @unchecked Sendable {
    let callback: AVAudioNodeTapBlock
    init(_ callback: @escaping AVAudioNodeTapBlock) { self.callback = callback }
}

@Test @MainActor func microphoneTapCanBeInvokedOnAudioWorker() async {
    let monitor = MicrophoneMonitor()
    var published: MeterFrame?
    monitor.onFrame = { published = $0 }
    let callback = TapBox(monitor.makeTap(sessionToken: monitor.generation))
    // AVAudioEngine invokes this on its worker. Never request/open a microphone here.
    await Task.detached {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2048)!
        buffer.frameLength = 2048
        buffer.floatChannelData![0].initialize(repeating: 0.1, count: 2048)
        callback.callback(buffer, AVAudioTime(sampleTime: 0, atRate: 16_000))
    }.value
    for _ in 0..<50 where published == nil { try? await Task.sleep(for: .milliseconds(10)) }
    #expect(published?.level ?? 0 > 0)
    #expect(published?.peaks.count == 40)
}
