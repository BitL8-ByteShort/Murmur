import Foundation
import Testing
@testable import MurmurCore

@Test func retryRetainsPreviousWordsWithoutDuplicatingOneSession() {
    var recovery = RecoveryBuffer()
    let first = UUID(), next = UUID(), date = Date(timeIntervalSince1970: 10)
    recovery.save(sessionID: first, text: "  Keep my code: let x = 42\n", createdAt: date)
    recovery.save(sessionID: next, text: "A new attempt", createdAt: date)
    recovery.save(sessionID: first, text: "  Keep my code: let x = 42\nMore words", createdAt: date)
    #expect(recovery.entries.count == 2)
    #expect(recovery.entries.first?.text == "  Keep my code: let x = 42\nMore words")
    #expect(recovery.entries.last?.id == next)
    recovery.save(sessionID: UUID(), text: "\n ", createdAt: date)
    #expect(recovery.entries.count == 2)
    recovery.clear()
    #expect(recovery.entries.isEmpty)
}
