import AppKit
import MurmurCore

enum PasteKeyboardEvents {
    static func make(remoteShortcut: RemotePasteShortcut? = nil) throws -> [CGEvent] {
        guard let source = CGEventSource(stateID: .privateState) else {
            throw OutputSafetyError.noEditableField
        }
        func event(_ key: CGKeyCode, down: Bool, flags: CGEventFlags, modifier: Bool = false) throws -> CGEvent {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else {
                throw OutputSafetyError.noEditableField
            }
            if modifier { event.type = .flagsChanged }
            event.flags = flags
            return event
        }
        guard let remoteShortcut else {
            return try [event(9, down: true, flags: .maskCommand), event(9, down: false, flags: .maskCommand)]
        }
        // TigerVNC forwards modifier key events themselves. Its macOS backend
        // also checks the left-device bits when interpreting flagsChanged.
        let modifiers: [(CGKeyCode, CGEventFlags)] = switch remoteShortcut {
        case .controlV: [(59, CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | 0x1))]
        case .controlShiftV: [(59, CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | 0x1)),
                             (56, CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | 0x2))]
        case .commandV: [(55, CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x8))]
        }
        var events = [CGEvent](), flags = CGEventFlags()
        for (key, modifier) in modifiers {
            flags.formUnion(modifier)
            events.append(try event(key, down: true, flags: flags, modifier: true))
        }
        events += try [event(9, down: true, flags: flags), event(9, down: false, flags: flags)]
        for (key, modifier) in modifiers.reversed() {
            flags.subtract(modifier)
            events.append(try event(key, down: false, flags: flags, modifier: true))
        }
        return events
    }
}
