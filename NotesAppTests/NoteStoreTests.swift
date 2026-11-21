import XCTest
import SwiftData
import UIKit
@testable import NotesApp

@MainActor
final class NoteStoreTests: XCTestCase {

    private func makeStore() throws -> (NoteStore, ModelContainer, AttachmentStore) {
        let container = try ModelContainerFactory.make(inMemory: true, preferCloudKit: false).container
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotesAppTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let attachments = AttachmentStore(root: root)
        return (NoteStore(context: container.mainContext, attachmentStore: attachments), container, attachments)
    }

    func testCreateNoteSetsTimestampsAndContent() throws {
        let (store, _, _) = try makeStore()
        let now = Date()
        let document = NoteDocument(blocks: [NoteBlock(kind: .heading1, text: "Hello")])
        let note = store.createNote(title: "Greeting", document: document, now: now)

        XCTAssertEqual(note.title, "Greeting")
        XCTAssertEqual(note.createdAt, now)
        XCTAssertEqual(note.updatedAt, now)
        XCTAssertEqual(note.document.blocks.first?.text, "Hello")
        XCTAssertEqual(store.fetchAllNotes().count, 1)
    }

    func testEditUpdatesTimestampAndSearchText() throws {
        let (store, _, _) = try makeStore()
        let note = store.createNote(title: "Draft", document: NoteDocument(blocks: [NoteBlock(text: "alpha")]))
        let originalUpdated = note.updatedAt

        let later = Date().addingTimeInterval(120)
        store.applyEdit(
            to: note,
            title: "Final",
            document: NoteDocument(blocks: [NoteBlock(text: "beta content")]),
            now: later
        )

        XCTAssertEqual(note.title, "Final")
        XCTAssertGreaterThan(note.updatedAt, originalUpdated)
        XCTAssertTrue(note.searchText.contains("beta content"))
        XCTAssertFalse(note.searchText.contains("alpha"))
    }

    func testAutosaveCanBeDisabledForTests() throws {
        let (store, _, _) = try makeStore()
        store.autosaves = false
        let note = store.createNote(title: "Unsaved", document: NoteDocument(blocks: [NoteBlock(text: "x")]))
        store.applyEdit(to: note, title: "Unsaved 2", document: NoteDocument(blocks: [NoteBlock(text: "y")]))
        // Model updates still happen, only automatic persistence is skipped.
        XCTAssertEqual(note.title, "Unsaved 2")
    }

    func testSoftDeleteAndRestore() throws {
        let (store, _, _) = try makeStore()
        let note = store.createNote(title: "Temp", document: NoteDocument())

        store.softDelete(note)
        XCTAssertNotNil(note.deletedAt)
        XCTAssertEqual(store.count(of: .trash), 1)
        XCTAssertTrue(store.fetchAllNotes().isEmpty)

        store.restore(note)
        XCTAssertNil(note.deletedAt)
        XCTAssertEqual(store.count(of: .trash), 0)
        XCTAssertEqual(store.fetchAllNotes().count, 1)
    }

    func testPermanentDeleteRemovesAttachmentFiles() throws {
        let (store, _, attachments) = try makeStore()
        let note = store.createNote(title: "With image", document: NoteDocument())
        let data = Self.makeImageData()
        let attachment = try store.attachImage(data: data, to: note)
        XCTAssertTrue(attachments.exists(attachment.fileName))

        store.permanentlyDelete(note)

        XCTAssertFalse(attachments.exists(attachment.fileName))
        XCTAssertEqual(store.fetchAllNotes().count, 0)
    }

    func testDuplicateCopiesBlocksAndTitle() throws {
        let (store, _, _) = try makeStore()
        let note = store.createNote(
            title: "Original",
            document: NoteDocument(blocks: [NoteBlock(text: "one"), NoteBlock(text: "two")])
        )
        let copy = store.duplicate(note)

        XCTAssertNotEqual(copy.id, note.id)
        XCTAssertEqual(copy.title, "Original Copy")
        XCTAssertEqual(copy.document.blocks.count, 2)
        XCTAssertEqual(store.fetchAllNotes().count, 2)
    }

    func testFlagToggles() throws {
        let (store, _, _) = try makeStore()
        let note = store.createNote(title: "Flags", document: NoteDocument())

        store.togglePin(note)
        XCTAssertTrue(note.isPinned)
        store.toggleFavorite(note)
        XCTAssertTrue(note.isFavorite)

        store.setArchived(note, archived: true)
        XCTAssertTrue(note.isArchived)
        XCTAssertFalse(note.isPinned)
        XCTAssertEqual(store.count(of: .archive), 1)
    }

    func testFoldersAndMove() throws {
        let (store, _, _) = try makeStore()
        let folder = store.createFolder(named: "Work")
        let note = store.createNote(title: "Task", document: NoteDocument())

        store.move(note, to: folder)
        XCTAssertEqual(note.folder?.id, folder.id)
        XCTAssertEqual(folder.activeNotes.count, 1)

        store.move(note, to: nil)
        XCTAssertNil(note.folder)
        XCTAssertEqual(store.count(of: .all), 1)
    }

    func testTagNormalizationAndApplication() throws {
        XCTAssertEqual(NoteStore.normalizedTag("  #Work Items "), "Work-Items")
        XCTAssertEqual(NoteStore.normalizedTag(""), "")

        let (store, _, _) = try makeStore()
        let note = store.createNote(title: "Tagged", document: NoteDocument())
        guard let tag = store.tag(named: "Travel") else {
            return XCTFail("Expected a tag")
        }
        store.addTag(tag, to: note)
        XCTAssertEqual(note.tags.count, 1)

        // Duplicate names resolve to the same tag instead of creating another.
        let again = store.tag(named: "travel")
        XCTAssertEqual(again?.id, tag.id)

        store.removeTag(tag, from: note)
        XCTAssertTrue(note.tags.isEmpty)
    }

    func testEmptyTrashRemovesDeletedNotesOnly() throws {
        let (store, _, _) = try makeStore()
        let keep = store.createNote(title: "Keep", document: NoteDocument())
        let bin = store.createNote(title: "Bin", document: NoteDocument())
        store.softDelete(bin)

        store.emptyTrash()

        XCTAssertEqual(store.fetchAllNotes().count, 1)
        XCTAssertEqual(store.fetchAllNotes().first?.id, keep.id)
        XCTAssertEqual(store.count(of: .trash), 0)
    }

    func testSeedDataCreatesNotesAndFolders() throws {
        let (store, _, _) = try makeStore()
        let count = SeedData.populate(store)

        XCTAssertEqual(store.fetchAllNotes().count, count)
        XCTAssertEqual(store.fetchFolders().count, 3)
        XCTAssertFalse(store.fetchTags().isEmpty)
        XCTAssertTrue(store.fetchAllNotes().contains { $0.isPinned })
    }

    func testLargeDocumentStaysWorkable() throws {
        let (store, _, _) = try makeStore()
        let document = SeedData.stressDocument(words: 2_000)
        let note = store.createNote(title: "Large", document: document)

        XCTAssertGreaterThan(NoteBodyCodec.decode(note.bodyJSON).blocks.count, 40)
        XCTAssertGreaterThan(note.wordCount, 1_000)
        XCTAssertFalse(note.searchText.isEmpty)
    }

    static func makeImageData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 240))
        let image = renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
            UIColor.white.setFill()
            context.fill(CGRect(x: 40, y: 40, width: 120, height: 120))
        }
        return image.jpegData(compressionQuality: 0.9) ?? Data()
    }
}
