import Foundation

public enum SpeechEngine: String, Codable, CaseIterable, Sendable, Identifiable {
    case apple, parakeet, moonshine, whisper
    public var id: String { rawValue }
    public var title: String {
        switch self { case .apple: "Apple Speech"; case .parakeet: "Parakeet Realtime";
        case .moonshine: "Moonshine Small"; case .whisper: "Whisper Turbo" }
    }
}
public struct AudioPacket: Sendable {
    public let sessionID: UUID
    public let samples: [Float]
    public let sampleRate: Double
    public init(sessionID: UUID, samples: [Float], sampleRate: Double = 16_000) {
        self.sessionID = sessionID; self.samples = samples; self.sampleRate = sampleRate
    }
}
public struct Utterance: Sendable, Equatable {
    public let sessionID: UUID
    public let id: UUID
    public let revision: Int
    public let text: String
    public let isFinal: Bool
    public init(sessionID: UUID, id: UUID, revision: Int, text: String, isFinal: Bool) {
        self.sessionID = sessionID; self.id = id; self.revision = revision; self.text = text; self.isFinal = isFinal
    }
}
public enum SpeechEvent: Sendable {
    case status(String), utterance(Utterance), activity(Bool), failed(String)
}
public protocol SpeechBackend: Actor {
    func prepare(sessionID: UUID, locale: String, report: @escaping @Sendable (SpeechEvent) -> Void) async throws
    func accept(_ packet: AudioPacket) async throws
    func flush() async throws
    func finish() async throws
    func suspend() async
    func unload() async
}
public enum SpeechFailure: LocalizedError {
    case unavailable(String)
    public var errorDescription: String? {
        if case .unavailable(let message) = self { return message }; return nil
    }
}
