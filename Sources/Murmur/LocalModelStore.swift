import Foundation
import FluidAudio
@preconcurrency import MoonshineVoice
@preconcurrency import WhisperKit
import MurmurCore

enum LocalModelStore {
    struct Receipt: Codable { let files: [String: Int] }
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Murmur/Models", isDirectory: true)
    }
    static func folder(_ engine: SpeechEngine) -> URL { root.appendingPathComponent(engine.rawValue, isDirectory: true) }
    static func installed(_ engine: SpeechEngine) -> Bool {
        let root = folder(engine)
        guard let data = try? Data(contentsOf: root.appendingPathComponent("ready.json")),
              let receipt = try? JSONDecoder().decode(Receipt.self, from: data), !receipt.files.isEmpty else { return false }
        return receipt.files.allSatisfy { path, size in
            (try? FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(path).path)[.size] as? Int) == size
        }
    }
    static func require(_ engine: SpeechEngine) throws {
        guard installed(engine) else { throw SpeechFailure.unavailable("Download \(engine.title) in Speech models before selecting it.") }
    }
    static func download(_ engine: SpeechEngine, progress: @escaping @Sendable (String) -> Void) async throws {
        let root = folder(engine)
        let name = switch engine { case .apple: ""; case .parakeet: "Parakeet"; case .moonshine: "Moonshine"; case .whisper: "Whisper" }
        guard !name.isEmpty else { return }
        let source = AppResources.root.appendingPathComponent("Licenses/Models/\(name)")
        let licenses = root.appendingPathComponent("Licenses")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: licenses.path) { try FileManager.default.copyItem(at: source, to: licenses) }
        switch engine {
        case .apple: return
        case .parakeet:
            try await ModelHub.download(.parakeetEou320, to: root) { progress("\(Int($0.fractionCompleted * 100))%") }
        case .moonshine:
            try await AssetDownloader(timeout: 600).ensureModelPresent(root: root, spec: .stt(language: "en", modelArch: .smallStreaming)) {
                let percent = $0.bytesTotal > 0 ? " · \(Int(100 * $0.bytesDownloaded / $0.bytesTotal))%" : ""
                progress("File \($0.fileIndex)/\($0.totalFiles)\(percent)")
            }
        case .whisper:
            let model = try await WhisperKit.download(variant: "openai_whisper-large-v3-v20240930_626MB", downloadBase: root) {
                progress("\(Int($0.fractionCompleted * 100))%")
            }
            progress("Preparing tokenizer…")
            _ = try await ModelUtilities.loadTokenizer(for: .largev3, tokenizerFolder: root, additionalSearchPaths: [model])
            try String(model.path.dropFirst(root.path.count + 1)).write(to: root.appendingPathComponent("model-path.txt"), atomically: true, encoding: .utf8)
        }
        try Task.checkCancellation()
        var files: [String: Int] = [:]
        let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
        while let url = iterator?.nextObject() as? URL {
            if url == licenses { iterator?.skipDescendants(); continue }
            guard url.lastPathComponent != "ready.json" else { continue }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true, let size = values.fileSize { files[String(url.path.dropFirst(root.path.count + 1))] = size }
        }
        guard !files.isEmpty else { throw SpeechFailure.unavailable("The download contained no model files.") }
        try JSONEncoder().encode(Receipt(files: files)).write(to: root.appendingPathComponent("ready.json"), options: .atomic)
    }
    static func delete(_ engine: SpeechEngine) throws {
        let url = folder(engine)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
    }
}

/// Callbacks can originate on SDK worker threads. Revisions and identities remain ordered there.
final class LocalSpeechReporter: @unchecked Sendable {
    private let lock = NSLock()
    private let session: UUID
    private let report: @Sendable (SpeechEvent) -> Void
    private var identities: [Int: UUID] = [:], revisions: [Int: Int] = [:]
    private var heardSpeech = false, active = false
    init(session: UUID, report: @escaping @Sendable (SpeechEvent) -> Void) { self.session = session; self.report = report }
    func text(_ text: String, segment: Int, final: Bool) {
        lock.withLock {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            heardSpeech = true
            report(.activity(active))
            let id = identities[segment] ?? UUID(); identities[segment] = id
            let revision = (revisions[segment] ?? 0) + 1; revisions[segment] = revision
            report(.utterance(.init(sessionID: session, id: id, revision: revision, text: text, isFinal: final)))
        }
    }
    func audio(_ samples: [Float]) {
        lock.withLock {
            let power = samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(1, samples.count))
            active = sqrt(power) > 0.004
            if heardSpeech { report(.activity(active)) }
        }
    }
    func error(_ error: Error) { report(.failed(error.localizedDescription)) }
}
