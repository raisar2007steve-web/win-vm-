import Foundation

/// Sample content used by SwiftUI previews, UI tests and the screenshot pipeline.
/// Never seeded automatically in a normal first launch.
enum SeedData {
    static func makeDefaultFolders(in store: NoteStore) -> [Folder] {
        let names: [(String, String)] = [
            ("Ideas", "lightbulb"),
            ("Work", "briefcase"),
            ("Personal", "person")
        ]
        return names.enumerated().map { index, entry in
            store.createFolder(named: entry.0, symbolName: entry.1)
        }
    }

    @discardableResult
    static func populate(_ store: NoteStore) -> Int {
        let folders = makeDefaultFolders(in: store)
        let ideas = folders.first { $0.name == "Ideas" }
        let work = folders.first { $0.name == "Work" }
        let personal = folders.first { $0.name == "Personal" }

        let designReview = NoteDocument(blocks: [
            NoteBlock(kind: .heading1, text: "Design review — Notes"),
            NoteBlock(kind: .paragraph, text: "Goals for this pass: faster capture, calmer typography, and structure that stays out of the way."),
            NoteBlock(kind: .heading2, text: "Decisions"),
            NoteBlock(kind: .checklist, text: "Floating compose button on every list", isChecked: true),
            NoteBlock(kind: .checklist, text: "Block editor with checklists and code", isChecked: true),
            NoteBlock(kind: .checklist, text: "Measure typing latency on a 2,000 word note", isChecked: false),
            NoteBlock(kind: .quote, text: "The best notes app disappears while you are writing."),
            NoteBlock(kind: .paragraph, text: "Next: verify autosave under slow disk conditions and confirm nothing is lost when the app is backgrounded mid-sentence.")
        ])

        let standup = NoteDocument(blocks: [
            NoteBlock(kind: .heading1, text: "Weekly standup"),
            NoteBlock(kind: .paragraph, text: "Shipped the attachment pipeline with downsampling. Photos are stored at 2048px, thumbnails at 400px."),
            NoteBlock(kind: .bullet, text: "CloudKit sync pending device verification"),
            NoteBlock(kind: .bullet, text: "Speech transcription needs a real microphone run"),
            NoteBlock(kind: .numbered, text: "Profile list scrolling with 1,000 notes"),
            NoteBlock(kind: .numbered, text: "Tune the debounce window for autosave"),
            NoteBlock(kind: .code, text: "store.applyEdit(to: note, title: title, document: document)")
        ])

        let groceries = NoteDocument(blocks: [
            NoteBlock(kind: .heading1, text: "Groceries"),
            NoteBlock(kind: .checklist, text: "Sourdough", isChecked: true),
            NoteBlock(kind: .checklist, text: "Olive oil", isChecked: false),
            NoteBlock(kind: .checklist, text: "Lemons", isChecked: false),
            NoteBlock(kind: .checklist, text: "Coffee beans", isChecked: false)
        ])

        let trip = NoteDocument(blocks: [
            NoteBlock(kind: .heading1, text: "Lisbon trip notes"),
            NoteBlock(kind: .paragraph, text: "Three days, carry-on only. Stay near Alfama so the mornings are walkable."),
            NoteBlock(kind: .heading2, text: "To book"),
            NoteBlock(kind: .checklist, text: "Tram 28 early pass", isChecked: true),
            NoteBlock(kind: .checklist, text: "Sintra day trip", isChecked: false),
            NoteBlock(kind: .table, rows: [
                ["Day", "Plan", "Cost"],
                ["1", "Alfama + castle", "€30"],
                ["2", "Sintra", "€45"]
            ])
        ])

        let reading = NoteDocument(blocks: [
            NoteBlock(kind: .heading1, text: "Reading list"),
            NoteBlock(kind: .bullet, text: "Thinking in Systems — Donella Meadows"),
            NoteBlock(kind: .bullet, text: "The Design of Everyday Things — Don Norman"),
            NoteBlock(kind: .paragraph, text: "Highlight: constraints are the most powerful design tool you have.")
        ])

        let quick = NoteDocument(blocks: [
            NoteBlock(kind: .paragraph, text: "Call the framer about the print size before Friday.")
        ])

        let notes: [(NoteDocument, String, Folder?, Bool, Bool, [String])] = [
            (designReview, "Design review — Notes", ideas, true, true, ["design", "product"]),
            (standup, "Weekly standup", work, false, true, ["work"]),
            (groceries, "Groceries", personal, false, false, ["home"]),
            (trip, "Lisbon trip notes", personal, false, false, ["travel"]),
            (reading, "Reading list", ideas, false, false, ["books"]),
            (quick, "", nil, false, false, ["quick"])
        ]

        for entry in notes {
            let note = store.createNote(title: entry.1, document: entry.0, folder: entry.2)
            note.isPinned = entry.3
            note.isFavorite = entry.4
            note.tags = entry.5.compactMap { store.tag(named: $0) }
        }
        store.persist()
        return notes.count
    }

    /// A large note used to test editor responsiveness and PDF layout.
    static func stressDocument(words: Int) -> NoteDocument {
        var blocks: [NoteBlock] = [NoteBlock(kind: .heading1, text: "Large document")]
        var produced = 0
        var index = 0
        while produced < words {
            blocks.append(NoteBlock(
                kind: index % 7 == 6 ? .bullet : .paragraph,
                text: "Paragraph \(index). " + String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 4)
            ))
            produced += 40
            index += 1
        }
        return NoteDocument(blocks: blocks)
    }
}
