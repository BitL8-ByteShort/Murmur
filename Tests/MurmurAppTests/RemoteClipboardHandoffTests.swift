import Testing
import MurmurCore
@testable import Murmur

@Test @MainActor func remotePasteRefreshesViewerBeforeKeysAndCompletesOnClipboardRead() async throws {
    var actions: [String] = []
    var requested = false
    try await RemoteClipboardHandoff.deliver(refresh: { actions.append("refresh") }, requested: { requested },
        validate: {}, paste: { actions.append("paste") }, pause: { actions.append("read"); requested = true })
    #expect(actions == ["refresh", "paste", "read"])
}

@Test @MainActor func remotePasteStopsIfFocusChangesDuringClipboardRefresh() async {
    var changed = false, pastes = 0
    do {
        try await RemoteClipboardHandoff.deliver(refresh: { changed = true }, requested: { true },
            validate: { if changed { throw OutputSafetyError.targetChanged } }, paste: { pastes += 1 }, pause: {})
        Issue.record("Do not paste after focus changes")
    } catch { #expect(error as? OutputSafetyError == .targetChanged) }
    #expect(pastes == 0)
}

@Test @MainActor func remoteClipboardTimeoutNeverRetriesPaste() async {
    var pastes = 0, waits = 0
    do {
        try await RemoteClipboardHandoff.deliver(refresh: {}, requested: { false }, validate: {},
            paste: { pastes += 1 }, attempts: 3, pause: { waits += 1 })
        Issue.record("An unread clipboard must retain the transcript for recovery")
    } catch { #expect(error as? OutputSafetyError == .remoteClipboardUnavailable) }
    #expect(pastes == 1)
    #expect(waits == 3)
}
