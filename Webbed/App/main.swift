import AppKit

// Pure AppKit app entry point — no SwiftUI App lifecycle.
// This gives us full, uncontested ownership of the main menu.

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
