import XCTest
import SwiftData
import UIKit
@testable import NotesApp

final class NoteBodyCodecTests: XCTestCase {
    func testRoundTripPreservesAllBlockTypes() {
        var imageBlock = NoteBlock(kind: .image)
        let attachmentID = UUID()
        imageBlock.attachmentID = attachmentID
        let document = NoteDocument(blocks: [
            NoteBlock(kind: .heading1, text: "Title"),
            NoteBlock(kind: .paragraph, text: "Body"),
            NoteBlock(kind: .checklist, text: "Done", isChecked: true),
            NoteBlock(kind: .code, text: "let x = 1"),
            imageBlock,
            NoteBlock(kind: .table, rows: [["A", "B"], ["1", "2"]])
        ])

        let decoded = NoteBodyCodec.decode(NoteBodyCodec.encode(document))

        XCTAssertEqual(decoded.blocks.count, 6)
        XCTAssertEqual(decoded.blocks[2].isChecked, true)
        XCTAssertEqual(decoded.blocks[4].attachmentID, attachmentID)
        XCTAssertEqual(decoded.blocks[5].rows.count, 2)
    }

    func testLegacyPlainTextPayloadIsPreserved() {
        let decoded = NoteBodyCodec.decode("Just some old text")
        XCTAssertEqual(decoded.blocks.count, 1)
        XCTAssertEqual(decoded.blocks.first?.text, "Just some old text")
    }

    func testEmptyPayloadProducesSingleParagraph() {
        let decoded = NoteBodyCodec.decode("")
        XCTAssertEqual(decoded.blocks.count, 1)
        XCTAssertEqual(decoded.blocks.first?.kind, .paragraph)
    }

    func testPlainTextAndMarkdownExport() {
        let document = NoteDocument(blocks: [
            NoteBlock(kind: .heading1, text: "Heading"),
            NoteBlock(kind: .bullet, text: "Item"),
            NoteBlock(kind: .checklist, text: "Task", isChecked: true)
        ])

        XCTAssertTrue(document.markdown.contains("# Heading"))
        XCTAssertTrue(document.markdown.contains("- Item"))
        XCTAssertTrue(document.markdown.contains("- [x] Task"))
        XCTAssertEqual(document.plainText.components(separatedBy: "\n").count, 3)
    }

    func testChecklistItemsExtraction() {
        let document = NoteDocument(blocks: [
            NoteBlock(kind: .checklist, text: "One", isChecked: false),
            NoteBlock(kind: .paragraph, text: "Not a task"),
            NoteBlock(kind: .checklist, text: "Two", isChecked: true)
        ])
        let items = document.checklistItems
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items[1].isChecked)
    }
}

final class NoteSearchTests: XCTestCase {
    @MainActor
    private func makeNote(_ title: String, _ body: String, tags: [String] = []) -> Note {
        let note = Note(title: title, document: NoteDocument(blocks: [NoteBlock(text: body)]))
        note.tags = tags.map { Tag(name: $0) }
        return note
    }

    @MainActor
    func testMatchesTitleBodyAndTags() {
        let note = makeNote("Lisbon Trip", "Book the tram early", tags: ["travel"])
        XCTAssertTrue(NoteSearch.matches(note, query: "lisbon"))
        XCTAssertTrue(NoteSearch.matches(note, query: "tram"))
        XCTAssertTrue(NoteSearch.matches(note, query: "travel"))
        XCTAssertTrue(NoteSearch.matches(note, query: "lisbon tram"))
        XCTAssertFalse(NoteSearch.matches(note, query: "berlin"))
    }

    @MainActor
    func testDiacriticInsensitiveMatching() {
        let note = makeNote("Café notes", "Crème brûlée")
        XCTAssertTrue(NoteSearch.matches(note, query: "cafe"))
        XCTAssertTrue(NoteSearch.matches(note, query: "creme"))
    }

    @MainActor
    func testEmptyQueryMatchesEverything() {
        let note = makeNote("Anything", "")
        XCTAssertTrue(NoteSearch.matches(note, query: "   "))
    }

    @MainActor
    func testSortOrderKeepsPinnedFirst() {
        let old = makeNote("Old", "a")
        old.updatedAt = Date(timeIntervalSince1970: 1_000)
        let new = makeNote("New", "b")
        new.updatedAt = Date(timeIntervalSince1970: 2_000)
        let pinnedOld = makeNote("Pinned Old", "c")
        pinnedOld.updatedAt = Date(timeIntervalSince1970: 500)
        pinnedOld.isPinned = true

        let sorted = NoteSortOrder.updatedNewest.sort([old, new, pinnedOld])
        XCTAssertEqual(sorted.map(\.displayTitle), ["Pinned Old", "New", "Old"])

        let oldestFirst = NoteSortOrder.updatedOldest.sort([old, new])
        XCTAssertEqual(oldestFirst.map(\.displayTitle), ["Old", "New"])

        let byTitle = NoteSortOrder.titleAscending.sort([new, old])
        XCTAssertEqual(byTitle.map(\.displayTitle), ["New", "Old"])
    }
}

final class ExportTests: XCTestCase {
    @MainActor
    func testMarkdownPlainTextAndArchive() {
        let note = Note(title: "Trip", document: NoteDocument(blocks: [
            NoteBlock(kind: .heading1, text: "Trip"),
            NoteBlock(kind: .paragraph, text: "Pack light")
        ]))
        note.tags = [Tag(name: "travel")]

        let markdown = ExportService.markdown(for: note)
        XCTAssertTrue(markdown.contains("# Trip"))
        XCTAssertTrue(markdown.contains("#travel"))

        let plain = ExportService.plainText(for: note)
        XCTAssertTrue(plain.contains("Pack light"))

        let archive = ExportService.archive(for: note)
        XCTAssertFalse(archive.isEmpty)
        XCTAssertNotNil(String(data: archive, encoding: .utf8))
    }

    @MainActor
    func testPDFRendersNonEmptyDocument() {
        let note = Note(title: "Report", document: NoteDocument(blocks: [
            NoteBlock(kind: .heading1, text: "Report"),
            NoteBlock(kind: .paragraph, text: String(repeating: "Long paragraph text. ", count: 200)),
            NoteBlock(kind: .checklist, text: "Task", isChecked: true),
            NoteBlock(kind: .table, rows: [["A", "B"], ["1", "2"]])
        ]))

        let data = ExportService.pdfData(for: note)
        XCTAssertGreaterThan(data.count, 1_000)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "%PDF")
    }

    func testSafeFileNameStripsUnsafeCharacters() {
        XCTAssertEqual(ExportService.safeFileName("a/b:c?d"), "a-b-c-d")
        XCTAssertEqual(ExportService.safeFileName("   "), "Note")
    }
}

@MainActor
final class PersistenceTests: XCTestCase {
    func testDataSurvivesNewContainerOnSameStore() throws {
        let schema = Schema(versionedSchema: NotesSchemaV1.self)
        let name = "test-store-\(UUID().uuidString)"
        let configuration = ModelConfiguration(
            name,
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        let first = try ModelContainer(for: schema, migrationPlan: NotesMigrationPlan.self, configurations: configuration)
        let store = NoteStore(context: first.mainContext)
        store.createNote(title: "Persisted", document: NoteDocument(blocks: [NoteBlock(text: "survives")]))
        XCTAssertTrue(store.persist())

        let second = try ModelContainer(for: schema, migrationPlan: NotesMigrationPlan.self, configurations: configuration)
        let reloaded = NoteStore(context: second.mainContext).fetchAllNotes()
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.first?.title, "Persisted")
        XCTAssertEqual(reloaded.first?.document.blocks.first?.text, "survives")
    }

    func testAttachmentStoreDownsamplesAndDeletes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("attach-\(UUID().uuidString)")
        let store = AttachmentStore(root: root)
        let bigData = NoteStoreTests.makeImageData()

        let fileName = try store.saveImageData(bigData, maxPixel: 64)
        XCTAssertTrue(store.exists(fileName))

        let image = store.image(for: fileName, maxPixel: 128)
        XCTAssertNotNil(image)
        XCTAssertLessThanOrEqual(max(image?.size.width ?? 0, image?.size.height ?? 0), 128)

        XCTAssertGreaterThan(store.byteCount(for: fileName), 0)
        store.delete(fileNames: [fileName])
        XCTAssertFalse(store.exists(fileName))
    }

    func testAutosaveEngineFlushesPendingWork() async {
        var saves = 0
        let engine = await AutosaveEngine(debounceMilliseconds: 10_000)
        await MainActor.run {
            engine.schedule { saves += 1 }
        }
        let pending = await engine.isPending
        XCTAssertTrue(pending)

        await MainActor.run { engine.flush() }
        let countAfterFlush = saves
        XCTAssertEqual(countAfterFlush, 1)

        // Flushing again must not double-save.
        await MainActor.run { engine.flush() }
        XCTAssertEqual(saves, 1)
    }

    func testAppLockConfigurationToggles() {
        let defaults = UserDefaults(suiteName: "lock-tests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        let lock = AppLockService(settings: settings)

        XCTAssertFalse(settings.lockEnabled)
        lock.enableLock()
        XCTAssertTrue(settings.lockEnabled)
        XCTAssertNotNil(KeychainStore.get("lock.configured"))

        lock.disableLock()
        XCTAssertFalse(settings.lockEnabled)
    }

    func testLocalHeuristicsAreDeterministicAndUseful() {
        let text = "We need to call the framer. The framer will confirm the size. Remember to book the van."

        let summary = HeuristicWriting.process(.summarize, text: text)
        XCTAssertFalse(summary.isEmpty)
        XCTAssertLessThanOrEqual(summary.count, text.count)

        let tasks = HeuristicWriting.process(.extractTasks, text: text)
        XCTAssertTrue(tasks.contains("- "))

        let tags = HeuristicWriting.process(.suggestTags, text: text)
        XCTAssertFalse(tags.isEmpty)

        let title = HeuristicWriting.process(.generateTitle, text: text)
        XCTAssertFalse(title.isEmpty)
        XCTAssertLessThanOrEqual(title.split(separator: " ").count, 8)

        let proofed = HeuristicWriting.proofread("teh quick brown fox")
        XCTAssertTrue(proofed.lowercased().contains("the quick"))
    }
}
