import AVFoundation
import FluidAudio
import MurmurCore

actor ParakeetBackend: SpeechBackend {
    private var manager: StreamingEouAsrManager?
    private var reporter: LocalSpeechReporter?
    private var session = UUID()
    private var segment = 0
    func prepare(sessionID: UUID, locale: String, report: @escaping @Sendable (SpeechEvent) -> Void) async throws {
        await suspend()
        try LocalModelStore.require(.parakeet)
        guard locale.hasPrefix("en") else { throw SpeechFailure.unavailable("Parakeet Realtime currently supports English. Choose Apple Speech for other languages.") }
        if manager == nil {
            report(.status("Loading Parakeet Realtime…"))
            let loaded = StreamingEouAsrManager(chunkSize: .ms320)
            try await loaded.loadModels(from: LocalModelStore.folder(.parakeet).appendingPathComponent(Repo.parakeetEou320.folderName))
            manager = loaded
        }
        try Task.checkCancellation()
        session = sessionID; segment = 0
        reporter = LocalSpeechReporter(session: sessionID, report: report)
        await connectCallback()
    }
    private func connectCallback() async {
        let reporter = reporter, segment = segment
        await manager?.setPartialTranscriptCallback { reporter?.text($0, segment: segment, final: false) }
    }
    func accept(_ packet: AudioPacket) async throws {
        guard packet.sessionID == session, let manager,
              let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(packet.samples.count)) else { return }
        try Task.checkCancellation()
        reporter?.audio(packet.samples)
        buffer.frameLength = buffer.frameCapacity
        packet.samples.withUnsafeBufferPointer { if let base = $0.baseAddress { buffer.floatChannelData![0].update(from: base, count: $0.count) } }
        _ = try await manager.process(audioBuffer: buffer)
    }
    func flush() async throws {
        try await finish()
        await manager?.setPartialTranscriptCallback { _ in }
        await manager?.reset(); segment += 1
        await connectCallback()
    }
    func finish() async throws {
        if let manager { reporter?.text(try await manager.finish(), segment: segment, final: true) }
    }
    func suspend() async {
        await manager?.setPartialTranscriptCallback { _ in }; await manager?.reset(); reporter = nil
    }
    func unload() async { await suspend(); await manager?.cleanup(); manager = nil }
}
