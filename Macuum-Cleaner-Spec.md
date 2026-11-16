# Macuum Cleaner — Application Specification

**App Name:** Macuum Cleaner  
**Git Repository:** `Maccum-Cleaner`  
**App Icon:** `AppImage.png` (placed at root of repository)  
**Target Platform:** macOS Sonoma (14.0) and later  
**Language:** Swift 5.9+ / SwiftUI  
**Distribution:** Direct download (notarized .dmg) + optional Mac App Store  
**Architecture:** Universal Binary (Apple Silicon + Intel)

---

## 1. Vision & Goals

Macuum Cleaner is a lightweight, safe, and transparent macOS cleaning utility that helps users reclaim disk space and keep their Mac tidy. It scans for well-known categories of junk files, presents a clear summary before anything is deleted, and never removes files without explicit user approval. It is not a system optimizer or a system "speed booster" — it is a focused, honest disk cleaner.

**Design principles:**
- Safety first: show the user exactly what will be deleted before acting
- Transparency: explain what each category is and why it is safe to delete
- Non-destructive by default: offer to move to Trash rather than permanent delete where appropriate
- Fast: scans should complete in under 30 seconds on typical Macs
- Lightweight: no background daemons, no login items, no always-on processes unless the user enables scheduled cleaning

---

## 2. Tech Stack

| Layer | Choice |
|-------|--------|
| UI | SwiftUI (macOS 14+) |
| Backend / Scanning | Foundation, FileManager, URLResourceValues |
| Concurrency | Swift Concurrency (async/await, TaskGroup) |
| Persistence | UserDefaults (settings), JSON file (scan history) |
| Sandboxing | **Not sandboxed** — distributed outside Mac App Store to allow full file system access. Notarized and Gatekeeper-compliant. |
| Minimum deployment | macOS 14.0 Sonoma |

---

## 3. Repository Structure

```
Maccum-Cleaner/
├── AppImage.png                  ← App icon for repo root
├── README.md
├── Macuum Cleaner.xcodeproj/
├── Macuum Cleaner/
│   ├── App/
│   │   ├── MaccumCleanerApp.swift
│   │   └── AppDelegate.swift
│   ├── Views/
│   │   ├── MainWindowView.swift           ← Root window with tab switcher
│   │   ├── CleanerTab/
│   │   │   ├── ScanView.swift             ← Scan progress & results
│   │   │   ├── CategoryRowView.swift      ← Individual junk category row
│   │   │   ├── FileListView.swift         ← Expandable file detail list
│   │   │   └── CleanConfirmView.swift     ← Confirmation sheet before clean
│   │   ├── AppManagerTab/
│   │   │   ├── AppManagerView.swift       ← Root view for App Manager tab
│   │   │   ├── AppListView.swift          ← Sortable/filterable app list
│   │   │   ├── AppRowView.swift           ← Single app row with icon, name, size
│   │   │   ├── AppDetailPanel.swift       ← Right panel: remnant files list
│   │   │   └── UninstallConfirmView.swift ← Confirmation sheet before uninstall
│   │   ├── SettingsView.swift
│   │   └── AboutView.swift
│   ├── Models/
│   │   ├── JunkCategory.swift         ← Category enum + metadata
│   │   ├── JunkFile.swift             ← Struct for a discovered file
│   │   ├── ScanResult.swift           ← Aggregated scan results
│   │   ├── ScanHistory.swift          ← Persisted past scan records
│   │   ├── InstalledApp.swift         ← Model for a discovered application
│   │   └── AppRemnant.swift           ← Model for leftover files of an app
│   ├── Scanners/
│   │   ├── ScannerProtocol.swift      ← Protocol all scanners conform to
│   │   ├── CacheScanner.swift
│   │   ├── LogScanner.swift
│   │   ├── TempFileScanner.swift
│   │   ├── TrashScanner.swift
│   │   ├── LanguageFileScanner.swift
│   │   ├── BrokenPrefsScanner.swift
│   │   ├── AppRemnantScanner.swift
│   │   ├── DeveloperJunkScanner.swift
│   │   ├── iOSBackupScanner.swift
│   │   ├── BrowserScanner.swift
│   │   ├── DownloadJunkScanner.swift
│   │   ├── DuplicateFileScanner.swift
│   │   ├── DSStoreScanner.swift
│   │   ├── FontCacheScanner.swift
│   │   ├── MailScanner.swift
│   │   ├── QuickLookScanner.swift
│   │   └── PackageManagerScanner.swift
│   ├── Engine/
│   │   ├── ScanEngine.swift           ← Orchestrates all scanners
│   │   ├── CleanEngine.swift          ← Performs deletion / trash
│   │   ├── AppDiscoveryEngine.swift   ← Discovers all installed apps
│   │   └── UninstallEngine.swift      ← Moves app + remnants to Trash
│   ├── Utilities/
│   │   ├── ByteFormatter.swift
│   │   ├── PathExpander.swift         ← Resolves ~ and env vars
│   │   └── SafetyValidator.swift      ← Validates paths before delete
│   ├── Resources/
│   │   ├── Assets.xcassets            ← App icon, colors
│   │   └── Localizable.strings
│   └── Info.plist
└── Tests/
    ├── ScannerTests/
    └── EngineTests/
```

---

## 4. User Interface

### 4.1 Main Window

Single-window app. Window size: 920 × 600 (resizable, minimum 760 × 500).

The app uses a **top-level tab bar** to switch between its two primary features: the Cleaner and the App Manager. Use SwiftUI's `TabView` with `.tabViewStyle(.automatic)` on macOS, rendering as a segmented control or toolbar-style picker at the top of the window.

```
┌────────────────────────────────────────────────────────────────┐
│  🧹 Macuum Cleaner                                [Settings] [?]│
├────────────────────────────────────────────────────────────────┤
│          [ 🧹 Cleaner ]    [ 📦 App Manager ]                  │
├────────────────────────────────────────────────────────────────┤
│  (content area switches based on selected tab)                 │
└────────────────────────────────────────────────────────────────┘
```

**Tab 1 — Cleaner (default):**

```
┌──────────────────┬─────────────────────────────────────────────┐
│  CATEGORIES      │  SCAN RESULTS / FILE DETAIL                 │
│                  │                                             │
│  ◉ System Cache  │  Select a category to see files             │
│  ◉ App Caches    │  or run a scan to get started.              │
│  ◉ Logs          │                                             │
│  ◉ Temp Files    │                                             │
│  ◉ Trash         │                                             │
│  ◉ Browser       │                                             │
│  ◉ App Remnants  │                                             │
│  ◉ Developer     │                                             │
│  ◉ iOS Backups   │                                             │
│  ◉ Downloads     │                                             │
│  ◉ Duplicates    │                                             │
│  ◉ DS_Store      │                                             │
│  ◉ Lang Files    │                                             │
│  ◉ Mail Junk     │                                             │
│  ◉ Pkg Mgrs      │                                             │
│                  │                                             │
├──────────────────┴─────────────────────────────────────────────┤
│  [  Scan Now  ]    Last scan: Never      [  Clean Selected  ]  │
│                    Total found: 0 B                            │
└────────────────────────────────────────────────────────────────┘
```

**Tab 2 — App Manager** (described fully in Section 4.7 below).

### 4.2 Scan State

While scanning:
- "Scan Now" button becomes "Scanning…" with a spinning progress indicator
- Each category row shows a live count as files are discovered
- A status bar at the bottom shows the current scanner name and file being examined
- Cancel button appears

After scan:
- Each category row shows file count + total size (e.g., "1,243 files · 4.2 GB")
- Rows with 0 results are dimmed
- Clicking a category row opens the file detail panel on the right
- Total found size is shown in bold at the bottom

### 4.3 File Detail Panel

Shows a sortable list of discovered files for the selected category:
- File icon, name, path, size, last modified date
- Checkbox per file (all checked by default)
- "Select All / Deselect All" toggle
- Path is truncated with ellipsis; hover shows full path in tooltip

### 4.4 Clean Confirmation Sheet

Before any deletion, a modal sheet appears:
- Summary: "You are about to remove X files totalling Y GB"
- Two-column list: Category → Size to delete
- Two action buttons:
  - **Move to Trash** (default, safe) — files go to Trash, recoverable
  - **Delete Permanently** — irreversible, shown in red, requires a second confirmation click ("Are you sure? This cannot be undone.")
- Cancel button

### 4.5 Settings

Accessible from toolbar icon. Settings include:
- Toggle: Show hidden files in results
- Toggle: Include system-level paths (requires Accessibility/Full Disk Access prompt)
- Toggle: Scheduled weekly scan + notification
- Exclusion list: Paths or folders to never scan or delete
- Danger zone: Enable permanent delete option (off by default)
- Reset all settings

### 4.6 App Icon & Branding

The app icon (`AppImage.png` at repo root) is used as the macOS `.icns`. Branding should feel clean, modern, and Mac-native — a vacuum or broom motif works well.

---

### 4.7 App Manager Tab

The App Manager tab is a full-featured application browser and uninstaller. It lists every app on the Mac, shows its size, and lets the user uninstall an app along with all of its associated leftover files in one action.

#### Layout

```
��──────────────────────────────────────────────────────────────────┐
│  [ 🧹 Cleaner ]    [ 📦 App Manager ]                            │
├──────────────────────────────────────────────────────────────────┤
│  🔍 Search apps…         Sort: [Name ▾]   Filter: [All ▾]        │
├─────────────────────────┬────────────────────────────────────────┤
│  APP LIST               │  APP DETAIL                            │
│                         │                                        │
│  ◻ Acrobat Reader       │  Adobe Acrobat Reader DC               │
│    Adobe · 1.2 GB       │  Version 23.006 · Bundle ID:           │
│                         │  com.adobe.Reader                      │
│  ◻ Affinity Photo       │                                        │
│    Serif · 890 MB       │  App bundle:                           │
│                         │  /Applications/Adobe Acrobat…  1.2 GB  │
│  ◻ Arc                  │                                        │
│    The Browser Co · …   │  LEFTOVER FILES           1.4 GB total │
│                         │  ──────────────────────────────────    │
│  ◻ CleanMyMac X         │  ☑ App Support    ~/Library/…  890 MB  │
│    MacPaw · 234 MB      │  ☑ Caches         ~/Library/…  312 MB  │
│                         │  ☑ Preferences    ~/Library/…   48 MB  │
│  ◻ Figma                │  ☑ Containers     ~/Library/…  120 MB  │
│    Figma Inc · 456 MB   │  ☑ Logs           ~/Library/…   30 MB  │
│                         │  ☑ Saved State    ~/Library/…    4 MB  │
│  ◻ Firefox              │                                        │
│    Mozilla · 210 MB     │  Total to remove if uninstalled:       │
│                         │  2.6 GB                                │
│  …                      │                                        │
│                         │  [ Uninstall App + Leftovers ]         │
│                         │  [ Uninstall App Only         ]        │
│                         │  [ Open in Finder             ]        │
├─────────────────────────┴────────────────────────────────────────┤
│  47 apps  ·  Total: 68.4 GB     [  Uninstall Selected (3)  ]     │
└──────────────────────────────────────────────────────────────────┘
```

#### App List (left panel)

- Lists all `.app` bundles discovered in `/Applications/`, `~/Applications/`, and `/System/Applications/` (system apps shown but cannot be uninstalled — grayed out with a lock icon)
- Each row shows: app icon (via `NSWorkspace.icon(forFile:)`), app name, developer/vendor (from `Info.plist` → `CFBundleGetInfoString` or App Store metadata), and total size on disk (app bundle + all associated remnants)
- Checkbox on each row for multi-select batch uninstall
- Clicking a row populates the right detail panel
- **Search bar** at the top filters the list in real time by app name or bundle ID
- **Sort menu:** Name (A→Z), Name (Z→A), Size (Largest first), Last Used, Recently Installed
- **Filter menu:** All, User-installed, System Apps (view only), Large Apps (>500 MB), Unused (not opened in 90+ days)

#### App Detail Panel (right panel)

Displays for the selected app:
- App icon (large, 64pt), name, version, bundle ID, install path
- **App Bundle Size:** size of the `.app` file itself
- **Leftover Files** section: a grouped list of all associated files found outside the app bundle, each with a checkbox (all checked by default):
  - Application Support: `~/Library/Application Support/<bundleID>/`
  - Caches: `~/Library/Caches/<bundleID>/`
  - Preferences: `~/Library/Preferences/<bundleID>.plist` (and variants)
  - Containers: `~/Library/Containers/<bundleID>/`
  - Group Containers: `~/Library/Group Containers/` entries matching the bundle ID prefix
  - Application Scripts: `~/Library/Application Scripts/<bundleID>/`
  - Saved Application State: `~/Library/Saved Application State/<bundleID>.savedState/`
  - WebKit data: `~/Library/WebKit/<bundleID>/`
  - Logs: `~/Library/Logs/<AppName>/` and `~/Library/Logs/<bundleID>/`
  - Launch Agents: `~/Library/LaunchAgents/<bundleID>.plist`
  - Launch Daemons: `/Library/LaunchDaemons/<bundleID>.plist` (FDA required)
  - Crash reports: `~/Library/Logs/DiagnosticReports/<AppName>*.crash`
- Each leftover group shows its path (truncated) and size
- Total size (bundle + selected leftovers) is shown prominently
- Three action buttons:
  - **Uninstall App + Leftovers** (default) — moves `.app` and all checked leftover items to Trash
  - **Uninstall App Only** — moves only the `.app` bundle to Trash, leaves support files
  - **Open in Finder** — reveals the `.app` in Finder

#### Multi-Select Batch Uninstall

When one or more app checkboxes are selected in the list:
- A "Uninstall Selected (N)" button appears in the status bar
- Clicking it opens the **Uninstall Confirmation Sheet** listing all selected apps and their total size
- The batch operation uninstalls each app sequentially (not concurrently, to avoid file-system conflicts)
- Progress is shown per app during the operation

#### Uninstall Confirmation Sheet

```
┌──────────────────────────────────────────────────────┐
│  Uninstall 2 Applications?                           │
│                                                      │
│  App                      Bundle + Leftovers         │
│  ─────────────────────── ──────────────────          │
│  Adobe Acrobat Reader DC   2.6 GB                    │
│  CleanMyMac X              890 MB                    │
│                                                      │
│  Total to remove: 3.5 GB                             │
│                                                      │
│  Files will be moved to Trash and can be             │
│  recovered until you empty the Trash.                │
│                                                      │
│        [ Cancel ]    [ Move to Trash ]               │
└──────────────────────────────────────────────────────┘
```

- Always moves to Trash (never permanently deletes) — this is non-negotiable for uninstall
- After confirmation, perform the uninstall and refresh the app list

#### "Unused Apps" Detection

The filter "Unused (90+ days)" surfaces apps the user likely forgot they installed. Detection:
- Read `kMDItemLastUsedDate` metadata via `MDItemCreate` / Spotlight query
- If `kMDItemLastUsedDate` is nil or older than 90 days (configurable in Settings), mark the app as unused
- Display a small badge "Not opened in 6 months" on these rows

#### System Apps

Apps inside `/System/Applications/` and `/System/Library/CoreServices/` are shown for reference but:
- Marked with a 🔒 lock icon
- Checkboxes are disabled
- Detail panel shows info but both uninstall buttons are disabled with tooltip: "System apps cannot be removed."

---

## 5. Junk File Categories (Full Specification)

Each scanner must implement `ScannerProtocol`:

```swift
protocol ScannerProtocol {
    var categoryID: JunkCategory { get }
    var displayName: String { get }
    var description: String { get }  // shown in UI tooltip
    var isEnabledByDefault: Bool { get }
    var requiresFullDiskAccess: Bool { get }
    func scan() async throws -> [JunkFile]
}
```

---

### Category 1 — System & Application Caches

**Display name:** System & App Caches  
**Description:** Cached data that apps regenerate automatically. Safe to delete.  
**Default enabled:** Yes  
**Requires FDA:** Partial (system-level cache needs Full Disk Access)

Paths to scan:
- `~/Library/Caches/` — all subdirectories, all files
- `/Library/Caches/` — requires Full Disk Access
- `/System/Library/Caches/` — read only, skip unless FDA granted
- Safari cache: `~/Library/Caches/com.apple.Safari/`
- Chrome cache: `~/Library/Caches/Google/Chrome/`
- Firefox cache: `~/Library/Caches/Firefox/`
- Edge cache: `~/Library/Caches/Microsoft Edge/`
- Brave cache: `~/Library/Caches/BraveSoftware/`

**Safety rules:**
- Skip `com.apple.LaunchServices-*.csstore` (may cause Finder issues if deleted live)
- Skip currently running app cache dirs by cross-referencing running processes

---

### Category 2 — Log Files

**Display name:** Log Files  
**Description:** Diagnostic logs written by apps and the OS. Safe to delete.  
**Default enabled:** Yes  
**Requires FDA:** Partial

Paths:
- `~/Library/Logs/` — full subtree
- `/Library/Logs/` — FDA required
- `/var/log/` — FDA required; skip active journal files
- `/private/var/log/` — same
- Crash reports: `~/Library/Logs/DiagnosticReports/`
- Crash reports (system): `/Library/Logs/DiagnosticReports/` (FDA)
- Hang reports: `~/Library/Logs/DiagnosticReports/*.hang`
- Low disk logs: `/private/var/db/diagnostics/`

**Safety rules:**
- Skip files modified in last 24 hours (may be actively written)
- Skip `.log` files under 10 KB (negligible)

---

### Category 3 — Temporary Files

**Display name:** Temporary Files  
**Description:** Short-lived files created by apps and the OS.  
**Default enabled:** Yes  
**Requires FDA:** Yes (for /tmp, /var/tmp)

Paths:
- `/tmp/` — FDA required
- `/var/tmp/` — FDA required
- `/private/tmp/` — FDA required
- `~/Library/Application Support/` — scan only for files matching `*.tmp`, `*.temp`, `~$*` (Office temp files), `*.swp`, `*.lock`
- Incomplete downloads: files ending in `.crdownload`, `.part`, `.download`

**Safety rules:**
- Never delete files in `/tmp` that are locked/open by a running process (use `lsof` to check)
- Skip files modified less than 1 hour ago

---

### Category 4 — Trash Contents

**Display name:** Trash  
**Description:** Files you've already deleted but haven't emptied from the Trash.  
**Default enabled:** Yes  
**Requires FDA:** Partial

Paths:
- `~/.Trash/` — user trash
- `/.Trashes/<UID>/` on all mounted external/internal volumes — FDA required
- Network drives: skip (may be someone else's trash)

**Display:** Show total size of Trash contents. The clean action calls `NSWorkspace.shared.recycle` or directly empties trash via FileManager.

---

### Category 5 — Application Caches (Browser-Specific)

**Display name:** Browser Data  
**Description:** Browsing history, cookies, offline page cache from web browsers.  
**Default enabled:** No (privacy-sensitive)  
**Requires FDA:** No

Sub-items (each independently toggleable):

**Safari:**
- History: `~/Library/Safari/History.db`
- Cookies: `~/Library/Cookies/Cookies.binarycookies`
- Web cache: `~/Library/Caches/com.apple.Safari/`
- Downloads list: `~/Library/Safari/Downloads.plist`

**Google Chrome:**
- History: `~/Library/Application Support/Google/Chrome/Default/History`
- Cookies: `~/Library/Application Support/Google/Chrome/Default/Cookies`
- Cache: `~/Library/Caches/Google/Chrome/`
- Session files: `~/Library/Application Support/Google/Chrome/Default/Sessions/`

**Firefox:**
- History/cookies: `~/Library/Application Support/Firefox/Profiles/*/places.sqlite`
- Cache: `~/Library/Caches/Firefox/Profiles/`
- Crash reports: `~/Library/Application Support/Firefox/Crash Reports/`

**Microsoft Edge, Brave, Arc:** same pattern as Chrome (adjust bundle IDs)

**Safety rules:**
- Always warn the user: "This will log you out of websites and remove saved passwords if the browser is configured that way."
- Never delete Keychain entries

---

### Category 6 — Application Remnants (Uninstalled Apps)

**Display name:** App Leftovers  
**Description:** Support files, caches, and preferences left by apps you've already uninstalled.  
**Default enabled:** Yes  
**Requires FDA:** No

Detection strategy:
1. Build a list of installed apps by scanning `/Applications/`, `~/Applications/`, and the Launch Services database
2. Extract bundle identifiers from each app's Info.plist
3. Scan the following locations for directories whose name contains a bundle ID no longer installed:
   - `~/Library/Application Support/`
   - `~/Library/Caches/`
   - `~/Library/Preferences/` (`.plist` files)
   - `~/Library/Containers/`
   - `~/Library/Group Containers/`
   - `~/Library/Logs/`
   - `~/Library/Application Scripts/`
   - `~/Library/Saved Application State/`
   - `~/Library/WebKit/`

**Safety rules:**
- Never flag items for apps that are still installed
- Use fuzzy matching cautiously — only delete if the bundle ID is a 100% match, not partial
- Show matched app name in the UI next to each leftover

---

### Category 7 — Developer Junk

**Display name:** Developer Cache  
**Description:** Large caches created by Xcode, simulators, and other dev tools.  
**Default enabled:** No (developer machines only)  
**Requires FDA:** No

Sub-items (independently toggleable):

| Sub-item | Path | Notes |
|---|---|---|
| Xcode Derived Data | `~/Library/Developer/Xcode/DerivedData/` | Rebuilds automatically |
| Xcode Archives | `~/Library/Developer/Xcode/Archives/` | Old build archives; warn before deleting |
| Xcode Device Support | `~/Library/Developer/Xcode/iOS DeviceSupport/` | Old iOS version support files |
| iOS Simulator data | `~/Library/Developer/CoreSimulator/Devices/` | Only flag simulators not recently used (>90 days) |
| Simulator caches | `~/Library/Developer/CoreSimulator/Caches/` | Safe |
| Swift Package cache | `~/Library/Caches/org.swift.swiftpm/` | Rebuilds automatically |
| Homebrew cache | `~/Library/Caches/Homebrew/` | Old downloaded formulae |
| Homebrew old versions | Run `brew cleanup --dry-run` output parsing | Only suggest; do not auto-run brew |
| npm cache | `~/.npm/_cacache/` | Safe |
| Yarn cache | `~/Library/Caches/Yarn/` | Safe |
| pip cache | `~/Library/Caches/pip/` | Safe |
| Gradle cache | `~/.gradle/caches/` | Safe |
| Maven cache | `~/.m2/repository/` | Warn user, large but intentional |
| Rust cargo registry | `~/.cargo/registry/` | Warn user |
| CocoaPods cache | `~/Library/Caches/CocoaPods/` | Safe |

---

### Category 8 — iOS/iPhone Backups

**Display name:** iPhone & iPad Backups  
**Description:** Local backups of iOS devices. Can be very large (1–50+ GB each).  
**Default enabled:** No (high-value data)  
**Requires FDA:** No

Paths:
- `~/Library/Application Support/MobileSync/Backup/`

**Display:** For each backup folder, resolve the device name and last backup date from `Info.plist` inside the backup directory. Show: Device name, iOS version, backup date, size.

**Safety rules:**
- Always display a warning: "These are your iPhone/iPad backups. Deleting them means you cannot restore your device to this point."
- Recommend keeping the most recent backup
- Never auto-select backups for deletion; user must manually check each one

---

### Category 9 — Language & Localization Files

**Display name:** Unused Language Files  
**Description:** App bundles include translations for all languages; unused ones waste space.  
**Default enabled:** Yes  
**Requires FDA:** No

Detection strategy:
1. Get the user's preferred languages from `NSLocale.preferredLanguages`
2. Scan all `.app` bundles in `/Applications/` and `~/Applications/`
3. For each app, find `*.lproj` directories inside the bundle's `Resources/` folder
4. Flag all `*.lproj` directories whose language code is NOT in the user's preferred languages list, and NOT `en` (keep English as a base)

**Safety rules:**
- Never modify system apps in `/System/Applications/` (read-only on modern macOS anyway)
- Always keep the base language (`Base.lproj`) and English (`en.lproj`)
- Skip apps in `~/Applications/` that are from the App Store (they re-download on update)
- After deletion, flag that some apps may need to be relaunched

---

### Category 10 — Broken & Orphaned Preferences

**Display name:** Orphaned Preferences  
**Description:** Preference (.plist) files left by apps that are no longer installed.  
**Default enabled:** Yes  
**Requires FDA:** No

Paths:
- `~/Library/Preferences/` — scan all `.plist` files

Detection:
1. Build installed apps list (same as Category 6)
2. For each `.plist`, extract the bundle ID from the filename convention (`com.company.appname.plist`)
3. If the bundle ID doesn't correspond to any installed app, flag it
4. Skip Apple system plists (prefix `com.apple.*`) by default — offer as opt-in

**Safety rules:**
- Do NOT delete `com.apple.*` plists unless user explicitly enables this in settings (risk of system instability)
- Skip plists modified in the last 7 days

---

### Category 11 — Download Folder Junk

**Display name:** Downloads Junk  
**Description:** Old installers, disk images, and duplicate downloads.  
**Default enabled:** No (user data)  
**Requires FDA:** No

What to flag:
- `.dmg` files older than 30 days in `~/Downloads/`
- `.pkg` files older than 30 days in `~/Downloads/`
- `.zip` files older than 90 days in `~/Downloads/`
- Files with duplicate-indicator suffixes: ` (1).ext`, ` (2).ext`, ` copy.ext`, ` - Copy.ext`
- Incomplete downloads: `*.crdownload`, `*.part`, `*.download`

**Safety rules:**
- Never scan outside `~/Downloads/` for this category
- Always require user confirmation per file; do not bulk-select by default

---

### Category 12 — Duplicate Files

**Display name:** Duplicate Files  
**Description:** Identical files taking up space twice.  
**Default enabled:** No (expensive to compute, requires care)  
**Requires FDA:** No

Scan scope: `~/Downloads/`, `~/Documents/`, `~/Desktop/` — user-configurable, never system dirs.

Algorithm:
1. Group files by exact size
2. For files in the same size bucket, compute SHA-256 hash
3. Files with identical hash = duplicates
4. Present groups: show original (oldest by creation date) vs duplicates

**Safety rules:**
- Always keep one copy; never delete all copies of a file
- Original is defined as the file with the earliest creation date
- Never auto-select for deletion — user must review each group

---

### Category 13 — .DS_Store Files

**Display name:** .DS_Store Files  
**Description:** Hidden macOS folder metadata files. Safe to delete; Finder recreates them.  
**Default enabled:** Yes  
**Requires FDA:** No

Scan scope: `~/` recursively, respecting exclusions.

**Safety rules:**
- Skip `.DS_Store` files on network shares (don't scan network volumes by default)
- Do not scan inside `.app` bundles

---

### Category 14 — Font Caches

**Display name:** Font Caches  
**Description:** Font registry caches that can grow stale.  
**Default enabled:** Yes  
**Requires FDA:** Partial

Paths:
- `~/Library/Caches/com.apple.FontRegistry/`
- `~/Library/Caches/ATS/` (older macOS compat)
- `/Library/Caches/com.apple.FontRegistry/` (FDA)
- `~/Library/Fonts/` — scan for duplicates or zero-byte fonts (do NOT delete non-duplicate valid fonts)

**After deletion note:** "Font caches will rebuild on next login. You may want to restart your Mac."

---

### Category 15 — Quick Look Caches

**Display name:** Quick Look Thumbnails  
**Description:** Thumbnail previews generated by Quick Look. Regenerated on demand.  
**Default enabled:** Yes  
**Requires FDA:** No

Paths:
- `~/Library/Caches/com.apple.QuickLook.thumbnailcache`
- `~/Library/Caches/QuickLook/`
- `~/Library/Application Support/Quick Look/`

---

### Category 16 — Mail Junk

**Display name:** Mail Attachments & Junk  
**Description:** Downloaded attachments and Mail caches.  
**Default enabled:** No (user data)  
**Requires FDA:** No

What to flag (user must approve each):
- Mail download attachments folder: `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/`
- Mail envelope index (can be rebuilt): `~/Library/Mail/V*/MailData/Envelope Index` — only suggest; do not auto-delete
- Deleted messages: within `~/Library/Mail/` — do not touch (Mail manages this)

**Safety rules:**
- Only the `Mail Downloads` folder is auto-scannable
- For anything else in `~/Library/Mail/`, only surface as advisory, never offer deletion

---

### Category 17 — Package Manager Leftovers

**Display name:** Package Manager Caches  
**Description:** Cached downloads from Homebrew, npm, pip, Cargo, etc.  
**Default enabled:** No (developer-focused)  
**Requires FDA:** No

This category is a subset of Developer Junk (Category 7) but surfaced separately for non-developers who may have installed Homebrew for one-off tools.

Paths:
- `~/Library/Caches/Homebrew/`
- `~/.npm/_cacache/`
- `~/Library/Caches/pip/`
- `~/Library/Caches/yarn/`
- `~/Library/Caches/Yarn/`
- `~/.gradle/caches/`
- `~/.pub-cache/` (Dart/Flutter)
- `~/.cocoapods/repos/` (CocoaPods spec repos)

---

### Category 18 — Notification & Activity Databases (NEW)

**Display name:** Notification History  
**Description:** Stored notification history database.  
**Default enabled:** No  
**Requires FDA:** Yes

Path:
- `~/Library/Application Support/NotificationCenter/` — notification history DB

**Safety rules:**
- Warn user: notifications will be cleared from Notification Center history

---

### Category 19 — Spotlight Index on External Volumes (NEW)

**Display name:** Spotlight Index Files  
**Description:** Hidden Spotlight metadata on external drives.  
**Default enabled:** Yes  
**Requires FDA:** No

For each mounted external volume:
- `.Spotlight-V100/` at volume root
- `.fseventsd/` at volume root
- `.DocumentRevisions-V100/` at volume root

**Safety rules:**
- Never touch these on the boot volume (macOS manages them)
- Only offer on user-mounted external drives

---

### Category 20 — iCloud Drive Conflicts (NEW)

**Display name:** iCloud Conflicts  
**Description:** Conflicting copies of iCloud files.  
**Default enabled:** Yes  
**Requires FDA:** No

Scan `~/Library/Mobile Documents/` and `~/iCloud Drive/` for files matching:
- `* (1).*`, `* (2).*` — duplicate iCloud copies
- Files named `* conflicted copy *`

---

### Category 21 — Screenshots (NEW)

**Display name:** Old Screenshots  
**Description:** Screenshots accumulate quickly on the Desktop.  
**Default enabled:** No (user data)  
**Requires FDA:** No

Scan `~/Desktop/` for files matching:
- `Screenshot *.png` (default macOS screenshot naming)
- `Screen Shot *.png` (older macOS naming)
- Files older than 30 days (threshold configurable in Settings)

---

### Category 22 — Virtual Machine & Docker Leftovers (NEW)

**Display name:** VM & Docker Leftovers  
**Description:** Disk images and data from virtual machines and Docker.  
**Default enabled:** No (high-risk user data)  
**Requires FDA:** No

What to surface (advisory only — never auto-select):
- VMware Fusion VMs: `~/Documents/Virtual Machines/`
- Parallels VMs: `~/Parallels/`
- UTM VMs: `~/Library/Containers/com.utmapp.UTM/`
- Docker desktop data: `~/Library/Containers/com.docker.docker/Data/vms/`
- VirtualBox: `~/VirtualBox VMs/`

**Safety rules:**
- Only surface size/location as information
- Require explicit user action with a prominent warning: "Virtual machine disk images contain entire operating systems. Only delete if you no longer need this VM."

---

### Category 23 — Old Time Machine Snapshots (NEW)

**Display name:** Local Time Machine Snapshots  
**Description:** Local snapshots APFS keeps for Time Machine.  
**Default enabled:** No  
**Requires FDA:** Yes

Detection: Run `tmutil listlocalsnapshots /` and display the list with dates and estimated sizes.

**Clean action:** Run `tmutil deletelocalsnapshots <snapshot>` for each selected snapshot.

**Safety rules:**
- Only delete snapshots older than 7 days by default
- Display warning: "Local snapshots are used to recover files when Time Machine disk is unavailable."

---

## 6. Scan Engine

### 6.1 ScanEngine

```swift
actor ScanEngine {
    func runAllScans(
        categories: [JunkCategory],
        progressHandler: @escaping (ScanProgress) -> Void
    ) async throws -> ScanResult
}
```

- Runs all enabled scanners concurrently using `TaskGroup`
- Reports per-scanner progress via `progressHandler`
- Respects user cancellation via `Task.checkCancellation()`
- Collects all `JunkFile` results into a `ScanResult`

### 6.2 CleanEngine

```swift
actor CleanEngine {
    func clean(
        files: [JunkFile],
        method: CleanMethod,
        progressHandler: @escaping (CleanProgress) -> Void
    ) async throws -> CleanResult
}

enum CleanMethod {
    case moveToTrash
    case permanentDelete  // only if user enabled in Settings
}
```

- Validates each path before deletion using `SafetyValidator`
- Never deletes files outside whitelisted scan paths
- Logs all deleted files to scan history

### 6.3 AppDiscoveryEngine

```swift
actor AppDiscoveryEngine {
    /// Discover all installed apps and compute their sizes (bundle + remnants).
    func discoverApps() async throws -> [InstalledApp]

    /// For a single app, find all associated leftover files outside the bundle.
    func findRemnants(for app: InstalledApp) async throws -> [AppRemnant]
}
```

Discovery process:
1. Enumerate `.app` bundles in `/Applications/`, `~/Applications/`, and `/System/Applications/`
2. For each bundle: read `Info.plist` to extract `CFBundleIdentifier`, `CFBundleShortVersionString`, `CFBundleDisplayName`, vendor string
3. Compute app bundle size using `URLResourceValues.totalFileSizeKey`
4. Query `kMDItemLastUsedDate` via `NSMetadataQuery` or `MDItem` for last-used date
5. Run `findRemnants()` concurrently per app using `TaskGroup`
6. Sum remnant sizes to produce `totalSizeOnDisk`

Performance target: discovery of 50+ apps should complete in under 10 seconds.

### 6.4 UninstallEngine

```swift
actor UninstallEngine {
    func uninstall(
        app: InstalledApp,
        includeRemnants: [AppRemnant],
        progressHandler: @escaping (UninstallProgress) -> Void
    ) async throws -> UninstallResult
}

struct UninstallProgress {
    let appName: String
    let currentStep: String    // e.g., "Removing app bundle…"
    let stepIndex: Int
    let totalSteps: Int
}

struct UninstallResult {
    let app: InstalledApp
    let removedItems: [URL]
    let totalBytesRecovered: Int64
    let errors: [(URL, Error)]
}
```

Uninstall sequence:
1. Validate that the app is not currently running (`NSRunningApplication.runningApplications(withBundleIdentifier:)`)
2. If running, prompt user: "Quit [App Name] before uninstalling?" — offer "Quit and Continue" or "Cancel"
3. Move the `.app` bundle to Trash via `FileManager.trashItem(at:resultingItemURL:)`
4. For each selected `AppRemnant`, move to Trash in order
5. Collect any errors (permission denied, file not found) and surface them in `UninstallResult.errors`
6. Post a macOS notification: "[App Name] has been uninstalled. 2.6 GB moved to Trash."
7. After completion, reload the app list in `AppDiscoveryEngine`

**Safety rules:**
- Never permanently delete; always use `FileManager.trashItem` for uninstall operations
- Never uninstall Macuum Cleaner itself
- Never uninstall apps in `/System/` or `/usr/`
- Validate every path with `SafetyValidator` before moving to Trash

### 6.5 SafetyValidator

A defensive layer that blocks deletion of:
- Any path starting with `/System/`, `/usr/`, `/bin/`, `/sbin/`, `/etc/`
- Running app binaries (checked via `NSRunningApplication`)
- Files that are currently open (checked via POSIX `flock` or `lsof` integration)
- The app's own bundle and support files
- Paths in the user-defined exclusion list

---

## 7. Permissions & Entitlements

The app requires the following permissions, requested at runtime with clear explanations:

| Permission | When Prompted | Purpose |
|---|---|---|
| Full Disk Access | First scan attempt of system/FDA paths | Scan `/Library/`, `/var/log/`, `/tmp/` |
| Accessibility | Never required | — |
| Notifications | On first launch (optional) | Weekly scan reminders |

The app must display a clear onboarding prompt explaining Full Disk Access and directing the user to System Settings → Privacy & Security → Full Disk Access.

**Entitlements file (`Macuum Cleaner.entitlements`):**
```xml
<key>com.apple.security.cs.allow-dyld-environment-variables</key> <false/>
<key>com.apple.security.cs.disable-library-validation</key> <false/>
```
No sandbox entitlement (direct distribution only).

---

## 8. Settings Model

```swift
struct AppSettings: Codable {
    // ── Cleaner settings ──
    var enabledCategories: Set<JunkCategory> = JunkCategory.defaultEnabled
    var showHiddenFiles: Bool = false
    var scanSystemPaths: Bool = false           // requires FDA
    var permanentDeleteEnabled: Bool = false
    var scheduledScanEnabled: Bool = false
    var scheduledScanDayOfWeek: Int = 1         // Monday
    var scheduledScanHour: Int = 9
    var excludedPaths: [String] = []
    var oldScreenshotThresholdDays: Int = 30
    var oldDownloadThresholdDays: Int = 30
    var iOSBackupWarningAcknowledged: Bool = false

    // ── App Manager settings ──
    var appManagerShowSystemApps: Bool = true
    var appManagerDefaultSort: AppSortOrder = .nameAscending
    var unusedAppThresholdDays: Int = 90        // "unused" badge threshold
    var appManagerScanLaunchDaemons: Bool = false // requires FDA
}

enum AppSortOrder: String, Codable {
    case nameAscending, nameDescending, sizeDescending, lastUsed, recentlyInstalled
}
```

---

## 9. Data Models

```swift
enum JunkCategory: String, CaseIterable, Codable, Identifiable {
    case systemCaches, appCaches, logs, tempFiles, trash,
         browserData, appRemnants, developerJunk, iOSBackups,
         languageFiles, brokenPrefs, downloadJunk, duplicates,
         dsStore, fontCaches, quickLookCaches, mailJunk,
         packageManagers, notificationHistory, spotlightExternal,
         iCloudConflicts, screenshots, vmDockerLeftovers, timeMachineSnapshots
    var id: String { rawValue }
}

struct JunkFile: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let size: Int64           // bytes
    let lastModified: Date
    let category: JunkCategory
    var isSelected: Bool = true
    var displayName: String   // human-readable, e.g., "Chrome Cache"
    var metadata: [String: String] = [:]  // e.g., ["device": "iPhone 15 Pro"]
}

struct ScanResult {
    let startDate: Date
    let endDate: Date
    var filesByCategory: [JunkCategory: [JunkFile]]
    var totalSize: Int64 { filesByCategory.values.flatMap { $0 }.reduce(0) { $0 + $1.size } }
    var totalFileCount: Int { filesByCategory.values.flatMap { $0 }.count }
}

// ── App Manager Models ──────────────────────────────────────────

struct InstalledApp: Identifiable, Hashable {
    let id: UUID
    let bundleURL: URL                  // path to .app
    let bundleIdentifier: String        // e.g., "com.adobe.Reader"
    let displayName: String             // e.g., "Adobe Acrobat Reader"
    let version: String                 // e.g., "23.006"
    let vendorName: String              // from Info.plist or App Store
    let bundleSize: Int64               // bytes, .app bundle only
    var remnants: [AppRemnant] = []
    let lastUsedDate: Date?             // from kMDItemLastUsedDate; nil if never
    let isSystemApp: Bool               // true for /System/ apps

    var totalSizeOnDisk: Int64 {
        bundleSize + remnants.reduce(0) { $0 + $1.size }
    }
    var isUnused: Bool {
        guard let d = lastUsedDate else { return true }
        return Date().timeIntervalSince(d) > 90 * 86400
    }
}

enum RemnantKind: String, CaseIterable {
    case applicationSupport = "Application Support"
    case caches             = "Caches"
    case preferences        = "Preferences"
    case containers         = "Containers"
    case groupContainers    = "Group Containers"
    case logs               = "Logs"
    case savedState         = "Saved Application State"
    case webKit             = "WebKit Data"
    case applicationScripts = "Application Scripts"
    case launchAgents       = "Launch Agents"
    case launchDaemons      = "Launch Daemons"
    case crashReports       = "Crash Reports"
}

struct AppRemnant: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let kind: RemnantKind
    let size: Int64
    var isSelected: Bool = true
}
```

---

## 10. Build & Distribution

### Build Requirements
- Xcode 16+
- macOS 14 SDK
- Developer ID Application certificate (for notarization)

### Notarization Steps
1. Archive via Xcode (`Product → Archive`)
2. Export with Developer ID
3. Submit to Apple notarization service (`notarytool`)
4. Staple the notarization ticket
5. Package into `.dmg` with `create-dmg` or Packages.app

### GitHub Release
- Tag format: `v1.0.0`
- Release assets: `Macuum-Cleaner-v1.0.0.dmg`
- `AppImage.png` must be committed to the repository root
- README.md must include: download link, system requirements, feature list, screenshots, and privacy statement

### Privacy Statement (required in README and App Store if applicable)
> "Macuum Cleaner does not collect, transmit, or store any personal data. All scanning and cleaning happens entirely on your device. No analytics, no telemetry, no network connections."

---

## 11. Error Handling

| Scenario | Handling |
|---|---|
| Full Disk Access not granted | Show permission guide sheet; skip FDA-requiring scanners gracefully |
| File deleted by user/system during scan | Catch `CocoaError.fileNoSuchFile`; skip silently |
| File locked / in use | Skip; add advisory note in results |
| Permission denied on individual file | Skip; log to console |
| Scan cancelled | Show partial results with "Scan incomplete" banner |
| Disk full during Trash move | Show specific error; offer permanent delete as alternative |
| SafetyValidator blocks a path | Log the block reason; never surface it as an error to the user |
| App is running when uninstall attempted | Prompt user to quit the app first; offer "Quit and Continue" |
| App bundle not found (deleted externally) | Refresh the app list; show "App no longer found" toast |
| Remnant path not found during uninstall | Skip silently; deduct from recovered-size total |
| Permission denied on remnant path | Show warning: "Some files could not be removed (permission denied)" with the specific paths listed |
| Uninstalling Macuum Cleaner itself attempted | Block with alert: "Macuum Cleaner cannot uninstall itself." |

---

## 12. Scheduled Scans

If the user enables scheduled scanning:
- Register a `BGProcessingTask` or use a LaunchAgent plist in `~/Library/LaunchAgents/`
- Run scan silently; show a macOS notification with results summary
- Notification: "Macuum found 2.3 GB of junk files. Tap to review."
- Never clean automatically without user interaction

---

## 13. Accessibility

- All interactive elements must have `accessibilityLabel` set
- Respect `NSAccessibility` reduce-motion settings
- Minimum tap target: 44pt
- Support VoiceOver navigation throughout

---

## 14. Localization

Initial release in English only. Architecture must support future localization via `Localizable.strings`. All user-facing strings must go through `NSLocalizedString` or SwiftUI's `LocalizedStringKey`.

---

## 15. Future Roadmap (Post-MVP)

- **Privacy Scan:** Identify apps with unusual file access patterns
- **Startup Items Manager:** View and disable login items and launch agents (natural follow-on to App Manager)
- **App Update Checker:** Highlight apps with available updates (via Sparkle or Mac App Store)
- **Disk Space Visualizer:** Treemap of disk usage, drillable to individual apps and folders
- **Menu Bar Mode:** Show disk usage in menu bar with quick-clean shortcut
- **Mac App Store version:** Sandboxed, limited feature set (App Manager limited to user apps only)
- **Automated cleaning profiles:** "Light", "Standard", "Deep Clean" presets
- **App Manager export:** Export the installed app list as CSV or JSON for inventory purposes

---

*Spec version 1.1 — added App Manager tab (application browser + uninstaller)*  
*Repository: `Maccum-Cleaner` | Icon: `AppImage.png` at repo root*
