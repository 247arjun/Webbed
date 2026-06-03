import SwiftUI
import WebbedKit

// MARK: - StorageView

struct StorageView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var stats: DiskCacheManager.Stats = .zero
    @State private var showClearConfirm = false
    @State private var pendingClearTarget: ClearTarget? = nil

    enum ClearTarget: String, Identifiable {
        case favicons, snapshots
        var id: String { rawValue }
        var displayName: String { self == .favicons ? "Favicons" : "Tab Previews" }
    }

    private var tabsDirectory: URL {
        let svc = appModel.tabStore.persistenceService
        return svc.tabsDirectory
    }

    var body: some View {
        List {
            Section {
                cacheRow(title: "Favicons", icon: "globe",
                         bytes: stats.faviconBytes, count: stats.faviconCount,
                         target: .favicons)
                cacheRow(title: "Tab Previews", icon: "photo",
                         bytes: stats.snapshotBytes, count: stats.snapshotCount,
                         target: .snapshots)
            } header: {
                Text("Disk Cache")
            } footer: {
                Text("**Clear** removes cached files. **Regenerate** also clears, then refetches each item the next time you visit the corresponding tab. Favicons live on this device only and never sync through iCloud.")
            }

            Section {
                LabeledContent("Total on disk", value: stats.totalBytes.bytesFormatted)
                LabeledContent("Total items", value: "\(stats.totalCount)")
                Button {
                    refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .navigationTitle("Storage")
        .onAppear { refresh() }
    }

    @ViewBuilder
    private func cacheRow(title: String,
                          icon: String,
                          bytes: Int64,
                          count: Int,
                          target: ClearTarget) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            VStack(alignment: .trailing) {
                Text(bytes.bytesFormatted).font(.body.monospacedDigit())
                Text("\(count) items").font(.caption).foregroundStyle(.secondary)
            }
            Menu {
                Button("Clear", role: .destructive) {
                    clear(target)
                }
                Button("Regenerate") {
                    regenerate(target)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private func refresh() {
        stats = DiskCacheManager.shared.stats(tabsDirectory: tabsDirectory)
    }

    private func clear(_ target: ClearTarget) {
        switch target {
        case .favicons:
            DiskCacheManager.shared.clearFavicons()
        case .snapshots:
            DiskCacheManager.shared.clearSnapshots(
                tabsDirectory: tabsDirectory, tabStore: appModel.tabStore
            )
        }
        refresh()
    }

    private func regenerate(_ target: ClearTarget) {
        switch target {
        case .favicons:
            DiskCacheManager.shared.regenerateFavicons(tabStore: appModel.tabStore)
        case .snapshots:
            DiskCacheManager.shared.regenerateSnapshots(
                tabsDirectory: tabsDirectory, tabStore: appModel.tabStore
            )
        }
        refresh()
    }
}
