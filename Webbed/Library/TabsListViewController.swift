import AppKit
import Combine
import WebbedKit

// MARK: - TabSortMode

enum TabSortMode: Int, CaseIterable {
    case lastVisited = 0
    case createdDate = 1
    case titleAZ     = 2
    case titleZA     = 3
    case manual      = 4

    var displayName: String {
        switch self {
        case .lastVisited: return "Last Visited"
        case .createdDate: return "Date Created"
        case .titleAZ:     return "Title (A→Z)"
        case .titleZA:     return "Title (Z→A)"
        case .manual:      return "Manual"
        }
    }

    var iconName: String {
        switch self {
        case .lastVisited: return "clock"
        case .createdDate: return "calendar"
        case .titleAZ:     return "textformat.abc"
        case .titleZA:     return "textformat.abc"
        case .manual:      return "hand.draw"
        }
    }
}

// MARK: - TabsListViewController

final class TabsListViewController: NSViewController,
                                    NSTableViewDataSource,
                                    NSTableViewDelegate,
                                    NSSearchFieldDelegate {

    // Callbacks
    var onSelectTab: ((UUID) -> Void)?
    var onOpenTab:   ((UUID) -> Void)?
    var onDeleteTab: ((UUID) -> Void)?
    var onCreateTab: (() -> Void)?
    var onBucketChanged: ((StorageBucket) -> Void)?
    var isWindowOpen: ((UUID) -> Bool)?

    // State
    private weak var tabStore: TabStore?
    private var cancellable: AnyCancellable?
    private var searchText: String = ""
    private(set) var currentBucket: StorageBucket = .active

    var sortMode: TabSortMode = .lastVisited {
        didSet { reloadData() }
    }

    // Subviews
    let searchField = NSSearchField()
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: "No tabs")

    // Sectioned rows
    private enum Row {
        case section(String)
        case tab(TabRecord)
    }
    private var rows: [Row] = []
    private static let tabColumnID = NSUserInterfaceItemIdentifier("TabColumn")

    init(tabStore: TabStore) {
        self.tabStore = tabStore
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 600))
        view.wantsLayer = true

        searchField.placeholderString = "Search Tabs"
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchChanged)

        let col = NSTableColumn(identifier: Self.tabColumnID)
        col.width = 240
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 56
        tableView.style = .sourceList
        tableView.usesAutomaticRowHeights = false
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.target = self
        tableView.doubleAction = #selector(rowDoubleClicked)
        tableView.allowsMultipleSelection = false

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center

        view.addSubview(scrollView)
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        bindStore()
        reloadData()
    }

    // MARK: - Store binding

    private func bindStore() {
        cancellable = tabStore?.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.reloadData() }
        }
    }

    func setBucket(_ bucket: StorageBucket) {
        currentBucket = bucket
        switch bucket {
        case .active:   break
        case .archived: tabStore?.loadArchived()
        case .trash:    tabStore?.loadTrashed()
        }
        onBucketChanged?(bucket)
        reloadData()
    }

    func selectTab(id: UUID) {
        for (i, row) in rows.enumerated() {
            if case let .tab(tab) = row, tab.id == id {
                tableView.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
                tableView.scrollRowToVisible(i)
                return
            }
        }
    }

    func reloadData() {
        guard let store = tabStore else { return }
        let source: [TabRecord]
        switch currentBucket {
        case .active:   source = Array(store.tabs.values)
        case .archived: source = Array(store.archivedTabs.values)
        case .trash:    source = Array(store.trashedTabs.values)
        }

        var filtered = source
        if !searchText.isEmpty {
            filtered = filtered.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.displayURLString.localizedCaseInsensitiveContains(searchText)
            }
        }

        let pinned = filtered.filter { $0.isPinnedTab }.sorted(by: sortComparator)
        let others = filtered.filter { !$0.isPinnedTab }.sorted(by: sortComparator)

        var newRows: [Row] = []
        if !pinned.isEmpty {
            newRows.append(.section("Pinned"))
            for t in pinned { newRows.append(.tab(t)) }
        }
        if !others.isEmpty {
            newRows.append(.section(pinned.isEmpty ? "Tabs" : "Others"))
            for t in others { newRows.append(.tab(t)) }
        }
        rows = newRows
        emptyLabel.stringValue = filtered.isEmpty
            ? (searchText.isEmpty ? bucketEmptyMessage() : "No matching tabs")
            : ""
        emptyLabel.isHidden = !filtered.isEmpty
        tableView.reloadData()
    }

    private func bucketEmptyMessage() -> String {
        switch currentBucket {
        case .active:   return "No tabs"
        case .archived: return "No archived tabs"
        case .trash:    return "Trash is empty"
        }
    }

    private func sortComparator(_ a: TabRecord, _ b: TabRecord) -> Bool {
        switch sortMode {
        case .lastVisited: return a.lastVisitedAt > b.lastVisitedAt
        case .createdDate: return a.createdAt > b.createdAt
        case .titleAZ:     return a.displayTitle.localizedCaseInsensitiveCompare(b.displayTitle) == .orderedAscending
        case .titleZA:     return a.displayTitle.localizedCaseInsensitiveCompare(b.displayTitle) == .orderedDescending
        case .manual:      return a.manualSortOrder < b.manualSortOrder
        }
    }

    // MARK: - Search

    @objc private func searchChanged() {
        searchText = searchField.stringValue
        reloadData()
    }

    // MARK: - Table data

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tv: NSTableView, isGroupRow row: Int) -> Bool {
        if case .section = rows[row] { return true }
        return false
    }

    func tableView(_ tv: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .section(let title):
            let label = NSTextField(labelWithString: title.uppercased())
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.textColor = .secondaryLabelColor
            return label
        case .tab(let tab):
            return TabListRowView(tab: tab)
        }
    }

    func tableView(_ tv: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .section = rows[row] { return 22 }
        return 56
    }

    func tableView(_ tv: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .section = rows[row] { return false }
        return true
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard tableView.selectedRow >= 0 else { return }
        if case let .tab(tab) = rows[tableView.selectedRow] {
            onSelectTab?(tab.id)
        }
    }

    @objc private func rowDoubleClicked() {
        guard tableView.clickedRow >= 0,
              case let .tab(tab) = rows[tableView.clickedRow] else { return }
        onOpenTab?(tab.id)
    }

    // MARK: - Context menu

    func tableView(_ tv: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
        guard case let .tab(tab) = rows[row] else { return [] }
        let trash = NSTableViewRowAction(
            style: .destructive,
            title: "Trash"
        ) { [weak self] _, _ in self?.onDeleteTab?(tab.id) }
        return [trash]
    }

    @objc func createClicked() {
        onCreateTab?()
    }
}

// MARK: - TabListRowView

private final class TabListRowView: NSView {

    init(tab: TabRecord) {
        super.init(frame: .zero)

        let title = NSTextField(labelWithString: tab.displayTitle)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1

        let url = NSTextField(labelWithString: tab.url?.host(percentEncoded: false) ?? tab.displayURLString)
        url.font = .systemFont(ofSize: 11)
        url.textColor = .secondaryLabelColor
        url.lineBreakMode = .byTruncatingTail
        url.maximumNumberOfLines = 1

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        if let favicon = FaviconCache.shared.image(forRef: tab.faviconRef) {
            icon.image = favicon
            icon.imageScaling = .scaleProportionallyDown
        } else {
            let symbol = tab.isPinnedTab ? "pin.fill" : "globe"
            icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            icon.contentTintColor = ThemeRegistry.theme(for: tab.themeID).controlTintColor
        }

        let stack = NSStackView(views: [title, url])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(stack)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            stack.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}
