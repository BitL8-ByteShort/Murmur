import AppKit

/// Supplies words only when a clipboard consumer asks for them. The callback
/// can run outside the main actor; the small acknowledgement is lock-protected.
final class RequestedPasteboardText: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
    private let text: String
    private let lock = NSLock()
    private var requested = false
    init(_ text: String) { self.text = text }
    var wasRequested: Bool { lock.withLock { requested } }
    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        guard type == .string else { return }
        item.setString(text, forType: type)
        lock.withLock { requested = true }
    }
}
