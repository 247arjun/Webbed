import SwiftUI
import WebbedKit

// MARK: - TabEditorView

struct TabEditorView: View {
    @EnvironmentObject private var tabStore: TabStore
    let tabID: UUID
    let isReadOnly: Bool
    let bucket: StorageBucket
    let onRestoredToActive: () -> Void

    @State private var address: String = ""
    @State private var isEditingAddress: Bool = false
    @State private var url: URL?
    @State private var title: String = ""
    @State private var canGoBack: Bool = false
    @State private var canGoForward: Bool = false
    @State private var isLoading: Bool = false
    @State private var progress: Double = 0
    @State private var pendingAction: WebAction? = nil
    @State private var showShare = false
    @State private var liveRefreshTimer: Timer?
    @State private var liveInterval: LiveModeInterval = .off

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(height: 2)
            }
            WebView(
                tabID: tabID,
                url: $url,
                title: $title,
                canGoBack: $canGoBack,
                canGoForward: $canGoForward,
                isLoading: $isLoading,
                estimatedProgress: $progress,
                pendingAction: $pendingAction
            )
            .ignoresSafeArea(edges: bucket == .active ? [.bottom] : [])
            bottomBar
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear {
            let tab = currentTab()
            self.url = tab?.url
            self.title = tab?.displayTitle ?? ""
            self.address = tab?.displayURLString ?? ""
            self.liveInterval = tab?.liveModeInterval ?? .off
            scheduleLiveRefresh(interval: liveInterval)
        }
        .onDisappear {
            liveRefreshTimer?.invalidate()
            liveRefreshTimer = nil
        }
        .onChange(of: url) { _, newURL in
            tabStore.updateURL(tabID: tabID, url: newURL)
            if !isEditingAddress { address = newURL?.absoluteString ?? "" }
        }
        .onChange(of: title) { _, newTitle in
            tabStore.updateTitle(tabID: tabID, title: newTitle)
        }
    }

    // MARK: - Address bar (in toolbar)

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 6) {
                if isLoading {
                    Button { pendingAction = .stop } label: { Image(systemName: "xmark") }
                } else {
                    Button { pendingAction = .reload } label: { Image(systemName: "arrow.clockwise") }
                }
                TextField("Search or enter URL", text: $address,
                          onEditingChanged: { editing in isEditingAddress = editing },
                          onCommit: submitAddress)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .frame(minWidth: 180)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { showShare = true } label: { Label("Share…", systemImage: "square.and.arrow.up") }
                Button { togglePinnedTab() } label: {
                    Label(currentTab()?.isPinnedTab == true ? "Unpin from Library" : "Pin in Library",
                          systemImage: currentTab()?.isPinnedTab == true ? "pin.slash" : "pin")
                }
                Menu {
                    ForEach(LiveModeInterval.allCases) { option in
                        Button {
                            setLiveMode(option)
                        } label: {
                            if option == liveInterval {
                                Label(option.displayName, systemImage: "checkmark")
                            } else {
                                Text(option.displayName)
                            }
                        }
                    }
                } label: {
                    Label("Live Mode…" + (liveInterval == .off ? "" : " (\(liveInterval.shortLabel))"),
                          systemImage: liveInterval == .off ? "dot.radiowaves.left.and.right" : "dot.radiowaves.left.and.right")
                }
                Divider()
                if bucket == .active {
                    Button { tabStore.archive(tabID: tabID) } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    Button(role: .destructive) { tabStore.trash(tabID: tabID) } label: {
                        Label("Move to Trash", systemImage: "trash")
                    }
                } else {
                    Button {
                        if bucket == .trash { tabStore.restoreFromTrash(tabID: tabID) }
                        else                { tabStore.unarchive(tabID: tabID) }
                        onRestoredToActive()
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                    if bucket == .trash {
                        Button(role: .destructive) {
                            tabStore.deleteForever(tabID: tabID)
                        } label: {
                            Label("Delete Forever", systemImage: "trash.fill")
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - iPhone Safari-style bottom bar

    private var bottomBar: some View {
        HStack {
            Button { pendingAction = .back } label: {
                Image(systemName: "chevron.left").imageScale(.large)
            }.disabled(!canGoBack)
            Spacer()
            Button { pendingAction = .forward } label: {
                Image(systemName: "chevron.right").imageScale(.large)
            }.disabled(!canGoForward)
            Spacer()
            ShareLink(item: url ?? URL(string: "about:blank")!) {
                Image(systemName: "square.and.arrow.up").imageScale(.large)
            }.disabled(url == nil)
            Spacer()
            Button { togglePinnedTab() } label: {
                Image(systemName: currentTab()?.isPinnedTab == true ? "pin.fill" : "pin")
                    .imageScale(.large)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Helpers

    private func currentTab() -> TabRecord? {
        tabStore.tabs[tabID] ?? tabStore.archivedTabs[tabID] ?? tabStore.trashedTabs[tabID]
    }

    private func submitAddress() {
        guard let resolved = URLHeuristics.resolve(address, using: AppSettings.shared.searchProvider) else { return }
        pendingAction = .load(resolved)
        url = resolved
    }

    private func togglePinnedTab() {
        guard let tab = currentTab() else { return }
        tabStore.updatePinnedTab(tabID: tabID, isPinnedTab: !tab.isPinnedTab)
    }

    private func setLiveMode(_ interval: LiveModeInterval) {
        liveInterval = interval
        tabStore.updateLiveMode(tabID: tabID, interval: interval)
        scheduleLiveRefresh(interval: interval)
    }

    private func scheduleLiveRefresh(interval: LiveModeInterval) {
        liveRefreshTimer?.invalidate()
        liveRefreshTimer = nil
        guard let seconds = interval.seconds else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { _ in
            Task { @MainActor in pendingAction = .reload }
        }
        RunLoop.main.add(timer, forMode: .common)
        liveRefreshTimer = timer
    }
}
