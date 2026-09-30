import Testing
@testable import MurmurCore

@Test func shortcutConflictsAndBareLettersAreRejected() throws {
    try ShortcutValidation.validate(ShortcutBinding.defaults)
    var bindings = ShortcutBinding.defaults
    bindings[.keepTalking] = bindings[.quickTalk]
    #expect(throws: ShortcutError.duplicate) { try ShortcutValidation.validate(bindings) }
    bindings = ShortcutBinding.defaults
    bindings[.quickTalk] = .init(keyCode: 0, modifiers: 0, label: "A")
    #expect(throws: ShortcutError.modifierRequired) { try ShortcutValidation.validate(bindings) }
}

@Test func hotkeyRepeatCannotStartAnotherSessionUntilRelease() {
    var gate = HotkeyPressGate()
    let first = gate.press(0)
    let repeated = gate.press(0)
    #expect(first)
    #expect(!repeated)
    gate.release(0)
    let next = gate.press(0)
    #expect(next)
}

@Test @MainActor func failedRebindingRetainsPreviouslyWorkingBindings() throws {
    let registry = ShortcutRegistry()
    var installed: [ShortcutAction: ShortcutBinding] = [:]
    let register: (ShortcutAction, ShortcutBinding) -> Bool = { action, binding in
        if binding.keyCode == 999 { return false }
        installed[action] = binding; return true
    }
    try registry.rebind(ShortcutBinding.defaults, register: register, unregister: { installed.removeAll() })
    var replacement = ShortcutBinding.defaults
    replacement[.keepTalking] = .init(keyCode: 999, modifiers: 6144, label: "bad")
    #expect(throws: (any Error).self) {
        try registry.rebind(replacement, register: register, unregister: { installed.removeAll() })
    }
    #expect(registry.bindings == ShortcutBinding.defaults)
    #expect(installed == ShortcutBinding.defaults)
}
