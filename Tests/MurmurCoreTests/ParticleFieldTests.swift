import Foundation
import Testing
@testable import MurmurCore

@Test func particleCloudRespondsToInputAndRemainsBoundedWithoutRandomFlicker() {
    let quiet = ParticleField.points(frame: .silence, phase: 0, reduceMotion: false)
    let voice = ParticleField.points(frame: .preview, phase: 0, reduceMotion: false)
    #expect(voice.count == 6000)
    #expect(voice.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) && (0..<8).contains($0.shade) })
    let quietHeight = quiet.map(\.y).max()! - quiet.map(\.y).min()!
    let voiceHeight = voice.map(\.y).max()! - voice.map(\.y).min()!
    #expect(voiceHeight > quietHeight * 3)
    let reduced = ParticleField.points(frame: .preview, phase: 50, reduceMotion: true)
    let same = ParticleField.points(frame: .preview, phase: 0, reduceMotion: true)
    #expect(zip(reduced, same).allSatisfy { $0.x == $1.x && $0.y == $1.y })
    let malformed = ParticleField.points(frame: .init(level: .nan, peaks: [.infinity]), phase: .nan, reduceMotion: false)
    #expect(malformed.allSatisfy { $0.x.isFinite && $0.y.isFinite })
}
