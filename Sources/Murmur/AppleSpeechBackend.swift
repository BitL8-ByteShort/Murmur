import AVFoundation
import Speech
import MurmurCore

actor AppleSpeechBackend: SpeechBackend {
    private var analyzer: SpeechAnalyzer?
    private var audioFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var inputTask: Task<Void, Error>?
    private var resultTask: Task<Void, Never>?
    private var report: (@Sendable (SpeechEvent) -> Void)?
    private var sessionID = UUID()
    private var utterances = ProgressiveUtteranceTracker(sessionID: UUID())
    private var heardSpeech = false
    private var audioActive = false

    static func supportedLocales() async -> [String] {
        await SpeechTranscriber.supportedLocales.map(\.identifier).sorted()
    }

    static func assetsInstalled(locale identifier: String) async -> Bool {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier)) else { return false }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        return await AssetInventory.status(forModules: [transcriber]) == .installed
    }

    static func installAssets(locale identifier: String) async throws {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier)) else {
            throw SpeechFailure.unavailable("That language isn't supported by Apple Speech on this Mac.")
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        try Task.checkCancellation()
    }

    func prepare(sessionID: UUID, locale identifier: String, report: @escaping @Sendable (SpeechEvent) -> Void) async throws {
        await suspend()
        self.sessionID = sessionID; self.report = report
        utterances = .init(sessionID: sessionID); heardSpeech = false; audioActive = false
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier)) else {
            throw SpeechFailure.unavailable("Local Apple Speech isn't available for that language on this Mac.")
        }
        // Use the same preset for installation, availability and recognition.
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
            throw SpeechFailure.unavailable("Install this language's Apple Speech assets in Speech models before dictating.")
        }
        guard let natural = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
              let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: natural),
              let converter = AVAudioConverter(from: natural, to: format) else {
            throw SpeechFailure.unavailable("Could not prepare local speech audio.")
        }
        try Task.checkCancellation()
        self.audioFormat = format; self.converter = converter
        let analyzer = SpeechAnalyzer(modules: [transcriber], options: .init(priority: .userInitiated, modelRetention: .processLifetime))
        self.analyzer = analyzer
        report(.status("Preparing Apple Speech…"))
        try await analyzer.prepareToAnalyze(in: format)
        try Task.checkCancellation()
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(128))
        self.continuation = continuation
        resultTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard !Task.isCancelled else { return }
                    await self?.receive(text: String(result.text.characters), start: result.range.start.seconds, isFinal: result.isFinal)
                }
            } catch { if !Task.isCancelled { await self?.failed(error, source: "transcription") } }
        }
        inputTask = Task { [weak self] in
            do { try await analyzer.start(inputSequence: stream) }
            catch {
                if !Task.isCancelled { await self?.failed(error, source: "audio analysis") }
                throw error
            }
        }
    }

    private func receive(text: String, start: Double, isFinal: Bool) {
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            heardSpeech = true
            report?(.activity(audioActive))
        }
        if let utterance = utterances.update(text: text, start: start, isFinal: isFinal) {
            report?(.utterance(utterance))
        }
    }
    private func failed(_ error: Error, source: String) { report?(.failed("Apple \(source): \(error.localizedDescription)")) }

    func accept(_ packet: AudioPacket) async throws {
        guard packet.sessionID == sessionID, let converter, let target = audioFormat,
              let source = AVAudioFormat(standardFormatWithSampleRate: packet.sampleRate, channels: 1) else { return }
        try Task.checkCancellation()
        // Confirm speech with the transcriber, then time pauses using input energy.
        // Apple's optional VAD gate rejects quiet live chunks between utterances.
        let sum = packet.samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        audioActive = sqrt(sum / Double(max(1, packet.samples.count))) > 0.004
        if heardSpeech { report?(.activity(audioActive)) }
        guard let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(packet.samples.count)) else { return }
        input.frameLength = input.frameCapacity
        packet.samples.withUnsafeBufferPointer { samples in
            if let base = samples.baseAddress { input.floatChannelData![0].update(from: base, count: samples.count) }
        }
        let capacity = AVAudioFrameCount(ceil(Double(packet.samples.count) * target.sampleRate / source.sampleRate)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if supplied { state.pointee = .noDataNow; return nil }
            supplied = true; state.pointee = .haveData; return input
        }
        if status == .error { throw error ?? SpeechFailure.unavailable("Speech audio conversion failed.") as NSError }
        if output.frameLength > 0, case .dropped = continuation?.yield(AnalyzerInput(buffer: output)) {
            throw SpeechFailure.unavailable("Speech recognition couldn't keep up. Your completed text is retained. Stop other heavy work and try again.")
        }
    }
    func flush() async throws {
        do { try await analyzer?.finalize(through: nil) }
        catch { throw SpeechFailure.unavailable("Apple pause finalization: \(error.localizedDescription)") }
    }
    func finish() async throws {
        continuation?.finish(); continuation = nil
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        _ = try await inputTask?.value
        await resultTask?.value
    }
    func suspend() async {
        continuation?.finish(); continuation = nil
        resultTask?.cancel(); inputTask?.cancel()
        await analyzer?.cancelAndFinishNow()
        await resultTask?.value
        _ = try? await inputTask?.value
        analyzer = nil; converter = nil; audioFormat = nil
        resultTask = nil; inputTask = nil; report = nil
    }
    func unload() async { await suspend(); await SpeechModels.endRetention() }
}
