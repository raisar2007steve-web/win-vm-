import SwiftUI

/// Renders and edits one block. Text blocks use vertically growing text fields so
/// Dynamic Type and long paragraphs behave, and images render from thumbnails.
struct BlockRowView: View {
    @Binding var block: NoteBlock
    var attachments: [Attachment]
    var onDelete: () -> Void
    var onOpenAttachment: (Attachment) -> Void
    @FocusState.Binding var focusedBlock: UUID?

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            marker
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, block.kind == .divider ? 6 : 2)
        .contentShape(Rectangle())
        .contextMenu {
            Menu("Change Style") {
                ForEach(BlockStyleOption.all, id: \.kind) { option in
                    Button {
                        block.kind = option.kind
                    } label: {
                        Label(option.title, systemImage: option.kind.systemImage)
                    }
                }
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Block", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var marker: some View {
        switch block.kind {
        case .heading1, .heading2, .paragraph, .code, .quote:
            Color.clear.frame(width: 0)
        case .bullet:
            Text("•")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .center)
                .padding(.top, 1)
        case .numbered:
            Text("–")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .center)
                .padding(.top, 1)
        case .checklist:
            Button {
                block.isChecked.toggle()
                Haptics.selection()
            } label: {
                Image(systemName: block.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(block.isChecked ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)
            .accessibilityIdentifier("checklistToggle")
        case .image, .audio, .document, .table, .divider:
            Color.clear.frame(width: 0)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch block.kind {
        case .paragraph:
            textField(font: .body, prompt: "Write something…")
        case .heading1:
            textField(font: .title2.weight(.bold), prompt: "Title")
        case .heading2:
            textField(font: .title3.weight(.semibold), prompt: "Heading")
        case .bullet, .numbered:
            textField(font: .body, prompt: "List item")
        case .checklist:
            textField(font: .body, prompt: "To-do")
                .strikethrough(block.isChecked, color: .secondary)
                .foregroundStyle(block.isChecked ? .secondary : .primary)
        case .code:
            textField(font: .system(.callout, design: .monospaced), prompt: "Code")
                .padding(10)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .quote:
            HStack(spacing: 10) {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: 3)
                textField(font: .body.italic(), prompt: "Quote")
                    .foregroundStyle(.secondary)
            }
        case .divider:
            Divider()
        case .image:
            attachmentCard(kind: .image)
        case .audio:
            attachmentCard(kind: .audio)
        case .document:
            attachmentCard(kind: .document)
        case .table:
            tableEditor
        }
    }

    private func textField(font: Font, prompt: String) -> some View {
        TextField(prompt, text: $block.text, axis: .vertical)
            .font(font)
            .textFieldStyle(.plain)
            .lineLimit(1...40)
            .focused($focusedBlock, equals: block.id)
            .accessibilityIdentifier("blockField-\(block.kind.rawValue)")
    }

    // MARK: - Attachments

    @ViewBuilder
    private func attachmentCard(kind: BlockKind) -> some View {
        if let attachment = attachments.first(where: { $0.id == block.attachmentID }) {
            Button {
                onOpenAttachment(attachment)
            } label: {
                switch attachment.kind {
                case .image, .scan, .handwriting:
                    if let image = ThumbnailCache.shared.image(named: attachment.fileName, maxPixel: 900) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxHeight: 260)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(alignment: .bottomLeading) {
                                if attachment.kind == .scan {
                                    Label("Scan", systemImage: "doc.viewfinder")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.ultraThinMaterial, in: Capsule())
                                        .padding(8)
                                }
                            }
                    } else {
                        placeholderCard(attachment, symbol: "photo")
                    }
                case .audio:
                    Label(attachment.displayName, systemImage: "waveform")
                        .font(.subheadline)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                case .document:
                    placeholderCard(attachment, symbol: "doc.text")
                }
            }
            .buttonStyle(.plain)
        } else {
            Label("Missing \(kind.displayName.lowercased()) attachment", systemImage: kind.systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func placeholderCard(_ attachment: Attachment, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Table

    @ViewBuilder
    private var tableEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(block.rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 6) {
                    ForEach(block.rows[rowIndex].indices, id: \.self) { columnIndex in
                        TextField(
                            columnIndex == 0 ? "Label" : "Value",
                            text: Binding(
                                get: {
                                    guard rowIndex < block.rows.count, columnIndex < block.rows[rowIndex].count else { return "" }
                                    return block.rows[rowIndex][columnIndex]
                                },
                                set: { newValue in
                                    guard rowIndex < block.rows.count, columnIndex < block.rows[rowIndex].count else { return }
                                    block.rows[rowIndex][columnIndex] = newValue
                                }
                            )
                        )
                        .font(rowIndex == 0 ? .caption.weight(.semibold) : .caption)
                        .textFieldStyle(.roundedBorder)
                    }
                }
            }
            HStack(spacing: 8) {
                Button {
                    let columns = block.rows.first?.count ?? 2
                    block.rows.append(Array(repeating: "", count: max(columns, 2)))
                } label: {
                    Label("Add Row", systemImage: "plus")
                        .font(.caption)
                }
                Button {
                    guard block.rows.count > 1 else { return }
                    block.rows.removeLast()
                } label: {
                    Label("Remove Row", systemImage: "minus")
                        .font(.caption)
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct BlockStyleOption {
    let kind: BlockKind
    let title: String

    static let all: [BlockStyleOption] = [
        BlockStyleOption(kind: .paragraph, title: "Body"),
        BlockStyleOption(kind: .heading1, title: "Title"),
        BlockStyleOption(kind: .heading2, title: "Heading"),
        BlockStyleOption(kind: .bullet, title: "Bulleted List"),
        BlockStyleOption(kind: .numbered, title: "Numbered List"),
        BlockStyleOption(kind: .checklist, title: "Checklist"),
        BlockStyleOption(kind: .quote, title: "Quote"),
        BlockStyleOption(kind: .code, title: "Code")
    ]
}
