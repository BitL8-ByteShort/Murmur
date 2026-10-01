import AppKit
import Observation
import MurmurCore

@MainActor @Observable
final class DictationCoordinator {
    private(set) var phase: SessionPhase = .idle
    private(set) var mode: CaptureMode = .quickTalk
    private(set) var status = "Mic off"
    private(set) var meter = MeterFrame.silence
    private(set) var transcript = ""
    private(set) var partial = ""
    private(set) var notice: String?
    private(set) var recovery = RecoveryBuffer()
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let capture = CaptureService()
    @ObservationIgnored private var backend: (any SpeechBackend)?
    @ObservationIgnored private var assembler = TranscriptAssembler(sessionID: UUID())
    @ObservationIgnored private var sessionID = UUID()
    @ObservationIgnored private var endpoint = EndpointPolicy(mode: .quickTalk, silenceSeconds: 1.2, inactivitySeconds: 300)
    @ObservationIgnored private var speechDetected = false
    @ObservationIgnored private var startedAt = 0.0
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var events: Task<Void, Never>?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var cleanup: Task<Void, Never>?
    @ObservationIgnored private var wake: AsyncStream<Void>.Continuation?
    @ObservationIgnored private var eventSink: AsyncStream<SpeechEvent>.Continuation?
    @ObservationIgnored private var flushing = false
    @ObservationIgnored private let insertion = TextInsertionService()
    @ObservationIgnored private var outputTask: Task<Void, Never>?
    @ObservationIgnored private var insertsIntoApp = false
    @ObservationIgnored private var delivery = InsertionDeliverySummary()
    @ObservationIgnored private var loadedEngine: SpeechEngine?
    @ObservationIgnored private var lastActivityText = ""
    @ObservationIgnored private var transcriptID = UUID()
    @ObservationIgnored private var transcriptDate = Date()
    @ObservationIgnored private let backendFactory: @MainActor (SpeechEngine) -> any SpeechBackend

    init(backendFactory: @escaping @MainActor (SpeechEngine) -> any SpeechBackend = DictationCoordinator.makeBackend) {
        self.backendFactory = backendFactory
        capture.onMeter = { [weak self] in self?.meter = $0 }
        capture.onFailure = { [weak self] in self?.fail($0) }
        capture.onPreparing = { [weak self] message in
            self?.status = message; self?.onChange?()
        }
    }
    private static func makeBackend(_ engine: SpeechEngine) -> any SpeechBackend {
        switch engine {
        case .apple: AppleSpeechBackend()
        case .parakeet: ParakeetBackend()
        case .moonshine: MoonshineBackend()
        case .whisper: WhisperBackend()
        }
    }
    var isActive: Bool { phase.isActive }
    var recoveryText: String { [transcript, partial].filter { !$0.isEmpty }.joined(separator: " ") }

    struct PreparedOutput {
        let destination: TextInsertionService.Target?
        let notice: String?
    }
    func prepareOutput(copyOnly: Bool, remoteShortcut: RemotePasteShortcut = .controlV) -> PreparedOutput {
        guard !copyOnly else { return .init(destination: nil, notice: nil) }
        do { return .init(destination: try insertion.captureDestination(remoteShortcut: remoteShortcut), notice: nil) }
        catch { return .init(destination: nil, notice: error.localizedDescription) }
    }

    func start(mode: CaptureMode, preferences: Preferences, output: PreparedOutput? = nil) async {
        guard !isActive else { return }
        let id = UUID(); sessionID = id
        recovery.save(sessionID: transcriptID, text: recoveryText, createdAt: transcriptDate)
        transcriptID = id; transcriptDate = Date()
        self.mode = mode; phase = .preparing; status = "Preparing \(preferences.engine.title)…"
        transcript = ""; partial = ""; notice = nil; meter = .silence
        let output = output ?? prepareOutput(copyOnly: preferences.copyOnly, remoteShortcut: preferences.remotePasteShortcut)
        insertion.begin(destination: output.destination)
        insertsIntoApp = output.destination != nil
        delivery = .init()
        notice = output.notice
        assembler.reset(sessionID: id)
        endpoint = .init(mode: mode, silenceSeconds: preferences.silenceSeconds, inactivitySeconds: preferences.inactivitySeconds)
        speechDetected = false; flushing = false; lastActivityText = ""
        onChange?()
        let (eventStream, sink) = AsyncStream<SpeechEvent>.makeStream(bufferingPolicy: .bufferingOldest(512))
        eventSink = sink
        events = Task { [weak self] in
            for await event in eventStream {
                guard let self, !Task.isCancelled, self.sessionID == id else { return }
                self.handle(event)
            }
        }
        do {
            await cleanup?.value
            try check(id)
            if loadedEngine != preferences.engine {
                await self.backend?.unload()
                let base = backendFactory(preferences.engine)
                self.backend = SerializedSpeechBackend(base)
                loadedEngine = preferences.engine
            }
            guard let backend = self.backend else { throw SpeechFailure.unavailable("Select a speech engine first.") }
            try await backend.prepare(sessionID: id, locale: preferences.locale) { event in sink.yield(event) }
            try check(id)
            let inbox = AudioInbox()
            let (wakeStream, wake) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
            self.wake = wake
            worker = Task { [weak self] in
                do {
                    for await _ in wakeStream {
                        while let packet = inbox.dequeue() {
                            try Task.checkCancellation()
                            try await backend.accept(packet)
                        }
                    }
                    while let packet = inbox.dequeue() { try await backend.accept(packet) }
                } catch { if !Task.isCancelled, self?.sessionID == id { self?.fail(error.localizedDescription) } }
            }
            try await capture.start(sessionID: id, microphoneID: preferences.microphoneID, inbox: inbox, wake: wake)
            try check(id)
            phase = .listening
            status = mode == .quickTalk ? "Quick Talk · listening" : "Keep Talking · listening"
            startedAt = ProcessInfo.processInfo.systemUptime
            timer = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                    guard let self, self.sessionID == id, self.phase == .listening else { return }
                    let decision = self.endpoint.update(speechDetected: self.speechDetected,
                        elapsedSeconds: ProcessInfo.processInfo.systemUptime - self.startedAt)
                    switch decision {
                    case .continueListening: break
                    case .noSpeechTimeout: self.cancel(); self.notice = "No speech detected. Try again when you're ready."; self.onChange?(); return
                    case .inactivityTimeout: Task { await self.finish() }; return
                    case .finalizeUtterance:
                        if mode == .quickTalk { Task { await self.finish() }; return }
                        if !self.flushing {
                            self.flushing = true
                            do { try await backend.flush() }
                            catch { self.fail(error.localizedDescription); return }
                            self.flushing = false
                        }
                    }
                }
            }
            onChange?()
        } catch {
            if sessionID == id {
                if error is CancellationError { cancel() }
                else { fail(error.localizedDescription) }
            }
        }
    }

    private func check(_ id: UUID) throws {
        try Task.checkCancellation()
        guard sessionID == id else { throw CancellationError() }
    }
    private func handle(_ event: SpeechEvent) {
        switch event {
        case .status(let message): status = message
        case .activity(let speech): speechDetected = speech
        case .failed(let message): fail(message)
        case .utterance(let utterance):
            if phase == .listening, !utterance.text.isEmpty, utterance.text != lastActivityText {
                lastActivityText = utterance.text
                _ = endpoint.update(speechDetected: true,
                    elapsedSeconds: ProcessInfo.processInfo.systemUptime - startedAt)
            }
            if let text = assembler.update(utterance) {
                transcript += transcript.isEmpty ? text : " " + text
                if insertsIntoApp {
                    let previous = outputTask, id = sessionID
                    outputTask = Task { [weak self] in
                        await previous?.value
                        guard let self, self.sessionID == id, !Task.isCancelled else { return }
                        do {
                            let result = try await self.insertion.insert(text, utteranceID: utterance.id)
                            guard self.sessionID == id else { return }
                            self.delivery.record(result)
                            if result == .sent {
                                self.notice = "Paste sent. Check the destination; Murmur couldn't confirm the insertion. Your words remain available for copying."
                            }
                        }
                        catch { if self.sessionID == id { self.insertsIntoApp = false; self.fail(error.localizedDescription) } }
                    }
                }
            }
            partial = assembler.partialText
        }
    }
    func finish() async {
        guard phase == .listening else { return }
        let id = sessionID
        phase = .finalizing; status = "Finishing…"
        capture.stop(); timer?.cancel(); timer = nil
        wake?.finish(); wake = nil
        onChange?()
        do {
            await worker?.value
            try check(id)
            try await backend?.finish()
            eventSink?.finish(); await events?.value
            await outputTask?.value
            try check(id)
            partial = assembler.partialText
            phase = .success
            status = delivery.status(hasWords: !recoveryText.isEmpty, hasPartial: !partial.isEmpty)
            if !partial.isEmpty { notice = "Some speech wasn't finalized. It's retained below for copying." }
            await backend?.suspend()
            onChange?()
            if partial.isEmpty {
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(650))
                    guard let self, self.sessionID == id, self.phase == .success else { return }
                    self.phase = .idle; self.status = "Mic off"; self.onChange?()
                }
            }
        } catch { if sessionID == id, !(error is CancellationError) { fail(error.localizedDescription) } }
    }
    func cancel() {
        let retained = recoveryText
        sessionID = UUID()
        capture.stop(); timer?.cancel(); worker?.cancel(); events?.cancel(); outputTask?.cancel()
        wake?.finish(); eventSink?.finish()
        timer = nil; wake = nil; eventSink = nil
        transcript = retained; partial = ""; phase = .idle; status = "Mic off"
        let backend = backend, previousCleanup = cleanup
        cleanup = Task { await previousCleanup?.value; await backend?.suspend() }
        onChange?()
    }
    private func fail(_ message: String) {
        let retained = recoveryText
        cancel()
        transcript = retained
        notice = message; phase = .failed; status = "Dictation stopped"
        onChange?()
    }
    func interrupt(_ message: String) { if isActive { fail(message) } }
    func dismiss() { cancel(); notice = nil; transcript = ""; onChange?() }
    func unloadModel() async {
        cancel()
        await cleanup?.value
        await backend?.unload(); backend = nil; loadedEngine = nil
    }
    func copyTranscript() {
        guard !recoveryText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(recoveryText, forType: .string)
    }
    func copyRecovery(_ entry: RecoveryEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
    }
    func clearPreviousTranscripts() { recovery.clear() }
}
