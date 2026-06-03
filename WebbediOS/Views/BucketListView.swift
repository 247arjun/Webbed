import SwiftUI
import WebbedKit

// MARK: - BucketListView

/// List of tabs in the Archived or Trash bucket. The active bucket has its
/// own dedicated view (`TabsListView`) because it surfaces pin/archive
/// actions that don't apply here.
struct BucketListView: View {
    @EnvironmentObject private var tabStore: TabStore
    @EnvironmentObject private var appModel: AppModel

    let bucket: StorageBucket
    @Binding var selection: UUID?
    @Binding var activeBucket: StorageBucket
    @Binding var showSettings: Bool

    @State private var searchText: String = ""

    private var source: [TabRecord] {
        switch bucket {
        case .archived: return Array(tabStore.archivedTabs.values)
        case .trash:    return Array(tabStore.trashedTabs.values)
        case .active:   return []
        }
    }

    private var filtered: [TabRecord] {
        let s = source.sorted(by: { $0.updatedAt > $1.updatedAt })
        if searchText.isEmpty { return s }
        return s.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
            || $0.displayURLString.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List(selection: $selection) {
            if filtered.isEmpty {
                ContentUnavailableView(
                    bucket == .archived ? "No archived tabs" : "Trash is empty",
                    systemImage: bucket == .archived ? "archivebox" : "trash",
                    description: Text(bucket == .archived
                                      ? "Swipe a tab in your list and Archive to send it here."
                                      : "Items in Trash are purged after 30 days.")
                )
            } else {
                Section(bucket == .archived ? "Archived" : "Trash") {
                    ForEach(filtered) { tab in
                        TabRowView(tab: tab)
                            .tag(tab.id)
                            .swipeActions(edge: .leading) {
                                Button {
                                    if bucket == .archived { tabStore.unarchive(tabID: tab.id) }
                                    else                   { tabStore.restoreFromTrash(tabID: tab.id) }
                                    activeBucket = .active
                                    selection = tab.id
                                } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }.tint(.green)
                            }
                            .swipeActions(edge: .trailing) {
                                if bucket == .trash {
                                    Button(role: .destructive) {
                                        if selection == tab.id { selection = nil }
                                        tabStore.deleteForever(tabID: tab.id)
                                    } label: {
                                        Label("Delete Forever", systemImage: "trash.fill")
                                    }
                                } else {
                                    Button(role: .destructive) {
                                        if selection == tab.id { selection = nil }
                                        tabStore.trash(tabID: tab.id)
                                    } label: {
                                        Label("Trash", systemImage: "trash")
                                    }
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(bucket == .archived ? "Archived" : "Trash")
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                BucketSwitcherMenu(activeBucket: $activeBucket, showSettings: $showSettings)
            }
            if bucket == .trash && !filtered.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        tabStore.emptyTrash()
                    } label: {
                        Text("Empty")
                    }
                }
            }
        }
    }
}
