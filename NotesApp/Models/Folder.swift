import Foundation
import SwiftData

/// A user created folder.
@Model
final class Folder {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var sortIndex: Int = 0
    var symbolName: String = "folder"

    @Relationship(deleteRule: .nullify, inverse: \Note.folder)
    var notes: [Note] = []

    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), sortIndex: Int = 0, symbolName: String = "folder") {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sortIndex = sortIndex
        self.symbolName = symbolName
    }

    var activeNotes: [Note] {
        notes.filter { $0.deletedAt == nil && !$0.isArchived }
    }
}

/// A tag that can be applied to many notes.
@Model
final class Tag {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()

    @Relationship(inverse: \Note.tags)
    var notes: [Note] = []

    init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }

    var activeNotes: [Note] {
        notes.filter { $0.deletedAt == nil && !$0.isArchived }
    }
}

/// A binary attachment stored on disk, referenced by id from a note.
@Model
final class Attachment {
    var id: UUID = UUID()
    var fileName: String = ""
    var displayName: String = ""
    var kindRaw: String = AttachmentKind.image.rawValue
    var byteCount: Int = 0
    var createdAt: Date = Date()
    var note: Note?

    init(
        id: UUID = UUID(),
        fileName: String,
        displayName: String = "",
        kind: AttachmentKind,
        byteCount: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fileName = fileName
        self.displayName = displayName.isEmpty ? fileName : displayName
        self.kindRaw = kind.rawValue
        self.byteCount = byteCount
        self.createdAt = createdAt
    }

    var kind: AttachmentKind {
        AttachmentKind(rawValue: kindRaw) ?? .document
    }
}

enum AttachmentKind: String, Codable, CaseIterable, Sendable {
    case image
    case scan
    case audio
    case document
    case handwriting

    var isVisual: Bool {
        self == .image || self == .scan || self == .handwriting
    }
}
