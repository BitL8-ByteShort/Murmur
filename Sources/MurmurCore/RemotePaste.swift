import Foundation

public enum RemotePasteShortcut: String, Codable, CaseIterable, Sendable, Identifiable {
    case controlV, controlShiftV, commandV
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .controlV: "Control–V · Linux / Windows"
        case .controlShiftV: "Control–Shift–V · Linux terminal"
        case .commandV: "Command–V · Remote Mac"
        }
    }
}

public enum RemoteDesktopPolicy {
    public static func accepts(bundleIdentifier: String, windowTitle: String, focusedRole: String) -> Bool {
        bundleIdentifier.lowercased() == "com.tigervnc.tigervnc" &&
        windowTitle.hasSuffix(" - TigerVNC") && focusedRole == "AXWindow"
    }
}
