import SwiftUI
import WebbedKit

// MARK: - MacWebsitesSettings

/// Safari-style Websites tab: capability sidebar on the left, list of origins
/// with grants on the right. Plus a global "On Other Sites" default.
struct MacWebsitesSettings: View {
    @ObservedObject private var store: PermissionStore = AppCoordinator.shared.permissionStore
    @State private var selectedKind: PermissionKind = .javascript

    var body: some View {
        HSplitView {
            // Capability sidebar
            List(selection: $selectedKind) {
                ForEach(PermissionKind.allCases) { kind in
                    Label(kind.displayName, systemImage: kind.symbolName)
                        .tag(kind)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)

            // Per-kind detail
            VStack(spacing: 0) {
                MacPermissionDetailView(kind: selectedKind, store: store)
            }
        }
    }
}

// MARK: - MacPermissionDetailView

struct MacPermissionDetailView: View {
    let kind: PermissionKind
    @ObservedObject var store: PermissionStore

    private var origins: [OriginPermissions] {
        store.origins.values
            .filter { $0.grants[kind] != nil }
            .sorted { $0.origin < $1.origin }
    }

    private var defaultDecision: PermissionDecision {
        store.defaults[kind] ?? kind.defaultDecision
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: kind.symbolName)
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text(kind.displayName).font(.headline)
                    Text(blurb).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)

            Divider()

            if origins.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No sites configured",
                    systemImage: kind.symbolName,
                    description: Text("Sites you grant or deny will appear here.")
                )
                Spacer()
            } else {
                Table(origins) {
                    TableColumn("Website") { o in
                        Text(o.origin).font(.body.monospaced())
                    }
                    TableColumn("Permission") { o in
                        Picker("", selection: bindingForOrigin(o)) {
                            if kind.supportsAsk { Text("Ask").tag(PermissionDecision.ask) }
                            Text("Allow").tag(PermissionDecision.allow)
                            Text("Deny").tag(PermissionDecision.deny)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    .width(140)
                    TableColumn("") { o in
                        Button {
                            store.resetDecision(for: o.origin, kind: kind)
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Reset to default")
                    }
                    .width(28)
                }
            }

            Divider()

            HStack {
                Text("On other sites:")
                    .foregroundStyle(.secondary)
                Picker("", selection: defaultBinding) {
                    if kind.supportsAsk { Text("Ask").tag(PermissionDecision.ask) }
                    Text("Allow").tag(PermissionDecision.allow)
                    Text("Deny").tag(PermissionDecision.deny)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 110)
                Spacer()
                if kind.requiresReload {
                    Label("Open tabs need a reload to pick up new rules.",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
    }

    private func bindingForOrigin(_ o: OriginPermissions) -> Binding<PermissionDecision> {
        Binding(
            get: { o.grants[kind] ?? kind.defaultDecision },
            set: { store.setDecision(for: o.origin, kind: kind, decision: $0) }
        )
    }

    private var defaultBinding: Binding<PermissionDecision> {
        Binding(
            get: { defaultDecision },
            set: { store.setDefault(kind, decision: $0) }
        )
    }

    private var blurb: String {
        switch kind {
        case .javascript:      return "When denied, the page renders with scripting disabled. Some sites won't work."
        case .popups:          return "When denied, JavaScript can't open new windows without a click."
        case .autoplay:        return "When denied, media requires a user gesture before playing."
        case .camera:          return "Controls access to webcams. Ask shows the system prompt."
        case .microphone:      return "Controls access to audio capture devices."
        case .location:        return "Controls access to GPS / geolocation."
        case .notifications:   return "Controls whether the site can request push notifications."
        case .pasteboard:      return "Controls JavaScript reads of the system clipboard."
        case .insecureContent: return "When denied, http subresources inside https pages are blocked."
        case .openInExternal:  return "Allow to always hand off main-frame loads to your external browser."
        }
    }
}
