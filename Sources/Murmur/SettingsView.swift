import SwiftUI
import MurmurCore

private enum SettingsPage: String, CaseIterable, Identifiable {
    case dictation = "Dictation", appearance = "Appearance", speech = "Speech models", shortcuts = "Shortcuts", privacy = "Privacy"
    var id: String { rawValue }
    var icon: String {
        switch self { case .dictation: "mic"; case .appearance: "sparkles"; case .speech: "cpu"; case .shortcuts: "command"; case .privacy: "lock" }
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var page: SettingsPage = .dictation
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
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                Spacer()
                Label("Local dictation", systemImage: "lock").font(.system(size: 11)).foregroundStyle(.secondary)
                Text("0.2.0 · Development preview").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .padding(24).frame(width: 222).background(MurmurTheme.surface.opacity(0.6))
            Rectangle().fill(.white.opacity(0.06)).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Text(page.rawValue.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(2)
                            .foregroundStyle(MurmurTheme.mint)
                        Spacer()
                        Label(model.status, systemImage: model.monitoring || model.dictation.phase == .listening ? "mic.fill" : "mic.slash")
                            .font(.system(size: 11)).foregroundStyle(model.monitoring || model.dictation.isActive ? MurmurTheme.mint : .secondary)
                    }
                    switch page {
                    case .dictation: dictation
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshPermissions() }
    }

    private var dictation: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Say what's on your mind.").font(.system(size: 29, weight: .semibold))
            Text("Quick Talk finishes after a pause. Keep Talking stays listening between thoughts.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button(model.dictation.isActive ? "Finish dictation" : "Quick Talk") { model.toggleDictation(.quickTalk) }
                    .buttonStyle(.borderedProminent).foregroundStyle(MurmurTheme.background)
                Button("Keep Talking") { model.toggleDictation(.keepTalking) }.buttonStyle(.bordered)
                    .disabled(model.dictation.isActive)
                if model.dictation.isActive { Button("Cancel") { model.cancelDictation() }.buttonStyle(.bordered) }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 14) {
                Picker("Microphone", selection: $model.preferences.microphoneID) {
                    Text("System default").tag("")
                    ForEach(model.microphones) { Text($0.name).tag($0.id) }
                }
                Picker("Language", selection: $model.preferences.locale) {
                    ForEach(model.locales, id: \.self) { identifier in
                        Text(Locale.current.localizedString(forIdentifier: identifier) ?? identifier).tag(identifier)
                    }
                }
                HStack {
                    Text("Quick Talk pause").font(.system(size: 12))
                    Slider(value: $model.preferences.silenceSeconds, in: 0.7...3, step: 0.1)
                    Text("\(model.preferences.silenceSeconds, specifier: "%.1f") s").font(.system(size: 11, design: .monospaced)).frame(width: 42)
                }
                Picker("Keep Talking inactivity", selection: $model.preferences.inactivitySeconds) {
                    Text("1 minute").tag(60.0); Text("5 minutes").tag(300.0); Text("15 minutes").tag(900.0); Text("Off").tag(0.0)
                }
            }.padding(18).card()
            VStack(alignment: .leading, spacing: 10) {
                Picker("TigerVNC paste", selection: $model.preferences.remotePasteShortcut) {
                    ForEach(RemotePasteShortcut.allCases) { Text($0.title).tag($0) }
                }
                Text("Only applies inside a TigerVNC desktop. Enable clipboard sharing in the viewer and click the remote text field before dictating. Murmur cannot inspect remote fields or passwords; it sends paste without Enter and keeps your words available for copying.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(18).card()
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Copy only", isOn: $model.preferences.copyOnly)
                Text("With Copy only off, start from a text field in another app using your shortcut. Murmur keeps that destination for the whole session.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if !model.accessibilityGranted {
                    Button("Allow typing into other apps…") { TextInsertionService.openPermissionSettings() }
                    Text("Enable Murmur in Accessibility, then return here. Dictation still works for copying without permission.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.font(.system(size: 12)).padding(18).card()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Transcript").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button("Copy") { model.dictation.copyTranscript() }.disabled(model.dictation.recoveryText.isEmpty)
                    Button("Clear") { model.dictation.dismiss() }.disabled(model.dictation.isActive)
                }
                Text(model.dictation.transcript.isEmpty ? "Your finalized words appear here." : model.dictation.transcript)
                    .font(.system(size: 14)).foregroundStyle(model.dictation.transcript.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                if !model.dictation.partial.isEmpty {
                    Text(model.dictation.partial).font(.system(size: 14)).foregroundStyle(MurmurTheme.mint).textSelection(.enabled)
                }
                if let notice = model.dictation.notice {
                    Text(notice).font(.system(size: 12)).foregroundStyle(MurmurTheme.peach)
                }
            }.padding(20).frame(minHeight: 160, alignment: .top).card()
            if !model.dictation.recovery.entries.isEmpty {
                DisclosureGroup("Previous transcripts · in memory") {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(model.dictation.recovery.entries.reversed()) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(entry.createdAt, format: .dateTime.hour().minute()).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Copy") { model.dictation.copyRecovery(entry) }
                                }
                                Text(entry.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(12).card()
                        }
                        Button("Clear previous transcripts") { model.dictation.clearPreviousTranscripts() }
                        Text("Kept only until you clear them or quit Murmur. Nothing is written to disk.").foregroundStyle(.secondary)
                    }.font(.system(size: 12)).padding(.top, 12)
                }.padding(18).card()
            }
            Text("Speech stays on this Mac. Murmur types finalized words and never presses Enter or sends a message.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Give your voice some room.").font(.system(size: 29, weight: .semibold))
            Text("A quiet bar when you need it. A little color when you speak.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(MurmurTheme.surface.opacity(0.65))
                VStack(spacing: 10) {
                    VoiceVisualizer(style: model.preferences.style,
                                    frame: model.monitoring || model.dictation.isActive ? model.visualizerFrame : .preview,
                                    reduceMotion: model.preferences.reduceMotion || systemReduceMotion,
                                    intensity: model.preferences.visualizerIntensity, still: model.preferences.stillVisualizer)
                        .frame(width: model.preferences.style == .auraRing ? 172 : model.preferences.style == .particleWave ? 550 : 270,
                               height: model.preferences.style == .waveform ? 46 : model.preferences.style == .auraRing ? 172 : 140)
                    HStack(spacing: 8) {
                        Circle().fill(MurmurTheme.mint).frame(width: 5, height: 5)
                        Text(model.monitoring || model.dictation.isActive ? "Live microphone" : "Appearance preview")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "waveform").foregroundStyle(MurmurTheme.mint)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(MurmurTheme.background, in: Capsule())
                    Text(model.dictation.isActive ? model.dictation.status : model.monitoring ? "Microphone preview · no transcription" : "Static sample · microphone off")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.frame(height: 252)

            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
                ForEach(VisualizerStyle.allCases) { style in
                    Button { model.preferences.style = style } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: style.icon)
                                    .foregroundStyle(model.preferences.style == style ? MurmurTheme.mint : .secondary)
                                Spacer()
                                if model.preferences.style == style {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(MurmurTheme.mint)
                                }
                            }
                            Text(style.title).font(.system(size: 13, weight: .semibold))
                            Text(style.detail)
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
                Toggle("Always on", isOn: $model.preferences.keepBarVisible)
                Text("Keep a tiny bar visible after dictation. The microphone stays off until you start.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Divider().overlay(.white.opacity(0.05))
                Toggle("Reduce visualizer motion", isOn: $model.preferences.reduceMotion)
                Toggle("Still visualizer", isOn: $model.preferences.stillVisualizer)
                HStack {
                    Text("Response strength")
                    Slider(value: $model.preferences.visualizerIntensity, in: 0.5...2, step: 0.1)
                    Text("\(model.preferences.visualizerIntensity, specifier: "%.1f")×").monospacedDigit().frame(width: 38)
                }
                Picker("Display", selection: $model.preferences.displayID) {
                    Text("Where the pointer is").tag("")
                    ForEach(NSScreen.screens, id: \.localizedName) { screen in
                        Text(screen.localizedName).tag(String(describing: screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? ""))
                    }
                }
                HStack {
                    Text("Bottom spacing")
                    Slider(value: $model.preferences.bottomOffset, in: 0...180, step: 1)
                    Text("\(Int(model.preferences.bottomOffset)) pt").monospacedDigit().frame(width: 44)
                }
            }.font(.system(size: 12)).padding(18).card()

            HStack(spacing: 12) {
                Button(model.monitoring || model.preparing ? "Stop microphone preview" : "Try live microphone") {
                    if model.monitoring || model.preparing { model.stopMonitor() } else { model.startMonitor() }
                }.buttonStyle(.borderedProminent).foregroundStyle(MurmurTheme.background)
                Button("Show voice bar") { model.showBar() }.buttonStyle(.bordered)
                Button("Close bar") { model.closeBar() }.buttonStyle(.borderless)
                Spacer()
            }
            Text("Preview the visualizer without dictation, or start Quick Talk from the voice bar.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var speech: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Mac. Your models.").font(.system(size: 29, weight: .semibold))
            Text("Download first, then choose Use model. Downloads never start the microphone.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            ForEach(SpeechEngine.allCases) { engine in
                HStack {
                    Image(systemName: "cpu").foregroundStyle(MurmurTheme.mint).frame(width: 30)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(engine.title).font(.system(size: 14, weight: .semibold))
                        Text(engine == .apple ? "System speech assets · selected language" : engine == .whisper ? "Whisper Turbo · multilingual · larger download" : "English · optional local download")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        if model.downloadingModel == engine { Text(model.downloadStatus).font(.system(size: 11)).foregroundStyle(MurmurTheme.mint) }
                    }
                    Spacer()
                    if engine == .apple {
                        Button(model.installingApple ? "Installing…" : "Install language") { model.installAppleAssets() }.disabled(model.installingApple)
                    } else if model.downloadingModel == engine {
                        Button("Cancel") { model.cancelDownload() }
                    } else if !model.installedModels.contains(engine) {
                        Button("Download") { model.download(engine) }.disabled(model.downloadingModel != nil)
                    }
                    if engine == .apple || model.installedModels.contains(engine) {
                        if model.preferences.engine == engine {
                            Label("Selected", systemImage: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(MurmurTheme.mint)
                        } else { Button("Use model") { model.selectModel(engine) }.disabled(model.dictation.isActive) }
                    }
                    if model.installedModels.contains(engine) {
                        Button { model.deleteModel(engine) } label: { Image(systemName: "trash") }
                            .help("Move downloaded model to Trash")
                            .disabled(model.dictation.isActive || model.downloadingModel != nil)
                    }
                }.padding(20).card()
            }
            Text("Models stay in Murmur's Application Support folder. Preparing a downloaded model can take a little time, especially on the first run. Cancel remains available while it loads.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Button("Open model folder") {
                try? FileManager.default.createDirectory(at: LocalModelStore.root, withIntermediateDirectories: true)
                NSWorkspace.shared.open(LocalModelStore.root)
            }
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("One thought. Or keep going.").font(.system(size: 29, weight: .semibold))
            Text("Use these shortcuts from any app. Click a binding to record a different combination.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            ForEach(ShortcutAction.allCases) { action in
                HStack {
                    Text(action.title).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Button(model.recordingShortcut == action ? "Press shortcut…" : model.preferences.shortcuts[action]?.label ?? "Record") {
                        model.recordingShortcut = action; model.shortcutError = nil
                    }.buttonStyle(.bordered)
                }.padding(20).card()
            }
            Button("Reset defaults") { model.resetShortcuts() }
            Text(model.shortcutError ?? "Include Control or Command. Escape cancels shortcut recording, or an active dictation.")
                .font(.system(size: 12)).foregroundStyle(model.shortcutError == nil ? .secondary : MurmurTheme.peach)
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
                ("Microphone", "Starts only when you choose dictation or live preview. Finish, Cancel, Close, and Quit end capture."),
                ("Accessibility", "Optional permission for typing into other apps. Murmur checks the destination and refuses password fields."),
                ("Remote desktops", "TigerVNC uses the selected remote paste shortcut. Only the viewer window can be checked; remote fields and passwords are not visible to Murmur. Remote paste does not press Enter; multiline text stays available for copying."),
                ("History", "No transcripts are written to disk. Previous attempts remain in memory for recovery until you clear them or quit."),
                ("Network", "Only explicit model or language downloads use the network. Recognition is local. No analytics or cloud rewriting.")
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
