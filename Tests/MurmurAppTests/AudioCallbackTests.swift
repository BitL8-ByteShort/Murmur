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

@Test func captureConverterDrainsFinalSamplesAndRejectsLateCallbacks() async throws {
    let source = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    let output = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    let inbox = AudioInbox(), session = UUID()
    let (_, wake) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let bridge = try CaptureBridge(from: source, to: output, sessionID: session, inbox: inbox, wake: wake,
                                  meter: { _ in }, failure: { Issue.record("\($0)") })
    try await Task.detached {
        let buffer = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 4800)!
        buffer.frameLength = 4800
        buffer.floatChannelData![0].initialize(repeating: 0.1, count: 4800)
        bridge.consume(buffer)
        try bridge.finish()
    }.value
    var samples = 0
    while let packet = inbox.dequeue() { samples += packet.samples.count }
    #expect(samples == 1600)
    try await Task.detached {
        let buffer = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 4800)!
        buffer.frameLength = 4800
        buffer.floatChannelData![0].initialize(repeating: 0.1, count: 4800)
        bridge.consume(buffer)
        try bridge.finish()
    }.value
    let lateCallbackCount = inbox.dequeue()?.samples.count ?? 0
    #expect(lateCallbackCount == 0)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["MURMUR_ENDING_FIXTURE"] != nil))
func parakeetRecognizesCompleteEndingAfterCaptureDrain() async throws {
    let path = ProcessInfo.processInfo.environment["MURMUR_ENDING_FIXTURE"]!
    let backend = SerializedSpeechBackend(ParakeetBackend()), events = EventCollector(), session = UUID()
    try await backend.prepare(sessionID: session, locale: "en_US") { events.append($0) }
    let inbox = AudioInbox()
    let (_, wake) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    try await Task.detached {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        #expect(file.processingFormat.sampleRate == 48_000)
        #expect(file.processingFormat.channelCount == 1)
        let all = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: all)
        let samples = Array(UnsafeBufferPointer(start: all.floatChannelData![0], count: Int(all.frameLength)))
        let lastSound = try #require(samples.lastIndex { abs($0) > 0.003 })
        // Match release at the end of speech plus the short capture tail, rather
        // than the long trailing silence normally present in a generated file.
        let end = min(samples.count, lastSound + 1 + 5760)
        let output = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let bridge = try CaptureBridge(from: file.processingFormat, to: output, sessionID: session,
            inbox: inbox, wake: wake, meter: { _ in }, failure: { Issue.record("\($0)") })
        for offset in stride(from: 0, to: end, by: 4800) {
            let count = min(4800, end - offset)
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(count))!
            buffer.frameLength = AVAudioFrameCount(count)
            samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress! + offset, count: count) }
            bridge.consume(buffer)
            while let packet = inbox.dequeue() { try await backend.accept(packet) }
        }
        try bridge.finish()
        while let packet = inbox.dequeue() { try await backend.accept(packet) }
    }.value
    try await backend.finish()
    var assembler = TranscriptAssembler(sessionID: session), words: [String] = []
    for event in events.snapshot {
        if case .utterance(let utterance) = event, let text = assembler.update(utterance) { words.append(text) }
        if case .failed(let error) = event { Issue.record("\(error)") }
    }
    #expect(words.joined(separator: " ").lowercased().contains("smooth operator"))
    #expect(assembler.partialText.isEmpty)
    await backend.unload()
}
