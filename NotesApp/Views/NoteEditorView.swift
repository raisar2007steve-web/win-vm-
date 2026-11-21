import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

/// The note editor: a scrolling stack of blocks with autosave, attachments, a
/// writing assistant, export, and protection.
struct NoteEditorView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @Bindable var note: Note
    @Query(sort: \Folder.sortIndex) private var folders: [Folder]

    @State private var blocks: [NoteBlock]
    @State private var title: String
    @State private var autosave = AutosaveEngine()
    @State private var isUnlocked: Bool

    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showPhotos = false
    @State private var showCamera = false
    @State private var showScanner = false
    @State private var showFiles = false
    @State private var showRecorder = false
    @State private var showHandwriting = false
    @State private var showIntelligence = false
    @State private var showMove = false
    @State private var showTags = false
    @State private var showReminder = false
    @State private var showDeleteConfirmation = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var viewedAttachment: Attachment?

    @FocusState private var focusedBlock: UUID?
    @FocusState private var titleFocused: Bool

    init(note: Note) {
        self.note = note
        _blocks = State(initialValue: note.document.blocks)
        _title = State(initialValue: note.title)
        _isUnlocked = State(initialValue: !note.isProtected)
    }

    var body: some View {
        Group {
            if note.isProtected && !isUnlocked {
                protectedGate
            } else {
                editor
            }
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(note.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onChange(of: blocks) { _, _ in scheduleAutosave() }
        .onChange(of: title) { _, _ in scheduleAutosave() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { flushAutosave() }
        }
        .onDisappear { flushAutosave() }
        .sheet(isPresented: $showIntelligence) {
            NoteIntelligenceSheet(text: intelligenceSourceText) { outcome, replaceBody in
                apply(outcome, replaceBody: replaceBody)
            }
        }
        .sheet(isPresented: $showRecorder) {
            AudioRecorderSheet { url, transcript in
                attachAudio(url: url, transcript: transcript)
            }
        }
        .sheet(isPresented: $showHandwriting) {
            HandwritingSheet { image in
                attachHandwriting(image)
            }
        }
        .sheet(isPresented: $showMove) {
            FolderPickerView(note: note)
        }
        .sheet(isPresented: $showTags) {
            TagPickerView(note: note)
        }
        .sheet(isPresented: $showReminder) {
            ReminderSheet(note: note)
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityView(items: shareItems)
        }
        .sheet(item: $viewedAttachment) { attachment in
            AttachmentViewerSheet(attachment: attachment) {
                removeAttachment(attachment)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                attachCapturedImage(image, kind: .image)
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView { pages in
                for page in pages {
                    attachCapturedImage(page, kind: .scan)
                }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showPhotos, selection: $photoSelection, maxSelectionCount: 8, matching: .images)
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items) }
        }
        .fileImporter(
            isPresented: $showFiles,
            allowedContentTypes: [.pdf, .plainText, .image, .data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                importFiles(urls)
            }
        }
        .confirmationDialog("Delete this note?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Note", role: .destructive) {
                flushAutosave()
                app.store.softDelete(note)
                SpotlightIndexer.remove(note)
                Haptics.warning()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It moves to Recently Deleted and can be restored for 30 days.")
        }
    }

    // MARK: - Editor

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Title", text: $title, axis: .vertical)
                    .font(.system(.largeTitle, design: .default).weight(.bold))
                    .textFieldStyle(.plain)
                    .lineLimit(1...3)
                    .focused($titleFocused)
                    .accessibilityIdentifier("noteTitleField")

                metadataRow

                if !note.sortedTags.isEmpty {
                    tagChips
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach($blocks) { $block in
                        BlockRowView(
                            block: $block,
                            attachments: note.attachments,
                            onDelete: { deleteBlock(block.id) },
                            onOpenAttachment: { viewedAttachment = $0 },
                            focusedBlock: $focusedBlock
                        )
                    }
                }
                .padding(.top, 4)

                addBlockBar

                if !note.attachments.isEmpty {
                    attachmentsFooter
                }

                saveStatusFooter
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("noteEditor")
    }

    private var metadataRow: some View {
        HStack(spacing: 8) {
            Text(Self.fullDate(note.updatedAt))
            Text("·")
            Text("\(note.wordCount) words")
            if let folder = note.folder {
                Text("·")
                Label(folder.name, systemImage: "folder")
                    .labelStyle(.titleAndIcon)
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var tagChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(note.sortedTags) { tag in
                    Text("#" + tag.name)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(.tint)
                }
            }
        }
    }

    private var addBlockBar: some View {
        HStack(spacing: 10) {
            Menu {
                Section("Text") {
                    ForEach(BlockStyleOption.all, id: \.kind) { option in
                        Button {
                            insertBlock(kind: option.kind)
                        } label: {
                            Label(option.title, systemImage: option.kind.systemImage)
                        }
                    }
                }
                Section("Structure") {
                    Button { insertBlock(kind: .table) } label: { Label("Table", systemImage: "tablecells") }
                    Button { insertBlock(kind: .divider) } label: { Label("Divider", systemImage: "minus") }
                }
            } label: {
                Label("Add Block", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.medium))
            }
            .accessibilityIdentifier("addBlockMenu")

            Spacer()

            Menu {
                Button { showPhotos = true } label: { Label("Photo Library", systemImage: "photo.on.rectangle") }
                if CameraPicker.isCameraAvailable {
                    Button { showCamera = true } label: { Label("Take Photo", systemImage: "camera") }
                }
                if DocumentScannerView.isSupported {
                    Button { showScanner = true } label: { Label("Scan Document", systemImage: "doc.viewfinder") }
                }
                Button { showFiles = true } label: { Label("Import File", systemImage: "folder.badge.plus") }
                Button { showRecorder = true } label: { Label("Voice Note", systemImage: "waveform") }
                Button { showHandwriting = true } label: { Label("Handwriting", systemImage: "scribble") }
            } label: {
                Label("Attach", systemImage: "paperclip")
                    .font(.subheadline.weight(.medium))
            }
            .accessibilityIdentifier("attachMenu")
        }
        .padding(.top, 6)
    }

    private var attachmentsFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("Attachments")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                ForEach(note.attachments) { attachment in
                    Button {
                        viewedAttachment = attachment
                    } label: {
                        Group {
                            if let image = ThumbnailCache.shared.image(named: attachment.fileName, maxPixel: 240) {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else {
                                Image(systemName: attachment.kind.isVisual ? "photo" : "doc")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color.secondary.opacity(0.1))
                            }
                        }
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 14)
    }

    private var saveStatusFooter: some View {
        HStack(spacing: 6) {
            if autosave.isPending {
                ProgressView().controlSize(.mini)
                Text("Saving…")
            } else {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.tertiary)
                Text(autosave.statusText)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.top, 18)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Button {
                    showIntelligence = true
                } label: {
                    Label("Writing Assistant", systemImage: "sparkles")
                }
            } label: {
                Image(systemName: "sparkles")
            }
            .accessibilityIdentifier("intelligenceMenu")

            Menu {
                Button {
                    app.store.togglePin(note)
                } label: {
                    Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
                }
                Button {
                    app.store.toggleFavorite(note)
                } label: {
                    Label(note.isFavorite ? "Remove Favorite" : "Favorite", systemImage: note.isFavorite ? "star.slash" : "star")
                }
                Button {
                    showTags = true
                } label: {
                    Label("Tags", systemImage: "number")
                }
                Button {
                    showMove = true
                } label: {
                    Label("Move to Folder", systemImage: "folder")
                }
                Button {
                    showReminder = true
                } label: {
                    Label(note.reminderAt == nil ? "Add Reminder" : "Change Reminder", systemImage: "bell")
                }
                Divider()
                Button {
                    app.store.setProtected(note, protected: !note.isProtected)
                    isUnlocked = !note.isProtected
                } label: {
                    Label(note.isProtected ? "Remove Protection" : "Protect Note", systemImage: note.isProtected ? "lock.open" : "lock")
                }
                Button {
                    app.store.setArchived(note, archived: !note.isArchived)
                } label: {
                    Label(note.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox")
                }
                Button {
                    app.store.duplicate(note)
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                Divider()
                Menu {
                    Button {
                        share([ExportService.markdown(for: note)])
                    } label: {
                        Label("Markdown", systemImage: "text.alignleft")
                    }
                    Button {
                        if let url = ExportService.pdfFile(for: note) { share([url]) }
                    } label: {
                        Label("PDF", systemImage: "doc.richtext")
                    }
                    Button {
                        if let url = ExportService.archiveFile(for: note) { share([url]) }
                    } label: {
                        Label("Note Archive (.note)", systemImage: "shippingbox")
                    }
                    Button {
                        share([ExportService.plainText(for: note)])
                    } label: {
                        Label("Plain Text", systemImage: "doc.plaintext")
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                Divider()
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Note", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityIdentifier("noteActionsMenu")
        }

        ToolbarItemGroup(placement: .keyboard) {
            Menu {
                ForEach(BlockStyleOption.all, id: \.kind) { option in
                    Button {
                        applyStyle(option.kind)
                    } label: {
                        Label(option.title, systemImage: option.kind.systemImage)
                    }
                }
            } label: {
                Image(systemName: "textformat")
            }

            Button {
                wrapFocusedText(with: "**")
            } label: {
                Image(systemName: "bold")
            }
            Button {
                wrapFocusedText(with: "_")
            } label: {
                Image(systemName: "italic")
            }
            Button {
                wrapFocusedText(with: "`")
            } label: {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
            }
            Button {
                wrapFocusedText(with: "==")
            } label: {
                Image(systemName: "highlighter")
            }
            Spacer()
            Button {
                focusedBlock = nil
                titleFocused = false
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
            }
        }
    }

    // MARK: - Protected note

    private var protectedGate: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 42))
                .foregroundStyle(.tint)
            Text("This note is protected")
                .font(.title3.weight(.semibold))
            Text("Authenticate with \(app.lock.biometryName) to read and edit it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task {
                    if await app.lock.authenticateForProtectedNote(note.id) {
                        isUnlocked = true
                    }
                }
            } label: {
                Label("Unlock Note", systemImage: "lock.open")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("unlockNoteButton")
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Editing

    private var intelligenceSourceText: String {
        if !blocks.isEmpty {
            let documentText = NoteDocument(blocks: blocks).plainText
            if !documentText.isEmpty { return documentText }
        }
        return note.searchText.isEmpty ? title : note.searchText
    }

    private func insertBlock(kind: BlockKind) {
        var block = NoteBlock(kind: kind)
        if kind == .table {
            block.rows = [["Item", "Value"], ["", ""]]
        }
        if kind == .divider {
            blocks.append(block)
            return
        }
        blocks.append(block)
        focusedBlock = block.id
        Haptics.impact()
    }

    private func deleteBlock(_ id: UUID) {
        let block = blocks.first { $0.id == id }
        blocks.removeAll { $0.id == id }
        if blocks.isEmpty { blocks = [NoteBlock()] }
        if let attachmentID = block?.attachmentID, let attachment = app.store.attachment(withID: attachmentID, in: note) {
            app.store.removeAttachment(attachment, from: note)
        }
        Haptics.selection()
    }

    private func applyStyle(_ kind: BlockKind) {
        guard let focusedBlock, let index = blocks.firstIndex(where: { $0.id == focusedBlock }) else { return }
        blocks[index].kind = kind
        Haptics.selection()
    }

    private func wrapFocusedText(with marker: String) {
        guard let focusedBlock, let index = blocks.firstIndex(where: { $0.id == focusedBlock }) else { return }
        var text = blocks[index].text
        if text.hasPrefix(marker) && text.hasSuffix(marker) && text.count > marker.count * 2 {
            text.removeFirst(marker.count)
            text.removeLast(marker.count)
        } else if !text.isEmpty {
            text = marker + text + marker
        }
        blocks[index].text = text
        Haptics.selection()
    }

    // MARK: - Autosave

    private func scheduleAutosave() {
        autosave.schedule {
            persistNow()
        }
    }

    private func flushAutosave() {
        autosave.flush()
        persistNow()
    }

    private func persistNow() {
        var sanitized = blocks
        if sanitized.isEmpty {
            sanitized = [NoteBlock()]
        }
        app.store.applyEdit(to: note, title: title, document: NoteDocument(blocks: sanitized))
        if !note.isArchived && note.deletedAt == nil {
            SpotlightIndexer.index([note])
        }
    }

    // MARK: - Attachments

    private func attachCapturedImage(_ image: UIImage, kind: AttachmentKind) {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        do {
            let attachment = try app.store.attachImage(data: data, to: note, kind: kind)
            insertAttachmentBlock(attachment, kind: kind)
        } catch {
            NSLog("[NotesApp] Attachment import failed.")
        }
    }

    private func attachHandwriting(_ image: UIImage) {
        guard let data = image.pngData() else { return }
        if let attachment = try? app.store.attachImage(data: data, to: note, kind: .handwriting) {
            insertAttachmentBlock(attachment, kind: .handwriting)
        }
    }

    private func attachAudio(url: URL, transcript: String?) {
        guard let attachment = try? app.store.attachFile(at: url, to: note, kind: .audio) else { return }
        insertAttachmentBlock(attachment, kind: .audio)
        if let transcript, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blocks.append(NoteBlock(kind: .paragraph, text: "Transcript: " + transcript))
        }
        scheduleAutosave()
    }

    private func insertAttachmentBlock(_ attachment: Attachment, kind: AttachmentKind) {
        var block = NoteBlock(kind: kind == .audio ? .audio : (kind == .document ? .document : .image))
        block.attachmentID = attachment.id
        blocks.append(block)
        scheduleAutosave()
        Haptics.success()
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            if let attachment = try? app.store.attachImage(data: data, to: note) {
                var block = NoteBlock(kind: .image)
                block.attachmentID = attachment.id
                blocks.append(block)
            }
        }
        photoSelection = []
        scheduleAutosave()
    }

    private func importFiles(_ urls: [URL]) {
        for url in urls {
            if let attachment = try? app.store.attachFile(at: url, to: note) {
                var block = NoteBlock(kind: .document)
                block.attachmentID = attachment.id
                blocks.append(block)
            }
        }
        scheduleAutosave()
    }

    private func removeAttachment(_ attachment: Attachment) {
        let attachmentID = attachment.id
        blocks.removeAll { $0.attachmentID == attachmentID }
        app.store.removeAttachment(attachment, from: note)
        viewedAttachment = nil
        scheduleAutosave()
    }

    private func share(_ items: [Any]) {
        guard !items.isEmpty else {
            Haptics.warning()
            return
        }
        shareItems = items
        showShareSheet = true
    }

    // MARK: - Intelligence

    private func apply(_ outcome: NoteIntelligence.Outcome, replaceBody: Bool) {
        switch outcome.action {
        case .generateTitle:
            title = outcome.text.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
        case .suggestTags:
            let names = outcome.text
                .replacingOccurrences(of: "#", with: "")
                .split(whereSeparator: { $0 == "," || $0 == "\n" })
            for name in names {
                if let tag = app.store.tag(named: String(name)) {
                    app.store.addTag(tag, to: note)
                }
            }
        case .extractTasks:
            let lines = outcome.text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " -•*")) }
                .filter { !$0.isEmpty }
            let newBlocks = lines.map { line -> NoteBlock in
                var block = NoteBlock(kind: .checklist)
                block.text = line
                return block
            }
            if replaceBody {
                blocks = newBlocks.isEmpty ? [NoteBlock()] : newBlocks
            } else {
                blocks.append(contentsOf: newBlocks)
            }
        default:
            if replaceBody {
                blocks = [NoteBlock(kind: .paragraph, text: outcome.text)]
            } else {
                blocks.append(NoteBlock(kind: .paragraph, text: outcome.text))
            }
        }
        scheduleAutosave()
        Haptics.success()
    }

    static func fullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
