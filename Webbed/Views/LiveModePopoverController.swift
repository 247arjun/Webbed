import AppKit
import WebbedKit

// MARK: - LiveModePopoverController

/// Popover with a list of auto-refresh cadence choices. Each row is a
/// fixed-height button; the container sizes itself to the rows + header
/// so there's no leftover slack.
final class LiveModePopoverController: NSViewController {

    private let current: LiveModeInterval
    private let onSelect: (LiveModeInterval) -> Void

    private static let rowHeight: CGFloat   = 26
    private static let rowWidth:  CGFloat   = 200
    private static let rowSpacing: CGFloat  = 1
    private static let edgePadding: CGFloat = 10

    init(current: LiveModeInterval, onSelect: @escaping (LiveModeInterval) -> Void) {
        self.current = current
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let header = NSTextField(labelWithString: "Auto-refresh page")
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .secondaryLabelColor
        header.translatesAutoresizingMaskIntoConstraints = false

        let rows = LiveModeInterval.allCases.map { option -> LiveModeRowButton in
            let row = LiveModeRowButton(option: option, isSelected: option == current)
            row.target = self
            row.action = #selector(rowClicked(_:))
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalToConstant: Self.rowWidth).isActive = true
            row.heightAnchor.constraint(equalToConstant: Self.rowHeight).isActive = true
            return row
        }

        let stack = NSStackView(views: [header] + rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Self.rowSpacing
        stack.setCustomSpacing(6, after: header)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Compute the actual content size so the popover hugs its rows.
        let headerHeight = ceil(header.intrinsicContentSize.height)
        let rowsHeight = Self.rowHeight * CGFloat(rows.count)
                       + Self.rowSpacing * CGFloat(max(rows.count - 1, 0))
        let totalHeight = headerHeight + 6 + rowsHeight + Self.edgePadding * 2
        let totalWidth  = Self.rowWidth + Self.edgePadding * 2

        let container = NSView(frame: NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor,         constant: Self.edgePadding),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.edgePadding),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.edgePadding),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor,   constant: -Self.edgePadding),
        ])
        preferredContentSize = NSSize(width: totalWidth, height: totalHeight)
        self.view = container
    }

    @objc private func rowClicked(_ sender: LiveModeRowButton) {
        onSelect(sender.option)
    }
}

// MARK: - LiveModeRowButton

private final class LiveModeRowButton: NSButton {
    let option: LiveModeInterval

    init(option: LiveModeInterval, isSelected: Bool) {
        self.option = option
        super.init(frame: .zero)
        title = option.displayName
        bezelStyle = .accessoryBarAction
        isBordered = false
        alignment = .left
        contentTintColor = .labelColor
        let symbol = isSelected ? "checkmark.circle.fill" : "circle"
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        imagePosition = .imageLeading
        imageHugsTitle = true
        font = .systemFont(ofSize: 13)
        setButtonType(.momentaryChange)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}
