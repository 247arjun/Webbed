import SwiftUI
import WebbedKit

/// Phase 4 stub. Phase 6 fleshes this out with the full settings surface.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var searchProvider: SearchProvider = AppSettings.shared.searchProvider
    @State private var homepage: String = AppSettings.shared.homepageURL?.absoluteString ?? ""

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

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1")
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
