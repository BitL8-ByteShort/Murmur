import AVFoundation
import Testing
import MurmurCore
@testable import Murmur

private final class TapBox: @unchecked Sendable {
    let callback: AVAudioNodeTapBlock
    init(_ callback: @escaping AVAudioNodeTapBlock) { self.callback = callback }
}

@Test func dictationTapConvertsAndQueuesOnAudioWorker() async throws {
    let source = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    let output = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    let inbox = AudioInbox(), session = UUID()
    let (_, wake) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let bridge = try CaptureBridge(from: source, to: output, sessionID: session, inbox: inbox, wake: wake,
                                  meter: { _ in }, failure: { Issue.record("\($0)") })
    let callback = TapBox(CaptureService.tap(for: bridge))
    await Task.detached {
        let buffer = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 1536)!
        buffer.frameLength = 1536
        buffer.floatChannelData![0].initialize(repeating: 0.1, count: 1536)
        callback.callback(buffer, AVAudioTime(sampleTime: 0, atRate: 48_000))
    }.value
    let packet = inbox.dequeue()
    #expect(packet?.sessionID == session)
    #expect(packet?.sampleRate == 16_000)
    #expect(packet?.samples.isEmpty == false)
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
