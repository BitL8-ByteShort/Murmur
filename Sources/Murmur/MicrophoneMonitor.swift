import AVFoundation
import CoreAudio
import MurmurCore

@MainActor
final class MicrophoneMonitor {
    private var input: (any MicrophoneInput)?
    private let resolveDevice: (String) throws -> AudioDeviceID
    private let makeInput: (AudioDeviceID) throws -> any MicrophoneInput
    private let requestAccess: @MainActor () async -> Bool
    private(set) var generation = UUID()
    private var lastPublication = 0.0
    var onFrame: ((MeterFrame) -> Void)?
    var onInterrupted: (() -> Void)?

    init(resolveDevice: @escaping (String) throws -> AudioDeviceID = InputDeviceStore.resolve,
         makeInput: @escaping (AudioDeviceID) throws -> any MicrophoneInput = { try InputOnlyCapture(device: $0) },
         requestAccess: @escaping @MainActor () async -> Bool = { await MicrophonePermission.request() }) {
        self.resolveDevice = resolveDevice; self.makeInput = makeInput
        self.requestAccess = requestAccess
    }

    func start(microphoneID: String = "") async throws -> Bool {
        stop()
        lastPublication = 0
        let token = generation
        let allowed = await requestAccess()
        guard token == generation else { return false }
        guard allowed else { throw MonitorError.denied }
        let input = try makeInput(resolveDevice(microphoneID))
        self.input = input
        do {
            try input.start(receive: makeTap(sessionToken: token), failure: { [weak self] _ in
                Task { @MainActor in
                    guard self?.generation == token else { return }
                    self?.onInterrupted?()
                }
            })
        } catch { stop(); throw error }
        return true
    }

    // Construct the callback outside actor isolation: HAL invokes it on its audio
    // worker. Only publishing the immutable frame hops back to MainActor.
    nonisolated func makeTap(sessionToken token: UUID) -> AVAudioNodeTapBlock {
        { [weak self] buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            // Work here is bounded to one tap buffer. No audio is retained or written.
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            let frame = AudioMeter.measure(samples)
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                let now = ProcessInfo.processInfo.systemUptime
                guard now - self.lastPublication >= 1.0 / 60 else { return }
                self.lastPublication = now
                self.onFrame?(frame)
            }
        }
    }

    func stop() {
        generation = UUID()
        input?.stop(); input = nil
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
