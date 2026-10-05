import AVFoundation
import CoreAudio
import MurmurCore

@MainActor
protocol DictationCapture: AnyObject {
    var onMeter: ((MeterFrame) -> Void)? { get set }
    var onFailure: ((String) -> Void)? { get set }
    var onPreparing: ((String) -> Void)? { get set }
    func start(sessionID: UUID, microphoneID: String, inbox: AudioInbox, wake: AsyncStream<Void>.Continuation) async throws
    func stop()
    func finish(tail: Duration) async throws
}

extension DictationCapture {
    func finish(tail: Duration) async throws { stop() }
}

@MainActor
final class CaptureService: DictationCapture {
    private var input: (any MicrophoneInput)?
    private let resolveDevice: (String) throws -> AudioDeviceID
    private let makeInput: (AudioDeviceID) throws -> any MicrophoneInput
    private let requestAccess: @MainActor ((() -> Void)?) async -> Bool
    private var token = UUID()
    private var bridge: CaptureBridge?
    var onMeter: ((MeterFrame) -> Void)?
    var onFailure: ((String) -> Void)?
    var onPreparing: ((String) -> Void)?

    init(resolveDevice: @escaping (String) throws -> AudioDeviceID = InputDeviceStore.resolve,
         makeInput: @escaping (AudioDeviceID) throws -> any MicrophoneInput = { try InputOnlyCapture(device: $0) },
         requestAccess: @escaping @MainActor ((() -> Void)?) async -> Bool = MicrophonePermission.request) {
        self.resolveDevice = resolveDevice; self.makeInput = makeInput
        self.requestAccess = requestAccess
    }

    func start(sessionID: UUID, microphoneID: String, inbox: AudioInbox,
               wake: AsyncStream<Void>.Continuation) async throws {
        stop()
        let generation = token
        let permitted = await requestAccess { [weak self] in
            self?.onPreparing?("Waiting for microphone permission…")
        }
        guard generation == token else { throw CancellationError() }
        guard permitted else { throw SpeechFailure.unavailable("Enable Murmur under System Settings → Privacy & Security → Microphone.") }
        let input = try makeInput(resolveDevice(microphoneID))
        let natural = input.format
        guard natural.sampleRate > 0, natural.channelCount > 0,
              let mono = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1) else {
            throw SpeechFailure.unavailable("No microphone input is available.")
        }
        let bridge = try CaptureBridge(from: natural, to: mono, sessionID: sessionID, inbox: inbox, wake: wake,
            meter: { [weak self] frame in Task { @MainActor in guard self?.token == generation else { return }; self?.onMeter?(frame) } },
            failure: { [weak self] message in Task { @MainActor in guard self?.token == generation else { return }; self?.onFailure?(message) } })
        self.bridge = bridge
        self.input = input
        do {
            try input.start(receive: Self.tap(for: bridge), failure: { [weak self] message in
                Task { @MainActor in guard self?.token == generation else { return }; self?.onFailure?(message) }
            })
        } catch { stop(); throw error }
    }
    // Explicitly outside MainActor; this is the boundary implicated in the original crash.
    nonisolated static func tap(for bridge: CaptureBridge) -> AVAudioNodeTapBlock {
        { buffer, _ in bridge.consume(buffer) }
    }
    func stop() {
        token = UUID()
        bridge?.cancel(); bridge = nil
        stopGraph()
        onMeter?(.silence)
    }
    func finish(tail: Duration) async throws {
        let generation = token
        // A key release can precede delivery of the microphone's last tap buffer.
        // Keep only this short tail, then end and drain conversion before the
        // coordinator closes the audio worker's stream.
        if tail > .zero { try await Task.sleep(for: tail) }
        try Task.checkCancellation()
        guard token == generation else { throw CancellationError() }
        let bridge = bridge
        stopGraph()
        if let bridge {
            try await Task.detached(priority: .userInitiated) { try bridge.finish() }.value
        }
        try Task.checkCancellation()
        guard token == generation else { throw CancellationError() }
        token = UUID(); self.bridge = nil
        onMeter?(.silence)
    }
    private func stopGraph() {
        input?.stop()
        input = nil
    }
}

/// Conversion stays on workers. The lock also joins a final in-flight tap with
/// the end-of-stream drain; late callbacks cannot enqueue after finish/cancel.
final class CaptureBridge: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let sessionID: UUID
    private let inbox: AudioInbox
    private let wake: AsyncStream<Void>.Continuation
    private let meter: @Sendable (MeterFrame) -> Void
    private let failure: @Sendable (String) -> Void
    private var meterTime = 0.0
    private var failed = false
    private let lock = NSLock()
    private var ended = false
    init(from: AVAudioFormat, to: AVAudioFormat, sessionID: UUID, inbox: AudioInbox,
         wake: AsyncStream<Void>.Continuation, meter: @escaping @Sendable (MeterFrame) -> Void,
         failure: @escaping @Sendable (String) -> Void) throws {
        guard let converter = AVAudioConverter(from: from, to: to) else { throw SpeechFailure.unavailable("Couldn't convert microphone input.") }
        self.converter = converter; outputFormat = to; self.sessionID = sessionID
        self.inbox = inbox; self.wake = wake; self.meter = meter; self.failure = failure
    }
    func consume(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard !failed, !ended else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if now - meterTime >= 1.0 / 60, let data = buffer.floatChannelData?[0] {
            meter(AudioMeter.measure(Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))))
            meterTime = now
        }
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * outputFormat.sampleRate / buffer.format.sampleRate)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        let result = converter.convert(to: output, error: &error) { _, state in
            if supplied { state.pointee = .noDataNow; return nil }
            supplied = true; state.pointee = .haveData; return buffer
        }
        if result == .error { failed = true; failure("Microphone conversion failed."); return }
        do {
            try enqueue(output)
        } catch { failed = true; failure("Dictation couldn't keep up. Your completed text is retained; try again after stopping other heavy tasks.") }
    }
    func cancel() { lock.withLock { ended = true } }
    func finish() throws {
        lock.lock(); defer { lock.unlock() }
        guard !ended else { return }
        ended = true
        guard !failed else { return }
        // noDataNow leaves the resampler's trailing samples buffered. EOF emits
        // those samples, without substituting silence or inventing speech.
        for _ in 0..<4 {
            guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 4096) else {
                throw SpeechFailure.unavailable("Couldn't finish microphone conversion. Your text is retained.")
            }
            var error: NSError?
            let result = converter.convert(to: output, error: &error) { _, state in state.pointee = .endOfStream; return nil }
            if result == .error { throw error ?? SpeechFailure.unavailable("Microphone conversion couldn't finish.") as NSError }
            try enqueue(output)
            if result == .endOfStream { return }
        }
        throw SpeechFailure.unavailable("Microphone conversion didn't finish. Your text is retained.")
    }
    private func enqueue(_ output: AVAudioPCMBuffer) throws {
        guard output.frameLength > 0, let data = output.floatChannelData?[0] else { return }
        try inbox.enqueue(.init(sessionID: sessionID, samples: Array(UnsafeBufferPointer(start: data, count: Int(output.frameLength)))))
        wake.yield(())
    }
}
