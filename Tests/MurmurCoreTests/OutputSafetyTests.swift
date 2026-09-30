import Foundation
import Testing
@testable import MurmurCore

@Test func clipboardLeaseDoesNotOverwriteNewUserCopies() {
    let lease = ClipboardLease(changeCount: 8, token: "murmur-operation")
    #expect(lease.owns(changeCount: 8, token: "murmur-operation"))
    #expect(!lease.owns(changeCount: 9, token: "murmur-operation"))
    #expect(!lease.owns(changeCount: 8, token: "another-copy"))
}

@Test func targetChangeSecureFieldsAndTerminalNewlinesRefuseInsertion() throws {
    try OutputSafety.validate(targetPID: 7, currentPID: 7, secure: false, terminal: false, text: "hello")
    #expect(throws: OutputSafetyError.targetChanged) {
        try OutputSafety.validate(targetPID: 7, currentPID: 8, secure: false, terminal: false, text: "hello")
    }
    #expect(throws: OutputSafetyError.secureField) {
        try OutputSafety.validate(targetPID: 7, currentPID: 7, secure: true, terminal: false, text: "hello")
    }
    #expect(throws: OutputSafetyError.terminalNewline) {
        try OutputSafety.validate(targetPID: 7, currentPID: 7, secure: false, terminal: true, text: "hello\nworld")
    }
}

@Test func insertionSpacingPreservesWordsAroundTheCaret() {
    #expect(InsertionSpacing.text("beautiful", before: "hello", after: "world") == " beautiful ")
    #expect(InsertionSpacing.text(",", before: "hello", after: "") == ",")
    #expect(InsertionSpacing.text("hello", before: "", after: "") == "hello")
    #expect(InsertionSpacing.text("hello", before: "\n", after: ".") == "hello")
}
