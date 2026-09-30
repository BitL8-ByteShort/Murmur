import Foundation
@preconcurrency import MoonshineVoice
import MurmurCore

actor MoonshineBackend: SpeechBackend {
    private var transcriber: Transcriber?
    private var stream: MoonshineVoice.Stream?
    private var reporter: LocalSpeechReporter?
    private var session = UUID()
    private var epoch = 0
    func prepare(sessionID: UUID, locale: String, report: @escaping @Sendable (SpeechEvent) -> Void) async throws {
        suspend()
        try LocalModelStore.require(.moonshine)
        guard locale.hasPrefix("en") else { throw SpeechFailure.unavailable("Moonshine Small currently supports English. Choose Apple Speech for other languages.") }
        if transcriber == nil {
            report(.status("Loading Moonshine Small…"))
            transcriber = try Transcriber(modelPath: LocalModelStore.folder(.moonshine).path, modelArch: .smallStreaming)
        }
        try Task.checkCancellation()
        session = sessionID; epoch = 0; reporter = LocalSpeechReporter(session: sessionID, report: report)
        try newStream()
    }
    private func newStream() throws {
        guard let transcriber else { return }
        let stream = try transcriber.createStream(updateInterval: 0.15)
        let reporter = reporter, epoch = epoch
        stream.addListener { event in
            if let error = event as? TranscriptError { reporter?.error(error.error); return }
            reporter?.text(event.line.text, segment: Int(truncatingIfNeeded: event.line.lineId) + epoch * 1_000_000, final: event.line.isComplete)
        }
        self.stream = stream
        try stream.start()
    }
    func accept(_ packet: AudioPacket) throws {
        guard packet.sessionID == session else { return }
        try Task.checkCancellation(); reporter?.audio(packet.samples)
        try stream?.addAudio(packet.samples, sampleRate: 16_000)
    }
    func flush() throws { try stream?.stop(); stream?.removeAllListeners(); stream = nil; epoch += 1; try newStream() }
    func finish() throws { try stream?.stop() }
    func suspend() { stream?.removeAllListeners(); stream = nil; reporter = nil }
    func unload() { suspend(); transcriber = nil }
}
