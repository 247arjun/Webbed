import AppKit
import WebbedKit

// MARK: - ThemePickerViewController

/// Popover content: row of coloured swatches for theme selection.
final class ThemePickerViewController: NSViewController {

    var currentThemeID: String
    var onSelect: ((String) -> Void)?

    init(currentThemeID: String, onSelect: @escaping (String) -> Void) {
        self.currentThemeID = currentThemeID
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 50))

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false

        for theme in ThemeRegistry.allThemes {
            let button = ThemeSwatchButton(theme: theme, isSelected: theme.id == currentThemeID)
            button.target = self
            button.action = #selector(swatchClicked(_:))
            stack.addArrangedSubview(button)
        }

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        self.view = container
    }

    @objc private func swatchClicked(_ sender: ThemeSwatchButton) {
        onSelect?(sender.themeID)
    }
}

// MARK: - ThemeSwatchButton

final class ThemeSwatchButton: NSButton {

    let themeID: String
    private let swatchColor: NSColor
    private let isSelectedTheme: Bool

    init(theme: WebbedTheme, isSelected: Bool) {
        self.themeID = theme.id
        self.swatchColor = theme.headerBackgroundColor
        self.isSelectedTheme = isSelected
        super.init(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
        isBordered = false
        title = ""
        bezelStyle = .inline
        setButtonType(.momentaryPushIn)
        setAccessibilityLabel(theme.displayName)
        setAccessibilityRole(.button)
        if isSelected { setAccessibilityValue("selected") }
        widthAnchor.constraint(equalToConstant: 30).isActive = true
        heightAnchor.constraint(equalToConstant: 30).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let circleRect = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(ovalIn: circleRect)
        swatchColor.setFill()
        path.fill()
        if isSelectedTheme {
            let ring = NSBezierPath(ovalIn: bounds)
            ring.lineWidth = 2.5
            NSColor.controlTextColor.withAlphaComponent(0.7).setStroke()
            ring.stroke()
        }
    }
}
