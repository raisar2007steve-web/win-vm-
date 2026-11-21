import Foundation

/// The block types supported by the note editor.
///
/// Notes are stored as an ordered array of blocks encoded to JSON. This keeps the
/// editor fast (only visible blocks are rendered) and lets rich structure exist
/// without shipping an attributed-string blob that is expensive to migrate.
enum BlockKind: String, Codable, CaseIterable, Sendable {
    case paragraph
    case heading1
    case heading2
    case bullet
    case numbered
    case checklist
    case code
    case quote
    case divider
    case image
    case audio
    case document
    case table

    var isTextual: Bool {
        switch self {
        case .paragraph, .heading1, .heading2, .bullet, .numbered, .checklist, .code, .quote:
            return true
        case .divider, .image, .audio, .document, .table:
            return false
        }
    }

    var isList: Bool {
        switch self {
        case .bullet, .numbered, .checklist:
            return true
        default:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .paragraph: return "Body"
        case .heading1: return "Title"
        case .heading2: return "Heading"
        case .bullet: return "Bulleted List"
        case .numbered: return "Numbered List"
        case .checklist: return "Checklist"
        case .code: return "Code"
        case .quote: return "Quote"
        case .divider: return "Divider"
        case .image: return "Image"
        case .audio: return "Audio"
        case .document: return "Document"
        case .table: return "Table"
        }
    }

    var systemImage: String {
        switch self {
        case .paragraph: return "text.alignleft"
        case .heading1: return "textformat.size.larger"
        case .heading2: return "textformat.size"
        case .bullet: return "list.bullet"
        case .numbered: return "list.number"
        case .checklist: return "checklist"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .quote: return "text.quote"
        case .divider: return "minus"
        case .image: return "photo"
        case .audio: return "waveform"
        case .document: return "doc"
        case .table: return "tablecells"
        }
    }
}

/// A single editable unit of a note.
struct NoteBlock: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var kind: BlockKind
    var text: String
    var isChecked: Bool
    var attachmentID: UUID?
    var rows: [[String]]
    var indentLevel: Int

    init(
        id: UUID = UUID(),
        kind: BlockKind = .paragraph,
        text: String = "",
        isChecked: Bool = false,
        attachmentID: UUID? = nil,
        rows: [[String]] = [],
        indentLevel: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.isChecked = isChecked
        self.attachmentID = attachmentID
        self.rows = rows
        self.indentLevel = indentLevel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decodeIfPresent(BlockKind.self, forKey: .kind) ?? .paragraph
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        isChecked = try container.decodeIfPresent(Bool.self, forKey: .isChecked) ?? false
        attachmentID = try container.decodeIfPresent(UUID.self, forKey: .attachmentID)
        rows = try container.decodeIfPresent([[String]].self, forKey: .rows) ?? []
        indentLevel = try container.decodeIfPresent(Int.self, forKey: .indentLevel) ?? 0
    }
}

/// The decoded body of a note.
struct NoteDocument: Codable, Hashable, Sendable {
    var blocks: [NoteBlock]

    init(blocks: [NoteBlock] = [NoteBlock()]) {
        self.blocks = blocks.isEmpty ? [NoteBlock()] : blocks
    }

    var isEmpty: Bool {
        blocks.allSatisfy { block in
            block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && block.attachmentID == nil
                && block.rows.isEmpty
        }
        && blocks.allSatisfy { $0.kind == .paragraph || $0.kind == .divider }
    }

    /// Searchable text used for the denormalised `searchText` column.
    var plainText: String {
        blocks.compactMap { block -> String? in
            switch block.kind {
            case .divider:
                return nil
            case .table:
                return block.rows.flatMap { $0 }.joined(separator: " ")
            default:
                let trimmed = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        }
        .joined(separator: "\n")
    }

    /// A one-line preview, used by list rows without decoding the whole document twice.
    var preview: String {
        blocks.lazy
            .filter { $0.kind.isTextual }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") }
            ?? ""
    }

    var checklistItems: [(id: UUID, text: String, isChecked: Bool)] {
        blocks.filter { $0.kind == .checklist }
            .map { (id: $0.id, text: $0.text, isChecked: $0.isChecked) }
    }

    var firstLine: String {
        blocks.first { $0.kind.isTextual && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?.text ?? ""
    }

    /// Markdown representation used for export and rich copy.
    var markdown: String {
        blocks.map { block -> String in
            switch block.kind {
            case .paragraph:
                return block.text
            case .heading1:
                return "# \(block.text)"
            case .heading2:
                return "## \(block.text)"
            case .bullet:
                return "- \(block.text)"
            case .numbered:
                return "1. \(block.text)"
            case .checklist:
                return "- [\(block.isChecked ? "x" : " ")] \(block.text)"
            case .code:
                return "```\n\(block.text)\n```"
            case .quote:
                return "> \(block.text)"
            case .divider:
                return "---"
            case .image:
                return "![image](attachment:\(block.attachmentID?.uuidString ?? ""))"
            case .audio:
                return "![audio](attachment:\(block.attachmentID?.uuidString ?? ""))"
            case .document:
                return "[document](attachment:\(block.attachmentID?.uuidString ?? ""))"
            case .table:
                guard let header = block.rows.first else { return "" }
                let divider = header.map { _ in "---" }.joined(separator: " | ")
                let body = block.rows.dropFirst().map { $0.joined(separator: " | ") }
                return ([header.joined(separator: " | "), divider] + body)
                    .map { "| \($0) |" }
                    .joined(separator: "\n")
            }
        }
        .joined(separator: "\n\n")
    }

    static let empty = NoteDocument()
}

/// JSON codec for note bodies with tolerance for damaged or legacy payloads.
enum NoteBodyCodec {
    static func encode(_ document: NoteDocument) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(document),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }

    static func decode(_ json: String) -> NoteDocument {
        guard !json.isEmpty, let data = json.data(using: .utf8) else {
            return NoteDocument()
        }
        if let document = try? JSONDecoder().decode(NoteDocument.self, from: data) {
            return document
        }
        // Legacy/plain-text payloads: keep the text rather than losing it.
        return NoteDocument(blocks: [NoteBlock(text: json)])
    }
}
