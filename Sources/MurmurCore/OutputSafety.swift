import Foundation

public enum OutputSafetyError: Error, LocalizedError, Equatable {
    case targetChanged, secureField, terminalNewline, permissionRequired, noEditableField, clipboardUnavailable
    public var errorDescription: String? {
        switch self {
        case .targetChanged: "The destination changed. Your words are saved in Murmur for copying."
        case .secureField: "Murmur won't type into a password field. Your words are saved for copying."
        case .terminalNewline: "Multiline text is kept for copying when the destination is a terminal."
        case .permissionRequired: "Allow Murmur in Accessibility to dictate into other apps. Your words are saved for copying."
        case .noEditableField: "Choose a text field in another app before starting. Your words are saved for copying."
        case .clipboardUnavailable: "The clipboard couldn't be preserved. Your words are saved for copying."
        }
    }
}

public struct ClipboardLease: Sendable {
    public let changeCount: Int
    public let token: String
    public init(changeCount: Int, token: String) { self.changeCount = changeCount; self.token = token }
    public func owns(changeCount: Int, token: String?) -> Bool { self.changeCount == changeCount && self.token == token }
}

public enum OutputSafety {
    public static func validate(targetPID: Int32, currentPID: Int32, secure: Bool, terminal: Bool, text: String) throws {
        guard targetPID == currentPID else { throw OutputSafetyError.targetChanged }
        guard !secure else { throw OutputSafetyError.secureField }
        if terminal && text.contains(where: { $0.isNewline }) { throw OutputSafetyError.terminalNewline }
    }
}

public enum InsertionSpacing {
    public static func text(_ text: String, before: String, after: String) -> String {
        func word(_ character: Character?) -> Bool {
            guard let character else { return false }
            return character.isLetter || character.isNumber
        }
        let prefix = word(before.last) && word(text.first) ? " " : ""
        let suffix = word(text.last) && word(after.first) ? " " : ""
        return prefix + text + suffix
    }
}
