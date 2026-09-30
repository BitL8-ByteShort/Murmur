import Foundation

public enum VisualizerStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case waveform, aura, auraRing
    public var id: String { rawValue }
    public var title: String {
        switch self { case .waveform: "Waveform"; case .aura: "Aura"; case .auraRing: "Aura Ring" }
    }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var version = 1
    public var style: VisualizerStyle = .waveform
    public var keepBarVisible = false
    public var reduceMotion = false
    public init() {}
}
