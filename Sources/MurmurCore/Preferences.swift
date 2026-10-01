import Foundation

public enum VisualizerStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case waveform, aura, auraRing, particleWave
    public var id: String { rawValue }
    public var title: String {
        switch self { case .waveform: "Waveform"; case .aura: "Aura"; case .auraRing: "Aura Ring"; case .particleWave: "Particle Wave" }
    }
    public var icon: String {
        switch self { case .waveform: "waveform"; case .aura: "sparkles"; case .auraRing: "circle.dotted.circle"; case .particleWave: "aqi.medium" }
    }
    public var detail: String {
        switch self { case .waveform: "Small and focused"; case .aura: "Crisp color and movement"; case .auraRing: "Layers that respond"; case .particleWave: "A flowing field of particles" }
    }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var version = 1
    public var style: VisualizerStyle = .waveform
    public var keepBarVisible = false
    public var reduceMotion = false
    public var engine: SpeechEngine = .apple
    public var locale = "en_US"
    public var microphoneID = ""
    public var silenceSeconds = 1.2
    public var inactivitySeconds = 300.0
    public var copyOnly = false
    public var remotePasteShortcut: RemotePasteShortcut = .controlV
    public var historyDays = 0
    public var displayID = ""
    public var bottomOffset = 18.0
    public var visualizerIntensity = 1.0
    public var stillVisualizer = false
    public var sounds = false
    public var shortcuts = ShortcutBinding.defaults
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case version, style, keepBarVisible, reduceMotion, engine, locale, microphoneID,
             silenceSeconds, inactivitySeconds, copyOnly, historyDays, displayID, bottomOffset,
             visualizerIntensity, stillVisualizer, sounds, shortcuts, remotePasteShortcut
    }
    public init(from decoder: any Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        style = (try? values.decode(VisualizerStyle.self, forKey: .style)) ?? .waveform
        keepBarVisible = (try? values.decode(Bool.self, forKey: .keepBarVisible)) ?? false
        reduceMotion = (try? values.decode(Bool.self, forKey: .reduceMotion)) ?? false
        engine = (try? values.decode(SpeechEngine.self, forKey: .engine)) ?? .apple
        locale = (try? values.decode(String.self, forKey: .locale)) ?? "en_US"
        microphoneID = (try? values.decode(String.self, forKey: .microphoneID)) ?? ""
        silenceSeconds = min(3, max(0.7, (try? values.decode(Double.self, forKey: .silenceSeconds)) ?? 1.2))
        inactivitySeconds = (try? values.decode(Double.self, forKey: .inactivitySeconds)) ?? 300
        copyOnly = (try? values.decode(Bool.self, forKey: .copyOnly)) ?? false
        remotePasteShortcut = (try? values.decode(RemotePasteShortcut.self, forKey: .remotePasteShortcut)) ?? .controlV
        historyDays = (try? values.decode(Int.self, forKey: .historyDays)) ?? 0
        displayID = (try? values.decode(String.self, forKey: .displayID)) ?? ""
        bottomOffset = (try? values.decode(Double.self, forKey: .bottomOffset)) ?? 18
        visualizerIntensity = (try? values.decode(Double.self, forKey: .visualizerIntensity)) ?? 1
        stillVisualizer = (try? values.decode(Bool.self, forKey: .stillVisualizer)) ?? false
        sounds = (try? values.decode(Bool.self, forKey: .sounds)) ?? false
        shortcuts = (try? values.decode([ShortcutAction: ShortcutBinding].self, forKey: .shortcuts)) ?? ShortcutBinding.defaults
        if (try? ShortcutValidation.validate(shortcuts)) == nil { shortcuts = ShortcutBinding.defaults }
    }
}
