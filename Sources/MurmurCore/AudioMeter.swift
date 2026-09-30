import Foundation

public struct MeterFrame: Sendable, Equatable {
    public let level: Float
    public let peaks: [Float]
    public init(level: Float, peaks: [Float]) { self.level = level; self.peaks = peaks }
    public static let silence = MeterFrame(level: 0, peaks: Array(repeating: 0, count: 40))
    /// Static, labeled appearance preview. Never used as live microphone data.
    public static let preview = MeterFrame(level: 0.48, peaks: (0..<40).map {
        Float(0.12 + abs(sin(Double($0) * 0.63)) * 0.75)
    })
}

public enum AudioMeter {
    /// Bounded time-domain amplitude bins, not a speech detector or spectral analyzer.
    public static func measure(_ samples: [Float], bins: Int = 40) -> MeterFrame {
        let count = min(max(bins, 1), 128)
        guard !samples.isEmpty else {
            return MeterFrame(level: 0, peaks: Array(repeating: 0, count: count))
        }
        var energy: Float = 0
        var peaks = Array(repeating: Float(0), count: count)
        for (index, value) in samples.enumerated() {
            let sample = value.isFinite ? min(abs(value), 1) : 0
            energy += sample * sample
            let bin = min(count - 1, index * count / samples.count)
            peaks[bin] = max(peaks[bin], sample)
        }
        let rms = sqrt(energy / Float(samples.count))
        let decibels = 20 * log10(max(rms, 0.000001))
        let level = max(0, min(1, (decibels + 60) / 60))
        return MeterFrame(level: level, peaks: peaks.map { min(1, $0 * 5) })
    }
}
