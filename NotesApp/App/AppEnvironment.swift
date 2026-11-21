import Foundation
import SwiftData
import SwiftUI

/// Single composition root. Views never construct services themselves, which keeps
/// previews and tests able to swap in an in-memory container.
@MainActor
@Observable
final class AppEnvironment {
    let container: ModelContainer
    let settings: AppSettings
    let lock: AppLockService
    let sync: SyncMonitor
    let intelligence: NoteIntelligence
    let store: NoteStore
    let storageMode: ModelContainerFactory.StorageMode

    /// Deep-link / app-intent navigation requests consumed by the root view.
    var pendingScope: NotesScope?
    var pendingNoteID: UUID?
    var pendingNewNote = false
    var showSettings = false

    init(
        container: ModelContainer,
        storageMode: ModelContainerFactory.StorageMode,
        settings: AppSettings? = nil,
        attachmentStore: AttachmentStore = .shared
    ) {
        let settings = settings ?? AppSettings()
        self.container = container
        self.storageMode = storageMode
        self.settings = settings
        self.store = NoteStore(context: container.mainContext, attachmentStore: attachmentStore)
        self.lock = AppLockService(settings: settings)
        self.sync = SyncMonitor()
        self.intelligence = NoteIntelligence()
        Haptics.isEnabled = settings.hapticsEnabled
        lock.refreshBiometry()
        sync.configure(storageMode: storageMode, settings: settings)
    }

    static func bootstrap() -> AppEnvironment {
        let arguments = ProcessInfo.processInfo.arguments
        let isUITesting = arguments.contains("-uiTesting")

        do {
            let (container, mode) = try ModelContainerFactory.make(preferCloudKit: !isUITesting)
            let environment = AppEnvironment(container: container, storageMode: mode)
            environment.prepareForLaunch(arguments: arguments)
            return environment
        } catch {
            // A store that cannot be opened must not produce an unusable app: retry
            // with an in-memory container so the UI still works and can report it.
            NSLog("[NotesApp] Persistent store unavailable, using in-memory store.")
            let fallback = try! ModelContainerFactory.make(inMemory: true, preferCloudKit: false).container
            let environment = AppEnvironment(container: fallback, storageMode: .local)
            environment.prepareForLaunch(arguments: arguments)
            return environment
        }
    }

    private func prepareForLaunch(arguments: [String]) {
        if arguments.contains("-resetStore") {
            wipeAllContent()
        }
        if arguments.contains("-seedDemoData") || arguments.contains("-uiDemoSeed") {
            let existing = store.count(of: .all)
            if existing == 0 {
                SeedData.populate(store)
            }
        }
        if arguments.contains("-disableLock") {
            settings.lockEnabled = false
        }
        if arguments.contains("-uiScreenshotMode") {
            settings.lockEnabled = false
        }
        SpotlightIndexer.index(store.fetchAllNotes())
    }

    private func wipeAllContent() {
        let context = container.mainContext
        let notes = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        for note in notes {
            let names = note.attachments.map(\.fileName)
            context.delete(note)
            AttachmentStore.shared.delete(fileNames: names)
        }
        for folder in (try? context.fetch(FetchDescriptor<Folder>())) ?? [] {
            context.delete(folder)
        }
        for tag in (try? context.fetch(FetchDescriptor<Tag>())) ?? [] {
            context.delete(tag)
        }
        try? context.save()
        settings.lockEnabled = false
        settings.lastBackgroundDate = nil
        ThumbnailCache.shared.clear()
    }

    func openScope(_ scope: NotesScope) {
        pendingScope = scope
    }

    func requestNewNote() {
        pendingNewNote = true
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "notesapp" else { return }
        switch url.host?.lowercased() {
        case "settings":
            showSettings = true
        case "new":
            pendingNewNote = true
        case "trash":
            pendingScope = .trash
        case "archive":
            pendingScope = .archive
        case "favorites":
            pendingScope = .favorites
        case "pinned":
            pendingScope = .pinned
        case "search":
            pendingScope = .all
        case "note":
            if let idString = url.pathComponents.dropFirst().first, let id = UUID(uuidString: idString) {
                pendingNoteID = id
            }
        default:
            pendingScope = .all
        }
    }
}

/// Lazily built once, on the main actor, when the root view first renders.
@MainActor
enum AppEnvironmentProvider {
    static let shared = AppEnvironment.bootstrap()
}
