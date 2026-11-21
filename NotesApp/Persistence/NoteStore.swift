import Foundation
import SwiftData

/// All note mutations funnel through here so timestamps, derived search text and
/// attachment cleanup stay consistent no matter which screen triggered them.
@MainActor
@Observable
final class NoteStore {
    private let context: ModelContext
    private let attachmentStore: AttachmentStore

    /// Set to false in tests that assert on unsaved state.
    var autosaves = true

    init(context: ModelContext, attachmentStore: AttachmentStore = .shared) {
        self.context = context
        self.attachmentStore = attachmentStore
    }

    // MARK: - Create and update

    @discardableResult
    func createNote(
        title: String = "",
        document: NoteDocument = NoteDocument(),
        folder: Folder? = nil,
        tags: [Tag] = [],
        now: Date = Date()
    ) -> Note {
        let note = Note(title: title, document: document, folder: folder, createdAt: now, updatedAt: now)
        note.tags = tags
        context.insert(note)
        save()
        return note
    }

    /// Applies an edit. Designed to be called from the autosave path, which
    /// debounces so typing never blocks on disk writes.
    func applyEdit(to note: Note, title: String, document: NoteDocument, now: Date = Date()) {
        note.apply(document: document, title: title, now: now)
        save()
    }

    // MARK: - Lifecycle

    func softDelete(_ note: Note) {
        note.deletedAt = Date()
        note.isPinned = false
        save()
    }

    func restore(_ note: Note) {
        note.deletedAt = nil
        note.updatedAt = Date()
        save()
    }

    func permanentlyDelete(_ note: Note) {
        let names = note.attachments.map(\.fileName)
        context.delete(note)
        save()
        attachmentStore.delete(fileNames: names)
    }

    /// Empties recently deleted notes. `olderThan` keeps items newer than the cutoff.
    func emptyTrash(olderThan cutoff: Date? = nil) {
        let notes = fetchDeletedNotes()
        for note in notes where cutoff == nil || (note.deletedAt ?? .distantPast) < (cutoff ?? .distantFuture) {
            permanentlyDelete(note)
        }
    }

    @discardableResult
    func duplicate(_ note: Note, now: Date = Date()) -> Note {
        let copy = Note(
            title: note.displayTitle + " Copy",
            document: note.document,
            folder: note.folder,
            createdAt: now,
            updatedAt: now
        )
        copy.tags = note.tags
        copy.isPinned = false
        copy.isFavorite = note.isFavorite
        copy.isProtected = note.isProtected
        for attachment in note.attachments {
            let clone = Attachment(
                fileName: attachment.fileName,
                displayName: attachment.displayName,
                kind: attachment.kind,
                byteCount: attachment.byteCount,
                createdAt: now
            )
            context.insert(clone)
            copy.attachments.append(clone)
        }
        context.insert(copy)
        save()
        return copy
    }

    // MARK: - Flags

    func togglePin(_ note: Note) {
        note.isPinned.toggle()
        note.updatedAt = Date()
        save()
    }

    func toggleFavorite(_ note: Note) {
        note.isFavorite.toggle()
        note.updatedAt = Date()
        save()
    }

    func setArchived(_ note: Note, archived: Bool) {
        note.isArchived = archived
        if archived { note.isPinned = false }
        note.updatedAt = Date()
        save()
    }

    func setProtected(_ note: Note, protected: Bool) {
        note.isProtected = protected
        save()
    }

    func move(_ note: Note, to folder: Folder?) {
        note.folder = folder
        note.updatedAt = Date()
        save()
    }

    func setReminder(_ note: Note, at date: Date?) {
        note.reminderAt = date
        save()
    }

    // MARK: - Folders and tags

    @discardableResult
    func createFolder(named name: String, symbolName: String = "folder") -> Folder {
        let existingCount = (try? context.fetchCount(FetchDescriptor<Folder>())) ?? 0
        let folder = Folder(name: name, sortIndex: existingCount, symbolName: symbolName)
        context.insert(folder)
        save()
        return folder
    }

    func rename(_ folder: Folder, to name: String) {
        folder.name = name
        save()
    }

    func delete(_ folder: Folder) {
        context.delete(folder)
        save()
    }

    @discardableResult
    func tag(named rawName: String) -> Tag? {
        let name = Self.normalizedTag(rawName)
        guard !name.isEmpty else { return nil }
        let descriptor = FetchDescriptor<Tag>()
        let existing = (try? context.fetch(descriptor)) ?? []
        if let match = existing.first(where: { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }) {
            return match
        }
        let tag = Tag(name: name)
        context.insert(tag)
        save()
        return tag
    }

    func addTag(_ tag: Tag, to note: Note) {
        guard !note.tags.contains(where: { $0.id == tag.id }) else { return }
        note.tags.append(tag)
        note.updatedAt = Date()
        save()
    }

    func removeTag(_ tag: Tag, from note: Note) {
        note.tags.removeAll { $0.id == tag.id }
        note.updatedAt = Date()
        save()
    }

    func delete(_ tag: Tag) {
        context.delete(tag)
        save()
    }

    static func normalizedTag(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: ",", with: " ")
        let collapsed = trimmed.split(separator: " ").joined(separator: "-")
        return String(collapsed.prefix(40))
    }

    // MARK: - Attachments

    @discardableResult
    func attachImage(data: Data, to note: Note, kind: AttachmentKind = .image) throws -> Attachment {
        let fileName = try attachmentStore.saveImageData(data)
        let attachment = Attachment(
            fileName: fileName,
            displayName: "Image",
            kind: kind,
            byteCount: attachmentStore.byteCount(for: fileName)
        )
        context.insert(attachment)
        note.attachments.append(attachment)
        note.updatedAt = Date()
        save()
        return attachment
    }

    @discardableResult
    func attachFile(at url: URL, to note: Note, kind: AttachmentKind = .document) throws -> Attachment {
        let fileName = try attachmentStore.saveDocument(from: url)
        let attachment = Attachment(
            fileName: fileName,
            displayName: url.lastPathComponent,
            kind: kind,
            byteCount: attachmentStore.byteCount(for: fileName)
        )
        context.insert(attachment)
        note.attachments.append(attachment)
        note.updatedAt = Date()
        save()
        return attachment
    }

    func removeAttachment(_ attachment: Attachment, from note: Note) {
        let fileName = attachment.fileName
        note.attachments.removeAll { $0.id == attachment.id }
        context.delete(attachment)
        save()
        attachmentStore.delete(fileNames: [fileName])
    }

    func attachment(withID id: UUID, in note: Note) -> Attachment? {
        note.attachments.first { $0.id == id }
    }

    // MARK: - Fetching

    func fetchAllNotes() -> [Note] {
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\Note.updatedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchDeletedNotes() -> [Note] {
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { $0.deletedAt != nil },
            sortBy: [SortDescriptor(\Note.deletedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchFolders() -> [Folder] {
        let descriptor = FetchDescriptor<Folder>(sortBy: [SortDescriptor(\Folder.sortIndex)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchTags() -> [Tag] {
        let descriptor = FetchDescriptor<Tag>(sortBy: [SortDescriptor(\Tag.name)])
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Persistence

    @discardableResult
    func save() -> Bool {
        guard autosaves else { return true }
        return persist()
    }

    /// Unconditional save used by the autosave engine and by scene transitions.
    @discardableResult
    func persist() -> Bool {
        do {
            try context.save()
            return true
        } catch {
            // Never log note contents. Only the failure category is emitted.
            NSLog("[NotesApp] Persistence save failed: \(error.localizedDescription)")
            return false
        }
    }

    func count(of kind: NoteCount) -> Int {
        switch kind {
        case .trash:
            return fetchDeletedNotes().count
        case .archive:
            let descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.deletedAt == nil && $0.isArchived })
            return (try? context.fetchCount(descriptor)) ?? 0
        case .all:
            let descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.deletedAt == nil && !$0.isArchived })
            return (try? context.fetchCount(descriptor)) ?? 0
        }
    }

    enum NoteCount {
        case all, archive, trash
    }
}
