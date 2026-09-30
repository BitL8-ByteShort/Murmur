import Foundation

public enum AudioQueueError: Error, Equatable { case overflow, unsupportedFormat }
public struct AudioQueue: Sendable {
    private var packets: [AudioPacket] = []
    private var head = 0
    public private(set) var pendingSamples = 0
    public init() {}
    public mutating func enqueue(_ packet: AudioPacket) throws {
        guard packet.sampleRate == 16_000 else { throw AudioQueueError.unsupportedFormat }
        guard packet.samples.count <= 480_000 - pendingSamples else { throw AudioQueueError.overflow }
        if packet.samples.isEmpty { return }
        packets.append(packet); pendingSamples += packet.samples.count
    }
    public mutating func dequeue() -> AudioPacket? {
        guard head < packets.count else { return nil }
        let packet = packets[head]; pendingSamples -= packet.samples.count; head += 1
        if head == packets.count { packets.removeAll(keepingCapacity: true); head = 0 }
        else if head > 64 { packets.removeFirst(head); head = 0 }
        return packet
    }
}

/// Synchronous tap-to-worker boundary. All mutable queue state is lock-protected.
public final class AudioInbox: @unchecked Sendable {
    private let lock = NSLock()
    private var queue = AudioQueue()
    public init() {}
    public func enqueue(_ packet: AudioPacket) throws { try lock.withLock { try queue.enqueue(packet) } }
    public func dequeue() -> AudioPacket? { lock.withLock { queue.dequeue() } }
}
