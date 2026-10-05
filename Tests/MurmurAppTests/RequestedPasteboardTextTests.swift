import AppKit
import Testing
@testable import Murmur

@Test @MainActor func clipboardAcknowledgementRequiresReadingTheActualWords() throws {
    let board = NSPasteboard(name: .init("MurmurTest-\(UUID())"))
    defer { board.releaseGlobally() }
    let provider = RequestedPasteboardText("Hello 🐼.")
    let item = NSPasteboardItem()
    item.setDataProvider(provider, forTypes: [.string])
    #expect(board.writeObjects([item]))
    #expect(!provider.wasRequested)
    #expect(board.availableType(from: [.string]) == .string)
    #expect(!provider.wasRequested)
    #expect(board.string(forType: .string) == "Hello 🐼.")
    #expect(provider.wasRequested)
}
