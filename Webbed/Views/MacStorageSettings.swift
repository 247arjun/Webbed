import SwiftUI
import WebbedKit

// MARK: - MacStorageSettings

struct MacStorageSettings: View {
    @State private var stats: DiskCacheManager.Stats = .zero
    @State private var refreshing = false

    private var tabStore: TabStore { AppCoordinator.shared.tabStore }
    private var tabsDirectory: URL { AppCoordinator.shared.persistenceService.tabsDirectory }

    var body: some View {
        Form {
            Section {
                cacheRow(
                    title: "Favicons",
                    icon: "globe",
                    bytes: stats.faviconBytes,
                    count: stats.faviconCount,
                    onClear: {
                        DiskCacheManager.shared.clearFavicons()
                        refresh()
                    },
                    onRegenerate: {
                        DiskCacheManager.shared.regenerateFavicons(tabStore: tabStore)
                        refresh()
                    }
                )
                cacheRow(
                    title: "Tab Previews",
                    icon: "photo",
                    bytes: stats.snapshotBytes,
                    count: stats.snapshotCount,
                    onClear: {
                        DiskCacheManager.shared.clearSnapshots(tabsDirectory: tabsDirectory,
                                                               tabStore: tabStore)
                        refresh()
                    },
                    onRegenerate: {
                        DiskCacheManager.shared.regenerateSnapshots(tabsDirectory: tabsDirectory,
                                                                    tabStore: tabStore)
                        refresh()
                    }
                )
            } header: {
                Text("Disk Cache")
            } footer: {
                Text("**Clear** removes cached files. **Regenerate** also clears, then refetches each item the next time you visit the corresponding tab. Favicons live on this device only and never sync through iCloud.")
                    .font(.caption)
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
        .formStyle(.grouped)
        .onAppear { refresh() }
    }

    private func refresh() {
        refreshing = true
        defer { refreshing = false }
        stats = DiskCacheManager.shared.stats(tabsDirectory: tabsDirectory)
    }

    @ViewBuilder
    private func cacheRow(title: String,
                          icon: String,
                          bytes: Int64,
                          count: Int,
                          onClear: @escaping () -> Void,
                          onRegenerate: @escaping () -> Void) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            VStack(alignment: .trailing) {
                Text(bytes.bytesFormatted).font(.body.monospacedDigit())
                Text("\(count) items").font(.caption).foregroundStyle(.secondary)
            }
            Menu {
                Button("Clear", role: .destructive, action: onClear)
                Button("Regenerate", action: onRegenerate)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}
