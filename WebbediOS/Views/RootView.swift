import SwiftUI
import WebbedKit

// MARK: - RootView

/// Top-level chrome for iOS / iPadOS. Mirrors Noted's `RootView`: master/detail
/// on regular size class via NavigationSplitView, push navigation on compact.
struct RootView: View {
    @EnvironmentObject private var tabStore: TabStore
    @EnvironmentObject private var appModel: AppModel

    @State private var activeBucket: StorageBucket = .active
    @State private var selectedTabID: UUID?
    @State private var showSettings = false
    @Environment(\.horizontalSizeClass) private var hSizeClass

    var body: some View {
        Group {
            if hSizeClass == .regular {
                NavigationSplitView {
                    sidebar
                } detail: {
                    detailPane
                }
            } else {
                NavigationStack {
                    sidebar
                        .navigationDestination(item: $selectedTabID) { id in
                            editor(for: id)
                        }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
        }
        .onChange(of: activeBucket) { _, _ in
            selectedTabID = nil
        }
        .onChange(of: appModel.pendingOpenTabID) { _, id in
            guard let id else { return }
            activeBucket = .active
            selectedTabID = id
            appModel.pendingOpenTabID = nil
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        switch activeBucket {
        case .active:
            TabsListView(
                selection: $selectedTabID,
                activeBucket: $activeBucket,
                showSettings: $showSettings
            )
        case .archived:
            BucketListView(
                bucket: .archived,
                selection: $selectedTabID,
                activeBucket: $activeBucket,
                showSettings: $showSettings
            )
        case .trash:
            BucketListView(
                bucket: .trash,
                selection: $selectedTabID,
                activeBucket: $activeBucket,
                showSettings: $showSettings
            )
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailPane: some View {
        if let id = selectedTabID, resolve(id) != nil {
            editor(for: id)
        } else {
            ContentUnavailableView(
                emptyTitle,
                systemImage: emptySymbol,
                description: Text(emptySubtitle)
            )
        }
    }

    @ViewBuilder
    private func editor(for id: UUID) -> some View {
        if let tab = resolve(id) {
            TabEditorView(
                tabID: id,
                isReadOnly: tab.isArchived || tab.isInTrash,
                bucket: bucketFor(tab),
                onRestoredToActive: {
                    activeBucket = .active
                    selectedTabID = id
                },
                onClosed: {
                    selectedTabID = nil
                }
            )
            .id(id)
        } else {
            ContentUnavailableView("Tab not found", systemImage: "questionmark.folder")
        }
    }

    // MARK: - Helpers

    private func resolve(_ id: UUID) -> TabRecord? {
        tabStore.tabs[id]
            ?? tabStore.archivedTabs[id]
            ?? tabStore.trashedTabs[id]
    }

    private func bucketFor(_ tab: TabRecord) -> StorageBucket {
        if tab.isInTrash   { return .trash }
        if tab.isArchived  { return .archived }
        return .active
    }

    private var emptyTitle: String {
        switch activeBucket {
        case .active:   return "No tab selected"
        case .archived: return "Archived Tabs"
        case .trash:    return "Trash"
        }
    }

    private var emptySymbol: String {
        switch activeBucket {
        case .active:   return "safari"
        case .archived: return "archivebox"
        case .trash:    return "trash"
        }
    }

    private var emptySubtitle: String {
        switch activeBucket {
        case .active:   return "Pick a tab from the sidebar or tap + to start one."
        case .archived: return "Tabs you archive show up here."
        case .trash:    return "Tabs you delete live here for 30 days before being purged."
        }
    }
}

// MARK: - TabSceneView (per-tab iPadOS window)

struct TabSceneView: View {
    @EnvironmentObject private var tabStore: TabStore
    @EnvironmentObject private var appModel: AppModel
    let tabID: UUID

    var body: some View {
        if let tab = tabStore.tabs[tabID] {
            TabEditorView(
                tabID: tabID,
                isReadOnly: false,
                bucket: tab.isInTrash ? .trash : tab.isArchived ? .archived : .active,
                onRestoredToActive: {}
            )
        } else {
            ContentUnavailableView("Tab not found", systemImage: "questionmark.folder")
        }
    }
}
