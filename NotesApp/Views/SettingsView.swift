import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query private var allNotes: [Note]

    @State private var showEmptyTrashConfirmation = false
    @State private var attachmentBytes = 0
    @State private var showLockInfo = false

    var body: some View {
        @Bindable var settings = app.settings

        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: app.sync.state.symbol)
                        .font(.title2)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.sync.state.label)
                            .font(.headline)
                        Text(app.sync.isOnline ? "Online · changes sync in the background" : "Offline · changes are saved locally")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("Sync with iCloud", isOn: $settings.cloudSyncEnabled)
                    .accessibilityIdentifier("cloudSyncToggle")
                if app.sync.state != .cloud(fallback: false) {
                    Text("Notes keep working without iCloud. Local changes merge when the container becomes available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("iCloud")
            }

            Section {
                Toggle("Require \(app.lock.biometryName) or Passcode", isOn: Binding(
                    get: { settings.lockEnabled },
                    set: { newValue in
                        if newValue {
                            app.lock.enableLock()
                        } else {
                            app.lock.disableLock()
                        }
                    }
                ))
                .accessibilityIdentifier("appLockToggle")

                if settings.lockEnabled {
                    Picker("Lock After", selection: $settings.lockGrace) {
                        ForEach(app.settings.lockGraceOptions) { option in
                            Text(option.label).tag(option.seconds)
                        }
                    }
                    Button("Lock Now") {
                        app.lock.lockNow()
                        dismiss()
                    }
                }

                Button {
                    showLockInfo = true
                } label: {
                    Label("How protection works", systemImage: "lock.shield")
                }
                .font(.footnote)
            } header: {
                Text("Privacy & Security")
            } footer: {
                Text("Note text is stored in the app container with iOS Data Protection. Protected notes ask for authentication every time they open.")
            }

            Section("Notes") {
                Picker("Default Sort", selection: $settings.sortOrder) {
                    ForEach(NoteSortOrder.allCases) { order in
                        Text(order.label).tag(order)
                    }
                }
                Toggle("Haptic Feedback", isOn: $settings.hapticsEnabled)
                Toggle("Prefer Larger Text", isOn: $settings.useLargeText)
            }

            Section("Apple Intelligence") {
                VStack(alignment: .leading, spacing: 6) {
                    Label(app.intelligence.isFoundationModelAvailable ? "Available" : "Limited Mode",
                          systemImage: app.intelligence.isFoundationModelAvailable ? "sparkles" : "cpu")
                        .font(.subheadline.weight(.medium))
                    Text(app.intelligence.availabilityDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Summaries, proofreading and tag suggestions run on device. Note content is never sent to an external AI service.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
            }

            Section("Storage") {
                LabeledContent("Notes", value: "\(allNotes.filter { $0.deletedAt == nil }.count)")
                LabeledContent("Attachments", value: ByteCountFormatter.string(fromByteCount: Int64(attachmentBytes), countStyle: .file))
                Button(role: .destructive) {
                    showEmptyTrashConfirmation = true
                } label: {
                    Label("Empty Recently Deleted", systemImage: "trash.slash")
                }
                .disabled(trashedCount == 0)
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
                Link(destination: URL(string: "https://support.apple.com/guide/iphone/welcome/ios")!) {
                    Label("iPhone User Guide", systemImage: "book")
                }
                Text("Notes is a native SwiftUI app with SwiftData storage. No analytics, no third-party SDKs, no note content in logs.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            attachmentBytes = await Task.detached(priority: .utility) {
                AttachmentStore.shared.totalBytes()
            }.value
        }
        .confirmationDialog(
            "Delete all notes in Recently Deleted?",
            isPresented: $showEmptyTrashConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete \(trashedCount) Notes", role: .destructive) {
                app.store.emptyTrash()
                Haptics.warning()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .alert("Protection", isPresented: $showLockInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The app lock uses LocalAuthentication: Face ID, Touch ID or your device passcode. Protected notes require authentication even when the app is unlocked. Attachments are written with complete file protection so they are unreadable while the device is locked.")
        }
    }

    private var trashedCount: Int {
        allNotes.filter { $0.deletedAt != nil }.count
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
