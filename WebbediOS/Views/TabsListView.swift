import SwiftUI
import WebbedKit

// MARK: - TabsListView (Active bucket)

struct TabsListView: View {
    @EnvironmentObject private var tabStore: TabStore
    @EnvironmentObject private var appModel: AppModel

    @Binding var selection: UUID?
    @Binding var activeBucket: StorageBucket
    @Binding var showSettings: Bool

    @State private var searchText: String = ""
    @State private var sortMode: SortMode = .lastVisited

    enum SortMode: String, CaseIterable, Identifiable {
        case lastVisited = "Last Visited"
        case created     = "Date Created"
        case titleAZ     = "Title (A→Z)"
        case titleZA     = "Title (Z→A)"
        var id: String { rawValue }
    }

    private var sortedAndFiltered: [TabRecord] {
        var all = Array(tabStore.tabs.values)
        if !searchText.isEmpty {
            all = all.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.displayURLString.localizedCaseInsensitiveContains(searchText)
            }
        }
        switch sortMode {
        case .lastVisited: return all.sorted { $0.lastVisitedAt > $1.lastVisitedAt }
        case .created:     return all.sorted { $0.createdAt > $1.createdAt }
        case .titleAZ:     return all.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        case .titleZA:     return all.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedDescending }
        }
    }

    private var pinned: [TabRecord] { sortedAndFiltered.filter { $0.isPinnedTab } }
    private var others: [TabRecord] { sortedAndFiltered.filter { !$0.isPinnedTab } }

    var body: some View {
        List(selection: $selection) {
            if !pinned.isEmpty {
                Section("Pinned") { ForEach(pinned) { row(for: $0) } }
            }
            Section(pinned.isEmpty ? "Tabs" : "Others") {
                if others.isEmpty && pinned.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No tabs yet" : "No matching tabs",
                        systemImage: "safari",
                        description: Text(searchText.isEmpty
                                          ? "Tap + to open your first tab."
                                          : "Try a different search.")
                    )
                } else {
                    ForEach(others) { row(for: $0) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Webbed")
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search tabs")
        .refreshable { appModel.refresh() }
        .toolbar { toolbarContent }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            BucketSwitcherMenu(activeBucket: $activeBucket, showSettings: $showSettings)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Sort by", selection: $sortMode) {
                    ForEach(SortMode.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Sort")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                let tab = tabStore.createTab(url: AppSettings.shared.homepageURL)
                selection = tab.id
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("New Tab")
        }
    }

    @ViewBuilder
    private func row(for tab: TabRecord) -> some View {
        TabRowView(tab: tab)
            .tag(tab.id)
            .swipeActions(edge: .leading) {
                Button {
                    tabStore.updatePinnedTab(tabID: tab.id, isPinnedTab: !tab.isPinnedTab)
                } label: {
                    Label(tab.isPinnedTab ? "Unpin" : "Pin",
                          systemImage: tab.isPinnedTab ? "pin.slash" : "pin")
                }.tint(.orange)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    if selection == tab.id { selection = nil }
                    tabStore.trash(tabID: tab.id)
                } label: {
                    Label("Trash", systemImage: "trash")
                }
                Button {
                    if selection == tab.id { selection = nil }
                    tabStore.archive(tabID: tab.id)
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }.tint(.gray)
            }
    }
}

// MARK: - TabRowView

struct TabRowView: View {
    let tab: TabRecord
    @ObservedObject private var favicons = FaviconCache.shared

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let img = favicons.image(forRef: tab.faviconRef) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: tab.isPinnedTab ? "pin.fill" : "globe")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 22, height: 22)
            .id(favicons.version)

            VStack(alignment: .leading, spacing: 2) {
                Text(tab.displayTitle)
                    .font(.body)
                    .lineLimit(1)
                Text(tab.url?.host(percentEncoded: false) ?? tab.displayURLString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - BucketSwitcherMenu

struct BucketSwitcherMenu: View {
    @Binding var activeBucket: StorageBucket
    @Binding var showSettings: Bool

    var body: some View {
        Menu {
            Section {
                Button { activeBucket = .active }   label: { Label("Tabs",     systemImage: "tray.2") }
                Button { activeBucket = .archived } label: { Label("Archived", systemImage: "archivebox") }
                Button { activeBucket = .trash }    label: { Label("Trash",    systemImage: "trash") }
            }
            Section {
                Button { showSettings = true } label: { Label("Settings…", systemImage: "gearshape") }
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .accessibilityLabel("Menu")
        }
    }
}

// MARK: - Color bridge

extension WebbedKit.PlatformColor {
    var swiftUIColor: Color { Color(uiColor: self) }
}
