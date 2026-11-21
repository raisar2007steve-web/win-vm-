import SwiftUI

struct NoteRowView: View {
    let note: Note

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(accentColor.gradient)
                .frame(width: 4)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    Text(note.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Self.relativeDate(note.updatedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    Text(Self.dateLabel(note.updatedAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let folder = note.folder {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Label(folder.name, systemImage: "folder")
                            .labelStyle(.titleAndIcon)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(note.previewText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 1)

                HStack(spacing: 6) {
                    if !note.sortedTags.isEmpty {
                        ForEach(note.sortedTags.prefix(3)) { tag in
                            Text("#" + tag.name)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                                .foregroundStyle(.tint)
                        }
                    }
                    if !note.attachments.isEmpty {
                        Label("\(note.attachments.count)", systemImage: "paperclip")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if note.isProtected {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if note.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
    }

    private var accentColor: Color {
        let palette: [Color] = [.orange, .pink, .purple, .blue, .teal, .green]
        return palette[AccentPalette.colorIndex(for: note) % palette.count]
    }

    static func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
            ? "d MMM"
            : "d MMM yyyy"
        return formatter.string(from: date)
    }

    static func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    let symbol: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .accessibilityIdentifier("emptyState")
    }
}
