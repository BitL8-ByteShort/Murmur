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
        guard let screen else { return }
        let expanded = model.monitoring || model.preparing
        let size: CGSize
        if expanded {
            size = switch model.preferences.style {
            case .waveform: CGSize(width: 360, height: 80)
            case .aura: CGSize(width: 320, height: 168)
            case .auraRing: CGSize(width: 228, height: 244)
            }
        } else { size = CGSize(width: 112, height: 32) }
        let visible = screen.visibleFrame
        let width = min(size.width, visible.width - 24)
        let height = min(size.height, visible.height - 24)
        panel.setFrame(CGRect(x: visible.midX - width / 2, y: visible.minY + 18,
                              width: width, height: height), display: true)
        panel.orderFrontRegardless()
    }
}

struct OverlayView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    var body: some View {
        Group {
            if model.monitoring || model.preparing {
                VStack(spacing: 8) {
                    VoiceVisualizer(style: model.preferences.style, frame: model.meter,
                                    reduceMotion: model.preferences.reduceMotion || systemReduceMotion)
                        .frame(height: model.preferences.style == .waveform ? 24 : model.preferences.style == .aura ? 108 : 172)
                        .padding(.horizontal, 18)
                    HStack(spacing: 10) {
                        Circle().fill(MurmurTheme.mint).frame(width: 5, height: 5)
                        Text(model.preparing ? "Preparing…" : "Mic preview").font(.system(size: 11, weight: .medium))
                        Spacer(minLength: 0)
                        Button { model.stopMonitor() } label: { Image(systemName: "stop.fill") }
                            .help("Stop microphone preview")
                        Button { model.closeBar() } label: { Image(systemName: "xmark") }
                            .help("Close bar and stop microphone")
                    }
                    .font(.system(size: 11)).padding(.horizontal, 16)
                }
                .padding(.vertical, 11)
            } else {
                HStack(spacing: 8) {
                    Button { model.startMonitor() } label: {
                        Image(systemName: "waveform").foregroundStyle(MurmurTheme.mint)
                    }.help("Start live microphone preview")
                    Text("Murmur").font(.system(size: 11, weight: .semibold))
                    Button { model.closeBar() } label: { Image(systemName: "xmark").font(.system(size: 8)) }
                        .help("Close voice bar")
                }.padding(.horizontal, 12).frame(height: 32)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MurmurTheme.surface.opacity(0.97), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.12), lineWidth: 1))
        .preferredColorScheme(.dark)
    }
}
