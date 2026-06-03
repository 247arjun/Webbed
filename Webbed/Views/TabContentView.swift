import AppKit
import WebKit
import WebbedKit

// MARK: - TabContentViewDelegate

@MainActor
protocol TabContentViewDelegate: AnyObject {
    func tabContentView(_ view: TabContentView, didSubmitAddress text: String)
    func tabContentViewDidClickBack(_ view: TabContentView)
    func tabContentViewDidClickForward(_ view: TabContentView)
    func tabContentViewDidClickReload(_ view: TabContentView)
    func tabContentViewDidClickStop(_ view: TabContentView)
    func tabContentViewDidClickClose(_ view: TabContentView)
    func tabContentViewDidClickPin(_ view: TabContentView)
    func tabContentViewDidClickLiveMode(_ view: TabContentView, sourceButton: NSButton)
    func tabContentViewDidClickTheme(_ view: TabContentView, sourceButton: NSButton)
    func tabContentViewDidClickMore(_ view: TabContentView, sourceButton: NSButton)
}

// Default no-op implementations so phases can adopt only what they need.
extension TabContentViewDelegate {
    func tabContentViewDidClickPin(_ view: TabContentView) {}
    func tabContentViewDidClickLiveMode(_ view: TabContentView, sourceButton: NSButton) {}
    func tabContentViewDidClickTheme(_ view: TabContentView, sourceButton: NSButton) {}
    func tabContentViewDidClickMore(_ view: TabContentView, sourceButton: NSButton) {}
}

// MARK: - HeaderDragView

/// Background view of the header band. Defers all mouse events to the window's
/// drag-by-background behaviour by claiming `mouseDownCanMoveWindow`.
final class HeaderDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        // Initiate a window drag.
        window?.performDrag(with: event)
    }
}

// MARK: - TabContentView

/// Root AppKit view for a single tab window.
///
/// ```
/// ┌──────────────────────────────────────────────┐
/// │  HEADER (38 pt drag region)                  │
/// │  [◀ ▶ ⟳]  [ address field … ]      [P 🎨⋯✕]│
/// │  ──────── progress bar (1 pt) ────────────── │
/// ├──────────────────────────────────────────────┤
/// │                                              │
/// │          WKWebView (fills remainder)         │
/// │                                              │
/// │                                        ╱╱╱  │ ← ResizeHandleView
/// └──────────────────────────────────────────────┘
/// ```
final class TabContentView: NSView {

    // MARK: - Public state

    let tabID: UUID
    private(set) var theme: WebbedTheme
    private(set) var isPinned: Bool = false

    weak var delegate: TabContentViewDelegate?

    // MARK: - Subviews

    let headerView = HeaderDragView()
    let backButton:    NSButton
    let forwardButton: NSButton
    let reloadButton:  NSButton
    let addressField:  NSTextField
    let pinButton:     NSButton
    let liveButton:    NSButton
    let themeButton:   NSButton
    let moreButton:    NSButton
    let closeButton:   NSButton
    let progressLayer = CALayer()
    let webView:      WKWebView
    let resizeHandle: ResizeHandleView

    // MARK: - Constraints we adjust on resize

    private var headerHeightConstraint: NSLayoutConstraint!
    private var leadingButtonsStack: NSStackView!
    private var trailingButtonsStack: NSStackView!

    // MARK: - Init

    init(tabID: UUID, theme: WebbedTheme, webView: WKWebView) {
        self.tabID = tabID
        self.theme = theme
        self.webView = webView

        backButton    = Self.headerButton(symbol: "chevron.left",  label: "Back")
        forwardButton = Self.headerButton(symbol: "chevron.right", label: "Forward")
        reloadButton  = Self.headerButton(symbol: "arrow.clockwise", label: "Reload")
        pinButton     = Self.headerButton(symbol: "pin",            label: "Pin tab on top")
        liveButton    = Self.headerButton(symbol: "dot.radiowaves.left.and.right", label: "Live Mode")
        themeButton   = Self.headerButton(symbol: "paintpalette",   label: "Theme")
        moreButton    = Self.headerButton(symbol: "ellipsis",       label: "More")
        closeButton   = Self.headerButton(symbol: "xmark",          label: "Close tab")

        addressField = NSTextField()
        addressField.isBordered = false
        addressField.isBezeled = false
        addressField.drawsBackground = false
        addressField.focusRingType = .none
        addressField.placeholderString = "Search Google or enter a URL"
        addressField.font = .systemFont(ofSize: 13)
        addressField.lineBreakMode = .byTruncatingMiddle
        addressField.cell?.usesSingleLineMode = true
        addressField.cell?.wraps = false
        addressField.cell?.isScrollable = true
        addressField.setAccessibilityLabel("Address")

        resizeHandle = ResizeHandleView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))

        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        setupSubviews()
        setupConstraints()
        applyTheme(theme)
        wireActions()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Theme

    func applyTheme(_ newTheme: WebbedTheme) {
        theme = newTheme
        layer?.backgroundColor = newTheme.bodyBackgroundColor.cgColor
        headerView.layer?.backgroundColor = newTheme.headerBackgroundColor.cgColor

        addressField.textColor = newTheme.titleTextColor
        if let cell = addressField.cell as? NSTextFieldCell {
            cell.placeholderAttributedString = NSAttributedString(
                string: addressField.placeholderString ?? "",
                attributes: [
                    .foregroundColor: newTheme.placeholderTextColor,
                    .font: NSFont.systemFont(ofSize: 13),
                ]
            )
        }

        for b in [backButton, forwardButton, reloadButton, pinButton, liveButton, themeButton, moreButton, closeButton] {
            b.contentTintColor = newTheme.controlTintColor
        }

        progressLayer.backgroundColor = newTheme.controlTintColor.withAlphaComponent(0.85).cgColor
        resizeHandle.theme = newTheme

        needsDisplay = true
    }

    // MARK: - Pin glyph

    func updatePinState(_ pinned: Bool) {
        isPinned = pinned
        let symbol = pinned ? "pin.fill" : "pin"
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        pinButton.image = NSImage(systemSymbolName: symbol,
                                  accessibilityDescription: pinned ? "Unpin tab" : "Pin tab")?
            .withSymbolConfiguration(config)
        pinButton.setAccessibilityLabel(pinned ? "Unpin tab" : "Pin tab")
        pinButton.setAccessibilityValue(pinned ? "pinned" : "unpinned")
    }

    func updateLiveModeGlyph(_ interval: LiveModeInterval) {
        let active = interval != .off
        let symbol = active ? "dot.radiowaves.left.and.right" : "dot.radiowaves.left.and.right"
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        liveButton.image = NSImage(systemSymbolName: symbol,
                                   accessibilityDescription: "Live Mode")?
            .withSymbolConfiguration(config)
        // Highlight the active state with a tinted background ring.
        if active {
            liveButton.contentTintColor = NSColor.systemRed
            liveButton.toolTip = "Live Mode: \(interval.displayName)"
        } else {
            liveButton.contentTintColor = theme.controlTintColor
            liveButton.toolTip = "Live Mode (off)"
        }
        liveButton.setAccessibilityValue(active ? interval.shortLabel : "off")
    }

    // MARK: - Address bar

    func updateAddress(_ text: String) {
        // Don't overwrite while the user is editing.
        if window?.firstResponder is NSText,
           addressField.currentEditor() != nil { return }
        addressField.stringValue = text
    }

    func updateNavButtons(canGoBack: Bool, canGoForward: Bool) {
        backButton.isEnabled = canGoBack
        forwardButton.isEnabled = canGoForward
    }

    func updateProgress(_ progress: Double, isLoading: Bool) {
        progressLayer.isHidden = !isLoading || progress >= 1.0
        let total = headerView.bounds.width
        let width = max(0, CGFloat(progress) * total)
        var frame = progressLayer.frame
        frame.size.width = width
        progressLayer.frame = frame

        let symbol = isLoading ? "xmark" : "arrow.clockwise"
        let label  = isLoading ? "Stop" : "Reload"
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        reloadButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(config)
        reloadButton.setAccessibilityLabel(label)
    }

    // MARK: - Setup

    private func setupSubviews() {
        headerView.wantsLayer = true
        addSubview(headerView)

        leadingButtonsStack = NSStackView(views: [backButton, forwardButton, reloadButton])
        leadingButtonsStack.orientation = .horizontal
        leadingButtonsStack.spacing = 4
        leadingButtonsStack.alignment = .centerY
        leadingButtonsStack.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(leadingButtonsStack)

        addressField.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(addressField)

        trailingButtonsStack = NSStackView(views: [pinButton, liveButton, themeButton, moreButton, closeButton])
        trailingButtonsStack.orientation = .horizontal
        trailingButtonsStack.spacing = 6
        trailingButtonsStack.alignment = .centerY
        trailingButtonsStack.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(trailingButtonsStack)

        progressLayer.backgroundColor = NSColor.systemBlue.cgColor
        progressLayer.frame = .zero
        progressLayer.isHidden = true
        headerView.wantsLayer = true
        headerView.layer?.addSublayer(progressLayer)

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.setValue(false, forKey: "drawsBackground")
        addSubview(webView)

        addSubview(resizeHandle)
    }

    private func setupConstraints() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false

        headerHeightConstraint = headerView.heightAnchor.constraint(
            equalToConstant: ChromeLayoutMetrics.headerHeight
        )

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerHeightConstraint,

            leadingButtonsStack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 10),
            leadingButtonsStack.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            trailingButtonsStack.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -10),
            trailingButtonsStack.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            addressField.leadingAnchor.constraint(equalTo: leadingButtonsStack.trailingAnchor, constant: 10),
            addressField.trailingAnchor.constraint(equalTo: trailingButtonsStack.leadingAnchor, constant: -10),
            addressField.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            webView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),

            resizeHandle.widthAnchor.constraint(equalToConstant: 28),
            resizeHandle.heightAnchor.constraint(equalToConstant: 28),
            resizeHandle.trailingAnchor.constraint(equalTo: trailingAnchor),
            resizeHandle.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func wireActions() {
        backButton.target    = self; backButton.action    = #selector(onBack)
        forwardButton.target = self; forwardButton.action = #selector(onForward)
        reloadButton.target  = self; reloadButton.action  = #selector(onReloadOrStop)
        pinButton.target     = self; pinButton.action     = #selector(onPin)
        liveButton.target    = self; liveButton.action    = #selector(onLive)
        themeButton.target   = self; themeButton.action   = #selector(onTheme)
        moreButton.target    = self; moreButton.action    = #selector(onMore)
        closeButton.target   = self; closeButton.action   = #selector(onClose)
        addressField.target  = self; addressField.action  = #selector(onAddressSubmit)
    }

    // MARK: - Responsive layout

    /// Adjust chrome density based on the current window width/height.
    func applyResponsiveLayout(for size: CGSize) {
        let widthMode  = ChromeLayoutMetrics.mode(forWidth: size.width)
        let isUltraTinyH = size.height < ChromeLayoutMetrics.ultraTinyHeightThreshold

        // Show / hide nav cluster in compact and tiny modes.
        let showNavCluster = (widthMode == .desktop)
        backButton.isHidden    = !showNavCluster
        forwardButton.isHidden = !showNavCluster
        reloadButton.isHidden  = !showNavCluster

        // In tiny mode, also hide pin + theme to give the URL field room.
        let tiny = widthMode == .tiny
        pinButton.isHidden   = tiny
        liveButton.isHidden  = tiny
        themeButton.isHidden = tiny

        // Header band height.
        headerHeightConstraint.constant = isUltraTinyH
            ? ChromeLayoutMetrics.headerHeightUltraTiny
            : ChromeLayoutMetrics.headerHeight

        // Mobile user agent flip.
        webView.customUserAgent = widthMode == .desktop ? nil : ChromeLayoutMetrics.mobileUserAgent

        // Resize progress layer container height.
        var progFrame = progressLayer.frame
        progFrame.size.height = 2
        progFrame.origin.y = 0
        progressLayer.frame = progFrame
    }

    // MARK: - Actions

    @objc private func onBack()           { delegate?.tabContentViewDidClickBack(self) }
    @objc private func onForward()        { delegate?.tabContentViewDidClickForward(self) }
    @objc private func onReloadOrStop() {
        if webView.isLoading { delegate?.tabContentViewDidClickStop(self) }
        else                  { delegate?.tabContentViewDidClickReload(self) }
    }
    @objc private func onPin()            { delegate?.tabContentViewDidClickPin(self) }
    @objc private func onLive()           { delegate?.tabContentViewDidClickLiveMode(self, sourceButton: liveButton) }
    @objc private func onTheme()          { delegate?.tabContentViewDidClickTheme(self, sourceButton: themeButton) }
    @objc private func onMore()           { delegate?.tabContentViewDidClickMore(self, sourceButton: moreButton) }
    @objc private func onClose()          { delegate?.tabContentViewDidClickClose(self) }

    @objc private func onAddressSubmit() {
        delegate?.tabContentView(self, didSubmitAddress: addressField.stringValue)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        // Resize progress layer to follow header width.
        let h: CGFloat = 2
        progressLayer.frame = NSRect(
            x: 0, y: 0,
            width: progressLayer.frame.width,
            height: h
        )
    }

    // MARK: - Header button factory

    private static func headerButton(symbol: String, label: String) -> NSButton {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(config)
        let button = NSButton(image: image ?? NSImage(), target: nil, action: nil)
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.setButtonType(.momentaryChange)
        button.setAccessibilityLabel(label)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 22),
            button.heightAnchor.constraint(equalToConstant: 22),
        ])
        return button
    }
}
