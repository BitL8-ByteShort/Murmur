import AppKit
@preconcurrency import ApplicationServices
import MurmurCore

/// The original app and focused field stay fixed throughout a dictation session.
@MainActor final class TextInsertionService {
    struct Target {
        let pid: pid_t
        let element: AXUIElement
        let terminal: Bool
        let remoteShortcut: RemotePasteShortcut?
        let remoteWindowTitle: String?
        let appName: String
    }
    private var target: Target?
    private var inserted = Set<UUID>()
    private var pendingClipboardRestore: (id: UUID, restore: () -> Void)?
    static var permissionGranted: Bool { AXIsProcessTrusted() }
    static func openPermissionSettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func captureDestination(remoteShortcut: RemotePasteShortcut = .controlV) throws -> Target {
        guard Self.permissionGranted else { throw OutputSafetyError.permissionRequired }
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw OutputSafetyError.noEditableField
        }
        let focused = focusedElement(app.processIdentifier)
        let bundle = app.bundleIdentifier?.lowercased() ?? ""
        if let window = focusedWindow(app.processIdentifier),
           let title = attribute(window, kAXTitleAttribute) as? String,
           RemoteDesktopPolicy.accepts(bundleIdentifier: bundle, windowTitle: title,
                                       focusedRole: attribute(focused ?? window, kAXRoleAttribute) as? String ?? ""),
           focused == nil || CFEqual(focused!, window), !hasSheet(window) {
            return Target(pid: app.processIdentifier, element: window, terminal: true,
                          remoteShortcut: remoteShortcut, remoteWindowTitle: title, appName: app.localizedName ?? "TigerVNC")
        }
        guard let element = focused else { throw OutputSafetyError.noEditableField }
        guard !isSecure(element) else { throw OutputSafetyError.secureField }
        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
        let editable = (attribute(element, "AXEditable") as? Bool) == true
        guard editable || [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) else {
            throw OutputSafetyError.noEditableField
        }
        return Target(pid: app.processIdentifier, element: element,
                      terminal: ["terminal", "iterm", "warp", "kitty", "alacritty"].contains { bundle.contains($0) },
                      remoteShortcut: nil, remoteWindowTitle: nil, appName: app.localizedName ?? "App")
    }
    func begin(destination: Target?) { target = destination; inserted.removeAll() }
    func insert(_ text: String, utteranceID: UUID) async throws -> TextInsertionResult {
        guard !text.isEmpty, !inserted.contains(utteranceID) else { return .verified }
        guard let target else { throw OutputSafetyError.noEditableField }
        try validate(target, text: text)
        var restoreClipboard: (() -> Void)?
        var delayRestoration = false
        defer {
            if delayRestoration, let restoreClipboard {
                let leaseID = UUID()
                pendingClipboardRestore = (leaseID, restoreClipboard)
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(1))
                    restoreClipboard()
                    if self?.pendingClipboardRestore?.id == leaseID { self?.pendingClipboardRestore = nil }
                }
            } else { restoreClipboard?() }
        }
        let remote = target.remoteShortcut != nil
        let words = remote && !inserted.isEmpty ? " " + text : text
        let result = try await InsertionDelivery.deliver(words, prefersPaste: remote || isWebEditor(target.element),
            read: { remote ? nil : self.snapshot(target.element) }, validate: { try self.validate(target, text: text) },
            direct: { output in
                var settable = DarwinBoolean(false)
                guard AXUIElementIsAttributeSettable(target.element, kAXSelectedTextAttribute as CFString, &settable) == .success,
                      settable.boolValue else { return false }
                return AXUIElementSetAttributeValue(target.element, kAXSelectedTextAttribute as CFString, output as CFString) == .success
            }, paste: { output in
                // Resolve our previous lease before snapshotting the clipboard
                // for another utterance. Each restore also checks its owner token.
                self.pendingClipboardRestore?.restore(); self.pendingClipboardRestore = nil
                let provider = remote ? RequestedPasteboardText(output) : nil
                restoreClipboard = try self.publishPasteboard(output, provider: provider)
                if remote {
                    try await RemoteClipboardHandoff.deliver(
                        refresh: { try await self.refreshViewerClipboard(target, text: output) },
                        requested: { provider?.wasRequested == true },
                        validate: { try self.validate(target, text: output) },
                        paste: { try self.postPaste(into: target, text: output) })
                } else {
                    try Task.checkCancellation()
                    try self.postPaste(into: target, text: output)
                }
            })
        delayRestoration = !remote && result == .sent
        inserted.insert(utteranceID)
        return result
    }
    private func refreshViewerClipboard(_ target: Target, text: String) async throws {
        try validate(target, text: text)
        guard let viewer = NSRunningApplication(processIdentifier: target.pid) else { throw OutputSafetyError.targetChanged }
        let current = NSRunningApplication.current
        // TigerVNC/FLTK on macOS checks external clipboard changes in
        // applicationDidBecomeActive, rather than polling while already active.
        // Returning to the SAME viewer triggers its clipboard announcement and
        // releases remote shortcut modifiers. Do not reactivate after a user
        // switches to any other application.
        guard current.activate(options: []) else { throw OutputSafetyError.remoteClipboardUnavailable }
        defer {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == current.processIdentifier {
                _ = viewer.activate(options: [])
            }
        }
        try await waitForActivation(current, allowedPrevious: target.pid)
        try Task.checkCancellation()
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == current.processIdentifier,
              viewer.activate(options: []) else { throw OutputSafetyError.targetChanged }
        try await waitForActivation(viewer, allowedPrevious: current.processIdentifier)
        try validate(target, text: text)
    }
    private func waitForActivation(_ app: NSRunningApplication, allowedPrevious: pid_t) async throws {
        for _ in 0..<100 {
            try Task.checkCancellation()
            let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if pid == app.processIdentifier { return }
            guard pid == allowedPrevious else { throw OutputSafetyError.targetChanged }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw OutputSafetyError.remoteClipboardUnavailable
    }
    private func validate(_ target: Target, text: String) throws {
        try OutputSafety.validate(targetPID: target.pid,
                                  currentPID: NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1,
                                  secure: isSecure(target.element), terminal: target.terminal, text: text)
        if let title = target.remoteWindowTitle {
            guard let current = focusedWindow(target.pid), CFEqual(current, target.element),
                  attribute(current, kAXTitleAttribute) as? String == title, !hasSheet(current) else {
                throw OutputSafetyError.targetChanged
            }
            if let focused = focusedElement(target.pid), !CFEqual(focused, current) {
                throw OutputSafetyError.targetChanged
            }
        } else {
            guard let current = focusedElement(target.pid), CFEqual(current, target.element) else { throw OutputSafetyError.targetChanged }
        }
    }
    private func focusedWindow(_ pid: pid_t) -> AXUIElement? {
        guard let value = attribute(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private func hasSheet(_ window: AXUIElement) -> Bool {
        (attribute(window, kAXChildrenAttribute) as? [AXUIElement] ?? []).contains {
            attribute($0, kAXRoleAttribute) as? String == kAXSheetRole
        }
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
    private func snapshot(_ element: AXUIElement) -> EditableTextSnapshot? {
        guard let text = attribute(element, kAXValueAttribute) as? String else { return nil }
        var range = CFRange()
        guard let value = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID(),
              AXValueGetValue(value as! AXValue, .cfRange, &range) else { return .init(text: text, selection: nil) }
        return .init(text: text, selection: NSRange(location: range.location, length: range.length))
    }
    private func isWebEditor(_ element: AXUIElement) -> Bool {
        var current: AXUIElement? = element
        for _ in 0..<32 {
            guard let node = current else { return false }
            if (attribute(node, kAXRoleAttribute) as? String) == "AXWebArea" { return true }
            guard let parent = attribute(node, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return false }
            current = (parent as! AXUIElement)
        }
        return false
    }
    private func publishPasteboard(_ text: String, provider: RequestedPasteboardText? = nil) throws -> () -> Void {
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
        let item = NSPasteboardItem()
        if let provider { item.setDataProvider(provider, forTypes: [.string]) }
        else { item.setString(text, forType: .string) }
        item.setString(token, forType: marker)
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
        return {
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
    }
    private func postPaste(into target: Target, text: String) throws {
        try validate(target, text: text)
        let events = try PasteKeyboardEvents.make(remoteShortcut: target.remoteShortcut)
        // Route through normal keyboard delivery so web/Electron editors receive
        // the paste command and input events, rather than a process-only event.
        for event in events { event.post(tap: .cghidEventTap) }
    }
}
