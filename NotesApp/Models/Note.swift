import Foundation
import SwiftData

/// A note. Content lives in `bodyJSON` as an encoded `NoteDocument`; `searchText`
/// is a denormalised copy of the plain text so queries never decode JSON.
@Model
final class Note {
    var id: UUID = UUID()
    var title: String = ""
    var bodyJSON: String = ""
    var searchText: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isPinned: Bool = false
    var isFavorite: Bool = false
    var isArchived: Bool = false
    var isProtected: Bool = false
    var deletedAt: Date?
    var reminderAt: Date?
    var accentIndex: Int = 0

    var folder: Folder?
    var tags: [Tag] = []

    @Relationship(deleteRule: .cascade, inverse: \Attachment.note)
    var attachments: [Attachment] = []

    init(
        id: UUID = UUID(),
        title: String = "",
        document: NoteDocument = NoteDocument(),
        folder: Folder? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.folder = folder
        self.apply(document)
    }

    var document: NoteDocument {
        NoteBodyCodec.decode(bodyJSON)
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let first = document.firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return first.isEmpty ? "New Note" : String(first.prefix(120))
    }

    var previewText: String {
        let body = document.preview
        return body.isEmpty ? "No additional text" : String(body.prefix(240))
    }

    var wordCount: Int {
        searchText.split { $0.isWhitespace || $0.isNewline }.count
    }

    var isDeleted: Bool { deletedAt != nil }

    var sortedTags: [Tag] {
        tags.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Applies a document and keeps the derived search text in sync.
    func apply(_ document: NoteDocument) {
        bodyJSON = NoteBodyCodec.encode(document)
        searchText = document.plainText
        accentIndex = abs(title.hashValue) % AccentPalette.count
    }

    func apply(document: NoteDocument, title: String, now: Date = Date()) {
        self.title = title
        apply(document)
        updatedAt = max(now, createdAt)
    }
}

enum AccentPalette {
    static let count = 6

    static func colorIndex(for note: Note) -> Int {
        abs(note.id.uuidString.hashValue) % count
    }
}
