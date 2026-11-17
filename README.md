<p align="center"><img src="AppImage.png" alt="Macuum Cleaner" width="140"></p>

# Macuum Cleaner

A lightweight, safe and transparent disk cleaner for macOS. It scans for well-known kinds of junk, shows you exactly what would be removed, and never deletes anything without your approval. It is a disk cleaner, not a "speed booster": no background daemons, no login items, no always-on processes (unless you turn on the weekly scan).

## Install

**Homebrew** (recommended):

```sh
brew tap git-maniam/tap
brew trust git-maniam/tap        # Homebrew 7+ only: third-party taps must be trusted once
brew install --cask macuum-cleaner
```

To upgrade later: `brew upgrade --cask macuum-cleaner`. To remove it along with its settings: `brew uninstall --cask --zap macuum-cleaner`.

**Manual download:** get `Macuum-Cleaner-vX.Y.Z.dmg` from the [Releases page](https://github.com/git-maniam/Macuum-Cleaner/releases), open it, and drag **Macuum Cleaner** to Applications. Releases are signed with a Developer ID certificate and notarized by Apple, so macOS opens them without warnings.

## Requirements

- macOS 14 Sonoma or later (Apple Silicon and Intel)
- Full Disk Access is optional; it lets the app scan protected locations (`/Library`, system logs, the Trash, iPhone backups).

## Full Disk Access

macOS does not let any app grant itself Full Disk Access, and neither Homebrew nor an installer can do it for you. On first launch Macuum Cleaner shows a short guide: it opens the right System Settings pane, gives you the app icon to drag into the list, and offers a **Relaunch** button because macOS applies the permission to newly started apps. It is optional; without it the protected locations are skipped.

**Managed Macs:** IT admins can pre-approve it with the MDM profile in [`packaging/mdm/`](packaging/mdm/) (a PPPC profile for `com.macuum.cleaner`).

## Features

**Cleaner** — 23 categories (Language Files arrives in v1.1), scanned in parallel in a few seconds:
system and app caches, logs, temporary files, Trash, browser data, app leftovers, developer caches, iPhone/iPad backups, orphaned preferences, download junk, duplicate files, `.DS_Store` files, font caches, Quick Look thumbnails, Mail downloads, package-manager caches, notification history, Spotlight files on external drives, iCloud conflict copies, old screenshots, VM/Docker data and local Time Machine snapshots.
Everything is moved to the Trash by default. Risky categories (backups, duplicates, downloads, VMs) are never pre-selected.

**App Manager** — lists every app with its size and leftover files (Application Support, caches, preferences, containers, logs, launch agents and more), flags apps you haven't opened in a while, and uninstalls apps with their leftovers in one step. Uninstalling always uses the Trash. System apps and Macuum Cleaner itself are protected.

**Safety** — every path is checked before removal: system folders, protected directories, running apps, the app's own files and your exclusion list are always blocked. Only files found by a scan can be cleaned.

## Privacy

Macuum Cleaner does not collect, transmit, or store any personal data. All scanning and cleaning happens entirely on your device. No analytics, no telemetry, no network connections.

## Building

```sh
brew install xcodegen
xcodegen generate
open "Macuum Cleaner.xcodeproj"
swift test --package-path Packages/MacuumCore   # core logic tests (temp-dir fixtures only)
```

The core (models, scanners, engines) lives in the `MacuumCore` Swift package; the app target only contains SwiftUI views. Opt-in read-only checks against your real machine: `MACUUM_LIVE=1 swift test --package-path Packages/MacuumCore`.

To regenerate the app icon set from `AppImage.png`: `swift scripts/make-icon.swift AppImage.png "Macuum Cleaner/Resources/Assets.xcassets/AppIcon.appiconset"`.

Release builds: see `scripts/release.sh` (needs a Developer ID certificate and notarytool credentials).

## License

See [LICENSE](LICENSE).
