import AppKit
import SwiftUI
import MurmurCore

private final class VoicePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayController {
    private let panel: NSPanel
    private let model: AppModel
    private var screenObserver: NSObjectProtocol?
    private var screen: NSScreen?

    init(model: AppModel) {
        self.model = model
        panel = VoicePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.title = "Murmur Voice Bar"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.contentView = NSHostingView(rootView: OverlayView(model: model))
        model.onOverlayChange = { [weak self] in self?.update() }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.screen = nil; self?.update() } }
        update()
    }

    func update() {
        guard model.barVisible else { panel.orderOut(nil); screen = nil; return }
        if screen == nil {
            let pointer = NSEvent.mouseLocation
            screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        }
        if !model.preferences.displayID.isEmpty {
            screen = NSScreen.screens.first { String(describing: $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? "") == model.preferences.displayID } ?? screen
        }
        guard let screen else { return }
        let expanded = model.isExpanded
        let size = expanded ? CGSize(width: 200, height: 56) : CGSize(width: 100, height: 28)
        let visible = screen.visibleFrame
        let width = min(size.width, visible.width - 24)
        let height = min(size.height, visible.height - 24)
        let offset = min(max(0, model.preferences.bottomOffset), max(0, visible.height - height - 12))
        panel.setFrame(CGRect(x: visible.midX - width / 2, y: visible.minY + offset,
                              width: width, height: height), display: true)
        panel.orderFrontRegardless()
    }
}

struct OverlayView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    var body: some View {
        Group {
            if model.isExpanded {
                HStack(spacing: 8) {
                    VoiceVisualizer(style: model.preferences.style, frame: model.visualizerFrame,
                                    reduceMotion: model.preferences.reduceMotion || systemReduceMotion,
                                    intensity: model.preferences.visualizerIntensity, still: model.preferences.stillVisualizer)
                        .frame(width: model.preferences.style == .auraRing ? 40 : 116,
                               height: model.preferences.style == .waveform ? 24 : 40)
                        .frame(width: 116, height: 40)
                        .help(model.status)
                    HStack(spacing: 4) {
                        Button {
                            if model.dictation.phase == .preparing { model.cancelDictation() }
                            else if model.dictation.isActive { Task { await model.dictation.finish() } }
                            else { model.stopMonitor() }
                        } label: { Image(systemName: "stop.fill").frame(width: 20, height: 20) }
                            .help("Finish dictation or stop preview")
                        Button { model.closeBar() } label: { Image(systemName: "xmark").frame(width: 20, height: 20) }
                            .help("Close bar and stop microphone")
                    }
                    .font(.system(size: 11))
                }
                .padding(.horizontal, 12)
            } else {
                HStack(spacing: 6) {
                    Button { model.toggleDictation(.quickTalk) } label: {
                        Image(systemName: "waveform").foregroundStyle(MurmurTheme.mint)
                    }.help("Start Quick Talk")
                    Text("Murmur").font(.system(size: 10, weight: .semibold))
                    Button { model.closeBar() } label: { Image(systemName: "xmark").font(.system(size: 8)) }
                        .help("Close voice bar")
                }.padding(.horizontal, 10).frame(height: 28)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MurmurTheme.surface.opacity(0.97), in: RoundedRectangle(cornerRadius: model.isExpanded ? 22 : 14))
        .overlay(RoundedRectangle(cornerRadius: model.isExpanded ? 22 : 14).stroke(.white.opacity(0.12), lineWidth: 1))
        .preferredColorScheme(.dark)
    }
}
