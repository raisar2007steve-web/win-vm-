import SwiftUI

struct LockScreenView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var didAttempt = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse, options: .repeating, value: app.lock.isAuthenticating)

                VStack(spacing: 6) {
                    Text("Notes is Locked")
                        .font(.title2.weight(.semibold))
                    Text("Unlock with \(app.lock.biometryName) to read your notes.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let error = app.lock.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button {
                    Task { await app.lock.authenticate() }
                } label: {
                    Label("Unlock", systemImage: app.lock.canUseBiometry ? "faceid" : "key.fill")
                        .frame(maxWidth: 240)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(app.lock.isAuthenticating)
                .accessibilityIdentifier("unlockButton")

                Text("Your notes never leave the device unless iCloud sync is enabled.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(32)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(24)
        }
        .task {
            guard !didAttempt else { return }
            didAttempt = true
            await app.lock.authenticate()
        }
    }
}
