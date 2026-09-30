import SwiftUI
import MurmurCore

enum MurmurTheme {
    static let mint = Color(red: 0.47, green: 0.94, blue: 0.79)
    static let blue = Color(red: 0.42, green: 0.69, blue: 1)
    static let lilac = Color(red: 0.77, green: 0.64, blue: 1)
    static let peach = Color(red: 1, green: 0.65, blue: 0.53)
    static let colors = [mint, blue, lilac, peach]
    static let background = Color(red: 0.055, green: 0.066, blue: 0.075)
    static let surface = Color(red: 0.10, green: 0.115, blue: 0.13)
}

struct VoiceVisualizer: View {
    let style: VisualizerStyle
    let frame: MeterFrame
    let reduceMotion: Bool
    var intensity = 1.0
    var still = false
    @State private var particlePhase = 0.0
    private var response: MeterFrame {
        if still { return .silence }
        let gain = Float(min(2, max(0.5, intensity)))
        return MeterFrame(level: min(1, frame.level * gain), peaks: frame.peaks.map { min(1, $0 * gain) })
    }

    var body: some View {
        Group {
            switch style {
            case .waveform: waveform
            case .aura: aura
            case .auraRing: rings
            case .particleWave: particles
            }
        }
        .animation(reduceMotion ? nil : .linear(duration: 0.016), value: frame)
        .accessibilityLabel("\(style.title) microphone level")
        .accessibilityValue("\(Int(frame.level * 100)) percent")
        .onChange(of: frame) { _, next in
            if style == .particleWave, !still, !reduceMotion, next.level > 0.01 {
                particlePhase = (particlePhase + 0.04 + Double(next.level) * 0.09).truncatingRemainder(dividingBy: .pi * 20)
            }
        }
    }

    private var particles: some View {
        let input = response, phase = particlePhase, reduced = reduceMotion
        return Canvas(rendersAsynchronously: true) { context, size in
            let points = ParticleField.points(frame: input, phase: phase, reduceMotion: reduced)
            var paths = Array(repeating: Path(), count: 8)
            for point in points {
                let radius = max(0.18, point.radius * size.height)
                paths[point.shade].addEllipse(in: CGRect(x: point.x * size.width - radius,
                    y: point.y * size.height - radius, width: radius * 2, height: radius * 2))
            }
            for shade in 0..<8 {
                let brightness = Double(shade) / 7
                context.fill(paths[shade], with: .color(Color(red: 0.04 + brightness * 0.08,
                    green: 0.55 + brightness * 0.34, blue: 0.58 + brightness * 0.36)
                    .opacity(0.12 + brightness * 0.85)))
            }
        }
    }

    private var waveform: some View {
        GeometryReader { geometry in
            HStack(spacing: min(3, geometry.size.width / CGFloat(max(1, response.peaks.count)) * 0.25)) {
                ForEach(Array(response.peaks.enumerated()), id: \.offset) { index, peak in
                    Capsule()
                        .fill(MurmurTheme.colors[min(3, index * 4 / max(1, response.peaks.count))])
                        .frame(height: max(3, CGFloat(peak) * geometry.size.height))
                }
            }
            .frame(height: geometry.size.height)
        }
    }

    private var aura: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<4) { index in
                    Ellipse()
                        .fill(RadialGradient(colors: [MurmurTheme.colors[index],
                                                     MurmurTheme.colors[index].opacity(0.65)],
                                             center: .center, startRadius: 0, endRadius: 60))
                        .overlay(Ellipse().stroke(MurmurTheme.colors[index].opacity(0.85), lineWidth: 1))
                        .frame(width: geometry.size.width * (0.18 + bandEnergy(index) * 0.26),
                               height: geometry.size.height * (0.2 + bandEnergy(index) * 0.75))
                        .opacity(0.6 + Double(response.level) * 0.4)
                        .offset(x: CGFloat(index - 2) * geometry.size.width * 0.17 + geometry.size.width * 0.06,
                                y: (index.isMultiple(of: 2) ? -1 : 1) * bandEnergy(index) * geometry.size.height * 0.16)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private var rings: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                ForEach(0..<3) { ring in
                    respondingRing(size: geometry.size, ring: ring)
                        .stroke(AngularGradient(colors: MurmurTheme.colors + [MurmurTheme.mint], center: .center),
                                style: StrokeStyle(lineWidth: ring == 0 ? max(1.2, min(3.5, side * 0.02)) : max(0.8, min(2, side * 0.014)), lineCap: .round))
                        .shadow(color: MurmurTheme.colors[ring].opacity(0.5), radius: min(6, side * 0.03))
                        .opacity(1 - Double(ring) * 0.2)
                }
                Image(systemName: "mic.fill")
                    .font(.system(size: min(23, max(10, side * 0.25)), weight: .medium))
                    .foregroundStyle(MurmurTheme.mint)
            }
        }
    }

    private func respondingRing(size: CGSize, ring: Int) -> Path {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let side = min(size.width, size.height)
        let base = side * (0.27 + Double(ring) * 0.055)
        return Path { path in
            for step in 0...160 {
                let angle = Double(step) / 160 * .pi * 2
                let bin = response.peaks.isEmpty ? 0 : (step * response.peaks.count / 160) % response.peaks.count
                let peak = response.peaks.isEmpty ? 0 : Double(response.peaks[bin])
                let motion = side * (reduceMotion ? Double(response.level) * 0.012 : peak * (0.035 + Double(ring) * 0.008))
                let radius = base + motion
                let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
    }

    private func bandEnergy(_ index: Int) -> Double {
        if reduceMotion { return Double(response.level) * 0.18 }
        guard !response.peaks.isEmpty else { return 0 }
        let lower = index * response.peaks.count / 4
        let upper = (index + 1) * response.peaks.count / 4
        let values = response.peaks[lower..<upper]
        return Double(values.reduce(0, +)) / Double(max(1, values.count))
    }
}
