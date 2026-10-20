import Foundation
import Testing
import MurmurCore
@testable import Murmur

@Test @MainActor func readyEditorNeedsNoAccessibilityRequestOrDelay() async throws {
    let value: String = try await FocusedDestinationResolver.resolve(read: { "field" },
        requestAccessibility: { Issue.record("Already available"); return true }, validate: {},
        pause: { _ in Issue.record("No delay for a ready editor") })
    #expect(value == "field")
}

@Test @MainActor func coldEditorRequestsAccessibilityAndWaitsForItsFocusedField() async throws {
    var requested = false, reads = 0, waits = 0
    let value: String = try await FocusedDestinationResolver.resolve(read: {
        reads += 1
        return requested && waits == 2 ? "composer" : nil
    }, requestAccessibility: { requested = true; return true }, validate: {}, pause: { _ in waits += 1 })
    #expect(value == "composer")
    #expect(reads == 3)
    #expect(waits == 2)
}

@Test @MainActor func unsupportedAccessibilityFailsWithoutWaiting() async {
    var requests = 0
    do {
        let _: String = try await FocusedDestinationResolver.resolve(read: { nil },
            requestAccessibility: { requests += 1; return false }, validate: {},
            pause: { _ in Issue.record("An unsupported app should not wait") })
        Issue.record("No focused editor")
    } catch { #expect(error as? OutputSafetyError == .noEditableField) }
    #expect(requests == 1)
}

@Test @MainActor func coldEditorRetryIsBounded() async {
    var requests = 0, waits = 0
    do {
        let _: String = try await FocusedDestinationResolver.resolve(read: { nil },
            requestAccessibility: { requests += 1; return true }, validate: {}, pause: { _ in waits += 1 })
        Issue.record("Do not accept an app without a focused editor")
    } catch { #expect(error as? OutputSafetyError == .noEditableField) }
    #expect(requests == 1)
    #expect(waits == 4)
}

@Test @MainActor func switchingDestinationDuringTreeStartupStopsCapture() async {
    var changed = false, reads = 0
    do {
        let _: String = try await FocusedDestinationResolver.resolve(read: { reads += 1; return nil },
            requestAccessibility: { true }, validate: { if changed { throw OutputSafetyError.targetChanged } },
            pause: { _ in changed = true })
        Issue.record("Never resolve a replacement app/window")
    } catch { #expect(error as? OutputSafetyError == .targetChanged) }
    #expect(reads == 1)
}

@Test @MainActor func secureEditorDoesNotRequestOrRetryAccessibility() async {
    do {
        let _: String = try await FocusedDestinationResolver.resolve(read: { throw OutputSafetyError.secureField },
            requestAccessibility: { Issue.record("Never retry a password field"); return true }, validate: {},
            pause: { _ in Issue.record("No retry") })
        Issue.record("Must refuse password fields")
    } catch { #expect(error as? OutputSafetyError == .secureField) }
}

@Test @MainActor func cancellationDuringEditorStartupNeverReadsAnotherField() async {
    var reads = 0
    do {
        let _: String = try await FocusedDestinationResolver.resolve(read: { reads += 1; return nil },
            requestAccessibility: { true }, validate: {}, pause: { _ in throw CancellationError() })
        Issue.record("Must propagate cancellation")
    } catch { #expect(error is CancellationError) }
    #expect(reads == 1)
}
