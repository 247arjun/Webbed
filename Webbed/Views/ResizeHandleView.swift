import AppKit
import WebbedKit

// MARK: - ResizeHandleView

/// Bottom-right resize affordance for borderless tab windows. Lifted from
/// Noted's `ResizeHandleView` with the Webbed theme type.
final class ResizeHandleView: NSView {

    var theme: WebbedTheme? { didSet { needsDisplay = true } }

    private var initialMouseLocation: NSPoint = .zero
    private var initialWindowFrame: NSRect = .zero
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        updateTrackingArea()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Cursor

    private static let resizeCursor: NSCursor = {
        if let cursor = NSCursor.perform(NSSelectorFromString("_windowResizeNorthWestSouthEastCursor"))?
            .takeUnretainedValue() as? NSCursor {
            return cursor
        }
        let size = NSSize(width: 16, height: 16)
        let img = NSImage(size: size, flipped: false) { _ in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 2, y: 14)); path.line(to: NSPoint(x: 14, y: 2))
            path.move(to: NSPoint(x: 9, y: 2));  path.line(to: NSPoint(x: 14, y: 2)); path.line(to: NSPoint(x: 14, y: 7))
            path.move(to: NSPoint(x: 7, y: 14)); path.line(to: NSPoint(x: 2, y: 14)); path.line(to: NSPoint(x: 2, y: 9))
            path.lineWidth = 1.5
            path.lineCapStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: 8, y: 8))
    }()

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: Self.resizeCursor)
    }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        updateTrackingArea()
    }

    private func updateTrackingArea() {
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true;  needsDisplay = true }
    override func mouseExited (with event: NSEvent) { isHovered = false; needsDisplay = true }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let baseAlpha: CGFloat = isHovered ? 0.85 : 0.40
        let color = (theme?.controlTintColor ?? .gray).withAlphaComponent(baseAlpha)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(isHovered ? 1.5 : 1.0)
        ctx.setLineCap(.round)
        let s = bounds.size
        for i in 0..<4 {
            let offset = CGFloat(i) * 5.0 + 5.0
            ctx.move(to: CGPoint(x: s.width - offset, y: 0))
            ctx.addLine(to: CGPoint(x: s.width, y: offset))
        }
        ctx.strokePath()
    }

    // MARK: - Mouse tracking

    override func mouseDown(with event: NSEvent) {
        initialMouseLocation = NSEvent.mouseLocation
        initialWindowFrame = window?.frame ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - initialMouseLocation.x
        let dy = current.y - initialMouseLocation.y

        let newWidth  = max(window.minSize.width,  initialWindowFrame.width + dx)
        let newHeight = max(window.minSize.height, initialWindowFrame.height - dy)

        var frame = initialWindowFrame
        frame.size.width  = newWidth
        frame.size.height = newHeight
        frame.origin.y = initialWindowFrame.maxY - newHeight
        window.setFrame(frame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        if let win = window, let ctrl = win.windowController as? TabWindowController {
            ctrl.windowDidEndResize()
        }
    }
}
