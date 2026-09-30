import SwiftUI
import MurmurCore

private enum SettingsPage: String, CaseIterable, Identifiable {
    case appearance = "Appearance", speech = "Speech models", shortcuts = "Shortcuts", privacy = "Privacy"
    var id: String { rawValue }
    var icon: String {
        switch self { case .appearance: "sparkles"; case .speech: "cpu"; case .shortcuts: "command"; case .privacy: "lock" }
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var page: SettingsPage = .appearance
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform").font(.system(size: 26)).foregroundStyle(MurmurTheme.mint)
                    Text("Murmur").font(.system(size: 23, weight: .semibold, design: .rounded))
                }.padding(.bottom, 5)
                Text("A little space for your voice.").font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.bottom, 28)
                ForEach(SettingsPage.allCases) { item in
                    Button { page = item } label: {
                        Label(item.rawValue, systemImage: item.icon)
                            .font(.system(size: 13, weight: page == item ? .semibold : .regular))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .foregroundStyle(page == item ? MurmurTheme.mint : .white.opacity(0.65))
                            .background(page == item ? MurmurTheme.mint.opacity(0.08) : .clear,
                                        in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Label("Design scaffold", systemImage: "hammer").font(.system(size: 11)).foregroundStyle(.secondary)
                Text("0.1.0 · Local development").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .padding(24).frame(width: 222).background(MurmurTheme.surface.opacity(0.6))
            Rectangle().fill(.white.opacity(0.06)).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Text(page.rawValue.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(2)
                            .foregroundStyle(MurmurTheme.mint)
                        Spacer()
                        Label(model.monitoring ? "Mic preview on" : "Mic off", systemImage: model.monitoring ? "mic.fill" : "mic.slash")
                            .font(.system(size: 11)).foregroundStyle(model.monitoring ? MurmurTheme.mint : .secondary)
                    }
                    switch page {
                    case .appearance: appearance
                    case .speech: speech
                    case .shortcuts: shortcuts
                    case .privacy: privacy
                    }
                    if let notice = model.notice {
                        Label(notice, systemImage: "exclamationmark.circle")
                            .font(.system(size: 12)).foregroundStyle(MurmurTheme.peach).padding(14).card()
                    }
                }.padding(32)
            }.frame(maxWidth: .infinity)
        }
        .frame(minWidth: 900, idealWidth: 980, minHeight: 650, idealHeight: 710)
        .background(MurmurTheme.background)
        .preferredColorScheme(.dark)
        .tint(MurmurTheme.mint)
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Give your voice some room.").font(.system(size: 29, weight: .semibold))
            Text("A quiet bar when you need it. A little color when you speak.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(MurmurTheme.surface.opacity(0.65))
                Ellipse().fill(MurmurTheme.lilac.opacity(0.07)).blur(radius: 32)
                    .frame(width: 320, height: 120)
                VStack(spacing: 10) {
                    VoiceVisualizer(style: model.preferences.style,
                                    frame: model.monitoring ? model.meter : .preview,
                                    reduceMotion: model.preferences.reduceMotion || systemReduceMotion)
                        .frame(width: model.preferences.style == .auraRing ? 172 : 270,
                               height: model.preferences.style == .waveform ? 46 : model.preferences.style == .aura ? 100 : 172)
                    HStack(spacing: 8) {
                        Circle().fill(MurmurTheme.mint).frame(width: 5, height: 5)
                        Text(model.monitoring ? "Live microphone" : "Appearance preview")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "waveform").foregroundStyle(MurmurTheme.mint)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(MurmurTheme.background, in: Capsule())
                    Text(model.monitoring ? "Responding to your microphone. No transcription." : "Static sample · microphone off")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.frame(height: 252)

            HStack(spacing: 10) {
                ForEach(VisualizerStyle.allCases) { style in
                    Button { model.preferences.style = style } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: style == .waveform ? "waveform" : style == .aura ? "sparkles" : "circle.dotted.circle")
                                    .foregroundStyle(model.preferences.style == style ? MurmurTheme.mint : .secondary)
                                Spacer()
                                if model.preferences.style == style {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(MurmurTheme.mint)
                                }
                            }
                            Text(style.title).font(.system(size: 13, weight: .semibold))
                            Text(style == .waveform ? "Small and focused" : style == .aura ? "Soft color and glow" : "Layers that respond")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        .background(MurmurTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(
                            model.preferences.style == style ? MurmurTheme.mint.opacity(0.6) : .white.opacity(0.08), lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                Toggle("Keep the small bar visible", isOn: $model.preferences.keepBarVisible)
                Text("The bar can stay open with the microphone off.").font(.system(size: 11)).foregroundStyle(.secondary)
                Divider().overlay(.white.opacity(0.05))
                Toggle("Reduce visualizer motion", isOn: $model.preferences.reduceMotion)
            }.font(.system(size: 12)).padding(18).card()

            HStack(spacing: 12) {
                Button(model.monitoring || model.preparing ? "Stop microphone preview" : "Try live microphone") {
                    if model.monitoring || model.preparing { model.stopMonitor() } else { model.startMonitor() }
                }.buttonStyle(.borderedProminent).foregroundStyle(MurmurTheme.background)
                Button("Show voice bar") { model.showBar() }.buttonStyle(.bordered)
                Button("Close bar") { model.closeBar() }.buttonStyle(.borderless)
                Spacer()
            }
            Text("This scaffold previews the design. Dictation, insertion, downloads, and global shortcuts are the next milestones.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var speech: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Mac. Your models.").font(.system(size: 29, weight: .semibold))
            Text("Downloads will be optional. Downloading a model won't select it or start your microphone.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            ForEach(["Apple Speech", "Parakeet Realtime", "Moonshine Small", "Whisper"], id: \.self) { name in
                HStack {
                    Image(systemName: "cpu").foregroundStyle(MurmurTheme.mint).frame(width: 30)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(name).font(.system(size: 14, weight: .semibold))
                        Text(name == "Apple Speech" ? "Planned default · system speech assets" : "Optional local download · integration planned")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Planned").font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(20).card()
            }
            Text("Download → Use model → Selected. Model preparation gets its own status and cancel control.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("One thought. Or keep going.").font(.system(size: 29, weight: .semibold))
            Text("These are proposed defaults. Global registration and editable shortcut recording are planned.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            shortcutRow("Quick Talk", description: "Talk, pause, and finish. Press again to finish early.", keys: "⌃ ⌥ Space")
            shortcutRow("Keep Talking", description: "Stay listening between sentences. Press again to stop.", keys: "⌃ ⌥ D")
            shortcutRow("Show / hide bar", description: "Open it without recording. Close it to stop the mic.", keys: "⌃ ⌥ B")
            Text("You'll be able to change each shortcut, see conflicts, and reset the defaults.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
    private func shortcutRow(_ title: String, description: String, keys: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(description).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(keys).font(.system(size: 12, design: .monospaced)).padding(10)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }.padding(20).card()
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Clear about what's listening.").font(.system(size: 28, weight: .semibold))
            Text("The microphone preview stays on this Mac. It doesn't save audio or send it anywhere.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            ForEach([
                ("Microphone", "Only starts when you choose the live preview. Stop, Close, and Quit end capture."),
                ("Accessibility", "Not requested by this scaffold. Future direct insertion will need permission."),
                ("History", "No transcript history yet. The planned default is off."),
                ("Network", "No model downloads, cloud speech, analytics, or update checks in this scaffold.")
            ], id: \.0) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.0).font(.system(size: 14, weight: .semibold))
                    Text(item.1).font(.system(size: 12)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(20).card()
            }
        }
    }
}

private extension View {
    func card() -> some View {
        background(MurmurTheme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.07), lineWidth: 1))
    }
}
