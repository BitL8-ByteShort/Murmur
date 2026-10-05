import Foundation
import MurmurCore

@MainActor enum RemoteClipboardHandoff {
    static func deliver(refresh: () async throws -> Void, requested: () -> Bool,
                        validate: () throws -> Void, paste: () throws -> Void,
                        attempts: Int = 150,
                        pause: () async throws -> Void = { try await Task.sleep(for: .milliseconds(10)) }) async throws {
        try validate()
        try Task.checkCancellation()
        try await refresh()
        try Task.checkCancellation()
        try validate()
        try paste()
        for _ in 0..<max(0, attempts) {
            try Task.checkCancellation()
            try validate()
            if requested() { return }
            try await pause()
        }
        try Task.checkCancellation()
        try validate()
        guard requested() else { throw OutputSafetyError.remoteClipboardUnavailable }
    }
}
