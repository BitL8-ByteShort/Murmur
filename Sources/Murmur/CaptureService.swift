import AVFoundation
import CoreAudio
import MurmurCore

@MainActor
final class CaptureService {
    private var engine: AVAudioEngine?
    private var observer: NSObjectProtocol?
    private var token = UUID()
    var onMeter: ((MeterFrame) -> Void)?
    var onFailure: ((String) -> Void)?
    var onPreparing: ((String) -> Void)?

    func start(sessionID: UUID, microphoneID: String, inbox: AudioInbox,
               wake: AsyncStream<Void>.Continuation) async throws {
        stop()
        let generation = token
        let permitted = await MicrophonePermission.request { [weak self] in
            self?.onPreparing?("Waiting for microphone permission…")
        }
        guard generation == token else { throw CancellationError() }
        guard permitted else { throw SpeechFailure.unavailable("Enable Murmur under System Settings → Privacy & Security → Microphone.") }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if !microphoneID.isEmpty {
            guard var device = InputDeviceStore.microphones().first(where: { $0.id == microphoneID })?.deviceID,
                  let unit = input.audioUnit else { throw SpeechFailure.unavailable("The selected microphone isn't connected.") }
            let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                             &device, UInt32(MemoryLayout<AudioDeviceID>.size))
            guard status == noErr else { throw SpeechFailure.unavailable("Couldn't select that microphone (\(status)).") }
        }
        let natural = input.outputFormat(forBus: 0)
        guard natural.sampleRate > 0, natural.channelCount > 0,
              let mono = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1) else {
            throw SpeechFailure.unavailable("No microphone input is available.")
        }
        let bridge = try CaptureBridge(from: natural, to: mono, sessionID: sessionID, inbox: inbox, wake: wake,
            meter: { [weak self] frame in Task { @MainActor in guard self?.token == generation else { return }; self?.onMeter?(frame) } },
            failure: { [weak self] message in Task { @MainActor in guard self?.token == generation else { return }; self?.onFailure?(message) } })
        input.installTap(onBus: 0, bufferSize: 512, format: natural, block: Self.tap(for: bridge))
        self.engine = engine
        engine.prepare()
        do { try engine.start() } catch { stop(); throw error }
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard self?.token == generation else { return }
                self?.onFailure?("Microphone configuration changed. Your text is retained; start again when the input is ready.")
            }
        }
    }
    // Explicitly outside MainActor; this is the boundary implicated in the original crash.
    nonisolated static func tap(for bridge: CaptureBridge) -> AVAudioNodeTapBlock {
        { buffer, _ in bridge.consume(buffer) }
    }
    func stop() {
        token = UUID()
        if let observer { NotificationCenter.default.removeObserver(observer) }; observer = nil
        if let engine { engine.inputNode.removeTap(onBus: 0); engine.stop() }
        engine = nil
        onMeter?(.silence)
    }
}

/// AVAudioEngine invokes consume serially. Its mutable converter/meter are never
/// touched by UI code; only immutable samples/levels cross the worker boundary.
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
    init(from: AVAudioFormat, to: AVAudioFormat, sessionID: UUID, inbox: AudioInbox,
         wake: AsyncStream<Void>.Continuation, meter: @escaping @Sendable (MeterFrame) -> Void,
         failure: @escaping @Sendable (String) -> Void) throws {
        guard let converter = AVAudioConverter(from: from, to: to) else { throw SpeechFailure.unavailable("Couldn't convert microphone input.") }
        self.converter = converter; outputFormat = to; self.sessionID = sessionID
        self.inbox = inbox; self.wake = wake; self.meter = meter; self.failure = failure
    }
    func consume(_ buffer: AVAudioPCMBuffer) {
        guard !failed else { return }
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
        guard output.frameLength > 0, let data = output.floatChannelData?[0] else { return }
        do {
            try inbox.enqueue(.init(sessionID: sessionID, samples: Array(UnsafeBufferPointer(start: data, count: Int(output.frameLength)))))
            wake.yield(())
        } catch { failed = true; failure("Dictation couldn't keep up. Your completed text is retained; try again after stopping other heavy tasks.") }
    }
}
