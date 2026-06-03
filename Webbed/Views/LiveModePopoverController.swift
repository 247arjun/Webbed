import AppKit
import WebbedKit

// MARK: - LiveModePopoverController

/// Popover with a list of auto-refresh cadence choices.
final class LiveModePopoverController: NSViewController {

    private let current: LiveModeInterval
    private let onSelect: (LiveModeInterval) -> Void

    init(current: LiveModeInterval, onSelect: @escaping (LiveModeInterval) -> Void) {
        self.current = current
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        let header = NSTextField(labelWithString: "Auto-refresh page")
        header.font = .systemFont(ofSize: 12, weight: .semibold)
        header.textColor = .secondaryLabelColor
        stack.addArrangedSubview(header)

        for option in LiveModeInterval.allCases {
            let row = LiveModeRowButton(option: option, isSelected: option == current)
            row.target = self
            row.action = #selector(rowClicked(_:))
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalToConstant: 200).isActive = true
            stack.addArrangedSubview(row)
        }

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 216, height: 280))
        container.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
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
        font = .systemFont(ofSize: 13)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}
