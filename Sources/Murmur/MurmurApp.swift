import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    var overlay: OverlayController?
    var hotkeys: HotkeyManager?
    private var sleepObserver: NSObjectProtocol?
    func applicationDidFinishLaunching(_ notification: Notification) {
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.model?.interrupt("Your Mac went to sleep. Dictation stopped; your text is retained.") }
        }
    }
    func applicationWillTerminate(_ notification: Notification) { model?.stopMonitor(); model?.cancelDictation() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct MurmurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Murmur", id: "settings") {
            SettingsView(model: model)
                .onAppear {
                    delegate.model = model
                    if delegate.overlay == nil { delegate.overlay = OverlayController(model: model) }
                    if delegate.hotkeys == nil { delegate.hotkeys = HotkeyManager(model: model) }
                }
        }
        .defaultSize(width: 980, height: 710)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) { OpenSettingsButton() }
        }
        MenuBarExtra("Murmur", systemImage: "waveform") {
            OpenSettingsButton()
            Button("Show voice bar") { model.showBar() }
            Button("Close voice bar") { model.closeBar() }
            Divider()
            Button("Quick Talk") { model.toggleDictation(.quickTalk) }
            Button("Keep Talking") { model.toggleDictation(.keepTalking) }
            Button("Cancel dictation") { model.cancelDictation() }
            Divider()
            Button(model.monitoring || model.preparing ? "Stop microphone preview" : "Start microphone preview") {
                if model.monitoring || model.preparing { model.stopMonitor() } else { model.startMonitor() }
            }
            Divider()
            Button("Quit Murmur") { model.stopMonitor(); model.cancelDictation(); NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

private struct OpenSettingsButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Murmur Settings…") {
            openWindow(id: "settings")
            NSApplication.shared.activate()
        }.keyboardShortcut(",")
    }
}
