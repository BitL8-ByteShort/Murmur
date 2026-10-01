import AppKit
import Testing
import MurmurCore
@testable import Murmur

@Test func remoteLinuxPastePressesControlBeforeVAndReleasesItAfterward() throws {
    let events = try PasteKeyboardEvents.make(remoteShortcut: .controlV)
    #expect(events.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [59, 9, 9, 59])
    #expect(events.map(\.type) == [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
    #expect(events.first?.flags.contains(.maskControl) == true)
    // TigerVNC reads the left-device bit on flagsChanged, not just the generic mask.
    #expect(events.first.map { $0.flags.rawValue & 1 } == 1)
    #expect(events.dropLast().allSatisfy { !$0.flags.contains(.maskCommand) })
    #expect(events.last?.flags.rawValue == 0)
}

@Test func remoteTerminalPasteReleasesBothModifiersAndNeverSendsEnter() throws {
    let events = try PasteKeyboardEvents.make(remoteShortcut: .controlShiftV)
    #expect(events.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [59, 56, 9, 9, 56, 59])
    try #require(events.count == 6)
    #expect(events[2].flags.contains([.maskControl, .maskShift]))
    #expect(events.last?.flags.rawValue == 0)
}

@Test func localMacPasteRetainsCommandVAndRemoteMacIncludesTheCommandKey() throws {
    let local = try PasteKeyboardEvents.make()
    #expect(local.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [9, 9])
    #expect(local.allSatisfy { $0.flags == .maskCommand })
    let remote = try PasteKeyboardEvents.make(remoteShortcut: .commandV)
    #expect(remote.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [55, 9, 9, 55])
    #expect(remote.last?.flags.rawValue == 0)
}
