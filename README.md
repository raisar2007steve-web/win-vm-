# Notes — native iOS notes app

A native SwiftUI + SwiftData notes app with a block editor, folders, tags, iCloud-ready
persistence, biometric lock, document scanning, voice notes, handwriting, on-device
writing assistance, and export.

The app targets iOS 17 and later and is built with the iOS SDK installed in Xcode.
It is written without third-party dependencies.

> **Verification status:** this project is compiled and tested on GitHub Actions
> macOS runners (`ios-ci.yml`), which run `xcodebuild build-for-testing`, the XCTest
> unit suite, the XCUITest suite, and capture simulator screenshots. See
> [docs/ENGINEERING_REPORT.md](docs/ENGINEERING_REPORT.md) for the results of the
> latest run. Physical-device testing has not been performed; see
> [docs/DEVICE_TESTING.md](docs/DEVICE_TESTING.md).

## Features

**Notes engine**
- Create, edit, duplicate, delete, restore, archive, pin, favorite
- Folders (create, rename, delete) and multiple tags per note
- Sorting by date edited, date created, or title; pinned notes always float up
- Debounced autosave (650 ms) plus flush on scene change, so nothing is lost
- Recently Deleted with restore and permanent deletion
- Full-text search across title, body, and tags (diacritic-insensitive, debounced)

**Block editor**
- Paragraphs, title, heading, bulleted/numbered lists, checklists, quotes, code,
  dividers, tables, images, documents, audio, handwriting
- Inline Markdown emphasis (bold, italic, code, highlight) with a keyboard toolbar
- Dynamic Type, dark mode, context menus, haptics, accessibility identifiers

**Capture**
- Camera photos and multi-page document scanning (VisionKit)
- Multi-select photo library import with ImageIO downsampling (2048 px, 400 px thumbnails)
- File import (PDF, text, images, any document) and `.note` archive export
- Voice notes with on-device speech transcription (Speech + AVFoundation)
- Apple Pencil / finger handwriting canvas (PencilKit) saved as an image attachment

**Apple Intelligence**
- Summarize, proofread, rewrite, extract tasks, suggest title, suggest tags
- Uses Foundation Models when the device and OS support it (gated by
  `#if canImport(FoundationModels)` + availability checks)
- Falls back to deterministic on-device heuristics; no network calls ever

**System integration**
- Face ID / Touch ID / passcode app lock with configurable grace period
- Protected notes that authenticate per note
- Share sheet, `.note` document type, `notesapp://` deep links
- Siri / Shortcuts app intents (create note, search notes, open notes)
- Spotlight indexing, local reminder notifications, haptics

**Persistence and security**
- SwiftData with a versioned schema and migration plan
- CloudKit sync requested first, automatic fallback to a local store
- Attachments written with complete file protection
- No analytics, no third-party SDKs, no note content in logs

## Architecture

```
NotesApp/
  App/            entry point, composition root, root navigation, settings
  Models/         SwiftData models + block document model
  Persistence/    schema versions, migration plan, container factory, NoteStore
  Services/       autosave, attachment store, search/sort, export, seeding, intelligence
  Security/       app lock, Keychain helper
  Sync/           iCloud + network status
  DeviceFeatures/ camera, scanner, audio, haptics, Spotlight, notifications
  Views/          sidebar, list, row, editor, block rows, sheets, settings
  Intents/        App Intents / Shortcuts
  Resources/      asset catalog
NotesAppTests/    unit tests (store, codec, search, export, persistence, lock)
NotesAppUITests/  XCUITest flows + performance metrics
scripts/ci/       toolchain selection, simulator pick, screenshot, gallery, report
```

`NoteStore` is the only place that mutates notes, so timestamps, derived search
text, and attachment cleanup stay consistent. Views read through `@Query` for live
updates; the editor keeps local state and writes through a debounced `AutosaveEngine`.

Notes are stored as JSON blocks (`bodyJSON`) with a denormalised `searchText`
column, so lists never decode JSON to filter.

## Build and run

Requirements: macOS with Xcode 16 or later (iOS 17+ SDK). Open
`NotesApp.xcodeproj`, pick the `NotesApp` scheme and an iOS simulator, and run.

Command line:

```bash
xcodebuild build-for-testing \
  -project NotesApp.xcodeproj -scheme NotesApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
```

## Test

```bash
xcodebuild test-without-building \
  -project NotesApp.xcodeproj -scheme NotesApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath DerivedData \
  -only-testing:NotesAppTests

xcodebuild test-without-building \
  -project NotesApp.xcodeproj -scheme NotesApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath DerivedData \
  -only-testing:NotesAppUITests
```

## CI

`.github/workflows/ios-ci.yml` runs on `macos-latest` for pushes, pull requests, and
manual dispatch:

1. selects the newest stable Xcode (`scripts/ci/select_xcode.sh`)
2. picks the newest available iPhone simulator
3. builds for testing (unsigned simulator build)
4. runs unit tests, then UI tests and performance metrics
5. captures simulator screenshots and exports XCUITest screenshot attachments
6. builds an HTML gallery, uploads artifacts, and publishes `docs/ci/`
7. fails the job if any executed step failed

## Signing and iCloud

`Config/NotesApp.entitlements` declares the CloudKit container
`iCloud.com.raisar2007steve.NotesApp`. Building for a device requires selecting your
team in Xcode and creating that container in your developer account, or removing the
entitlements for a local-only build. Simulator builds and CI do not require signing.

## Known limitations

- No Share Extension or widget extension target yet (both need extra app-extension
  targets and App Group entitlements). In-app share sheet and `.note` document
  import/export work today.
- Inline formatting applies to a whole block; selection-level formatting needs a
  `UITextView`-based editor.
- CloudKit sync is wired through SwiftData but has not been verified against a real
  iCloud account (no Apple ID in CI).
- Tables support a fixed column count taken from the header row.
- Physical-device features (camera, Face ID, microphone, Speech) are implemented and
  permission-gated, but have not been exercised on hardware.
