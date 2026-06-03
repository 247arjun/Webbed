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
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 480, height: 360))
        window.center()
        window.setFrameAutosaveName("WebbedSettings")
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }
}

// MARK: - MacSettingsView (SwiftUI)

struct MacSettingsView: View {
    @State private var searchProvider: SearchProvider = AppSettings.shared.searchProvider
    @State private var homepage: String = AppSettings.shared.homepageURL?.absoluteString ?? ""
    @State private var defaultTheme: String = AppSettings.shared.defaultThemeID
    @State private var launchBehavior: LaunchBehavior = AppSettings.shared.launchBehavior
    @State private var mobileBreakpoint: Double = AppSettings.shared.mobileBreakpoint
    @State private var syncTabPreviews: Bool = AppSettings.shared.syncTabPreviews
    @State private var syncWithICloud: Bool = AppSettings.shared.syncWithICloud

    var body: some View {
        Form {
            Section {
                Picker("Search Engine", selection: $searchProvider) {
                    ForEach(SearchProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .onChange(of: searchProvider) { _, new in
                    AppSettings.shared.searchProvider = new
                }
                TextField("Homepage", text: $homepage, prompt: Text("https://example.com"))
                    .onSubmit { commitHomepage() }
            } header: { Text("Browsing") }

            Section {
                Picker("Default Theme", selection: $defaultTheme) {
                    ForEach(ThemeRegistry.allThemes) { t in
                        Text(t.displayName).tag(t.id)
                    }
                }
                .onChange(of: defaultTheme) { _, new in
                    AppSettings.shared.defaultThemeID = new
                }
            } header: { Text("Appearance") }

            Section {
                Picker("On Launch", selection: $launchBehavior) {
                    ForEach(LaunchBehavior.allCases, id: \.rawValue) { b in
                        Text(b.displayName).tag(b)
                    }
                }
                .onChange(of: launchBehavior) { _, new in
                    AppSettings.shared.launchBehavior = new
                }
                Slider(value: $mobileBreakpoint, in: 400...900, step: 20) {
                    Text("Mobile chrome breakpoint")
                } minimumValueLabel: { Text("400") } maximumValueLabel: { Text("900") }
                .onChange(of: mobileBreakpoint) { _, new in
                    AppSettings.shared.mobileBreakpoint = new
                }
                LabeledContent("Current breakpoint", value: "\(Int(mobileBreakpoint)) pt")
            } header: { Text("Behavior") }

            Section {
                Toggle("Sync with iCloud", isOn: $syncWithICloud)
                    .onChange(of: syncWithICloud) { _, new in
                        AppSettings.shared.syncWithICloud = new
                    }
                Toggle("Sync tab previews", isOn: $syncTabPreviews)
                    .onChange(of: syncTabPreviews) { _, new in
                        AppSettings.shared.syncTabPreviews = new
                    }
                LabeledContent("Save location", value: AppSettings.shared.saveLocationDisplayPath)
                    .font(.caption)
            } header: { Text("Sync") }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 460, idealWidth: 480, minHeight: 380)
    }

    private func commitHomepage() {
        let trimmed = homepage.trimmingCharacters(in: .whitespacesAndNewlines)
        AppSettings.shared.homepageURL = trimmed.isEmpty ? nil : URL(string: trimmed)
    }
}
