import Foundation

public enum EndpointDecision: Sendable, Equatable {
    case continueListening, finalizeUtterance, noSpeechTimeout, inactivityTimeout
}
public struct EndpointPolicy: Sendable {
    private let mode: CaptureMode
    private let silenceSeconds: Double
    private let inactivitySeconds: Double
    private let finishQuickTalkOnPause: Bool
    private var lastSpeech: Double?
    private var pendingSpeech = false
    private var ended = false
    public init(mode: CaptureMode, silenceSeconds: Double, inactivitySeconds: Double, finishQuickTalkOnPause: Bool = true) {
        self.mode = mode
        self.silenceSeconds = min(3, max(0.7, silenceSeconds))
        self.inactivitySeconds = inactivitySeconds
        self.finishQuickTalkOnPause = finishQuickTalkOnPause
    }
    public mutating func update(speechDetected: Bool, elapsedSeconds: Double) -> EndpointDecision {
        guard !ended else { return .continueListening }
        if speechDetected { lastSpeech = elapsedSeconds; pendingSpeech = true; return .continueListening }
        if (mode != .quickTalk || finishQuickTalkOnPause),
           let lastSpeech, pendingSpeech, elapsedSeconds - lastSpeech >= silenceSeconds {
            pendingSpeech = false
            if mode == .quickTalk { ended = true }
            return .finalizeUtterance
        }
        if mode == .quickTalk, lastSpeech == nil, elapsedSeconds >= 15 { ended = true; return .noSpeechTimeout }
        if mode == .keepTalking, inactivitySeconds > 0, elapsedSeconds - (lastSpeech ?? 0) >= inactivitySeconds {
            ended = true; return .inactivityTimeout
        }
        return .continueListening
    }
}
