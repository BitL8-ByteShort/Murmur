import Foundation
import Testing
@testable import MurmurCore

@Test func tigerVNCPasteChoiceSurvivesSavingWithoutChangingOtherPreferences() throws {
    let saved = Data(#"{"version":1,"remotePasteShortcut":"controlShiftV","style":"particleWave","silenceSeconds":1.0}"#.utf8)
    let preferences = try JSONDecoder().decode(Preferences.self, from: saved)
    let encoded = try JSONEncoder().encode(preferences)
    let values = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(values["remotePasteShortcut"] as? String == "controlShiftV")
    #expect(preferences.style == .particleWave)
    #expect(preferences.silenceSeconds == 1.0)
}

@Test func onlyAnActualTigerVNCDesktopCanUseRemotePaste() {
    #expect(RemoteDesktopPolicy.accepts(bundleIdentifier: "com.tigervnc.tigervnc",
        windowTitle: "Linux desktop - TigerVNC", focusedRole: "AXWindow"))
    #expect(!RemoteDesktopPolicy.accepts(bundleIdentifier: "com.example.editor",
        windowTitle: "Linux desktop - TigerVNC", focusedRole: "AXWindow"))
    #expect(!RemoteDesktopPolicy.accepts(bundleIdentifier: "com.tigervnc.tigervnc",
        windowTitle: "Options", focusedRole: "AXWindow"))
    #expect(!RemoteDesktopPolicy.accepts(bundleIdentifier: "com.tigervnc.tigervnc",
        windowTitle: "Linux desktop - TigerVNC", focusedRole: "AXTextField"))
}

@Test func oldOrInvalidRemotePasteSettingsDefaultToLinuxWithoutResettingSavedSettings() throws {
    for json in [#"{"style":"auraRing"}"#, #"{"style":"auraRing","remotePasteShortcut":"invalid"}"#] {
        let preferences = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        #expect(preferences.remotePasteShortcut == .controlV)
        #expect(preferences.style == .auraRing)
    }
}
