import Foundation

/// What the note list is currently showing.
enum NotesScope: Hashable, Identifiable {
    case all
    case quick
    case pinned
    case favorites
    case archive
    case trash
    case folder(UUID)
    case tag(UUID)

    var id: String {
        switch self {
        case .all: return "all"
        case .quick: return "quick"
        case .pinned: return "pinned"
        case .favorites: return "favorites"
        case .archive: return "archive"
        case .trash: return "trash"
        case .folder(let id): return "folder-\(id.uuidString)"
        case .tag(let id): return "tag-\(id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .all: return "All Notes"
        case .quick: return "Quick Notes"
        case .pinned: return "Pinned"
        case .favorites: return "Favorites"
        case .archive: return "Archive"
        case .trash: return "Recently Deleted"
        case .folder: return "Folder"
        case .tag: return "Tag"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "note.text"
        case .quick: return "square.and.pencil"
        case .pinned: return "pin"
        case .favorites: return "star"
        case .archive: return "archivebox"
        case .trash: return "trash"
        case .folder: return "folder"
        case .tag: return "number"
        }
    }

    var supportsCreating: Bool {
        switch self {
        case .trash, .archive, .pinned, .favorites, .tag:
            return false
        default:
            return true
        }
    }

    var showsDeletedNotes: Bool {
        self == .trash
    }
}
