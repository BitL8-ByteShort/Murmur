import AppKit
import AVFoundation

@MainActor enum MicrophonePermission {
    static func request(waiting: (() -> Void)? = nil) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined:
            waiting?()
            // A nonactivating voice panel must bring the app forward for first-use consent.
            let destination = NSWorkspace.shared.frontmostApplication
            NSApplication.shared.activate()
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard !Task.isCancelled else { return false }
            if NSApplication.shared.isActive,
               let destination, destination.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                destination.activate()
            }
            return allowed
        @unknown default: return false
        }
    }
}
