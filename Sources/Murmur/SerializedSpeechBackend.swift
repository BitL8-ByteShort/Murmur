import Foundation
import MurmurCore

/// Actor reentrancy must not let a pause reset model state during an audio decode.
actor SerializedSpeechBackend: SpeechBackend {
    private let base: any SpeechBackend
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(_ base: any SpeechBackend) { self.base = base }
    private func perform(_ action: @Sendable () async throws -> Void) async throws {
        if busy { await withCheckedContinuation { waiters.append($0) } }
        else { busy = true }
        defer {
            if waiters.isEmpty { busy = false }
            else { waiters.removeFirst().resume() }
        }
        try Task.checkCancellation()
        try await action()
    }
    func prepare(sessionID: UUID, locale: String, report: @escaping @Sendable (SpeechEvent) -> Void) async throws {
        try await perform { try await self.base.prepare(sessionID: sessionID, locale: locale, report: report) }
    }
    func accept(_ packet: AudioPacket) async throws { try await perform { try await self.base.accept(packet) } }
    func flush() async throws { try await perform { try await self.base.flush() } }
    func finish() async throws { try await perform { try await self.base.finish() } }
    func suspend() async { try? await perform { await self.base.suspend() } }
    func unload() async { try? await perform { await self.base.unload() } }
}
