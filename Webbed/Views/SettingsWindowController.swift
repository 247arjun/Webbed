import AppKit
import SwiftUI
import WebbedKit

// MARK: - SettingsWindowController

@MainActor
final class SettingsWindowController: NSWindowController {

    convenience init() {
        let host = NSHostingController(rootView: MacSettingsView())
        let window = NSWindow(contentViewController: host)
        window.title = "Webbed Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 700, height: 500))
        window.minSize = NSSize(width: 560, height: 400)
        window.center()
        window.setFrameAutosaveName("WebbedSettings")
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }
}

// MARK: - MacSettingsView (root TabView)

struct MacSettingsView: View {
    var body: some View {
        TabView {
            MacGeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            MacAppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            MacWebsitesSettings()
                .tabItem { Label("Websites", systemImage: "globe") }
            MacStorageSettings()
                .tabItem { Label("Storage", systemImage: "internaldrive") }
            MacSyncSettings()
                .tabItem { Label("Sync", systemImage: "icloud") }
        }
        .frame(minWidth: 560, idealWidth: 700, minHeight: 400, idealHeight: 500)
        .padding()
    }
}

// MARK: - General

struct MacGeneralSettings: View {
    @State private var searchProvider: SearchProvider = AppSettings.shared.searchProvider
    @State private var homepage: String = AppSettings.shared.homepageURL?.absoluteString ?? ""
    @State private var launchBehavior: LaunchBehavior = AppSettings.shared.launchBehavior
    @State private var externalBrowserBundleID: String = AppSettings.shared.externalBrowserBundleID
    @State private var browsers: [InstalledBrowser] = []

    var body: some View {
        Form {
            Section("Browsing") {
                Picker("Search Engine", selection: $searchProvider) {
                    ForEach(SearchProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .onChange(of: searchProvider) { _, new in AppSettings.shared.searchProvider = new }

                TextField("Homepage", text: $homepage, prompt: Text("https://example.com"))
                    .onSubmit { commitHomepage() }
            }

            Section("External Browser") {
                Picker("Open in Browser", selection: $externalBrowserBundleID) {
                    ForEach(browsers) { b in Text(b.displayName).tag(b.bundleID) }
                }
                .onChange(of: externalBrowserBundleID) { _, new in
                    AppSettings.shared.externalBrowserBundleID = new
                }
                Text("Used by the **Open in Browser** button in each tab window.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Launch") {
                Picker("On Launch", selection: $launchBehavior) {
                    ForEach(LaunchBehavior.allCases, id: \.rawValue) { b in
                        Text(b.displayName).tag(b)
                    }
                }
                .onChange(of: launchBehavior) { _, new in AppSettings.shared.launchBehavior = new }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            browsers = InstalledBrowsers.all()
            if !browsers.contains(where: { $0.bundleID == externalBrowserBundleID }) {
                externalBrowserBundleID = InstalledBrowsers.systemDefaultBundleID
                AppSettings.shared.externalBrowserBundleID = externalBrowserBundleID
            }
        }
    }

    private func commitHomepage() {
        let trimmed = homepage.trimmingCharacters(in: .whitespacesAndNewlines)
        AppSettings.shared.homepageURL = trimmed.isEmpty ? nil : URL(string: trimmed)
    }
}

// MARK: - Appearance

struct MacAppearanceSettings: View {
    @State private var chromeStyle: ChromeStyle = AppSettings.shared.chromeStyle
    @State private var mobileBreakpoint: Double = AppSettings.shared.mobileBreakpoint

    var body: some View {
        Form {
            Section {
                Picker("Window Chrome", selection: $chromeStyle) {
                    ForEach(ChromeStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: chromeStyle) { _, new in
                    AppSettings.shared.chromeStyle = new
                    NotificationCenter.default.post(name: .webbedChromeStyleChanged, object: nil)
                }
                Text(chromeStyle.blurb)
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Theme") } footer: {
                Text("**Color** uses the site's declared `theme-color` meta tag, or falls back to a dominant color sampled from the favicon. **System** uses neutral chrome that follows your OS appearance.")
                    .font(.caption)
            }

            Section("Responsive Chrome") {
                Slider(value: $mobileBreakpoint, in: 400...900, step: 20) {
                    Text("Mobile chrome breakpoint")
                } minimumValueLabel: { Text("400") } maximumValueLabel: { Text("900") }
                .onChange(of: mobileBreakpoint) { _, new in AppSettings.shared.mobileBreakpoint = new }
                LabeledContent("Current breakpoint", value: "\(Int(mobileBreakpoint)) pt")
                Text("Tab windows narrower than this width collapse to mobile chrome and request mobile pages.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Sync

struct MacSyncSettings: View {
    @State private var syncWithICloud: Bool = AppSettings.shared.syncWithICloud
    @State private var syncTabPreviews: Bool = AppSettings.shared.syncTabPreviews

    var body: some View {
        Form {
            Section("iCloud") {
                Toggle("Sync with iCloud", isOn: $syncWithICloud)
                    .onChange(of: syncWithICloud) { _, new in AppSettings.shared.syncWithICloud = new }
                Toggle("Sync tab previews", isOn: $syncTabPreviews)
                    .onChange(of: syncTabPreviews) { _, new in AppSettings.shared.syncTabPreviews = new }

                LabeledContent("Status") {
                    MacICloudStatusLabel(
                        toggleOn: syncWithICloud,
                        available: StorageLocationResolver.iCloudAvailable,
                        active: syncWithICloud && StorageLocationResolver.iCloudDirectory() != nil
                    )
                }
                LabeledContent("Save location", value: AppSettings.shared.saveLocationDisplayPath)
                    .font(.caption)
                if syncWithICloud && !StorageLocationResolver.iCloudAvailable {
                    Text("Sign in to iCloud and turn on iCloud Drive in System Settings to sync tabs across devices.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - MacICloudStatusLabel

struct MacICloudStatusLabel: View {
    let toggleOn: Bool
    let available: Bool
    let active: Bool

    var body: some View {
        let (symbol, tint, text): (String, Color, String) = {
            if !toggleOn  { return ("icloud.slash",           .secondary, "Disabled") }
            if !available { return ("exclamationmark.icloud", .orange,    "iCloud unavailable") }
            if active     { return ("checkmark.icloud",       .green,     "Syncing") }
            return ("icloud", .secondary, "Local only")
        }()
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).font(.caption)
        }
    }
}
