import SwiftUI
import WebbedKit

// MARK: - SitePermissionsSheet

/// Per-tab quick-toggle sheet, mirrors macOS popover. Presented from the
/// TabEditorView overflow menu.
struct SitePermissionsSheet: View {
    let host: String
    @EnvironmentObject private var store: PermissionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(PermissionKind.allCases) { kind in
                        SitePermissionRow(host: host, kind: kind, store: store)
                    }
                } header: {
                    Text("Permissions for \(host)")
                } footer: {
                    Text("Changes take effect on next reload.")
                }

                Section {
                    Button("Reset All", role: .destructive) {
                        store.resetOrigin(host)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Site Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - SitePermissionRow

struct SitePermissionRow: View {
    let host: String
    let kind: PermissionKind
    @ObservedObject var store: PermissionStore

    var body: some View {
        HStack {
            Label(kind.displayName, systemImage: kind.symbolName)
            Spacer()
            Picker("", selection: binding) {
                if kind.supportsAsk { Text("Ask").tag(PermissionDecision.ask) }
                Text("Allow").tag(PermissionDecision.allow)
                Text("Deny").tag(PermissionDecision.deny)
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private var binding: Binding<PermissionDecision> {
        Binding(
            get: { store.decision(for: host, kind: kind) },
            set: { store.setDecision(for: host, kind: kind, decision: $0) }
        )
    }
}

// MARK: - SitePermissionsListView (Settings → Site Settings)

struct SitePermissionsListView: View {
    @EnvironmentObject private var store: PermissionStore
    @State private var selectedKind: PermissionKind = .javascript

    var body: some View {
        List {
            Section("Capability") {
                Picker("Permission", selection: $selectedKind) {
                    ForEach(PermissionKind.allCases) { kind in
                        Label(kind.displayName, systemImage: kind.symbolName).tag(kind)
                    }
                }
                .pickerStyle(.navigationLink)
            }

            Section("On Other Sites") {
                Picker("Default", selection: defaultBinding) {
                    if selectedKind.supportsAsk { Text("Ask").tag(PermissionDecision.ask) }
                    Text("Allow").tag(PermissionDecision.allow)
                    Text("Deny").tag(PermissionDecision.deny)
                }
                .pickerStyle(.segmented)
            }

            let originsForKind = store.origins.values
                .filter { $0.grants[selectedKind] != nil }
                .sorted { $0.origin < $1.origin }

            Section(selectedKind.displayName) {
                if originsForKind.isEmpty {
                    Text("No sites have a custom rule for \(selectedKind.displayName.lowercased()).")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(originsForKind) { o in
                        HStack {
                            Text(o.origin).font(.body.monospaced())
                            Spacer()
                            Picker("", selection: bindingForOrigin(o)) {
                                if selectedKind.supportsAsk { Text("Ask").tag(PermissionDecision.ask) }
                                Text("Allow").tag(PermissionDecision.allow)
                                Text("Deny").tag(PermissionDecision.deny)
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                store.resetDecision(for: o.origin, kind: selectedKind)
                            } label: {
                                Label("Reset", systemImage: "arrow.uturn.backward")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Site Settings")
    }

    private func bindingForOrigin(_ o: OriginPermissions) -> Binding<PermissionDecision> {
        Binding(
            get: { o.grants[selectedKind] ?? selectedKind.defaultDecision },
            set: { store.setDecision(for: o.origin, kind: selectedKind, decision: $0) }
        )
    }

    private var defaultBinding: Binding<PermissionDecision> {
        Binding(
            get: { store.defaults[selectedKind] ?? selectedKind.defaultDecision },
            set: { store.setDefault(selectedKind, decision: $0) }
        )
    }
}
