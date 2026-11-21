import SwiftUI
import PencilKit
import UserNotifications
import UIKit

// MARK: - Writing assistant

struct NoteIntelligenceSheet: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    let text: String
    var onApply: (NoteIntelligence.Outcome, Bool) -> Void

    @State private var selectedAction: NoteIntelligence.Action = .summarize
    @State private var outcome: NoteIntelligence.Outcome?
    @State private var isRunning = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(app.intelligence.isFoundationModelAvailable ? "Apple Intelligence" : "On-device assistant",
                              systemImage: "sparkles")
                            .font(.headline)
                        Text(app.intelligence.availabilityDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(NoteIntelligence.Action.allCases) { action in
                                Button {
                                    selectedAction = action
                                    outcome = nil
                                } label: {
                                    Label(action.title, systemImage: action.systemImage)
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            selectedAction == action ? Color.accentColor : Color.secondary.opacity(0.12),
                                            in: Capsule()
                                        )
                                        .foregroundStyle(selectedAction == action ? Color.white : Color.primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button {
                        Task { await run() }
                    } label: {
                        HStack {
                            if isRunning { ProgressView().controlSize(.small) }
                            Text(isRunning ? "Working…" : selectedAction.title)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunning)
                    .accessibilityIdentifier("runIntelligenceButton")

                    if let outcome {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Result")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(outcome.text)
                                .font(.body)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                            if !outcome.usedOnDeviceModel {
                                Text("Produced by the built-in local processor. On-device Apple Intelligence was not available for this request.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            HStack(spacing: 10) {
                                Button("Insert") {
                                    onApply(outcome, false)
                                    dismiss()
                                }
                                .buttonStyle(.bordered)

                                if selectedAction != .generateTitle && selectedAction != .suggestTags {
                                    Button("Replace Body") {
                                        onApply(outcome, true)
                                        dismiss()
                                    }
                                    .buttonStyle(.bordered)
                                }

                                Button {
                                    UIPasteboard.general.string = outcome.text
                                    Haptics.success()
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.bordered)
                            }
                            .font(.subheadline)
                        }
                    }

                    if let error = app.intelligence.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("Everything runs on this device. Your note text is never uploaded to an external AI service.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(20)
            }
            .navigationTitle("Writing Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func run() async {
        isRunning = true
        outcome = await app.intelligence.perform(selectedAction, on: text)
        isRunning = false
    }
}

// MARK: - Voice notes

struct AudioRecorderSheet: View {
    @Environment(\.dismiss) private var dismiss

    var onComplete: (URL, String?) -> Void

    @State private var recorder = AudioRecorder()
    @State private var transcript: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 190, height: 190)
                    Circle()
                        .fill(Color.accentColor.opacity(0.2 + recorder.level * 0.5))
                        .frame(width: 130 + recorder.level * 40, height: 130 + recorder.level * 40)
                    Image(systemName: recorder.isRecording ? "waveform" : "mic.fill")
                        .font(.system(size: 46, weight: .medium))
                        .foregroundStyle(.tint)
                        .symbolEffect(.variableColor.iterative, isActive: recorder.isRecording)
                }

                Text(recorder.formattedDuration)
                    .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())

                switch recorder.state {
                case .failed(let message):
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                default:
                    Text(recorder.isTranscribing ? "Transcribing on device…" : "Recording stays on this device unless you add it to iCloud.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                HStack(spacing: 16) {
                    Button("Cancel") {
                        recorder.cancel()
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Button {
                        if recorder.isRecording {
                            recorder.stop()
                        } else {
                            Task { await recorder.start() }
                        }
                    } label: {
                        Label(recorder.isRecording ? "Stop" : "Record",
                              systemImage: recorder.isRecording ? "stop.fill" : "record.circle")
                            .frame(width: 130)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("recordButton")

                    Button("Attach") {
                        save()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!recorder.isRecording && recorder.state != .finished)
                    .accessibilityIdentifier("attachRecordingButton")
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Voice Note")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    private func save() {
        if recorder.isRecording { recorder.stop() }
        guard let url = recorder.takeRecording() else {
            dismiss()
            return
        }
        let captured = url
        Task {
            let text = await recorder.transcribe(captured)
            await MainActor.run {
                onComplete(captured, text)
                dismiss()
            }
        }
    }
}

// MARK: - Handwriting

struct HandwritingSheet: View {
    @Environment(\.dismiss) private var dismiss

    var onComplete: (UIImage) -> Void

    @State private var drawing = PKDrawing()
    @State private var canvasSize: CGSize = .zero

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                PencilCanvas(drawing: $drawing)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .onAppear { canvasSize = proxy.size }
                    .onChange(of: proxy.size) { _, newValue in canvasSize = newValue }
            }
            .navigationTitle("Handwriting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") { drawing = PKDrawing() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Attach") {
                        let rect = CGRect(origin: .zero, size: canvasSize == .zero ? CGSize(width: 600, height: 400) : canvasSize)
                        let image = drawing.image(from: rect, scale: 2)
                        onComplete(image)
                        dismiss()
                    }
                    .disabled(drawing.strokes.isEmpty)
                }
            }
        }
        .ignoresSafeArea(.keyboard)
    }
}

struct PencilCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: UIColor.label, width: 3)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.delegate = context.coordinator
        canvas.drawing = drawing
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing != drawing {
            uiView.drawing = drawing
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var drawing: Binding<PKDrawing>

        init(drawing: Binding<PKDrawing>) {
            self.drawing = drawing
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing.wrappedValue = canvasView.drawing
        }
    }
}

// MARK: - Attachment viewer

struct AttachmentViewerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let attachment: Attachment
    var onDelete: () -> Void

    @State private var showShare = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if attachment.kind.isVisual,
                   let image = AttachmentStore.shared.image(for: attachment.fileName, maxPixel: 2600) {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: image.size.width)
                    }
                    .background(Color.black)
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: attachment.kind == .audio ? "waveform" : "doc.text")
                            .font(.system(size: 52))
                            .foregroundStyle(.tint)
                        Text(attachment.displayName)
                            .font(.headline)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if attachment.kind == .audio {
                            Text("Audio is stored with the note. Speech transcripts appear in the note body.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(attachment.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showShare = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .sheet(isPresented: $showShare) {
                ActivityView(items: [AttachmentStore.shared.url(for: attachment.fileName)])
            }
            .confirmationDialog("Remove this attachment from the note?", isPresented: $showDeleteConfirmation) {
                Button("Remove Attachment", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

// MARK: - Reminder

struct ReminderSheet: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    let note: Note

    @State private var date = Date().addingTimeInterval(3600)
    @State private var permissionDenied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Remind me", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                } footer: {
                    Text("Reminders are local notifications. No note content leaves the device.")
                }

                if permissionDenied {
                    Section {
                        Text("Notifications are turned off for Notes. Enable them in Settings to use reminders.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if note.reminderAt != nil {
                    Section {
                        Button("Remove Reminder", role: .destructive) {
                            NotificationScheduler.cancelReminder(for: note)
                            app.store.setReminder(note, at: nil)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            let scheduled = await NotificationScheduler.scheduleReminder(for: note, at: date)
                            if scheduled {
                                app.store.setReminder(note, at: date)
                                Haptics.success()
                                dismiss()
                            } else {
                                permissionDenied = true
                            }
                        }
                    }
                }
            }
            .onAppear { date = note.reminderAt ?? Date().addingTimeInterval(3600) }
        }
        .presentationDetents([.medium])
    }
}
