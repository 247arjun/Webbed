import AppKit

// MARK: - TabWindow

/// Borderless, transparent NSWindow that hosts a single browser tab. Modeled
/// after Noted's `NoteWindow` but tuned for a browser (larger min size and
/// default size, room for chrome).
final class TabWindow: NSWindow {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        configure()
    }

    private func configure() {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false   // explicit drag region in header
        level = .normal
        collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary]
        minSize = NSSize(width: 320, height: 280)
        isReleasedWhenClosed = false
        tabbingMode = .disallowed
        animationBehavior = .documentWindow
    }

    // Borderless windows must opt-in to become key/main.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
