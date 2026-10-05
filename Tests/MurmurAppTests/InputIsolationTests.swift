import AudioToolbox
import AVFoundation
import CoreAudio
import MurmurCore
import Testing
@testable import Murmur

private struct PropertyWrite: Equatable {
    let property: AudioUnitPropertyID
    let scope: AudioUnitScope
    let bus: AudioUnitElement
    let value: UInt32
}

@Test func inputOnlyUnitDisablesPlaybackBeforeBindingSelectedDevice() throws {
    var writes: [PropertyWrite] = []
    try InputOnlyConfiguration.configure(device: 75) { property, scope, bus, value in
        writes.append(.init(property: property, scope: scope, bus: bus, value: value))
    }
    #expect(writes == [
        .init(property: kAudioOutputUnitProperty_EnableIO, scope: kAudioUnitScope_Input, bus: 1, value: 1),
        .init(property: kAudioOutputUnitProperty_EnableIO, scope: kAudioUnitScope_Output, bus: 0, value: 0),
        .init(property: kAudioOutputUnitProperty_CurrentDevice, scope: kAudioUnitScope_Global, bus: 0, value: 75)
    ])
}

@Test func outputDisableFailureNeverOpensTheSelectedDevice() {
    var bound = false
    enum Rejected: Error { case output }
    do {
        try InputOnlyConfiguration.configure(device: 75) { property, scope, _, _ in
            if property == kAudioOutputUnitProperty_EnableIO, scope == kAudioUnitScope_Output { throw Rejected.output }
            if property == kAudioOutputUnitProperty_CurrentDevice { bound = true }
        }
        Issue.record("Configuration should fail when output cannot be disabled")
    } catch {}
    #expect(!bound)
}

private let availableInputs = [
    Microphone(id: "builtin", name: "MacBook microphone", deviceID: 75),
    Microphone(id: "airpods", name: "AirPods", deviceID: 124)
]

@Test func explicitMicrophoneWinsOverBluetoothDefault() throws {
    #expect(try InputDeviceStore.resolve("builtin", microphones: availableInputs, defaultDevice: 124) == 75)
    #expect(try InputDeviceStore.resolve("", microphones: availableInputs, defaultDevice: 124) == 124)
}

@Test func missingSelectedInputDoesNotFallBackToAirPods() {
    #expect(throws: (any Error).self) {
        try InputDeviceStore.resolve("disconnected-usb", microphones: availableInputs, defaultDevice: 124)
    }
    #expect(throws: (any Error).self) {
        try InputDeviceStore.resolve("", microphones: availableInputs, defaultDevice: nil)
    }
}

private final class FakeInput: MicrophoneInput {
    let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    var receive: AVAudioNodeTapBlock?
    var failure: (@Sendable (String) -> Void)?
    var stops = 0
    func start(receive: @escaping AVAudioNodeTapBlock, failure: @escaping @Sendable (String) -> Void) throws {
        self.receive = receive; self.failure = failure
    }
    func stop() { stops += 1 }
}

private final class InputCallback: @unchecked Sendable {
    let receive: AVAudioNodeTapBlock
    init(_ receive: @escaping AVAudioNodeTapBlock) { self.receive = receive }
    func send() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800)!
        buffer.frameLength = 4800
        buffer.floatChannelData![0].initialize(repeating: 0.1, count: 4800)
        receive(buffer, AVAudioTime(sampleTime: 0, atRate: 48_000))
    }
}

@Test @MainActor func selectedInputFeedsDictationAndDrainsBeforeClosing() async throws {
    let input = FakeInput(), inbox = AudioInbox(), session = UUID()
    var opened: [AudioDeviceID] = []
    let capture = CaptureService(resolveDevice: { id in
        try InputDeviceStore.resolve(id, microphones: availableInputs, defaultDevice: 124)
    }, makeInput: { opened.append($0); return input }, requestAccess: { _ in true })
    let (_, wake) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    try await capture.start(sessionID: session, microphoneID: "builtin", inbox: inbox, wake: wake)
    #expect(opened == [75])
    let callback = InputCallback(try #require(input.receive))
    await Task.detached { callback.send() }.value
    try await capture.finish(tail: .zero)
    var count = 0
    while let packet = inbox.dequeue() {
        #expect(packet.sessionID == session)
        #expect(packet.sampleRate == 16_000)
        count += packet.samples.count
    }
    #expect(count == 1600)
    #expect(input.stops == 1)
    await Task.detached { callback.send() }.value
    #expect((inbox.dequeue()?.samples.count ?? 0) == 0)
}

@Test @MainActor func livePreviewUsesSelectedInputAndIgnoresStoppedCallbacks() async throws {
    let input = FakeInput()
    var opened: [AudioDeviceID] = [], level = 0.0, interrupted = false
    let monitor = MicrophoneMonitor(resolveDevice: { id in
        try InputDeviceStore.resolve(id, microphones: availableInputs, defaultDevice: 124)
    }, makeInput: { opened.append($0); return input }, requestAccess: { true })
    monitor.onFrame = { level = Double($0.level) }
    monitor.onInterrupted = { interrupted = true }
    #expect(try await monitor.start(microphoneID: "builtin"))
    #expect(opened == [75])
    let callback = InputCallback(try #require(input.receive))
    await Task.detached { callback.send() }.value
    for _ in 0..<50 where level == 0 { try await Task.sleep(for: .milliseconds(10)) }
    #expect(level > 0)
    monitor.stop()
    #expect(input.stops == 1)
    await Task.detached { callback.send() }.value
    input.failure?("Late device-change notification")
    try await Task.sleep(for: .milliseconds(30))
    #expect(level == 0)
    #expect(!interrupted)
}

@Test @MainActor func canceledPermissionWaitNeverOpensAnInput() async throws {
    var permission: CheckedContinuation<Bool, Never>?
    var opened = false
    let monitor = MicrophoneMonitor(makeInput: { _ in opened = true; return FakeInput() }, requestAccess: {
        await withCheckedContinuation { permission = $0 }
    })
    let pending = Task { try await monitor.start(microphoneID: "builtin") }
    for _ in 0..<50 where permission == nil { try await Task.sleep(for: .milliseconds(10)) }
    let response = try #require(permission)
    monitor.stop()
    response.resume(returning: true)
    #expect(try await pending.value == false)
    #expect(!opened)
}
