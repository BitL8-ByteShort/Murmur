import Foundation

public enum CaptureMode: String, Sendable { case quickTalk, keepTalking }
public enum SessionPhase: String, Sendable {
    case idle, preparing, listening, finalizing, inserting, success, failed
    public var isActive: Bool {
        [.preparing, .listening, .finalizing, .inserting].contains(self)
    }
}

/// Foundation for the future recognizer coordinator. No microphone or insertion side effects.
public struct SessionState: Sendable {
    public private(set) var id = UUID()
    public private(set) var mode: CaptureMode = .quickTalk
    public private(set) var phase: SessionPhase = .idle
    public init() {}

    @discardableResult public mutating func begin(_ mode: CaptureMode) -> UUID {
        id = UUID(); self.mode = mode; phase = .preparing
        return id
    }
    public mutating func prepared(sessionID: UUID) {
        guard sessionID == id, phase == .preparing else { return }
        phase = .listening
    }
    public mutating func endpoint(sessionID: UUID) {
        guard sessionID == id, phase == .listening else { return }
        phase = .finalizing
    }
    public mutating func finalized(sessionID: UUID) {
        guard sessionID == id, phase == .finalizing else { return }
        phase = .inserting
    }
    public mutating func inserted(sessionID: UUID) {
        guard sessionID == id, phase == .inserting else { return }
        phase = mode == .keepTalking ? .listening : .success
    }
    public mutating func fail(sessionID: UUID) {
        guard sessionID == id, phase.isActive else { return }
        phase = .failed
    }
    public mutating func cancel() { id = UUID(); phase = .idle }
}

public enum OverlayPolicy {
    public static func isVisible(pinned: Bool, manuallyOpened: Bool, phase: SessionPhase) -> Bool {
        pinned || manuallyOpened || phase.isActive
    }
}
