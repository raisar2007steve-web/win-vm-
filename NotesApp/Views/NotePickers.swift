import SwiftUI
import SwiftData
import UIKit

/// Move a note between folders.
struct FolderPickerView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Folder.sortIndex) private var folders: [Folder]

    let note: Note

    var body: some View {
        NavigationStack {
            List {
                Button {
                    app.store.move(note, to: nil)
                    dismiss()
                } label: {
                    Label("No Folder", systemImage: "tray")
                }

                ForEach(folders) { folder in
                    Button {
                        app.store.move(note, to: folder)
                        dismiss()
                    } label: {
                        HStack {
                            Label(folder.name, systemImage: folder.symbolName)
                            Spacer()
                            if note.folder?.id == folder.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Move Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Apply and remove tags.
struct TagPickerView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Tag.name) private var tags: [Tag]

    let note: Note
    @State private var newTag = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Add Tag") {
                    HStack {
                        TextField("travel, work, recipe…", text: $newTag)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit(addTag)
                        Button("Add", action: addTag)
                            .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section("Tags") {
                    if tags.isEmpty {
                        Text("No tags yet")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(tags) { tag in
                        Button {
                            toggle(tag)
                        } label: {
                            HStack {
                                Text("#" + tag.name)
                                Spacer()
                                if note.tags.contains(where: { $0.id == tag.id }) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func addTag() {
        guard let tag = app.store.tag(named: newTag) else { return }
        app.store.addTag(tag, to: note)
        newTag = ""
        Haptics.impact()
    }

    private func toggle(_ tag: Tag) {
        if note.tags.contains(where: { $0.id == tag.id }) {
            app.store.removeTag(tag, from: note)
        } else {
            app.store.addTag(tag, to: note)
        }
        Haptics.selection()
    }
}

/// UIActivityViewController bridge so the app can share generated files.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
