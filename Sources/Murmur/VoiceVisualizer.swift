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
            }
        }
        .animation(reduceMotion ? nil : .linear(duration: 0.016), value: frame)
        .accessibilityLabel("\(style.title) microphone level")
        .accessibilityValue("\(Int(frame.level * 100)) percent")
    }

    private var waveform: some View {
        GeometryReader { geometry in
            HStack(spacing: 3) {
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
                        .offset(x: CGFloat(index - 2) * geometry.size.width * 0.17 + 20,
                                y: (index.isMultiple(of: 2) ? -1 : 1) * bandEnergy(index) * geometry.size.height * 0.16)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private var rings: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<3) { ring in
                    respondingRing(size: geometry.size, ring: ring)
                        .stroke(AngularGradient(colors: MurmurTheme.colors + [MurmurTheme.mint], center: .center),
                                style: StrokeStyle(lineWidth: ring == 0 ? 3.5 : 2, lineCap: .round))
                        .shadow(color: MurmurTheme.colors[ring].opacity(0.5), radius: 6)
                        .opacity(1 - Double(ring) * 0.2)
                }
                Image(systemName: "mic.fill")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(MurmurTheme.mint)
            }
        }
    }

    private func respondingRing(size: CGSize, ring: Int) -> Path {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let base = min(size.width, size.height) * (0.29 + Double(ring) * 0.063)
        return Path { path in
            for step in 0...160 {
                let angle = Double(step) / 160 * .pi * 2
                let bin = response.peaks.isEmpty ? 0 : (step * response.peaks.count / 160) % response.peaks.count
                let peak = response.peaks.isEmpty ? 0 : Double(response.peaks[bin])
                let motion = reduceMotion ? Double(response.level) * 2 : peak * (12 + Double(ring) * 3)
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
