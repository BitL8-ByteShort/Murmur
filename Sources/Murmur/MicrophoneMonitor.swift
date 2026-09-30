import AVFoundation
import MurmurCore

@MainActor
final class MicrophoneMonitor {
    private let engine = AVAudioEngine()
    private var tapInstalled = false
    private var generation = UUID()
    private var lastPublication = 0.0
    var onFrame: ((MeterFrame) -> Void)?
    var onInterrupted: (() -> Void)?
    private var configurationObserver: NSObjectProtocol?

    init() {
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.onInterrupted?() }
        }
    }

    func start() async throws -> Bool {
        stop()
        lastPublication = 0
        let token = generation
        let allowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard token == generation else { return false }
        guard allowed else { throw MonitorError.denied }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw MonitorError.noInput }
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            // Work here is bounded to one tap buffer. No audio is retained or written.
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            let frame = AudioMeter.measure(samples)
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                let now = ProcessInfo.processInfo.systemUptime
                guard now - self.lastPublication >= 1.0 / 30 else { return }
                self.lastPublication = now
                self.onFrame?(frame)
            }
        }
        tapInstalled = true
        engine.prepare()
        do { try engine.start() }
        catch { stop(); throw error }
        return true
    }

    func stop() {
        generation = UUID()
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        onFrame?(.silence)
    }
}

private enum MonitorError: LocalizedError {
    case denied, noInput
    var errorDescription: String? {
        switch self {
        case .denied: "Microphone access is off. Enable Murmur in System Settings → Privacy & Security → Microphone."
        case .noInput: "No microphone is available. Connect an input device and try again."
        }
    }
}
