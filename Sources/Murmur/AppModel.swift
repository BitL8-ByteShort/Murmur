import AppKit
import Observation
import MurmurCore

@MainActor @Observable
final class AppModel {
    var preferences: Preferences {
        didSet {
            if oldValue.microphoneID != preferences.microphoneID {
                // Also invalidate a queued start before the coordinator becomes active.
                dictationTask?.cancel(); holdingQuickTalk = false
                interrupt("Microphone changed. Start again to use the selected input.")
            }
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
    var dictation = DictationCoordinator()
    var locales = ["en_US"]
    var microphones: [Microphone] = []
    var installingApple = false
    var recordingShortcut: ShortcutAction? { didSet { shortcutRecordingChanged?(recordingShortcut != nil) } }
    var shortcutError: String?
    var installedModels = Set<SpeechEngine>()
    var downloadingModel: SpeechEngine?
    var downloadStatus = ""
    var accessibilityGranted = TextInsertionService.permissionGranted
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var downloadID = UUID()
    @ObservationIgnored var rebindShortcuts: (([ShortcutAction: ShortcutBinding]) throws -> Void)?
    @ObservationIgnored var updateCaptureHotkey: ((Bool) -> Void)?
    @ObservationIgnored var shortcutRecordingChanged: ((Bool) -> Void)?
    @ObservationIgnored var onOverlayChange: (() -> Void)?
    @ObservationIgnored private let microphone = MicrophoneMonitor()
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var dictationTask: Task<Void, Never>?
    @ObservationIgnored private var holdingQuickTalk = false

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
        dictation.onChange = { [weak self] in
            guard let self else { return }
            self.updateCaptureHotkey?(self.dictation.isActive); self.onOverlayChange?()
        }
        microphones = InputDeviceStore.microphones()
        refreshModels()
        Task { locales = await AppleSpeechBackend.supportedLocales() }
    }
    var barVisible: Bool {
        OverlayPolicy.isVisible(pinned: preferences.keepBarVisible, manuallyOpened: manuallyOpened,
                                phase: dictation.phase) || monitoring || preparing
    }
    var isExpanded: Bool { monitoring || preparing || dictation.isActive }
    var visualizerFrame: MeterFrame { dictation.isActive ? dictation.meter : meter }
    var status: String { preparing ? "Preparing microphone…" : monitoring ? "Live microphone preview" : dictation.status }

    func toggleDictation(_ mode: CaptureMode) {
        if dictation.isActive {
            holdingQuickTalk = false
            if dictation.phase == .preparing { cancelDictation() }
            else { Task { await dictation.finish() } }
            return
        }
        startDictation(mode, held: false)
    }
    func beginHeldQuickTalk() {
        guard !holdingQuickTalk, !dictation.isActive else { return }
        holdingQuickTalk = true
        startDictation(.quickTalk, held: true)
    }
    func releaseHeldQuickTalk() {
        guard holdingQuickTalk else { return }
        holdingQuickTalk = false
        if dictation.phase == .listening, dictation.mode == .quickTalk {
            Task { await dictation.finish() }
        } else if dictation.phase == .preparing || !dictation.isActive {
            // Releasing before preparation finishes must never open the mic later.
            cancelDictation()
        }
    }
    private func startDictation(_ mode: CaptureMode, held: Bool) {
        stopMonitor(); manuallyOpened = false
        let preferences = preferences
        let output = dictation.prepareOutput(copyOnly: preferences.copyOnly, remoteShortcut: preferences.remotePasteShortcut)
        dictationTask = Task {
            guard !Task.isCancelled else { return }
            await dictation.start(mode: mode, preferences: preferences, output: output, heldQuickTalk: held)
        }
    }
    func cancelDictation() { holdingQuickTalk = false; dictationTask?.cancel(); dictation.cancel() }
    func refreshModels() { installedModels = Set(SpeechEngine.allCases.filter { $0 != .apple && LocalModelStore.installed($0) }) }
    func refreshPermissions() { accessibilityGranted = TextInsertionService.permissionGranted; refreshModels() }
    func download(_ engine: SpeechEngine) {
        guard downloadingModel == nil else { return }
        downloadingModel = engine; downloadStatus = "Starting…"; notice = nil
        let id = UUID(); downloadID = id
        downloadTask = Task {
            do {
                try await LocalModelStore.download(engine) { [weak model = self] status in
                    Task { @MainActor in if model?.downloadID == id { model?.downloadStatus = status } }
                }
            } catch { if !(error is CancellationError) { notice = error.localizedDescription } }
            guard downloadID == id else { return }
            refreshModels(); downloadingModel = nil; downloadStatus = ""; downloadTask = nil
        }
    }
    func cancelDownload() {
        downloadStatus = "Cancelling…"; downloadTask?.cancel()
    }
    func selectModel(_ engine: SpeechEngine) {
        guard !dictation.isActive, engine == .apple || installedModels.contains(engine) else { return }
        Task { await dictation.unloadModel(); preferences.engine = engine }
    }
    func deleteModel(_ engine: SpeechEngine) {
        guard !dictation.isActive, downloadingModel == nil else { return }
        Task {
            if preferences.engine == engine { await dictation.unloadModel(); preferences.engine = .apple }
            do { try LocalModelStore.delete(engine); refreshModels() }
            catch { notice = error.localizedDescription }
        }
    }
    func installAppleAssets() {
        guard !installingApple else { return }
        installingApple = true; notice = nil
        Task {
            do { try await AppleSpeechBackend.installAssets(locale: preferences.locale) }
            catch { notice = error.localizedDescription }
            installingApple = false
        }
    }
    func assignShortcut(_ action: ShortcutAction, binding: ShortcutBinding) {
        var bindings = preferences.shortcuts; bindings[action] = binding
        do {
            try ShortcutValidation.validate(bindings)
            try rebindShortcuts?(bindings)
            preferences.shortcuts = bindings; recordingShortcut = nil; shortcutError = nil
        } catch { shortcutError = error.localizedDescription }
    }
    func resetShortcuts() {
        recordingShortcut = nil
        do { try rebindShortcuts?(ShortcutBinding.defaults); preferences.shortcuts = ShortcutBinding.defaults; shortcutError = nil }
        catch { shortcutError = error.localizedDescription }
    }
    func interrupt(_ message: String) {
        let active = dictation.isActive || monitoring || preparing
        stopMonitor()
        if dictation.isActive { dictation.interrupt(message) }
        if active { notice = message }
    }

    func startMonitor() {
        guard !preparing, !monitoring else { return }
        cancelDictation()
        notice = nil
        preparing = true
        let token = UUID(); requestID = token
        onOverlayChange?()
        Task {
            do {
                let started = try await microphone.start(microphoneID: preferences.microphoneID)
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
        cancelDictation()
        stopMonitor()
        manuallyOpened = false
        preferences.keepBarVisible = false
        onOverlayChange?()
    }
}
