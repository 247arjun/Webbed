import SwiftUI
import WebbedKit

/// Phase 0 stub. Phase 4 replaces this with the real `NavigationSplitView` /
/// `NavigationStack` master/detail mirrored from Noted's `RootView`.
struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tint)
            Text("Webbed")
                .font(.title.weight(.semibold))
            Text("Phase 0 scaffold")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview { RootView() }
