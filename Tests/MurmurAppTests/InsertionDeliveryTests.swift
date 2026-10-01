import Foundation
import Testing
import MurmurCore
@testable import Murmur

@Test func recognizedWordsWithoutAnyDeliveryAreNotReportedInserted() {
    var summary = InsertionDeliverySummary()
    #expect(summary.status(hasWords: true, hasPartial: true) == "Transcript ready")
    #expect(summary.status(hasWords: true, hasPartial: false) == "Transcript ready")
    summary.record(.verified)
    #expect(summary.status(hasWords: true, hasPartial: true) == "Some words inserted")
    #expect(summary.status(hasWords: true, hasPartial: false) == "Inserted")
    summary.record(.sent)
    #expect(summary.status(hasWords: true, hasPartial: false) == "Paste sent · check app")
}

@Test @MainActor func acceptedWriteWithoutTextChangeFallsBackToPaste() async throws {
    var current = EditableTextSnapshot(text: "", selection: NSRange(location: 0, length: 0))
    var pasteCount = 0
    let result = try await InsertionDelivery.deliver("One, two, three, four.", prefersPaste: false,
        read: { current }, validate: {}, direct: { _ in true }, paste: { text in
            pasteCount += 1
            current = .init(text: text, selection: NSRange(location: (text as NSString).length, length: 0))
        }, pause: {})
    #expect(result == .verified)
    #expect(pasteCount == 1)
    #expect(current.text == "One, two, three, four.")
}

@Test @MainActor func confirmedNativeWriteIsNotPastedTwice() async throws {
    var current = EditableTextSnapshot(text: "alpha beta", selection: NSRange(location: 5, length: 0))
    var pasteCount = 0
    let result = try await InsertionDelivery.deliver("words", prefersPaste: false,
        read: { current }, validate: {}, direct: { text in
            #expect(text == " words")
            current = .init(text: "alpha words beta", selection: NSRange(location: 11, length: 0))
            return true
        }, paste: { _ in pasteCount += 1 }, pause: {})
    #expect(result == .verified)
    #expect(pasteCount == 0)
}

@Test @MainActor func webEditorUsesPasteAndConfirmsInsertionAtUnicodeSelection() async throws {
    var current = EditableTextSnapshot(text: "🐼 old tail", selection: NSRange(location: 3, length: 3))
    var directCount = 0
    let result = try await InsertionDelivery.deliver("new", prefersPaste: true,
        read: { current }, validate: {}, direct: { _ in directCount += 1; return true }, paste: { text in
            #expect(text == "new")
            current = .init(text: "🐼 new tail", selection: NSRange(location: 6, length: 0))
        }, pause: {})
    #expect(result == .verified)
    #expect(directCount == 0)
}

@Test @MainActor func pasteWithNoObservedChangeNeverReportsInserted() async {
    let unchanged = EditableTextSnapshot(text: "", selection: NSRange(location: 0, length: 0))
    do {
        _ = try await InsertionDelivery.deliver("Words", prefersPaste: true,
            read: { unchanged }, validate: {}, direct: { _ in false }, paste: { _ in }, pause: {})
        Issue.record("A no-op paste must not report successful insertion")
    } catch { #expect(error as? OutputSafetyError == .insertionNotConfirmed) }
}

@Test @MainActor func unexpectedFieldChangeDoesNotCauseDuplicatePaste() async {
    var current = EditableTextSnapshot(text: "Start", selection: NSRange(location: 5, length: 0))
    var pasteCount = 0
    do {
        _ = try await InsertionDelivery.deliver("words", prefersPaste: false,
            read: { current }, validate: {}, direct: { _ in
                current = .init(text: "Changed by the app", selection: NSRange(location: 18, length: 0))
                return true
            }, paste: { _ in pasteCount += 1 }, pause: {})
        Issue.record("An unexpected edit needs recovery rather than a second write")
    } catch { #expect(error as? OutputSafetyError == .insertionNotConfirmed) }
    #expect(pasteCount == 0)
}

@Test @MainActor func fieldChangeDuringWaitStopsPasteFallback() async {
    let original = EditableTextSnapshot(text: "", selection: NSRange(location: 0, length: 0))
    var validations = 0, pasteCount = 0
    do {
        _ = try await InsertionDelivery.deliver("Words", prefersPaste: false,
            read: { original }, validate: {
                validations += 1
                if validations > 1 { throw OutputSafetyError.targetChanged }
            }, direct: { _ in true }, paste: { _ in pasteCount += 1 }, pause: {})
        Issue.record("Changing focus must stop output")
    } catch { #expect(error as? OutputSafetyError == .targetChanged) }
    #expect(pasteCount == 0)
}

@Test @MainActor func unreadableEditorReportsSentWithoutClaimingVerification() async throws {
    var pasteCount = 0
    var waits = 0
    let result = try await InsertionDelivery.deliver("Words", prefersPaste: true,
        read: { nil }, validate: {}, direct: { _ in Issue.record("Do not write blindly through AX"); return true },
        paste: { _ in pasteCount += 1 }, pause: { waits += 1 })
    #expect(result == .sent)
    #expect(pasteCount == 1)
    #expect(waits == 0)
}
