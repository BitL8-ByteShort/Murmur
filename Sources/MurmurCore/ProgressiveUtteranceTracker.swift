import Foundation

/// Streaming revisions replace one provisional passage even when its timestamps move.
public struct ProgressiveUtteranceTracker: Sendable {
    private let sessionID: UUID
    private var activeID = UUID()
    private var revision = 0
    private var finalStarts: Set<Int64> = []
    private var finalEnding: Character?
    public init(sessionID: UUID) { self.sessionID = sessionID }

    public mutating func update(text: String, start: Double, isFinal: Bool) -> Utterance? {
        guard start.isFinite, start >= 0, start < Double(Int64.max) / 1000 else { return nil }
        if isFinal, !finalStarts.insert(Int64((start * 1000).rounded())).inserted { return nil }
        revision += 1
        var passage = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Finalizing a pause can make Apple repeat the previous sentence's
        // punctuation as its own result or as the next passage's prefix.
        if let finalEnding, ".!?。！？".contains(finalEnding), passage.first == finalEnding {
            let remainder = passage.dropFirst()
            if remainder.isEmpty || remainder.first?.isWhitespace == true {
                passage = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // Apple's empty result explicitly revokes provisional recognition. Other
        // adapters' empty finals retain uncertain words, so express this as a revision.
        let revoked = passage.isEmpty
        let result = Utterance(sessionID: sessionID, id: activeID, revision: revision, text: passage, isFinal: isFinal && !revoked)
        if isFinal && !revoked { finalEnding = passage.last }
        if isFinal { activeID = UUID(); revision = 0 }
        return result
    }
}
