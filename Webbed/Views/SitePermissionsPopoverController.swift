import AppKit
import WebbedKit

// MARK: - SitePermissionsPopoverController

/// Quick per-origin permissions popover anchored to the More button.
/// Power-user friendly: every PermissionKind on one screen, with segmented
/// controls for Ask/Allow/Deny.
final class SitePermissionsPopoverController: NSViewController {

    private let host: String
    private weak var store: PermissionStore?
    private let onClose: () -> Void

    private static let rowHeight: CGFloat = 30
    private static let width: CGFloat     = 360
    private static let edgePadding: CGFloat = 12

    init(host: String, store: PermissionStore, onClose: @escaping () -> Void) {
        self.host = host
        self.store = store
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let header = NSTextField(labelWithString: "Permissions for \(host)")
        header.font = .systemFont(ofSize: 12, weight: .semibold)
        header.lineBreakMode = .byTruncatingMiddle
        header.maximumNumberOfLines = 1

        let sub = NSTextField(labelWithString: "Changes take effect on next reload.")
        sub.font = .systemFont(ofSize: 10)
        sub.textColor = .secondaryLabelColor

        let resetButton = NSButton(title: "Reset All", target: self, action: #selector(resetAll))
        resetButton.bezelStyle = .accessoryBarAction
        resetButton.controlSize = .small

        let rows = PermissionKind.allCases.map { kind in
            permissionRow(for: kind)
        }

        let stack = NSStackView(views: [header, sub] + rows + [resetButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.setCustomSpacing(8, after: sub)
        stack.setCustomSpacing(12, after: rows.last!)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let totalHeight = 22 + 14 + 8                              // header + sub + custom gap
            + Self.rowHeight * CGFloat(rows.count)
            + 4 * CGFloat(max(rows.count - 1, 0))
            + 12 + 24                                              // bottom spacing + button
            + Self.edgePadding * 2
        let container = NSView(frame: NSRect(x: 0, y: 0, width: Self.width, height: totalHeight))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: Self.edgePadding),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.edgePadding),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.edgePadding),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Self.edgePadding),
        ])
        preferredContentSize = NSSize(width: Self.width, height: totalHeight)
        self.view = container
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        onClose()
    }

    private func permissionRow(for kind: PermissionKind) -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: kind.displayName)
        icon.imageScaling = .scaleProportionallyDown
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: kind.displayName)
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingTail

        let segments: [String] = kind.supportsAsk ? ["Ask", "Allow", "Deny"] : ["Allow", "Deny"]
        let seg = NSSegmentedControl(labels: segments, trackingMode: .selectOne, target: self, action: #selector(segmentChanged(_:)))
        seg.tag = PermissionKind.allCases.firstIndex(of: kind) ?? 0
        seg.controlSize = .small
        seg.segmentStyle = .roundRect
        seg.selectedSegment = indexFor(decision: store?.decision(for: host, kind: kind) ?? kind.defaultDecision, kind: kind)

        let row = NSStackView(views: [icon, label, seg])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            row.heightAnchor.constraint(equalToConstant: Self.rowHeight),
            row.widthAnchor.constraint(equalToConstant: Self.width - Self.edgePadding * 2),
        ])
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        seg.setContentHuggingPriority(.required, for: .horizontal)
        return row
    }

    private func indexFor(decision: PermissionDecision, kind: PermissionKind) -> Int {
        if kind.supportsAsk {
            switch decision {
            case .ask: return 0
            case .allow: return 1
            case .deny: return 2
            }
        } else {
            return decision == .deny ? 1 : 0
        }
    }

    private func decisionFor(index: Int, kind: PermissionKind) -> PermissionDecision {
        if kind.supportsAsk {
            switch index {
            case 1: return .allow
            case 2: return .deny
            default: return .ask
            }
        } else {
            return index == 1 ? .deny : .allow
        }
    }

    @objc private func segmentChanged(_ sender: NSSegmentedControl) {
        let kinds = PermissionKind.allCases
        guard sender.tag < kinds.count else { return }
        let kind = kinds[sender.tag]
        let decision = decisionFor(index: sender.selectedSegment, kind: kind)
        store?.setDecision(for: host, kind: kind, decision: decision)
    }

    @objc private func resetAll() {
        store?.resetOrigin(host)
        // Reload the view so segments snap back to defaults.
        loadView()
        view.needsDisplay = true
    }
}
