import Foundation
import AppIntents

/// Siri / Shortcuts / Spotlight actions.
struct CreateNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Note"
    static var description = IntentDescription("Creates a new note with the text you provide.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Text", description: "The body text of the note.", requestValueDialog: "What should the note say?")
    var text: String

    @Parameter(title: "Title")
    var noteTitle: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Create a note with \(\.$text)") {
            \.$noteTitle
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let resolvedTitle = await MainActor.run { () -> String in
            let environment = AppEnvironmentProvider.shared
            let document = NoteDocument(blocks: [NoteBlock(kind: .paragraph, text: text)])
            let note = environment.store.createNote(title: noteTitle ?? "", document: document)
            SpotlightIndexer.index([note])
            return note.displayTitle
        }
        return .result(dialog: "Saved “\(resolvedTitle)” to Notes.")
    }
}

struct SearchNotesIntent: AppIntent {
    static var title: LocalizedStringResource = "Search Notes"
    static var description = IntentDescription("Finds notes matching your search text.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Search Text", requestValueDialog: "What are you looking for?")
    var query: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await MainActor.run { () -> (count: Int, titles: [String]) in
            let environment = AppEnvironmentProvider.shared
            let matches = NoteSearch.filter(environment.store.fetchAllNotes(), query: query)
            return (matches.count, matches.prefix(3).map(\.displayTitle))
        }

        if result.count == 0 {
            return .result(dialog: "No notes match “\(query)”.")
        }
        let titles = result.titles.map { "“\($0)”" }.joined(separator: ", ")
        return .result(dialog: "\(result.count) notes match “\(query)”: \(titles).")
    }
}

struct OpenQuickNotesIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Notes"
    static var description = IntentDescription("Opens Notes on the all notes list.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            AppEnvironmentProvider.shared.openScope(.all)
        }
        return .result()
    }
}

struct NotesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateNoteIntent(),
            phrases: [
                "Create a note in \(.applicationName)",
                "New note in \(.applicationName)"
            ],
            shortTitle: "New Note",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: SearchNotesIntent(),
            phrases: [
                "Search \(.applicationName)",
                "Find a note in \(.applicationName)"
            ],
            shortTitle: "Search Notes",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: OpenQuickNotesIntent(),
            phrases: [
                "Open \(.applicationName)"
            ],
            shortTitle: "Open Notes",
            systemImageName: "note.text"
        )
    }
}
