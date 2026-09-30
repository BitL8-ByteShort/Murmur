import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    var overlay: OverlayController?
    func applicationWillTerminate(_ notification: Notification) { model?.stopMonitor() }
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
            Button(model.monitoring || model.preparing ? "Stop microphone preview" : "Start microphone preview") {
                if model.monitoring || model.preparing { model.stopMonitor() } else { model.startMonitor() }
            }
            Text("Dictation is planned")
            Divider()
            Button("Quit Murmur") { model.stopMonitor(); NSApplication.shared.terminate(nil) }
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
