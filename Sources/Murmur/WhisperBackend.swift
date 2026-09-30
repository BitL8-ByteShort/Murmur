import Foundation
@preconcurrency import WhisperKit
import MurmurCore

actor WhisperBackend: SpeechBackend {
    private var kit: WhisperKit?
    private var window = DictationAudioWindow()
    private var reporter: LocalSpeechReporter?
    private var session = UUID()
    private var language = "en"
    private var pending: [Snapshot] = []
    private var decodingTask: Task<Void, Never>?
    private var decodingError: Error?

    private struct Snapshot {
        let samples: [Float]
        let segment: Int
        let skipBefore: Float
        let final: Bool
    }

    func prepare(sessionID: UUID, locale: String, report: @escaping @Sendable (SpeechEvent) -> Void) async throws {
        await suspend()
        session = sessionID
        language = String(locale.prefix(2))
        reporter = LocalSpeechReporter(session: sessionID, report: report)
        try LocalModelStore.require(.whisper)
        // Keep only the selected model resident between takes. Core ML can spend
        // tens of seconds loading it, even with already-downloaded assets.
        if kit != nil { return }
        let root = LocalModelStore.folder(.whisper)
        // Loading a downloaded model never lists or downloads remote model files.
        let pointer = root.appendingPathComponent("model-path.txt")
        let folder = (try? String(contentsOf: pointer, encoding: .utf8)).map { root.appendingPathComponent($0) }
        try Task.checkCancellation()
        guard let folder else { throw CocoaError(.fileNoSuchFile) }
        report(.status("Loading Whisper Turbo · first launch can take a minute…"))
        kit = try await WhisperKit(WhisperKitConfig(modelFolder: folder.path, tokenizerFolder: root,
            verbose: false, prewarm: false, load: true, download: false))
        try Task.checkCancellation()
    }

    func accept(_ packet: AudioPacket) async throws {
        guard packet.sessionID == session else { return }
        let samples = packet.samples
        reporter?.audio(samples)
        try Task.checkCancellation()
        if let decodingError { throw decodingError }
        window.append(samples)
        if window.shouldDecode || (window.isBoundary && window.hasPendingSpeech) {
            try enqueue(final: window.isBoundary)
        }
        if window.isBoundary { window.advance() }
    }

    private func enqueue(final: Bool) throws {
        let snapshot = Snapshot(samples: window.samples, segment: window.segment,
                                skipBefore: window.skipBefore, final: final)
        // Keep the newest revision while inference runs. Never discard a final
        // window or block incoming microphone audio behind a slow decode.
        if pending.last?.segment == snapshot.segment { pending[pending.count - 1] = snapshot }
        else {
            guard pending.count < 2 else {
                throw NSError(domain: "Murmur.Whisper", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    "Whisper cannot keep up on this Mac. Try Moonshine, Parakeet, or Apple Speech."])
            }
            pending.append(snapshot)
        }
        window.didDecode()
        guard decodingTask == nil else { return }
        decodingTask = Task {
            do {
                while !pending.isEmpty {
                    try Task.checkCancellation()
                    let next = pending.removeFirst()
                    try await decode(next)
                }
            } catch {
                if !Task.isCancelled {
                    decodingError = error
                    reporter?.error(error)
                }
                pending.removeAll()
            }
            decodingTask = nil
        }
    }

    private func decode(_ snapshot: Snapshot) async throws {
        guard let kit else { return }
        let options = DecodingOptions(language: language, temperatureFallbackCount: 0,
            skipSpecialTokens: true, wordTimestamps: true, concurrentWorkerCount: 1)
        let results = try await kit.transcribe(audioArray: snapshot.samples, decodeOptions: options)
        try Task.checkCancellation()
        let valid = results.flatMap(\.segments).filter { $0.noSpeechProb < 0.6 && $0.avgLogprob > -1 && $0.compressionRatio < 2.4 }
        let text: String
        if snapshot.skipBefore > 0 {
            text = valid.flatMap { $0.words ?? [] }.filter { $0.end > snapshot.skipBefore + 0.05 }.map(\.word).joined()
        } else { text = valid.map(\.text).joined() }
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reporter?.text(text, segment: snapshot.segment, final: snapshot.final)
        }
    }

    func flush() async throws {
        try await finish()
        window.advance()
    }
    func finish() async throws {
        if window.hasPendingSpeech { try enqueue(final: true) }
        await decodingTask?.value
        if let decodingError { throw decodingError }
    }
    func suspend() async {
        decodingTask?.cancel()
        await decodingTask?.value
        decodingTask = nil
        pending.removeAll()
        decodingError = nil
        window = DictationAudioWindow()
        reporter = nil
    }
    func unload() async {
        await suspend()
        await kit?.unloadModels()
        kit = nil
    }
}
