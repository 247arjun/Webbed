# Webbed — Engineering Plan

A cross-platform synced browser for macOS / iOS / iPadOS that intentionally mirrors the architecture and feel of `Noted/` (read as reference only — no changes to `Noted/`).

Webbed treats **a browsing session = a "tab" record**, the same way Noted treats a note as a record. Each tab is a syncable object with state (URL, title, last scroll, pin, theme, frame). On macOS, every tab can live as its own borderless tear-out window (the Noted sticky-note window paradigm applied to web pages). On iOS/iPadOS the same tabs render in a SwiftUI master/detail.

---

## 1. Goals & Non-Goals

### 1.1 Primary Goals
1. Cross-platform browser: macOS, iPadOS, iOS, sharing a single source of truth via iCloud.
2. Reuse Apple's web engine — `WKWebView` on every platform. No bundled engine.
3. Per-tab tear-out windows on macOS (borderless, custom chrome, optional pin-on-top), styled like Noted's sticky-note windows but tuned for a browser.
4. Responsive layout — the macOS window collapses gracefully to a "mobile" layout below a width breakpoint, just like resizing a Noted window.
5. Master/detail sidebar UI on iPadOS (regular size class) and a stack-based UI on iPhone (compact size class), driven by `NavigationSplitView`, mirroring Noted's `RootView`.
6. Sync: tab records and a "pinned tabs / sessions" list sync across devices via iCloud Drive ubiquity container.
7. Minimal app size and minimal external dependencies. Zero third-party Swift packages.
8. Native feel on every platform.

### 1.2 Non-Goals for v1
- Custom rendering engine, custom JS engine, custom networking stack.
- Extensions / Chrome / Safari extension compatibility.
- Profile management beyond a single default profile.
- Sync of cookies, autofill, passwords (let the OS / iCloud Keychain / Safari handle credentials via `ASWebAuthenticationSession` if needed later).
- Sync of full history (only the synced tab/session list — local history is per-device).
- Reader mode, content blockers, ad blocking, downloads manager UI, dev tools surface.
- Cross-device drag-and-drop of tabs (handoff is a stretch goal — see §13).

---

## 2. Mapping from Noted → Webbed

| Noted concept | Webbed concept |
|---|---|
| `NoteRecord` | `TabRecord` (URL, title, favicon ref, scroll, pin, frame, theme, group) |
| Rich text RTF body | Last-rendered favicon + snapshot thumbnail (small PNG sidecar) |
| `NoteStore` | `TabStore` |
| `FilePersistenceService` (json + rtf sidecar per UUID) | `FilePersistenceService` (json + png sidecar per UUID) |
| Per-note borderless `NoteWindow` (macOS) | Per-tab borderless `TabWindow` (macOS) with `WKWebView` host |
| `NoteContentView` | `TabContentView` (chrome + web view) |
| `NoteTextView` (`NSTextView`) | `WebChromeView` hosting `WKWebView` |
| `WindowManager` | `WindowManager` (same role; one controller per tab) |
| `AllNotesWindowController` (master/detail) | `LibraryWindowController` — tab library + preview pane |
| `ThemeRegistry` (sticky colors) | `ThemeRegistry` (chrome accent palettes) |
| `RootView` (iOS NavigationSplitView) | `RootView` (iOS NavigationSplitView over the tab library) |
| `RichTextEditor` (UIViewRepresentable over UITextView) | `WebView` (UIViewRepresentable over `WKWebView`) |
| `MarkdownShortcuts` | URL / search auto-detection in the address field |
| `iCloudChangeObserver` | Same class, generic over record type |

Webbed will fork the **patterns** but not literal code. Naming, ownership graph, and storage layout deliberately track Noted so the codebase is immediately recognizable.

---

## 3. Architecture

### 3.1 Stack Decision
- **macOS**: AppKit shell + SwiftUI for utility panes (settings, theme picker popovers). Pure AppKit main entry (`main.swift` calling `NSApplication.shared.run()`), same as Noted, to keep full control of the main menu and borderless windows.
- **iOS/iPadOS**: SwiftUI App lifecycle. `NavigationSplitView` on regular size class, `NavigationStack` on compact. Same pattern as `Noted/NotedIOS/Views/RootView.swift`.
- **Shared**: a Swift package `WebbedKit` containing models, persistence, settings, sync observer, and platform-agnostic helpers.
- **Web engine**: `WKWebView` everywhere. iOS/iPad have no choice; macOS uses the same engine deliberately for parity, smaller binary, and consistent web behavior.

### 3.2 Ownership Graph
```
AppCoordinator (singleton)
├── TabStore                  (active / archived / trash buckets, like NoteStore)
├── WindowManager             (one TabWindowController per open tab — macOS only)
├── PersistenceService        (FilePersistenceService → iCloud Drive)
├── ThemeRegistry
├── FaviconCache              (in-memory + on-disk LRU)
└── ICloudChangeObserver
```

### 3.3 Repo Layout
```
Webbed/
├── project.yml                   # xcodegen, modeled after Noted/project.yml
├── Configs/
│   ├── Signing.xcconfig
│   └── Signing.local.xcconfig.example
├── Webbed/                       # macOS target
│   ├── App/                      # main.swift, AppDelegate, NotedAppShortcuts → WebbedAppShortcuts
│   ├── Windows/                  # TabWindow, TabWindowController, WindowManager
│   ├── Views/                    # TabContentView, WebChromeView, AddressBarView,
│   │                             #   ResizeHandleView, ThemePickerViewController,
│   │                             #   SettingsWindowController
│   ├── Library/                  # LibraryWindowController, TabsListViewController,
│   │                             #   TabDetailViewController  (Noted's AllNotes equivalent)
│   ├── Services/                 # AppCoordinator
│   ├── Resources/                # Info.plist, Webbed.entitlements, Assets.xcassets
│   └── Supporting/
├── WebbediOS/                    # iOS / iPadOS target
│   ├── App/                      # WebbedApp.swift, AppDelegate, AppModel, Shortcuts
│   ├── Views/                    # RootView, TabsListView, TabEditorView,
│   │                             #   WebView (UIViewRepresentable), AddressBar,
│   │                             #   GroupListView, SettingsView, ThemePickerView
│   └── Resources/                # Info.plist, WebbediOS.entitlements
└── WebbedKit/                    # Swift Package
    ├── Package.swift
    └── Sources/WebbedKit/
        ├── Models/               # TabRecord, TabGroup, PersistedRect, WebbedTheme
        ├── Services/             # TabStore, PersistenceService, AppSettings,
        │                         #   StorageLocationResolver, iCloudChangeObserver,
        │                         #   FaviconCache, URLHeuristics, SearchProviders,
        │                         #   TabIntents
        └── Supporting/           # Logging, PlatformTypes
```
Mirrors `Noted/` one-to-one so contributors who know Noted know Webbed.

### 3.4 Dependencies
- Apple frameworks only: `WebKit`, `AppKit`, `UIKit`, `SwiftUI`, `Combine`, `Foundation`, `os.log`, `AppIntents`, `UniformTypeIdentifiers`.
- No SPM packages outside of the in-repo `WebbedKit`. No CocoaPods. No Carthage.
- Build tool: `xcodegen` (already in the project workflow for Noted) — keeps the `.xcodeproj` regenerable from `project.yml`.

---

## 4. Data Model (in `WebbedKit/Models/`)

### 4.1 `TabRecord`
```swift
public struct TabRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var url: URL?              // nil = "New Tab" home
    public var title: String          // last known page title, empty until first load
    public var faviconRef: String?    // sha1 of favicon bytes → FaviconCache key
    public var snapshotRef: String?   // sha1 of last snapshot → on-disk png
    public var scrollY: Double        // last vertical scroll position
    public var themeID: String        // chrome accent
    public var isPinned: Bool         // tear-out window floats above others (macOS)
    public var isPinnedTab: Bool      // appears in Pinned section of library (all platforms)
    public var groupID: UUID?         // nil = ungrouped
    public var frame: PersistedRect   // macOS tear-out window frame
    public var createdAt: Date
    public var updatedAt: Date
    public var lastVisitedAt: Date
    public var isClosed: Bool         // window not currently open (macOS)
    public var isArchived: Bool
    public var manualSortOrder: Int
    public var isInTrash: Bool
    public var trashedAt: Date?
}
```
Same bucket model and decoding strategy as `NoteRecord` (back-compatible `decodeIfPresent` for evolving fields).

### 4.2 `TabGroup` (lightweight; v1)
```swift
public struct TabGroup: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var themeID: String
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date
}
```
Optional — wired up only if §10 (Groups) ships in v1.

### 4.3 `PersistedRect`
Identical to Noted's — copy verbatim.

### 4.4 `WebbedTheme`
Reuse the field shape of `NoteTheme` (header bg, body bg, title color, control tint) but values map to **browser chrome** accent rather than sticky-note paper. Default themes:
- `graphite` (system default)
- `aqua`
- `pumpkin`
- `forest`
- `rose`

Each theme also defines a `chromeBlur` flag (use `NSVisualEffectView` material on macOS, `UIVisualEffectView` on iOS) for adaptive translucent chrome.

---

## 5. Persistence (in `WebbedKit/Services/`)

Identical disk layout to Noted, swapped extensions:
```
<iCloudContainer or local>/
├── <uuid>.json   ← TabRecord metadata
├── <uuid>.png    ← snapshot sidecar (optional, lossy WebP-style PNG, ~80kB cap)
├── Groups/<uuid>.json
├── Archived/<uuid>.json + .png
└── Trash/<uuid>.json + .png
```

- `PersistenceService` protocol with the same surface: `loadActive`, `loadArchived`, `loadTrashed`, `save`, `move(noteID:to:)`, `permanentlyDelete`, `purgeExpiredTrash`, `migrateNotes(to:)`.
- `FilePersistenceService` uses `NSFileCoordinator` for safe iCloud co-access, same as Noted.
- `StorageLocationResolver` resolves iCloud ubiquity container `iCloud.com.arjun.Webbed` (matching the Noted naming convention `iCloud.com.arjun.Noted`) or falls back to `Application Support/Webbed/`.
- 30-day Trash purge, run on launch via `AppCoordinator`.
- `iCloudChangeObserver` reused unchanged in pattern — observes `NSMetadataQuery` and emits `(id, kind)` changes.

**Note on web cache & cookies**: WebKit's own `WKWebsiteDataStore` storage stays per-device. Only tab metadata syncs. Pinned tabs sync, so opening Webbed on iPad shows the same pinned set, but session cookies are not transferred.

---

## 6. Web Engine (`WKWebView`)

### 6.1 Configuration
A single helper, `WebbedKit/Services/WebViewFactory`:
```swift
public enum WebViewFactory {
    public static func make(for tab: TabRecord) -> WKWebView { … }
}
```
Configuration:
- `WKWebViewConfiguration` with a shared `WKProcessPool` so multiple tabs share render processes (memory win).
- `defaultDataStore()` (persistent) so logins survive launches; non-persistent dataStore optional in a future "Private Tab" mode.
- `allowsBackForwardNavigationGestures = true`
- `allowsLinkPreview = true`
- `mediaTypesRequiringUserActionForPlayback = .all`
- `preferences.javaScriptCanOpenWindowsAutomatically = false` (we intercept `webView(_:createWebViewWith:for:windowFeatures:)` to spawn a new `TabRecord` instead).
- Inject a tiny user-script that:
  - Reports document title changes (KVO-able via `.title`, so no script needed) — we just KVO `title`, `URL`, `estimatedProgress`, `canGoBack`, `canGoForward`, `isLoading`.
  - Captures favicon link via DOM (`document.querySelectorAll('link[rel~="icon"]')`), posts to a `WKScriptMessageHandler`.
- Snapshot via `WKWebView.takeSnapshot(with:completionHandler:)` debounced 1.5s after `didFinishNavigation`. Save as PNG sidecar, update `snapshotRef`.

### 6.2 Per-platform host views
- **macOS**: `WebChromeView` (NSView) owns the `WKWebView` and a top "address bar" strip (matches Noted's header band: 34pt tall, drag region, controls cluster right-aligned).
- **iOS/iPadOS**: `WebView` `UIViewRepresentable` (modeled directly on `Noted/NotedIOS/Views/RichTextEditor.swift`) wrapping the same `WKWebView`. Address bar lives in the SwiftUI toolbar.

### 6.3 New windows / popups
`webView(_:createWebViewWith:for:windowFeatures:)`: create a new `TabRecord`, open via `WindowManager.openNewTabWindow(...)`, return its `WKWebView`. On iOS, push a new tab in the active group.

---

## 7. macOS UI Architecture

### 7.1 Window roster
Same as Noted:
1. **Tear-out tab windows** — borderless `TabWindow`, one per open tab. Custom chrome.
2. **Library window** — `LibraryWindowController` (master/detail, mirrors `AllNotesWindowController`).
3. **Settings window** — `SettingsWindowController` (SwiftUI hosted in `NSHostingController`).

### 7.2 `TabWindow` (borderless)
Copy `Noted/Noted/Windows/NoteWindow.swift` verbatim in **shape**:
- `styleMask = [.borderless]`
- `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = true`
- `level = .normal` (flips to `.floating` when pinned)
- `minSize = NSSize(width: 320, height: 280)` (smaller than browser convention; allows mobile-mode collapse)
- Default new tab size: 1024×720, cascaded.
- `canBecomeKey/canBecomeMain = true`.

### 7.3 `TabContentView` layout
```
┌────────────────────────────────────────────────┐
│  HEADER (38 pt, drag region except controls)   │
│  [◀ ▶ ⟳] [ Address Bar / Search             ] │
│                          [Pin][🎨][⋯][✕]      │
├────────────────────────────────────────────────┤
│                                                │
│           WKWebView fills remainder            │
│                                                │
│                                          ╱╱╱  │ ← ResizeHandleView (Noted reuse)
└────────────────────────────────────────────────┘
```
- Reuse `ResizeHandleView` literally from Noted (copy file, change import).
- Title bar hidden (`titleVisibility = .hidden` doesn't apply to borderless — use `[.borderless]` and draw our own header band).
- Address bar = `NSTextField` styled like Noted's title field (no border, custom focus ring) with embedded loading progress drawn as a thin bar below the field.
- Controls cluster: Pin (toggles `.floating`), Theme (popover with palette of accent colors → `ThemePickerViewController` reused), More (overflow menu: Reload, Duplicate, Move to Group, Mute, Open in Library, Send to Trash), Close.
- Header is the drag region. Address-bar field drags are suppressed when first-responder (same rule as Noted's title field: drag from header empty space only).

### 7.4 Responsive collapse (the "mobile mode" the user asked for)
A `compactWidthThreshold` (default **600 pt**) is checked on every `windowDidResize`:
- ≥ 600 pt → "desktop chrome": back/forward/reload visible left, full URL bar, controls right.
- < 600 pt → "mobile chrome": just URL bar + a single overflow `⋯` button. Back/forward become edge-swipe gestures (already enabled via `allowsBackForwardNavigationGestures`).
- The threshold also flips the `WKWebView` `customUserAgent` to a mobile-Safari UA string so responsive sites render their mobile layout. Toggle is purely width-driven; no manual switch. (User-agent is per-tab, not synced.)

Two further breakpoints:
- `tinyWidthThreshold` = **360 pt** — hide URL text entirely, show only domain + lock glyph; address bar expands on click.
- `ultraTinyHeightThreshold` = **220 pt** — collapse header to 28 pt and shrink controls.

All breakpoints live in one file `Webbed/Views/ChromeLayoutMetrics.swift` so they're easy to tune.

### 7.5 Pin-on-top
Toggling the pin control:
1. Calls `tabStore.updatePinned(tabID:, isPinned:)` (mirrors `updatePinned` in `NoteStore`).
2. Updates window `level = isPinned ? .floating : .normal`.
3. Swaps pin glyph (`pin` ↔ `pin.fill`), exactly as in `NoteContentView.updatePinState`.

### 7.6 `WindowManager` & cascade
Cascade logic, restore-on-launch, "close" only marks `isClosed=true`, `openWindow(for:)` reuses or recreates — all lifted from Noted's `WindowManager` with `noteID` → `tabID`.

### 7.7 Main Menu
Modeled on `Noted/Noted/App/AppDelegate.swift`:
- **File**: New Tab (⌘T), New Window (⌘N — opens a fresh `TabRecord` in a new tear-out), Duplicate Tab, Close Tab (⌘W), Library… (⇧⌘L), Archived Tabs…, Trash…
- **Edit**: standard Undo/Redo/Cut/Copy/Paste/Find (Find ⌘F triggers `WKWebView`'s text search via `findString:configuration:resultHandler:`).
- **View**: Reload (⌘R), Force Reload (⇧⌘R), Stop (⌘.), Zoom In/Out/Actual Size (`pageZoom` on `WKWebView`), Toggle Reader Mode (deferred).
- **History**: Back, Forward, Home, Recently Closed.
- **Window**: Pin Tab on Top, standard window menu.

### 7.8 Library window (Noted's AllNotes equivalent)
`LibraryWindowController` is a near line-for-line port of `AllNotesWindowController`:
- `NSSplitViewController` with a sidebar (`TabsListViewController`) and detail (`TabDetailViewController`).
- Sidebar list shows tabs grouped by **Pinned**, **Groups**, **Others**. Search field, sort modes (Last Visited, Date Created, Title, Manual). Drag-to-reorder for Manual mode.
- Detail pane previews the tab: large favicon, title, URL, snapshot thumbnail, last-visited timestamp, quick actions (Open in Window, Pin, Theme, Archive, Trash).
- Toolbar: `+` New Tab, Search field, Folder/Bucket switcher (Active / Archived / Trash) — direct copy of Noted's `folderItemID` pattern.
- Bucket switching clears the detail pane and updates the window title (same hooks as Noted's `onBucketChanged`).

---

## 8. iOS / iPadOS UI

Direct port of Noted's iOS layer.

### 8.1 `WebbedApp` (SwiftUI App)
```swift
@main
struct WebbedApp: App {
    @UIApplicationDelegateAdaptor(WebbedAppDelegate.self) var appDelegate
    @StateObject var appModel = AppModel.shared
    var body: some Scene {
        WindowGroup("Webbed", id: "main") {
            RootView()
                .environmentObject(appModel)
                .environmentObject(appModel.tabStore)
        }
        // Per-tab scenes — iPadOS Stage Manager / Split View. On iPhone collapses to push nav.
        WindowGroup("Tab", id: "tab", for: UUID.self) { $tabID in
            if let id = tabID { TabSceneView(tabID: id).environmentObject(appModel) }
        }
    }
}
```
Direct shape match with `Noted/NotedIOS/App/NotedApp.swift`.

### 8.2 `RootView`
Copy `Noted/NotedIOS/Views/RootView.swift`. Replace:
- `NoteListView` → `TabsListView`
- `BucketListView` → `BucketListView` (same name, generic over `TabRecord`)
- `NoteEditorView` → `TabEditorView`
- Sidebar root switches by `activeBucket: StorageBucket`.

Behavior preserved: `@Environment(\.horizontalSizeClass)` chooses `NavigationSplitView` vs `NavigationStack`. iPad gets master/detail; iPhone gets push.

### 8.3 `TabEditorView`
Hosts the SwiftUI chrome:
- Toolbar (top): back / forward / reload / address bar / overflow.
- `WebView` (UIViewRepresentable wrapping `WKWebView`) fills body.
- Bottom toolbar on iPhone (Safari-style): tabs button (returns to list), share, bookmarks (optional), forward.
- Pull-to-reload via `UIRefreshControl` attached to `WKWebView.scrollView`.

### 8.4 Tabs list
- Active / Pinned / Groups sections (same shape as Noted's pinned / others sections).
- Search (`.searchable`).
- `Menu`-based sort picker.
- `+` toolbar item creates a new tab and selects it.
- Swipe actions: Pin / Archive / Move to Trash (matches Noted).

### 8.5 Per-tab windows on iPadOS
The `WindowGroup(for: UUID.self)` enables Stage Manager / Split View per-tab — the closest iPad equivalent to macOS tear-out windows. The user can drag a tab from the list to a new iPad window.

---

## 9. Sync Semantics

- Tab metadata syncs through the iCloud Drive container exactly like Noted notes.
- **Conflict rule**: last-writer-wins on `updatedAt` per field group:
  - URL/title/scroll → updated on navigation and on background.
  - Frame → updated on debounced move/resize (macOS only — iOS ignores `frame` field).
  - Pinned, theme, group → immediate save.
- **Open-state is local**: `isClosed` is **not** synced across devices (mark it `localOnly` in JSON via a small `LocalState` sidecar JSON, or simply re-derive on launch). Otherwise opening on iPad would force-open a window on Mac.
- **Snapshot sidecars**: capped at 80 kB. Snapshots only sync if the user enables "Sync tab previews" (default ON; toggle in Settings — keeps iCloud usage bounded).
- **Favicons**: not synced — re-fetched from origin on each device, cached in `FaviconCache`.
- **History**: not synced in v1.

---

## 10. Tab Groups (v1, optional)

A `TabGroup` record + a flat `groupID` on `TabRecord` is enough for v1 — no nested groups.
- Library sidebar (macOS) and SwiftUI sidebar (iOS) show groups as expandable sections.
- Drag a tab onto a group in the sidebar to move it.
- "Open All in Group" command → opens a tear-out window per tab (macOS) / pushes tabs into the active scene (iOS).

If §10 risks bleeding into v1 scope it ships in v1.1 — the `groupID` field is added now so the data model is forward-compatible.

---

## 11. Address Bar & Search

`URLHeuristics` in `WebbedKit/Services/`:
- If input parses as a URL with scheme → use as-is.
- If input has a `.` and no spaces → prepend `https://`.
- Else → search via current `SearchProvider` (**default Google**; pluggable: DuckDuckGo, Bing, Kagi, Brave, plus `?`-style first-token bangs).
- `SearchProviders.swift` defines a small enum + URL templates. Settings exposes the selector.

Address bar autocomplete: local-only matches against the last 200 distinct visited URLs (per-device history table in a tiny JSON file under `Application Support`). No sync. Cap size; FIFO eviction.

---

## 12. Settings

Mirror `Noted/NotedKit/Services/AppSettings.swift` structure (`UserDefaults`-backed, `@MainActor` singleton):
- `syncWithICloud: Bool`
- `customSaveLocationURL: URL?` (macOS only, security-scoped bookmark)
- `defaultThemeID: String`
- `launchBehavior: LaunchBehavior` — `libraryAndRestore | libraryOnly | restoreOnly` (parallel to Noted's enum)
- `searchProvider: SearchProvider`
- `defaultMobileBreakpoint: Double` (advanced; default 600)
- `syncTabPreviews: Bool`
- `homepageURL: URL?` (nil → built-in home)

Settings UI is SwiftUI on both platforms (macOS hosts the same view via `NSHostingController` in `SettingsWindowController`).

---

## 13. App Intents (for parity with Noted)

`WebbedKit/Services/TabIntents.swift`:
- `OpenTabIntent(url:)` — opens a new tab (or focuses an existing matching URL).
- `OpenPinnedTabIntent(id:)` — opens a specific pinned tab.
- `SearchWebIntent(query:)` — opens new tab with the current search provider.
Registered via `IntentHostRegistry.current = AppCoordinator.shared`, exactly as Noted does for `NoteIntentHost`.

Handoff (`NSUserActivity` with `webpageURL`) is a stretch goal — easy because `WKWebView` exposes the current URL.

---

## 14. Build & Tooling

- `project.yml` is a near-clone of `Noted/project.yml`:
  - `bundleIdPrefix: com.arjun` (or user-chosen).
  - Targets: `Webbed` (macOS), `WebbediOS` (iOS).
  - Package dep: `WebbedKit` (local).
  - Shared `Configs/Signing.xcconfig` + `Signing.local.xcconfig.example`.
- Deployment targets:
  - **macOS 26.0+** (parity with Noted; lets the chrome adopt Liquid Glass materials).
  - iOS 17.0+.
- Swift 6.0 language mode; `@MainActor` discipline matching Noted.
- No CI gating in v1; document a one-line `xcodegen generate && xcodebuild -scheme Webbed build` smoke test in `README.md`.

---

## 15. Security & Privacy

- `WKWebView` provides per-origin sandboxing; we don't bypass it.
- No third-party SDKs → no third-party telemetry.
- Default search provider Google (changeable in Settings; DuckDuckGo / Kagi / Bing / Brave available out of the box).
- Mixed-content (http inside https): block by default; show inline notice with a one-tap "Load anyway" affordance.
- Camera / mic / location: route `WKUIDelegate` permission prompts to native OS dialogs; remember per-origin grants in `UserDefaults`.
- `App Sandbox` entitlements (macOS) match Noted's setup: iCloud container, user-selected file read/write (for downloads), outgoing network. No `com.apple.security.network.server`.
- iOS entitlements: iCloud container only.

---

## 16. Implementation Phases

### Phase 0 — Scaffolding
1. Create `WebbedKit/` Swift package with `PlatformTypes`, `Logging`, `PersistedRect`, empty `TabRecord`, `WebbedTheme`.
2. Create `project.yml`, `Configs/`, `Webbed/`, `WebbediOS/` skeletons.
3. `xcodegen generate`; both targets compile with a stub view that says "Webbed".

### Phase 1 — Single Tab, macOS
1. `TabRecord`, `TabStore`, `FilePersistenceService` (json + png sidecar), `StorageLocationResolver` (container `iCloud.com.arjun.Webbed`).
2. `AppCoordinator`, AppKit `main.swift`, `AppDelegate`, main menu.
3. `TabWindow` (borderless), `TabContentView` (header + address field + `WKWebView` + `ResizeHandleView`).
4. `WebViewFactory`, KVO on title/URL/progress, address bar load+submit (Google as default search).
5. New Tab (⌘T), Close Tab (⌘W), restore-on-launch re-opens pinned tabs as tear-out windows, persist frame.

### Phase 2 — Polish & Responsive macOS
1. Pin-on-top, theme picker popover, overflow menu.
2. Snapshots on navigation, favicon capture.
3. Responsive breakpoints (desktop / mobile / tiny chrome).
4. Resize debounce + frame persistence (lift from Noted).

### Phase 3 — Library Window
1. `LibraryWindowController` (master/detail), `TabsListViewController`, `TabDetailViewController`.
2. Bucket switcher (Active / Archived / Trash), search, sort modes.
3. Open-from-library → tear-out window via `WindowManager`.

### Phase 4 — iOS / iPadOS
1. `WebbediOS` target boots, loads `TabStore`.
2. `RootView` (NavigationSplitView/Stack), `TabsListView`, `TabEditorView`, `WebView` (UIViewRepresentable).
3. Address bar in `.toolbar`, Safari-style bottom bar on iPhone.
4. Per-tab `WindowGroup(for: UUID.self)` scene for iPadOS multi-window.

### Phase 5 — Sync
1. iCloud container wiring (Webbed entitlement + ubiquity container ID). **DONE** — `iCloud.com.arjun.Webbed` declared in both targets' entitlements and `Info.plist` `NSUbiquitousContainers`; container registered in Xcode under team `24CVMV6NZZ`.
2. `iCloudChangeObserver` adapted; verify external updates land in `TabStore`.
3. `isClosed` left local; snapshot sync toggle.

### Phase 6 — Intents, Settings, Search Providers
1. `OpenTabIntent`, `SearchWebIntent`.
2. `AppSettings`, `SettingsView` (SwiftUI shared), `SettingsWindowController` (macOS host).
3. Search-provider picker, mobile breakpoint slider.

### Phase 7 — v1.1 candidates
- Tab groups UI.
- Handoff via `NSUserActivity`.
- Reader mode (uses Safari's reader JS? — likely roll our own using `Readability.js` bundled locally, still zero external Swift deps).
- Per-origin permission management UI.
- Downloads pane.

---

## 17. Resolved Decisions (locked before Phase 1)

| # | Decision | Value |
|---|---|---|
| 1 | iCloud ubiquity container ID | `iCloud.com.arjun.Webbed` (matches Noted convention) |
| 2 | macOS bundle ID | `com.arjun.Webbed` |
| 2 | iOS bundle ID | `com.arjun.Webbed.ios` |
| 3 | macOS deployment target | **26.0** (parity with Noted; uses Liquid Glass where available) |
| 3 | iOS deployment target | 17.0 |
| 4 | Default search provider | **Google** (`https://www.google.com/search?q={query}`) |
| 5 | Launch behavior — macOS | Pinned tabs re-open as tear-out windows on launch (mirrors Noted's "restore windows" semantics). `LaunchBehavior` enum still exposes the three modes so the user can override. |
| 5 | Launch behavior — iOS/iPadOS | Pinned tabs are surfaced in the list but opened lazily on first selection — no eager `WKWebView` instantiation at launch. |
| 6 | Snapshot privacy | Never snapshot pages loaded in Private mode. Private mode itself is post-v1; the snapshot path will already check the tab's `isPrivate` flag so it's safe when Private ships. |

---

## 18. What Webbed Inherits Verbatim from Noted (Patterns, Not Code)

These files in Noted are the closest templates and should be re-read when implementing the corresponding Webbed file:

| Webbed file | Noted reference |
|---|---|
| `Webbed/App/main.swift` | `Noted/Noted/App/main.swift` |
| `Webbed/App/AppDelegate.swift` | `Noted/Noted/App/AppDelegate.swift` |
| `Webbed/Services/AppCoordinator.swift` | `Noted/Noted/Services/AppCoordinator.swift` |
| `Webbed/Windows/TabWindow.swift` | `Noted/Noted/Windows/NoteWindow.swift` |
| `Webbed/Windows/TabWindowController.swift` | `Noted/Noted/Windows/NoteWindowController.swift` |
| `Webbed/Windows/WindowManager.swift` | `Noted/Noted/Windows/WindowManager.swift` |
| `Webbed/Views/TabContentView.swift` | `Noted/Noted/Views/NoteContentView.swift` |
| `Webbed/Views/ResizeHandleView.swift` | `Noted/Noted/Views/ResizeHandleView.swift` (near-verbatim copy) |
| `Webbed/Library/LibraryWindowController.swift` | `Noted/Noted/AllNotes/AllNotesWindowController.swift` |
| `Webbed/Library/TabsListViewController.swift` | `Noted/Noted/AllNotes/AllNotesViewController.swift` |
| `Webbed/Library/TabDetailViewController.swift` | `Noted/Noted/AllNotes/NoteDetailViewController.swift` |
| `WebbediOS/App/WebbedApp.swift` | `Noted/NotedIOS/App/NotedApp.swift` |
| `WebbediOS/App/AppModel.swift` | `Noted/NotedIOS/App/AppModel.swift` |
| `WebbediOS/Views/RootView.swift` | `Noted/NotedIOS/Views/RootView.swift` |
| `WebbediOS/Views/TabsListView.swift` | `Noted/NotedIOS/Views/NoteListView.swift` |
| `WebbediOS/Views/TabEditorView.swift` | `Noted/NotedIOS/Views/NoteEditorView.swift` |
| `WebbediOS/Views/WebView.swift` | `Noted/NotedIOS/Views/RichTextEditor.swift` |
| `WebbedKit/Models/TabRecord.swift` | `Noted/NotedKit/Sources/NotedKit/Models/NoteRecord.swift` |
| `WebbedKit/Models/WebbedTheme.swift` | `Noted/NotedKit/Sources/NotedKit/Models/NoteTheme.swift` |
| `WebbedKit/Services/TabStore.swift` | `Noted/NotedKit/Sources/NotedKit/Services/NoteStore.swift` |
| `WebbedKit/Services/PersistenceService.swift` | `Noted/NotedKit/Sources/NotedKit/Services/PersistenceService.swift` |
| `WebbedKit/Services/AppSettings.swift` | `Noted/NotedKit/Sources/NotedKit/Services/AppSettings.swift` |
| `WebbedKit/Services/iCloudChangeObserver.swift` | `Noted/NotedKit/Sources/NotedKit/Services/iCloudChangeObserver.swift` |
| `WebbedKit/Services/StorageLocationResolver.swift` | `Noted/NotedKit/Sources/NotedKit/Services/StorageLocationResolver.swift` |
| `WebbedKit/Services/TabIntents.swift` | `Noted/NotedKit/Sources/NotedKit/Services/NoteIntents.swift` |

Reading these in pairs is the fastest onramp for anyone implementing a Webbed file.
