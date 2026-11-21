import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Folder.sortIndex) private var folders: [Folder]
    @Query(sort: \Tag.name) private var tags: [Tag]

    @State private var scope: NotesScope = .all
    @State private var path = NavigationPath()
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(scope: $scope, path: $path)
                    .navigationSplitViewColumnWidth(min: 240, ideal: 280)
            } detail: {
                NavigationStack(path: $path) {
                    NoteListView(scope: resolvedScope, path: $path)
                        .navigationDestination(for: Note.self) { note in
                            NoteEditorView(note: note)
                        }
                }
                .id(scope.id)
            }
            .navigationSplitViewStyle(.balanced)

            if app.lock.isLocked {
                LockScreenView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: app.lock.isLocked)
        .sheet(isPresented: Binding(get: { app.showSettings }, set: { app.showSettings = $0 })) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { app.showSettings = false }
                        }
                    }
            }
        }
        .onOpenURL { url in
            app.handleDeepLink(url)
        }
        .onChange(of: app.pendingScope) { _, newValue in
            guard let newValue else { return }
            scope = newValue
            app.pendingScope = nil
        }
        .onChange(of: app.pendingNewNote) { _, newValue in
            guard newValue else { return }
            app.pendingNewNote = false
            createAndOpenNote()
        }
        .onChange(of: app.pendingNoteID) { _, newValue in
            guard let newValue else { return }
            app.pendingNoteID = nil
            openNote(withID: newValue)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background, .inactive:
                app.lock.noteDidEnterBackground()
            case .active:
                app.lock.lockIfNeeded()
            @unknown default:
                break
            }
        }
        .task {
            app.lock.lockIfNeeded()
        }
    }

    private var resolvedScope: NotesScope {
        switch scope {
        case .folder(let id):
            return folders.first { $0.id == id }.map { .folder($0.id) } ?? .all
        case .tag(let id):
            return tags.first { $0.id == id }.map { .tag($0.id) } ?? .all
        default:
            return scope
        }
    }

    private func createAndOpenNote() {
        let folder: Folder? = {
            if case .folder(let id) = scope { return folders.first { $0.id == id } }
            return nil
        }()
        let note = app.store.createNote(document: NoteDocument(blocks: [NoteBlock()]), folder: folder)
        Haptics.success()
        path.append(note)
    }

    private func openNote(withID id: UUID) {
        let all = (try? app.container.mainContext.fetch(FetchDescriptor<Note>())) ?? []
        guard let note = all.first(where: { $0.id == id }) else { return }
        path.append(note)
    }
}

