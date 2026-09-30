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
    private var detectionTask: Task<Void, Never>?
    private var report: (@Sendable (SpeechEvent) -> Void)?
    private var sessionID = UUID()
    private var identities: [Int64: UUID] = [:]
    private var revisions: [Int64: Int] = [:]
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
        identities.removeAll(); revisions.removeAll(); heardSpeech = false; audioActive = false
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier)) else {
            throw SpeechFailure.unavailable("Local Apple Speech isn't available for that language on this Mac.")
        }
        // Use the same preset for installation, availability and recognition.
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
            throw SpeechFailure.unavailable("Install this language's Apple Speech assets in Speech models before dictating.")
        }
        let detector = SpeechDetector(detectionOptions: .init(sensitivityLevel: .medium), reportResults: true)
        guard let natural = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
              let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber, detector], considering: natural),
              let converter = AVAudioConverter(from: natural, to: format) else {
            throw SpeechFailure.unavailable("Could not prepare local speech audio.")
        }
        try Task.checkCancellation()
        self.audioFormat = format; self.converter = converter
        let analyzer = SpeechAnalyzer(modules: [transcriber, detector], options: .init(priority: .userInitiated, modelRetention: .processLifetime))
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
            } catch { if !Task.isCancelled { await self?.failed(error) } }
        }
        detectionTask = Task { [weak self] in
            do {
                for try await result in detector.results {
                    guard !Task.isCancelled else { return }
                    await self?.detected(result.speechDetected)
                }
            } catch { if !Task.isCancelled { await self?.failed(error) } }
        }
        inputTask = Task { [weak self] in
            do { try await analyzer.start(inputSequence: stream) }
            catch {
                if !Task.isCancelled { await self?.failed(error) }
                throw error
            }
        }
    }

    private func receive(text: String, start: Double, isFinal: Bool) {
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            heardSpeech = true
            report?(.activity(audioActive))
        }
        let key = Int64((start * 1000).rounded())
        let identity = identities[key] ?? UUID(); identities[key] = identity
        let revision = (revisions[key] ?? 0) + 1; revisions[key] = revision
        report?(.utterance(.init(sessionID: sessionID, id: identity, revision: revision, text: text, isFinal: isFinal)))
    }
    private func detected(_ speech: Bool) { report?(.activity(speech)) }
    private func failed(_ error: Error) { report?(.failed(error.localizedDescription)) }

    func accept(_ packet: AudioPacket) async throws {
        guard packet.sessionID == sessionID, let converter, let target = audioFormat,
              let source = AVAudioFormat(standardFormatWithSampleRate: packet.sampleRate, channels: 1) else { return }
        try Task.checkCancellation()
        // SpeechDetector currently emits errors only. Confirm speech with the transcriber,
        // then use the input's energy for responsive pause timing (not its result stream).
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
    func flush() async throws { try await analyzer?.finalize(through: nil) }
    func finish() async throws {
        continuation?.finish(); continuation = nil
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        _ = try await inputTask?.value
        await resultTask?.value
        await detectionTask?.value
    }
    func suspend() async {
        continuation?.finish(); continuation = nil
        resultTask?.cancel(); detectionTask?.cancel(); inputTask?.cancel()
        await analyzer?.cancelAndFinishNow()
        await resultTask?.value; await detectionTask?.value
        _ = try? await inputTask?.value
        analyzer = nil; converter = nil; audioFormat = nil
        resultTask = nil; inputTask = nil; detectionTask = nil; report = nil
    }
    func unload() async { await suspend(); await SpeechModels.endRetention() }
}
