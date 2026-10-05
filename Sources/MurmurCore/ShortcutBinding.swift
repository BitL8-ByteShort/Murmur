import Foundation

public enum ShortcutAction: String, Codable, CaseIterable, Sendable, Identifiable {
    case quickTalk, keepTalking, toggleBar
    public var id: String { rawValue }
    public var title: String {
        switch self { case .quickTalk: "Quick Talk"; case .keepTalking: "Keep Talking"; case .toggleBar: "Show / hide bar" }
    }
}
public struct ShortcutBinding: Codable, Equatable, Hashable, Sendable {
    public let keyCode: UInt32
    public let modifiers: UInt32
    public let label: String
    public init(keyCode: UInt32, modifiers: UInt32, label: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.label = label
    }
    public static let defaults: [ShortcutAction: ShortcutBinding] = [
        .quickTalk: .init(keyCode: 49, modifiers: 6144, label: "⌃⌥Space"),
        .keepTalking: .init(keyCode: 2, modifiers: 6144, label: "⌃⌥D"),
        .toggleBar: .init(keyCode: 11, modifiers: 6144, label: "⌃⌥B")
    ]
}
public enum ShortcutError: LocalizedError, Equatable {
    case duplicate, modifierRequired, incomplete, registrationFailed(String)
    public var errorDescription: String? {
        switch self {
        case .duplicate: "That shortcut belongs to another Murmur action."
        case .modifierRequired: "Include Command or Control in the shortcut. Escape cancels recording."
        case .incomplete: "Each action needs a shortcut."
        case .registrationFailed(let label): "\(label) is already in use. Your previous shortcuts are retained."
        }
    }
}
public enum ShortcutValidation {
    public static func validate(_ bindings: [ShortcutAction: ShortcutBinding]) throws {
        guard bindings.count == ShortcutAction.allCases.count else { throw ShortcutError.incomplete }
        var seen: Set<String> = []
        for binding in bindings.values {
            guard binding.modifiers & (256 | 4096) != 0 else { throw ShortcutError.modifierRequired }
            guard seen.insert("\(binding.keyCode):\(binding.modifiers)").inserted else { throw ShortcutError.duplicate }
        }
    }
}
public struct HotkeyPressGate: Sendable {
    private var held: Set<UInt32> = []
    public init() {}
    public mutating func press(_ id: UInt32) -> Bool { held.insert(id).inserted }
    @discardableResult public mutating func release(_ id: UInt32) -> Bool { held.remove(id) != nil }
    public mutating func reset() { held.removeAll() }
}
@MainActor public final class ShortcutRegistry {
    public private(set) var bindings: [ShortcutAction: ShortcutBinding] = [:]
    public init() {}
    public func rebind(_ desired: [ShortcutAction: ShortcutBinding],
                       register: (ShortcutAction, ShortcutBinding) -> Bool, unregister: () -> Void) throws {
        try ShortcutValidation.validate(desired)
        let old = bindings
        unregister()
        for action in ShortcutAction.allCases {
            guard let binding = desired[action] else { continue }
            if !register(action, binding) {
                unregister()
                for previous in ShortcutAction.allCases {
                    if let binding = old[previous] { _ = register(previous, binding) }
                }
                throw ShortcutError.registrationFailed(binding.label)
            }
        }
        bindings = desired
    }
}
