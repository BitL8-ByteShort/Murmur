import AppKit
@preconcurrency import ApplicationServices
import MurmurCore

/// The original app and focused field stay fixed throughout a dictation session.
@MainActor final class TextInsertionService {
    struct Target {
        let pid: pid_t
        let element: AXUIElement
        let terminal: Bool
    }
    private var target: Target?
    private var inserted = Set<UUID>()
    static var permissionGranted: Bool { AXIsProcessTrusted() }
    static func openPermissionSettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func captureDestination() throws -> Target {
        guard Self.permissionGranted else { throw OutputSafetyError.permissionRequired }
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let element = focusedElement(app.processIdentifier) else { throw OutputSafetyError.noEditableField }
        guard !isSecure(element) else { throw OutputSafetyError.secureField }
        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
        let editable = (attribute(element, "AXEditable") as? Bool) == true
        guard editable || [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) else {
            throw OutputSafetyError.noEditableField
        }
        let bundle = app.bundleIdentifier?.lowercased() ?? ""
        return Target(pid: app.processIdentifier, element: element,
                      terminal: ["terminal", "iterm", "warp", "kitty", "alacritty"].contains { bundle.contains($0) })
    }
    func begin(destination: Target?) { target = destination; inserted.removeAll() }
    func insert(_ text: String, utteranceID: UUID) async throws {
        guard !text.isEmpty, !inserted.contains(utteranceID) else { return }
        guard let target else { throw OutputSafetyError.noEditableField }
        try validate(target, text: text)
        let context = caretContext(target.element)
        let output = InsertionSpacing.text(text, before: context.before, after: context.after)
        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(target.element, kAXSelectedTextAttribute as CFString, &settable) == .success,
           settable.boolValue,
           AXUIElementSetAttributeValue(target.element, kAXSelectedTextAttribute as CFString, output as CFString) == .success {
            inserted.insert(utteranceID); return
        }
        try await paste(output, into: target)
        inserted.insert(utteranceID)
    }
    private func validate(_ target: Target, text: String) throws {
        try OutputSafety.validate(targetPID: target.pid,
                                  currentPID: NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1,
                                  secure: isSecure(target.element), terminal: target.terminal, text: text)
        guard let current = focusedElement(target.pid), CFEqual(current, target.element) else { throw OutputSafetyError.targetChanged }
    }
    private func focusedElement(_ pid: pid_t) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    private func isSecure(_ element: AXUIElement) -> Bool {
        (attribute(element, kAXSubroleAttribute) as? String) == "AXSecureTextField" ||
        (attribute(element, "AXProtectedContent") as? Bool) == true
    }
    private func caretContext(_ element: AXUIElement) -> (before: String, after: String) {
        guard let text = attribute(element, kAXValueAttribute) as? String,
              let value = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return ("", "") }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range), range.location >= 0, range.length >= 0 else { return ("", "") }
        let ns = text as NSString
        guard range.location + range.length <= ns.length else { return ("", "") }
        return (ns.substring(to: range.location), ns.substring(from: range.location + range.length))
    }
    private func paste(_ text: String, into target: Target) async throws {
        let board = NSPasteboard.general
        var original: [[NSPasteboard.PasteboardType: Data]] = []
        for item in board.pasteboardItems ?? [] {
            var types: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { throw OutputSafetyError.clipboardUnavailable }
                types[type] = data
            }
            original.append(types)
        }
        let marker = NSPasteboard.PasteboardType("com.saltypanda.murmur.clipboard-lease")
        let token = UUID().uuidString
        board.clearContents()
        let item = NSPasteboardItem(); item.setString(text, forType: .string); item.setString(token, forType: marker)
        guard board.writeObjects([item]) else {
            let items = original.map { types in
                let saved = NSPasteboardItem()
                for (type, data) in types { saved.setData(data, forType: type) }
                return saved
            }
            board.clearContents(); if !items.isEmpty { board.writeObjects(items) }
            throw OutputSafetyError.clipboardUnavailable
        }
        let lease = ClipboardLease(changeCount: board.changeCount, token: token)
        defer {
            if lease.owns(changeCount: board.changeCount, token: board.string(forType: marker)) {
                board.clearContents()
                let items = original.map { types in
                    let item = NSPasteboardItem()
                    for (type, data) in types { item.setData(data, forType: type) }
                    return item
                }
                if !items.isEmpty { board.writeObjects(items) }
            }
        }
        try validate(target, text: text)
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { throw OutputSafetyError.noEditableField }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.postToPid(target.pid); up.postToPid(target.pid)
        // Keep the temporary text available while the destination handles its paste event.
        try? await Task.sleep(for: .seconds(1))
    }
}
