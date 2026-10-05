import AVFoundation
import Foundation
import Testing
import MurmurCore
@testable import Murmur

final class EventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [SpeechEvent] = []
    func append(_ event: SpeechEvent) { lock.withLock { collected.append(event) } }
    var snapshot: [SpeechEvent] { lock.withLock { collected } }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["MURMUR_MODEL_ENGINE"] != nil))
func downloadedBackendSupportsTwoContinuousUtterancesAndWarmRestart() async throws {
    let name = ProcessInfo.processInfo.environment["MURMUR_MODEL_ENGINE"]!
    let engine = SpeechEngine(rawValue: name)!
    if engine == .apple { #expect(await AppleSpeechBackend.assetsInstalled(locale: "en_US")) }
    else { #expect(LocalModelStore.installed(engine)) }
    let base: any SpeechBackend = switch engine {
    case .apple: AppleSpeechBackend()
    case .parakeet: ParakeetBackend()
    case .moonshine: MoonshineBackend()
    case .whisper: WhisperBackend()
    }
    let backend = SerializedSpeechBackend(base)
    let events = EventCollector(), session = UUID()
    try await backend.prepare(sessionID: session, locale: "en_US") { events.append($0) }
    let fixture = ProcessInfo.processInfo.environment["MURMUR_FIXTURE_PATH"]!
    let packetSize: AVAudioFrameCount = engine == .apple ? 160 : 1600
    let packetDelay = engine == .apple ? 10 : 100
    for take in 0..<2 {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: fixture))
        while file.framePosition < file.length {
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: packetSize)!
            try file.read(into: buffer)
            let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
            try await backend.accept(.init(sessionID: session, samples: samples))
            try await Task.sleep(for: .milliseconds(packetDelay))
        }
        for _ in 0..<15 {
            try await backend.accept(.init(sessionID: session, samples: Array(repeating: 0, count: 1600)))
            try await Task.sleep(for: .milliseconds(100))
        }
        if take == 0 {
            try await backend.flush()
            if engine == .apple {
                // Match small live packets and quiet room noise between thoughts.
                let quiet = (0..<Int(packetSize)).map { Float(sin(Double($0) * 0.27) * 0.001) }
                for gap in 0..<(10_000 / packetDelay) {
                    try await backend.accept(.init(sessionID: session, samples: quiet))
                    try await Task.sleep(for: .milliseconds(packetDelay))
                    if gap > 0, gap % (1200 / packetDelay) == 0 { try await backend.flush() }
                }
                try await backend.flush()
            }
        } else { try await backend.finish() }
    }
    var assembler = TranscriptAssembler(sessionID: session), finals: [String] = []
    for event in events.snapshot {
        switch event {
        case .utterance(let utterance): if let text = assembler.update(utterance) { finals.append(text) }
        case .failed(let message): Issue.record("\(message)")
        default: break
        }
    }
    let text = finals.joined(separator: " ").lowercased()
    #expect(text.components(separatedBy: "quick brown fox").count == 3)
    #expect(assembler.partialText.isEmpty)
    await backend.suspend()
    let newSession = UUID(), second = EventCollector()
    try await backend.prepare(sessionID: newSession, locale: "en_US") { second.append($0) }
    try await backend.finish()
    #expect(second.snapshot.allSatisfy { event in
        if case .utterance(let utterance) = event { return utterance.sessionID == newSession }
        return true
    })
    await backend.unload()
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["MURMUR_FIXTURE_PATH"] != nil))
func appleBackendRecognizesRealAudioAndVADWithoutOpeningMicrophone() async throws {
    let fixture = ProcessInfo.processInfo.environment["MURMUR_FIXTURE_PATH"]!
    #expect(await AppleSpeechBackend.assetsInstalled(locale: "en_US"))
    let backend = AppleSpeechBackend(), events = EventCollector(), session = UUID()
    try await backend.prepare(sessionID: session, locale: "en_US") { events.append($0) }
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: fixture))
    #expect(file.processingFormat.sampleRate == 16_000)
    #expect(file.processingFormat.channelCount == 1)
    while file.framePosition < file.length {
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1600)!
        try file.read(into: buffer)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        try await backend.accept(.init(sessionID: session, samples: samples))
        try await Task.sleep(for: .milliseconds(100))
    }
    for _ in 0..<20 {
        try await backend.accept(.init(sessionID: session, samples: Array(repeating: 0, count: 1600)))
        try await Task.sleep(for: .milliseconds(100))
    }
    try await backend.finish()
    var assembler = TranscriptAssembler(sessionID: session)
    var finalized: [String] = []
    var detectedSpeech = false, detectedPause = false, hadPartial = false
    for event in events.snapshot {
        switch event {
        case .utterance(let utterance):
            if !utterance.isFinal { hadPartial = true }
            if let final = assembler.update(utterance) { finalized.append(final) }
        case .activity(true): detectedSpeech = true
        case .activity(false): if detectedSpeech { detectedPause = true }
        case .failed(let message): Issue.record("\(message)")
        default: break
        }
    }
    let text = finalized.joined(separator: " ").lowercased()
    #expect(text.contains("local dictation"))
    #expect(text.contains("quick brown fox"))
    #expect(assembler.partialText.isEmpty)
    #expect(text.components(separatedBy: "hello").count == 2)
    #expect(detectedSpeech)
    #expect(detectedPause)
    #expect(hadPartial)
    await backend.unload()
}
