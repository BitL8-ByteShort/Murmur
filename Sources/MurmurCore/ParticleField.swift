import Foundation

public struct VoiceParticle: Sendable {
    public let x: Double
    public let y: Double
    public let radius: Double
    public let shade: Int
}

/// A deterministic field: no random flicker, blur, or idle animation timer.
public enum ParticleField {
    private struct Seed: Sendable {
        let x: Double, angle: Double, depth: Double, radius: Double, brightness: Double
    }
    private static let seeds: [Seed] = {
        var state: UInt64 = 0x4D55524D5552
        func random() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(UInt64(1) << 53)
        }
        return (0..<6000).map { _ in
            Seed(x: random(), angle: random() * .pi * 2, depth: sqrt(random()), radius: random(), brightness: random())
        }
    }()
    public static func points(frame: MeterFrame, phase: Double, reduceMotion: Bool) -> [VoiceParticle] {
        func clamp(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
        let level = clamp(Double(frame.level))
        let phase = reduceMotion || !phase.isFinite ? 0 : phase
        return seeds.map { seed in
            let bin = min(max(0, frame.peaks.count - 1), Int(seed.x * Double(frame.peaks.count)))
            let peak = frame.peaks.isEmpty ? 0 : clamp(Double(frame.peaks[bin]))
            let envelope = pow(max(0, sin(seed.x * .pi)), 0.65)
            let energy = reduceMotion ? level * 0.18 : level * 0.45 + peak * 0.55
            let fold = seed.x * .pi * 4 + sin(seed.x * .pi * 2) + phase
            let cross = cos(seed.angle) * seed.depth
            let depth = sin(seed.angle) * seed.depth
            let thickness = envelope * (0.035 + energy * 0.4)
            let ribbon = sin(fold) * envelope * (0.025 + energy * 0.2)
                + sin(fold * 2.2 - phase) * envelope * energy * 0.055
            let x = 0.065 + seed.x * 0.87 + depth * sin(fold) * envelope * 0.015
            let y = 0.5 + ribbon + cross * thickness + depth * cos(fold) * thickness * 0.3
            let shade = min(7, max(0, Int((0.3 + depth * 0.25 + seed.brightness * 0.48) * envelope * 8)))
            return VoiceParticle(x: x, y: min(0.96, max(0.04, y)),
                                 radius: 0.0028 + seed.radius * 0.0026, shade: shade)
        }
    }
}
