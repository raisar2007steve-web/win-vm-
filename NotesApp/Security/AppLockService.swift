import Foundation
import LocalAuthentication
import SwiftUI

/// Face ID / Touch ID / passcode gate for the app and for protected notes.
@MainActor
@Observable
final class AppLockService {
    private enum Key {
        static let configuredMarker = "lock.configured"
    }

    /// True while the UI must be replaced with the lock screen.
    private(set) var isLocked = false
    private(set) var isAuthenticating = false
    private(set) var biometryType: LABiometryType = .none
    private(set) var lastError: String?
    /// Set when a specific note was opened from the lock screen flow.
    private(set) var pendingProtectedNoteID: UUID?

    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        refreshBiometry()
        // A configured lock always starts locked on a cold launch.
        if settings.lockEnabled {
            isLocked = true
        }
    }

    var biometryName: String {
        switch biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        case .none: return "Passcode"
        @unknown default: return "Passcode"
        }
    }

    var canUseBiometry: Bool { biometryType != .none }

    func refreshBiometry() {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            biometryType = context.biometryType
        } else {
            biometryType = .none
            lastError = error?.localizedDescription
        }
    }

    func enableLock() {
        settings.lockEnabled = true
        KeychainStore.set("enabled", for: Key.configuredMarker)
        isLocked = false
    }

    func disableLock() {
        settings.lockEnabled = false
        KeychainStore.delete(Key.configuredMarker)
        isLocked = false
    }

    /// Called when the app returns to the foreground.
    func lockIfNeeded(now: Date = Date()) {
        guard settings.lockEnabled else { return }
        guard let lastBackground = settings.lastBackgroundDate else {
            isLocked = true
            return
        }
        if now.timeIntervalSince(lastBackground) >= settings.lockGrace {
            isLocked = true
        }
    }

    func noteDidEnterBackground(now: Date = Date()) {
        settings.lastBackgroundDate = now
    }

    /// Authenticates with biometrics, falling back to the device passcode.
    @discardableResult
    func authenticate(reason: String = "Unlock your notes") async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        lastError = nil
        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.localizedFallbackTitle = "Use Passcode"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            lastError = "Device authentication is unavailable."
            return false
        }

        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if success {
                isLocked = false
                settings.lastBackgroundDate = nil
            }
            return success
        } catch {
            // LAError descriptions never contain note data.
            lastError = "Authentication was not completed."
            return false
        }
    }

    /// Authenticates before revealing a protected note without unlocking the app.
    func authenticateForProtectedNote(_ noteID: UUID) async -> Bool {
        let success = await authenticate(reason: "Open protected note")
        if success {
            pendingProtectedNoteID = noteID
        }
        return success
    }

    func consumePendingProtectedNote() -> UUID? {
        defer { pendingProtectedNoteID = nil }
        return pendingProtectedNoteID
    }

    func lockNow() {
        guard settings.lockEnabled else { return }
        isLocked = true
        settings.lastBackgroundDate = Date()
    }

    func clearError() {
        lastError = nil
    }
}
