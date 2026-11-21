import SwiftUI
import SwiftData

struct NoteListView: View {
    @Environment(AppEnvironment.self) private var app
    let scope: NotesScope
    @Binding var path: NavigationPath

    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query private var folders: [Folder]
    @Query private var tags: [Tag]

    @State private var searchText = ""
    @State private var appliedSearch = ""
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        Group {
            if displayedNotes.isEmpty {
                EmptyStateView(
                    title: emptyTitle,
                    message: emptyMessage,
                    symbol: emptySymbol
                )
            } else {
                noteList
            }
        }
        .navigationTitle(scopeTitle)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search notes")
        .onChange(of: searchText) { _, newValue in
            scheduleSearch(newValue)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                sortMenu
            }
            if scope.supportsCreating {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        compose()
                    } label: {
                        Label("New Note", systemImage: "square.and.pencil")
                    }
                    .accessibilityIdentifier("newNoteToolbarButton")
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if scope.supportsCreating {
                composeButton
            }
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    // MARK: - List

    private var noteList: some View {
        List {
            ForEach(displayedNotes) { note in
                NavigationLink(value: note) {
                    NoteRowView(note: note)
                }
                .accessibilityIdentifier("noteRow-\(note.id.uuidString)")
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if scope.showsDeletedNotes {
                        Button(role: .destructive) {
                            app.store.permanentlyDelete(note)
                            Haptics.warning()
                        } label: {
                            Label("Delete", systemImage: "trash.slash")
                        }
                        Button {
                            app.store.restore(note)
                            Haptics.success()
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.green)
                    } else {
                        Button(role: .destructive) {
                            app.store.softDelete(note)
                            SpotlightIndexer.remove(note)
                            Haptics.warning()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            app.store.togglePin(note)
                            Haptics.impact()
                        } label: {
                            Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
                        }
                        .tint(.orange)
                    }
                }
                .contextMenu {
                    contextActions(for: note)
                }
            }
        }
        .listStyle(.plain)
        .animation(.default, value: displayedNotes.map(\.id))
    }

    @ViewBuilder
    private func contextActions(for note: Note) -> some View {
        if scope.showsDeletedNotes {
            Button {
                app.store.restore(note)
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            Button(role: .destructive) {
                app.store.permanentlyDelete(note)
            } label: {
                Label("Delete Permanently", systemImage: "trash.slash")
            }
        } else {
            Button {
                app.store.togglePin(note)
            } label: {
                Label(note.isPinned ? "Unpin Note" : "Pin Note", systemImage: note.isPinned ? "pin.slash" : "pin")
            }
            Button {
                app.store.toggleFavorite(note)
            } label: {
                Label(note.isFavorite ? "Remove Favorite" : "Favorite", systemImage: note.isFavorite ? "star.slash" : "star")
            }
            Button {
                app.store.setArchived(note, archived: !note.isArchived)
            } label: {
                Label(note.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox")
            }
            Button {
                app.store.duplicate(note)
                Haptics.success()
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            Divider()
            Menu {
                Button("None") { app.store.move(note, to: nil) }
                ForEach(folders) { folder in
                    Button(folder.name) { app.store.move(note, to: folder) }
                }
            } label: {
                Label("Move to Folder", systemImage: "folder")
            }
            Button(role: .destructive) {
                app.store.softDelete(note)
                Haptics.warning()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: Binding(
                get: { app.settings.sortOrder },
                set: { app.settings.sortOrder = $0 }
            )) {
                ForEach(NoteSortOrder.allCases) { order in
                    Text(order.label).tag(order)
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .accessibilityIdentifier("sortMenu")
    }

    private var composeButton: some View {
        Button {
            compose()
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle().fill(.tint)
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                )
        }
        .buttonStyle(.plain)
        .padding(20)
        .accessibilityLabel("New Note")
        .accessibilityIdentifier("newNoteButton")
    }

    // MARK: - Data

    private var displayedNotes: [Note] {
        let scoped = scopeNotes
        let searched = NoteSearch.filter(scoped, query: appliedSearch)
        return app.settings.sortOrder.sort(searched)
    }

    private var scopeNotes: [Note] {
        switch scope {
        case .all:
            return allNotes.filter { $0.deletedAt == nil && !$0.isArchived }
        case .quick:
            return allNotes.filter { $0.deletedAt == nil && !$0.isArchived && $0.folder == nil }
        case .pinned:
            return allNotes.filter { $0.deletedAt == nil && !$0.isArchived && $0.isPinned }
        case .favorites:
            return allNotes.filter { $0.deletedAt == nil && !$0.isArchived && $0.isFavorite }
        case .archive:
            return allNotes.filter { $0.deletedAt == nil && $0.isArchived }
        case .trash:
            return allNotes.filter { $0.deletedAt != nil }
        case .folder(let id):
            return allNotes.filter { $0.deletedAt == nil && !$0.isArchived && $0.folder?.id == id }
        case .tag(let id):
            return allNotes.filter { note in
                note.deletedAt == nil && !note.isArchived && note.tags.contains { $0.id == id }
            }
        }
    }

    private var scopeTitle: String {
        switch scope {
        case .folder(let id):
            return folders.first { $0.id == id }?.name ?? "Folder"
        case .tag(let id):
            return "#" + (tags.first { $0.id == id }?.name ?? "Tag")
        default:
            return scope.title
        }
    }

    private var emptySymbol: String {
        appliedSearch.isEmpty ? scope.symbol : "magnifyingglass"
    }

    private var emptyTitle: String {
        if !appliedSearch.isEmpty { return "No Results" }
        switch scope {
        case .trash: return "No Deleted Notes"
        case .archive: return "Nothing Archived"
        case .pinned: return "No Pinned Notes"
        case .favorites: return "No Favorites"
        case .quick: return "No Quick Notes"
        default: return "No Notes Yet"
        }
    }

    private var emptyMessage: String {
        if !appliedSearch.isEmpty {
            return "No notes match “\(appliedSearch)”. Try a shorter search."
        }
        switch scope {
        case .trash: return "Deleted notes stay here for 30 days before they are removed forever."
        case .archive: return "Archived notes are hidden from your main list but never deleted."
        case .pinned: return "Pin important notes to keep them at the top of every list."
        case .favorites: return "Favorite the notes you reach for most."
        case .quick: return "Notes without a folder live here."
        default: return "Tap the compose button to write your first note. Everything saves automatically."
        }
    }

    // MARK: - Actions

    private func compose() {
        let folder: Folder? = {
            if case .folder(let id) = scope { return folders.first { $0.id == id } }
            return nil
        }()
        let note = app.store.createNote(document: NoteDocument(blocks: [NoteBlock()]), folder: folder)
        Haptics.impact(.medium)
        path.append(note)
    }

    /// Debounces search so a fast typist triggers one filter pass, not one per keystroke.
    private func scheduleSearch(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            appliedSearch = ""
            return
        }
        searchTask = Task { [trimmed] in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                appliedSearch = trimmed
            }
        }
    }
}
