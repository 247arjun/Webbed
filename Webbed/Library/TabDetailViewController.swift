import AppKit
import WebbedKit

// MARK: - TabDetailViewController

/// Right-pane detail view for the Library window: snapshot + metadata + actions.
final class TabDetailViewController: NSViewController {

    // Callbacks
    var onOpenTab:        ((UUID) -> Void)?
    var onDeleteTab:      ((UUID) -> Void)?
    var onArchiveTab:     ((UUID) -> Void)?
    var onRestoreTab:     ((UUID) -> Void)?
    var onMoveToTrash:    ((UUID) -> Void)?
    var onDeleteForever:  ((UUID) -> Void)?

    private weak var tabStore: TabStore?
    private(set) var currentTabID: UUID?

    // Subviews
    private let imageView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let urlField   = NSTextField(labelWithString: "")
    private let metaField  = NSTextField(labelWithString: "")
    private let openButton    = NSButton(title: "Open in Window", target: nil, action: nil)
    private let archiveButton = NSButton(title: "Archive",        target: nil, action: nil)
    private let trashButton   = NSButton(title: "Move to Trash",  target: nil, action: nil)
    private let emptyLabel = NSTextField(labelWithString: "Select a tab")

    init(tabStore: TabStore) {
        self.tabStore = tabStore
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 600))

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.borderColor = NSColor.separatorColor.cgColor
        imageView.layer?.borderWidth = 1

        titleField.font = .systemFont(ofSize: 18, weight: .semibold)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 2

        urlField.font = .systemFont(ofSize: 12)
        urlField.textColor = .secondaryLabelColor
        urlField.lineBreakMode = .byTruncatingMiddle
        urlField.maximumNumberOfLines = 1

        metaField.font = .systemFont(ofSize: 11)
        metaField.textColor = .tertiaryLabelColor

        openButton.target    = self; openButton.action    = #selector(openClicked)
        archiveButton.target = self; archiveButton.action = #selector(archiveClicked)
        trashButton.target   = self; trashButton.action   = #selector(trashClicked)
        trashButton.bezelColor = NSColor.systemRed

        let buttonRow = NSStackView(views: [openButton, archiveButton, trashButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        let stack = NSStackView(views: [imageView, titleField, urlField, metaField, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 16)
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 32),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            imageView.heightAnchor.constraint(equalToConstant: 280),
            imageView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        clearDetail()
    }

    func showTab(id: UUID) {
        currentTabID = id
        guard let store = tabStore,
              let tab = store.tabs[id] ?? store.archivedTabs[id] ?? store.trashedTabs[id] else {
            clearDetail()
            return
        }
        titleField.stringValue = tab.displayTitle
        urlField.stringValue   = tab.displayURLString
        metaField.stringValue  = "Last visited \(Self.formatter.string(from: tab.lastVisitedAt))"

        // Load snapshot if available.
        if let svc = store.persistenceService as? FilePersistenceService,
           let url = svc.snapshotURL(for: id),
           let img = NSImage(contentsOf: url) {
            imageView.image = img
        } else {
            imageView.image = NSImage(systemSymbolName: "safari", accessibilityDescription: nil)
        }

        // Reveal subviews
        for v in [imageView, titleField, urlField, metaField, openButton, archiveButton, trashButton] {
            v.isHidden = false
        }
        emptyLabel.isHidden = true

        // Bucket-aware buttons.
        if tab.isInTrash {
            openButton.title = "Restore"
            archiveButton.isHidden = true
            trashButton.title = "Delete Forever"
        } else if tab.isArchived {
            openButton.title = "Restore"
            archiveButton.isHidden = true
            trashButton.title = "Move to Trash"
        } else {
            openButton.title = "Open in Window"
            archiveButton.isHidden = false
            archiveButton.title = "Archive"
            trashButton.title = "Move to Trash"
        }
    }

    func clearDetail() {
        currentTabID = nil
        for v in [imageView, titleField, urlField, metaField, openButton, archiveButton, trashButton] {
            v.isHidden = true
        }
        emptyLabel.isHidden = false
    }

    // MARK: - Actions

    @objc private func openClicked() {
        guard let id = currentTabID, let store = tabStore else { return }
        if let tab = store.archivedTabs[id] ?? store.trashedTabs[id] {
            if tab.isInTrash       { onRestoreTab?(id) }
            else if tab.isArchived { onRestoreTab?(id) }
        } else {
            onOpenTab?(id)
        }
    }

    @objc private func archiveClicked() {
        guard let id = currentTabID else { return }
        onArchiveTab?(id)
        clearDetail()
    }

    @objc private func trashClicked() {
        guard let id = currentTabID, let store = tabStore else { return }
        if let tab = store.trashedTabs[id], tab.isInTrash {
            onDeleteForever?(id)
        } else {
            onMoveToTrash?(id)
        }
        clearDetail()
    }

    // MARK: - Formatter

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
