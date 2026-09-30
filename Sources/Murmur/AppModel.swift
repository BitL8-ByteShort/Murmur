import AppKit
import Observation
import MurmurCore

@MainActor @Observable
final class AppModel {
    var preferences: Preferences {
        didSet {
            if let data = try? JSONEncoder().encode(preferences) {
                UserDefaults.standard.set(data, forKey: "murmur.preferences.v1")
            }
            onOverlayChange?()
        }
    }
    var meter = MeterFrame.silence
    var monitoring = false
    var preparing = false
    var manuallyOpened = false
    var notice: String?
    @ObservationIgnored var onOverlayChange: (() -> Void)?
    @ObservationIgnored private let microphone = MicrophoneMonitor()
    @ObservationIgnored private var requestID = UUID()

    init() {
        if let data = UserDefaults.standard.data(forKey: "murmur.preferences.v1"),
           let saved = try? JSONDecoder().decode(Preferences.self, from: data), saved.version == 1 {
            preferences = saved
        } else { preferences = Preferences() }
        microphone.onFrame = { [weak self] frame in self?.meter = frame }
        microphone.onInterrupted = { [weak self] in
            guard let self, self.monitoring else { return }
            self.stopMonitor()
            self.notice = "Microphone configuration changed. Start the preview again when your input is ready."
        }
    }
    var barVisible: Bool { preferences.keepBarVisible || manuallyOpened || monitoring || preparing }
    var status: String { preparing ? "Preparing microphone…" : monitoring ? "Live microphone preview" : "Mic off" }

    func startMonitor() {
        guard !preparing, !monitoring else { return }
        notice = nil
        preparing = true
        manuallyOpened = true
        let token = UUID(); requestID = token
        onOverlayChange?()
        Task {
            do {
                let started = try await microphone.start()
                guard requestID == token else { return }
                preparing = false; monitoring = started
            } catch {
                guard requestID == token else { return }
                preparing = false; monitoring = false; notice = error.localizedDescription
            }
            onOverlayChange?()
        }
    }
    func stopMonitor() {
        requestID = UUID()
        microphone.stop()
        monitoring = false; preparing = false; meter = .silence
        onOverlayChange?()
    }
    func showBar() { manuallyOpened = true; onOverlayChange?() }
    func closeBar() {
        stopMonitor()
        manuallyOpened = false
        preferences.keepBarVisible = false
        onOverlayChange?()
    }
}
