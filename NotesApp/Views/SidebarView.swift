import SwiftUI
import SwiftData
import UIKit

struct SidebarView: View {
    @Environment(AppEnvironment.self) private var app
    @Binding var scope: NotesScope
    @Binding var path: NavigationPath

    @Query(sort: \Folder.sortIndex) private var folders: [Folder]
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query private var allNotes: [Note]

    @State private var newFolderName = ""
    @State private var isCreatingFolder = false

    var body: some View {
        List(selection: Binding<NotesScope?>(
            get: { scope },
            set: { newValue in
                if let newValue {
                    scope = newValue
                    path = NavigationPath()
                }
            }
        )) {
            Section {
                row(.all, count: activeCount)
                row(.quick, count: quickCount)
                row(.pinned, count: pinnedCount)
                row(.favorites, count: favoriteCount)
            }

            Section("Folders") {
                ForEach(folders) { folder in
                    row(.folder(folder.id), title: folder.name, symbol: folder.symbolName, count: folder.activeNotes.count)
                        .contextMenu {
                            Button {
                                renameFolder(folder)
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                app.store.delete(folder)
                            } label: {
                                Label("Delete Folder", systemImage: "trash")
                            }
                        }
                }
                Button {
                    isCreatingFolder = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }

            if !tags.isEmpty {
                Section("Tags") {
                    ForEach(tags) { tag in
                        row(.tag(tag.id), title: tag.name, symbol: "number", count: tag.activeNotes.count)
                    }
                }
            }

            Section {
                row(.archive, count: archivedCount)
                row(.trash, count: trashedCount)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Notes")
        .safeAreaInset(edge: .bottom) {
            Button {
                app.showSettings = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "gearshape")
                    Text("Settings")
                    Spacer()
                    Image(systemName: app.sync.state.symbol)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .accessibilityIdentifier("settingsButton")
        }
        .alert("New Folder", isPresented: $isCreatingFolder) {
            TextField("Name", text: $newFolderName)
            Button("Cancel", role: .cancel) { newFolderName = "" }
            Button("Create") {
                let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                let folder = app.store.createFolder(named: name)
                newFolderName = ""
                scope = .folder(folder.id)
                Haptics.success()
            }
        } message: {
            Text("Give the folder a short name.")
        }
    }

    private func row(_ value: NotesScope, title: String? = nil, symbol: String? = nil, count: Int) -> some View {
        Label {
            HStack {
                Text(title ?? value.title)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .foregroundStyle(.secondary)
                        .font(.footnote.monospacedDigit())
                }
            }
        } icon: {
            Image(systemName: symbol ?? value.symbol)
        }
        .tag(value)
        .accessibilityIdentifier("scope-\(value.id)")
    }

    private var activeCount: Int { allNotes.filter { $0.deletedAt == nil && !$0.isArchived }.count }
    private var quickCount: Int { allNotes.filter { $0.deletedAt == nil && !$0.isArchived && $0.folder == nil }.count }
    private var pinnedCount: Int { allNotes.filter { $0.deletedAt == nil && !$0.isArchived && $0.isPinned }.count }
    private var favoriteCount: Int { allNotes.filter { $0.deletedAt == nil && !$0.isArchived && $0.isFavorite }.count }
    private var archivedCount: Int { allNotes.filter { $0.deletedAt == nil && $0.isArchived }.count }
    private var trashedCount: Int { allNotes.filter { $0.deletedAt != nil }.count }

    private func renameFolder(_ folder: Folder) {
        let alert = UIAlertController(title: "Rename Folder", message: nil, preferredStyle: .alert)
        alert.addTextField { field in field.text = folder.name }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            let name = alert.textFields?.first?.text ?? ""
            Task { @MainActor in
                guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                app.store.rename(folder, to: name)
            }
        })
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let controller = scene.keyWindow?.rootViewController {
            controller.present(alert, animated: true)
        }
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? {
        windows.first { $0.isKeyWindow }
    }
}
