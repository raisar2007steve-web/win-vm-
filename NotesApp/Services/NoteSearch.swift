import Foundation

/// Search and sorting helpers kept free of SwiftData so they are trivially unit testable.
enum NoteSearch {
    static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }

    static func matches(_ note: Note, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let tokens = fold(trimmed).split(separator: " ").map(String.init)
        let haystack = fold(note.title + "\n" + note.searchText + "\n" + note.tags.map(\.name).joined(separator: " "))
        return tokens.allSatisfy { haystack.contains($0) }
    }

    static func filter(_ notes: [Note], query: String) -> [Note] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return notes }
        return notes.filter { matches($0, query: query) }
    }
}

enum NoteSortOrder: String, CaseIterable, Identifiable, Codable {
    case updatedNewest
    case updatedOldest
    case createdNewest
    case createdOldest
    case titleAscending

    var id: String { rawValue }

    var label: String {
        switch self {
        case .updatedNewest: return "Date Edited (Newest)"
        case .updatedOldest: return "Date Edited (Oldest)"
        case .createdNewest: return "Date Created (Newest)"
        case .createdOldest: return "Date Created (Oldest)"
        case .titleAscending: return "Title (A–Z)"
        }
    }

    func sort(_ notes: [Note]) -> [Note] {
        notes.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            switch self {
            case .updatedNewest:
                return lhs.updatedAt > rhs.updatedAt
            case .updatedOldest:
                return lhs.updatedAt < rhs.updatedAt
            case .createdNewest:
                return lhs.createdAt > rhs.createdAt
            case .createdOldest:
                return lhs.createdAt < rhs.createdAt
            case .titleAscending:
                return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
            }
        }
    }
}
