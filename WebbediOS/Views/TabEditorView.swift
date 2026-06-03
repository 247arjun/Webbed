import SwiftUI
import WebbedKit

// MARK: - TabEditorView

struct TabEditorView: View {
    @EnvironmentObject private var tabStore: TabStore
    let tabID: UUID
    let isReadOnly: Bool
    let bucket: StorageBucket
    let onRestoredToActive: () -> Void
    var onClosed: (() -> Void)? = nil

    @State private var address: String = ""
    @State private var isEditingAddress: Bool = false
    @State private var url: URL?
    @State private var title: String = ""
    @State private var canGoBack: Bool = false
    @State private var canGoForward: Bool = false
    @State private var isLoading: Bool = false
    @State private var progress: Double = 0
    @State private var pendingAction: WebAction? = nil
    @State private var liveRefreshTimer: Timer?
    @State private var liveInterval: LiveModeInterval = .off
    @State private var showSitePermissions = false
    @State private var autoTintFromSite: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(height: 2)
                    .tint(Color(uiColor: chromeTheme.controlTintColor))
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
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomChrome
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .tint(Color(uiColor: chromeTheme.controlTintColor))
        .toolbarBackground(
            chromeTheme.isSynthesized
                ? Color(uiColor: chromeTheme.headerBackgroundColor)
                : Color.clear,
            for: .navigationBar
        )
        .toolbarBackground(chromeTheme.isSynthesized ? .visible : .automatic,
                           for: .navigationBar)
        .toolbarColorScheme(toolbarScheme, for: .navigationBar)
        .onAppear {
            let tab = currentTab()
            self.url = tab?.url
            self.title = tab?.displayTitle ?? ""
            self.address = tab?.displayURLString ?? ""
            self.liveInterval = tab?.liveModeInterval ?? .off
            self.autoTintFromSite = tab?.autoTintFromSite ?? true
            scheduleLiveRefresh(interval: liveInterval)
        }
        .onDisappear {
            liveRefreshTimer?.invalidate()
            liveRefreshTimer = nil
        }
        .sheet(isPresented: $showSitePermissions) {
            if let host = url?.host {
                SitePermissionsSheet(host: host)
            }
        }
        .onChange(of: url) { _, newURL in
            tabStore.updateURL(tabID: tabID, url: newURL)
            if !isEditingAddress { address = newURL?.absoluteString ?? "" }
        }
        .onChange(of: title) { _, newTitle in
            tabStore.updateTitle(tabID: tabID, title: newTitle)
        }
    }

    // MARK: - Top toolbar (menu only — URL bar lives at the bottom)

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    if let url = url { UIApplication.shared.open(url) }
                } label: {
                    Label("Open in Browser", systemImage: "safari")
                }
                .disabled(url == nil)

                if let host = url?.host {
                    Button {
                        showSitePermissions = true
                    } label: {
                        Label("Site Settings for \(host)…", systemImage: "slider.horizontal.3")
                    }
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
                          systemImage: liveInterval == .off ? "bolt.circle" : "bolt.circle.fill")
                }
                Button {
                    toggleAutoTint()
                } label: {
                    Label(autoTintFromSite ? "Match Site Color (On)" : "Match Site Color (Off)",
                          systemImage: autoTintFromSite ? "paintpalette.fill" : "paintpalette")
                }
                .disabled(AppSettings.shared.chromeStyle != .color)
                Divider()
                if bucket == .active {
                    Button { tabStore.archive(tabID: tabID) } label: {
                        Label("Archive", systemImage: "archivebox")
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
                            onClosed?()
                        } label: {
                            Label("Delete Forever", systemImage: "trash.fill")
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
        }
    }

    // MARK: - Safari-style glass chrome (bottom)

    private var bottomChrome: some View {
        VStack(spacing: 10) {
            urlPill
            actionRow
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var urlPill: some View {
        HStack(spacing: 10) {
            Button {
                pendingAction = isLoading ? .stop : .reload
            } label: {
                Image(systemName: isLoading ? "xmark" : "arrow.clockwise")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            TextField("Search or enter website", text: $address,
                      onEditingChanged: { editing in isEditingAddress = editing },
                      onCommit: submitAddress)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.URL)
                .submitLabel(.go)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(in: .capsule)
    }

    private var actionRow: some View {
        HStack(spacing: 0) {
            actionButton(systemImage: "chevron.left", label: "Back",
                         enabled: canGoBack) { pendingAction = .back }
            Spacer(minLength: 0)
            actionButton(systemImage: "chevron.right", label: "Forward",
                         enabled: canGoForward) { pendingAction = .forward }
            Spacer(minLength: 0)
            ShareLink(item: url ?? URL(string: "about:blank")!) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18, weight: .regular))
                    .frame(width: 44, height: 32)
            }
            .disabled(url == nil)
            .foregroundStyle(.primary)
            .opacity(url == nil ? 0.4 : 1.0)
            Spacer(minLength: 0)
            actionButton(systemImage: currentTab()?.isPinnedTab == true ? "pin.fill" : "pin",
                         label: currentTab()?.isPinnedTab == true ? "Unpin" : "Pin",
                         enabled: true) { togglePinnedTab() }
            Spacer(minLength: 0)
            actionButton(systemImage: "trash", label: "Move to Trash",
                         enabled: bucket != .trash, role: .destructive) {
                trashAndDismiss()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassEffect(in: .capsule)
    }

    @ViewBuilder
    private func actionButton(systemImage: String,
                              label: String,
                              enabled: Bool,
                              role: ButtonRole? = nil,
                              action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .regular))
                .frame(width: 44, height: 32)
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
        .foregroundStyle(role == .destructive ? AnyShapeStyle(Color.red)
                                              : AnyShapeStyle(HierarchicalShapeStyle.primary))
        .opacity(enabled ? 1.0 : 0.4)
    }

    private func trashAndDismiss() {
        switch bucket {
        case .active:
            tabStore.trash(tabID: tabID)
        case .archived:
            tabStore.trash(tabID: tabID)
        case .trash:
            return
        }
        onClosed?()
    }

    // MARK: - Helpers

    private func currentTab() -> TabRecord? {
        tabStore.tabs[tabID] ?? tabStore.archivedTabs[tabID] ?? tabStore.trashedTabs[tabID]
    }

    /// Resolved chrome theme — System or synthesized from the current tab's
    /// dominantColor depending on AppSettings.chromeStyle + per-tab opt-out.
    private var chromeTheme: WebbedTheme {
        guard AppSettings.shared.chromeStyle == .color else { return .system() }
        guard let tab = currentTab(), tab.autoTintFromSite,
              let data = tab.dominantColor,
              let color = DominantColor.color(from: data) else { return .system() }
        return .color(from: color)
    }

    /// When the chrome is tinted with a dark color, ask the toolbar to use
    /// dark color scheme so the system glyphs flip white.
    private var toolbarScheme: ColorScheme? {
        guard chromeTheme.isSynthesized else { return nil }
        let isDarkText = chromeTheme.titleTextColor == UIColor.black
        return isDarkText ? .light : .dark
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

    private func toggleAutoTint() {
        autoTintFromSite.toggle()
        tabStore.updateAutoTintFromSite(tabID: tabID, enabled: autoTintFromSite)
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
