import SwiftUI
import WebbedKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel

    @State private var searchProvider: SearchProvider = AppSettings.shared.searchProvider
    @State private var homepage: String = AppSettings.shared.homepageURL?.absoluteString ?? ""
    @State private var defaultTheme: String = AppSettings.shared.defaultThemeID
    @State private var launchBehavior: LaunchBehavior = AppSettings.shared.launchBehavior
    @State private var mobileBreakpoint: Double = AppSettings.shared.mobileBreakpoint
    @State private var syncWithICloud: Bool = AppSettings.shared.syncWithICloud
    @State private var syncTabPreviews: Bool = AppSettings.shared.syncTabPreviews

    var body: some View {
        Form {
            Section("Search") {
                Picker("Search Engine", selection: $searchProvider) {
                    ForEach(SearchProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .onChange(of: searchProvider) { _, new in
                    AppSettings.shared.searchProvider = new
                }
            }

            Section("Homepage") {
                TextField("https://example.com", text: $homepage)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.URL)
                    .onSubmit { commitHomepage() }
                Button("Save Homepage") { commitHomepage() }
            }

            Section("Appearance") {
                Picker("Default Theme", selection: $defaultTheme) {
                    ForEach(ThemeRegistry.allThemes) { t in
                        Text(t.displayName).tag(t.id)
                    }
                }
                .onChange(of: defaultTheme) { _, new in
                    AppSettings.shared.defaultThemeID = new
                }
            }

            Section {
                Picker("On Launch", selection: $launchBehavior) {
                    ForEach(LaunchBehavior.allCases, id: \.rawValue) { b in
                        Text(b.displayName).tag(b)
                    }
                }
                .onChange(of: launchBehavior) { _, new in
                    AppSettings.shared.launchBehavior = new
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mobile chrome breakpoint: \(Int(mobileBreakpoint)) pt")
                        .font(.subheadline)
                    Slider(value: $mobileBreakpoint, in: 400...900, step: 20) {
                        Text("Mobile breakpoint")
                    } minimumValueLabel: { Text("400").font(.caption) }
                      maximumValueLabel: { Text("900").font(.caption) }
                    .onChange(of: mobileBreakpoint) { _, new in
                        AppSettings.shared.mobileBreakpoint = new
                    }
                }
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
                LabeledContent("Status") {
                    iCloudStatusLabel(
                        toggleOn: syncWithICloud,
                        available: StorageLocationResolver.iCloudAvailable,
                        active: appModel.usingICloud
                    )
                }
                LabeledContent("Save location") {
                    Text(AppSettings.shared.saveLocationDisplayPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } header: { Text("Sync") } footer: {
                if syncWithICloud && !StorageLocationResolver.iCloudAvailable {
                    Text("Sign in to iCloud and turn on iCloud Drive in System Settings to sync tabs across devices.")
                        .font(.caption)
                }
            }

            Section("Privacy") {
                NavigationLink {
                    SitePermissionsListView()
                } label: {
                    Label("Site Settings", systemImage: "slider.horizontal.3")
                }
            }

            Section("About") {
                LabeledContent("Version",
                               value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1")
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func commitHomepage() {
        let trimmed = homepage.trimmingCharacters(in: .whitespacesAndNewlines)
        AppSettings.shared.homepageURL = trimmed.isEmpty ? nil : URL(string: trimmed)
    }
}

// MARK: - iCloudStatusLabel (shared shape)

struct iCloudStatusLabel: View {
    let toggleOn: Bool
    let available: Bool
    let active: Bool

    var body: some View {
        let (symbol, tint, text): (String, Color, String) = {
            if !toggleOn          { return ("icloud.slash",      .secondary, "Disabled") }
            if !available         { return ("exclamationmark.icloud", .orange, "iCloud unavailable") }
            if active             { return ("checkmark.icloud",  .green,     "Syncing") }
            return ("icloud", .secondary, "Local only")
        }()
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).font(.caption)
        }
    }
}
