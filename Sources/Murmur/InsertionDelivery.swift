import Foundation
import MurmurCore

enum TextInsertionResult: Equatable { case verified, sent }

struct InsertionDeliverySummary {
    private var verifiedCount = 0
    private var sentCount = 0
    mutating func record(_ result: TextInsertionResult) {
        if result == .verified { verifiedCount += 1 }
        else { sentCount += 1 }
    }
    func status(hasWords: Bool, hasPartial: Bool) -> String {
        guard hasWords else { return "No speech detected" }
        if sentCount > 0 { return "Paste sent · check app" }
        if verifiedCount > 0 { return hasPartial ? "Some words inserted" : "Inserted" }
        return "Transcript ready"
    }
}

struct EditableTextSnapshot: Equatable {
    let text: String
    let selection: NSRange?

    var validSelection: NSRange? {
        guard let selection, selection.location >= 0, selection.length >= 0 else { return nil }
        let length = (text as NSString).length
        guard selection.location <= length, selection.length <= length - selection.location else { return nil }
        return selection
    }
    func spaced(_ words: String) -> String {
        guard let range = validSelection else { return words }
        let value = text as NSString
        return InsertionSpacing.text(words, before: value.substring(to: range.location),
            after: value.substring(from: range.location + range.length))
    }
    func replacingSelection(with words: String) -> String? {
        guard let range = validSelection else { return nil }
        return (text as NSString).replacingCharacters(in: range, with: words)
    }
}

@MainActor enum InsertionDelivery {
    static func deliver(_ words: String, prefersPaste: Bool,
        read: () -> EditableTextSnapshot?, validate: () throws -> Void,
        direct: (String) throws -> Bool, paste: (String) async throws -> Void,
        unconfirmedWaits: Int = 25,
        pause: () async -> Void = { try? await Task.sleep(for: .milliseconds(40)) }
    ) async throws -> TextInsertionResult {
        try Task.checkCancellation()
        try validate()
        let before = read()
        let output = before?.spaced(words) ?? words
        let expected = before?.replacingSelection(with: output)
        func confirmed(_ after: EditableTextSnapshot?) -> Bool {
            guard let before, let after, let expected, after.text == expected else { return false }
            if expected != before.text { return true }
            // Replacing selected words with themselves changes only the caret.
            guard let range = before.validSelection, let caret = after.validSelection else { return false }
            return caret == NSRange(location: range.location + (output as NSString).length, length: 0)
                && caret != range
        }
        func observe(attempts: Int) async throws -> Bool {
            for _ in 0..<attempts {
                try Task.checkCancellation()
                try validate()
                let after = read()
                if confirmed(after) { return true }
                if let after, let before, after != before { throw OutputSafetyError.insertionNotConfirmed }
                await pause()
            }
            try Task.checkCancellation()
            try validate()
            let after = read()
            if confirmed(after) { return true }
            // Only an unchanged field can be retried without risking duplication.
            guard after == before else { throw OutputSafetyError.insertionNotConfirmed }
            return false
        }
        if !prefersPaste, expected != nil {
            let accepted = try direct(output)
            if try await observe(attempts: accepted ? 6 : 0) { return .verified }
        }
        try Task.checkCancellation()
        try validate()
        guard read() == before else { throw OutputSafetyError.targetChanged }
        try await paste(output)
        if expected != nil {
            guard try await observe(attempts: 50) else { throw OutputSafetyError.insertionNotConfirmed }
            return .verified
        }
        // Unreadable editors still receive ordinary paste. Keep the clipboard
        // available while they consume it, but never claim a verified insertion.
        for _ in 0..<max(0, unconfirmedWaits) {
            try Task.checkCancellation()
            try validate()
            await pause()
        }
        return .sent
    }
}
