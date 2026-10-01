import AppKit
import Carbon
import MurmurCore

@MainActor final class HotkeyManager {
    private let model: AppModel
    private let registry = ShortcutRegistry()
    private var references: [EventHotKeyRef] = []
    private var escape: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var monitor: Any?
    private var gate = HotkeyPressGate()
    init(model: AppModel) {
        self.model = model
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard identifier.signature == 0x4D55524D else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { manager.received(identifier.id, released: GetEventKind(event) == UInt32(kEventHotKeyReleased)) }
            return noErr
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.record(event) ?? false }
            return consumed ? nil : event
        }
        model.rebindShortcuts = { [weak self] bindings in try self?.rebind(bindings) }
        model.updateCaptureHotkey = { [weak self] active in self?.setCaptureActive(active) }
        model.shortcutRecordingChanged = { [weak self] active in self?.setRecording(active) }
        do { try rebind(model.preferences.shortcuts) } catch { model.shortcutError = error.localizedDescription }
    }
    private func setRecording(_ active: Bool) {
        if active { model.releaseHeldQuickTalk() }
        gate.reset()
        if active {
            references.forEach { UnregisterEventHotKey($0) }; references.removeAll()
            setCaptureActive(false)
        } else if references.isEmpty {
            do { try rebind(model.preferences.shortcuts) }
            catch { model.shortcutError = error.localizedDescription }
            setCaptureActive(model.dictation.isActive)
        }
    }
    private func rebind(_ bindings: [ShortcutAction: ShortcutBinding]) throws {
        model.releaseHeldQuickTalk()
        gate.reset()
        try registry.rebind(bindings, register: { action, binding in
            var reference: EventHotKeyRef?
            let index = UInt32(ShortcutAction.allCases.firstIndex(of: action)!)
            let status = RegisterEventHotKey(binding.keyCode, binding.modifiers,
                EventHotKeyID(signature: 0x4D55524D, id: index), GetApplicationEventTarget(), 0, &reference)
            if status == noErr, let reference { self.references.append(reference); return true }
            return false
        }, unregister: {
            self.references.forEach { UnregisterEventHotKey($0) }; self.references.removeAll()
        })
    }
    private func setCaptureActive(_ active: Bool) {
        if !active, let escape { UnregisterEventHotKey(escape); self.escape = nil }
        if active, escape == nil {
            var reference: EventHotKeyRef?
            if RegisterEventHotKey(53, 0, EventHotKeyID(signature: 0x4D55524D, id: 99), GetApplicationEventTarget(), 0, &reference) == noErr {
                escape = reference
            }
        }
    }
    private func received(_ id: UInt32, released: Bool) {
        if released {
            if gate.release(id), id == 0 { model.releaseHeldQuickTalk() }
            return
        }
        guard model.recordingShortcut == nil, gate.press(id) else { return }
        switch id {
        case 0: model.beginHeldQuickTalk()
        case 1: model.toggleDictation(.keepTalking)
        case 2: if model.barVisible { model.closeBar() } else { model.showBar() }
        case 99: model.cancelDictation()
        default: break
        }
    }
    private func record(_ event: NSEvent) -> Bool {
        guard let action = model.recordingShortcut else { return false }
        if event.keyCode == 53 { model.recordingShortcut = nil; return true }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0, label = ""
        for (flag, value, symbol) in [(NSEvent.ModifierFlags.control, UInt32(controlKey), "⌃"),
                                     (.option, UInt32(optionKey), "⌥"), (.shift, UInt32(shiftKey), "⇧"),
                                     (.command, UInt32(cmdKey), "⌘")] {
            if flags.contains(flag) { modifiers |= value; label += symbol }
        }
        let key = [49: "Space", 123: "←", 124: "→", 125: "↓", 126: "↑" ][Int(event.keyCode)]
            ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        model.assignShortcut(action, binding: .init(keyCode: UInt32(event.keyCode), modifiers: modifiers, label: label + key))
        if model.recordingShortcut != nil { setRecording(true) }
        return true
    }
}
