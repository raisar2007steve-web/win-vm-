import Foundation
import UIKit
import UniformTypeIdentifiers

/// Exports notes as Markdown, plain text, PDF or a portable `.note` archive.
enum ExportService {
    static let noteArchiveType = UTType(exportedAs: "com.raisar2007steve.note-archive", conformingTo: .json)

    // MARK: - Text

    static func markdown(for note: Note) -> String {
        var output = "# \(note.displayTitle)\n\n"
        output += note.document.markdown
        if !note.tags.isEmpty {
            output += "\n\n" + note.tags.map { "#" + $0.name }.joined(separator: " ")
        }
        return output
    }

    static func plainText(for note: Note) -> String {
        let body = note.document.blocks.compactMap { block -> String? in
            switch block.kind {
            case .divider: return "———"
            case .table: return block.rows.map { $0.joined(separator: "  |  ") }.joined(separator: "\n")
            default:
                let trimmed = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        }.joined(separator: "\n\n")
        return "\(note.displayTitle)\n\n\(body)"
    }

    /// Portable JSON archive, suitable for `.note` files and handoff between devices.
    static func archive(for note: Note) -> Data {
        struct ArchivedAttachment: Codable {
            let displayName: String
            let kind: String
            let byteCount: Int
        }
        struct ArchivedNote: Codable {
            let title: String
            let createdAt: Date
            let updatedAt: Date
            let tags: [String]
            let folder: String?
            let document: NoteDocument
            let attachments: [ArchivedAttachment]
            let version: Int
        }
        let archived = ArchivedNote(
            title: note.displayTitle,
            createdAt: note.createdAt,
            updatedAt: note.updatedAt,
            tags: note.tags.map(\.name),
            folder: note.folder?.name,
            document: note.document,
            attachments: note.attachments.map {
                ArchivedAttachment(displayName: $0.displayName, kind: $0.kind.rawValue, byteCount: $0.byteCount)
            },
            version: 1
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(archived)) ?? Data()
    }

    // MARK: - PDF

    static func pdfData(for note: Note, pageSize: CGSize = CGSize(width: 595, height: 842)) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let margin: CGFloat = 56
        let contentWidth = pageSize.width - margin * 2
        let bottomLimit = pageSize.height - margin

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.preferredFont(forTextStyle: .largeTitle).withSize(26),
            .foregroundColor: UIColor.label
        ]
        let metaAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.preferredFont(forTextStyle: .footnote),
            .foregroundColor: UIColor.secondaryLabel
        ]

        return renderer.pdfData { context in
            context.beginPage()
            var y = margin

            func beginNewPageIfNeeded(_ required: CGFloat) {
                if y + required > bottomLimit {
                    context.beginPage()
                    y = margin
                }
            }

            func draw(_ text: String, attributes: [NSAttributedString.Key: Any], spacingAfter: CGFloat) {
                guard !text.isEmpty else { return }
                let attributed = NSAttributedString(string: text, attributes: attributes)
                let bounding = attributed.boundingRect(
                    with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                beginNewPageIfNeeded(bounding.height)
                attributed.draw(with: CGRect(x: margin, y: y, width: contentWidth, height: bounding.height),
                                options: [.usesLineFragmentOrigin, .usesFontLeading],
                                context: nil)
                y += bounding.height + spacingAfter
            }

            draw(note.displayTitle, attributes: titleAttributes, spacingAfter: 6)

            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            var meta = "Edited " + formatter.string(from: note.updatedAt)
            if !note.tags.isEmpty {
                meta += "  ·  " + note.tags.map { "#" + $0.name }.joined(separator: " ")
            }
            draw(meta, attributes: metaAttributes, spacingAfter: 20)

            for block in note.document.blocks {
                switch block.kind {
                case .paragraph:
                    draw(block.text, attributes: bodyAttributes(size: 12), spacingAfter: 10)
                case .heading1:
                    draw(block.text, attributes: bodyAttributes(size: 20, weight: .bold), spacingAfter: 8)
                case .heading2:
                    draw(block.text, attributes: bodyAttributes(size: 16, weight: .semibold), spacingAfter: 8)
                case .bullet:
                    draw("•  " + block.text, attributes: bodyAttributes(size: 12), spacingAfter: 6)
                case .numbered:
                    draw("–  " + block.text, attributes: bodyAttributes(size: 12), spacingAfter: 6)
                case .checklist:
                    draw((block.isChecked ? "☑  " : "☐  ") + block.text, attributes: bodyAttributes(size: 12), spacingAfter: 6)
                case .code:
                    draw(block.text, attributes: [
                        .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                        .foregroundColor: UIColor.label
                    ], spacingAfter: 10)
                case .quote:
                    draw("“" + block.text + "”", attributes: [
                        .font: UIFont.italicSystemFont(ofSize: 12),
                        .foregroundColor: UIColor.secondaryLabel
                    ], spacingAfter: 10)
                case .divider:
                    beginNewPageIfNeeded(12)
                    let path = UIBezierPath()
                    path.move(to: CGPoint(x: margin, y: y))
                    path.addLine(to: CGPoint(x: pageSize.width - margin, y: y))
                    UIColor.separator.setStroke()
                    path.lineWidth = 0.5
                    path.stroke()
                    y += 14
                case .image, .audio, .document:
                    let attachment = note.attachments.first { $0.id == block.attachmentID }
                    let label = block.kind == .image ? "Image" : block.kind == .audio ? "Audio recording" : "Document"
                    draw("[\(label): \(attachment?.displayName ?? "attachment")]",
                         attributes: [
                            .font: UIFont.italicSystemFont(ofSize: 11),
                            .foregroundColor: UIColor.secondaryLabel
                         ], spacingAfter: 10)
                case .table:
                    for row in block.rows {
                        draw(row.joined(separator: "   |   "), attributes: bodyAttributes(size: 11), spacingAfter: 4)
                    }
                    y += 6
                }
            }

            let footer = "Exported from Notes · " + formatter.string(from: Date())
            draw(footer, attributes: metaAttributes, spacingAfter: 0)
        }
    }

    private static func bodyAttributes(size: CGFloat, weight: UIFont.Weight = .regular) -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: UIColor.label
        ]
    }

    // MARK: - Temporary files

    static func writeTemporaryFile(name: String, data: Data) -> URL? {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    static func markdownFile(for note: Note) -> URL? {
        writeTemporaryFile(name: safeFileName(note.displayTitle) + ".md", data: Data(markdown(for: note).utf8))
    }

    static func pdfFile(for note: Note) -> URL? {
        writeTemporaryFile(name: safeFileName(note.displayTitle) + ".pdf", data: pdfData(for: note))
    }

    static func archiveFile(for note: Note) -> URL? {
        writeTemporaryFile(name: safeFileName(note.displayTitle) + ".note", data: archive(for: note))
    }

    static func safeFileName(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let filtered = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let name = String(filtered).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Note" : String(name.prefix(60))
    }
}
