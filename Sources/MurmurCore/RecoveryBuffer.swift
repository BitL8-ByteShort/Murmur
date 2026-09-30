import Foundation

/// Session recovery lives only in memory, until the user clears it or quits.
public struct RecoveryEntry: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let createdAt: Date
    public let text: String
}

public struct RecoveryBuffer: Sendable {
    public private(set) var entries: [RecoveryEntry] = []
    public init() {}
    public mutating func save(sessionID: UUID, text: String, createdAt: Date) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let entry = RecoveryEntry(id: sessionID, createdAt: createdAt, text: text)
        if let index = entries.firstIndex(where: { $0.id == sessionID }) { entries[index] = entry }
        else { entries.append(entry) }
    }
    public mutating func clear() { entries.removeAll() }
}
