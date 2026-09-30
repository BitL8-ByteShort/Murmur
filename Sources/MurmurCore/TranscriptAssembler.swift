import Foundation

public struct TranscriptAssembler: Sendable {
    private var sessionID: UUID
    private var revisions: [UUID: Int] = [:]
    private var partials: [UUID: String] = [:]
    private var order: [UUID] = []
    private var committed: Set<UUID> = []
    public init(sessionID: UUID) { self.sessionID = sessionID }
    public var partialText: String { order.compactMap { partials[$0] }.joined(separator: " ") }
    public mutating func reset(sessionID: UUID) { self = .init(sessionID: sessionID) }
    public mutating func update(_ utterance: Utterance) -> String? {
        guard utterance.sessionID == sessionID, !committed.contains(utterance.id),
              utterance.revision >= (revisions[utterance.id] ?? -1) else { return nil }
        let text = utterance.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !utterance.isFinal || !text.isEmpty else { return nil }
        if revisions[utterance.id] == nil { order.append(utterance.id) }
        revisions[utterance.id] = utterance.revision
        if utterance.isFinal {
            committed.insert(utterance.id); partials.removeValue(forKey: utterance.id)
            return text.isEmpty ? nil : text
        }
        if text.isEmpty { partials.removeValue(forKey: utterance.id) }
        else { partials[utterance.id] = text }
        return nil
    }
}
