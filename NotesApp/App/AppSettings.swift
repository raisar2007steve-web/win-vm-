import Foundation
import SwiftUI

/// User preferences. Persisted in `UserDefaults` and published through `@Observable`.
@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let sortOrder = "settings.sortOrder"
        static let lockEnabled = "settings.lockEnabled"
        static let lockGrace = "settings.lockGrace"
        static let lastUnlock = "settings.lastUnlock"
        static let lastLock = "settings.lastLock"
        static let cloudSyncEnabled = "settings.cloudSyncEnabled"
        static let hapticsEnabled = "settings.hapticsEnabled"
        static let lastOpenedNote = "settings.lastOpenedNote"
        static let useLargeText = "settings.useLargeText"
    }

    private let defaults: UserDefaults

    var sortOrder: NoteSortOrder {
        didSet { defaults.set(sortOrder.rawValue, forKey: Key.sortOrder) }
    }

    var lockEnabled: Bool {
        didSet { defaults.set(lockEnabled, forKey: Key.lockEnabled) }
    }

    /// Seconds the app may stay in the background before it re-locks.
    var lockGrace: Double {
        didSet { defaults.set(lockGrace, forKey: Key.lockGrace) }
    }

    var cloudSyncEnabled: Bool {
        didSet { defaults.set(cloudSyncEnabled, forKey: Key.cloudSyncEnabled) }
    }

    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Key.hapticsEnabled) }
    }

    var lastOpenedNoteID: String? {
        didSet { defaults.set(lastOpenedNoteID, forKey: Key.lastOpenedNote) }
    }

    var useLargeText: Bool {
        didSet { defaults.set(useLargeText, forKey: Key.useLargeText) }
    }

    var lastBackgroundDate: Date? {
        get {
            let stamp = defaults.double(forKey: Key.lastLock)
            return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
        }
        set {
            defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Key.lastLock)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let rawSort = defaults.string(forKey: Key.sortOrder) ?? NoteSortOrder.updatedNewest.rawValue
        sortOrder = NoteSortOrder(rawValue: rawSort) ?? .updatedNewest
        lockEnabled = defaults.bool(forKey: Key.lockEnabled)
        lockGrace = defaults.object(forKey: Key.lockGrace) as? Double ?? 60
        cloudSyncEnabled = defaults.object(forKey: Key.cloudSyncEnabled) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Key.hapticsEnabled) as? Bool ?? true
        lastOpenedNoteID = defaults.string(forKey: Key.lastOpenedNote)
        useLargeText = defaults.bool(forKey: Key.useLargeText)
    }

    var lockGraceOptions: [LockGraceOption] {
        [
            LockGraceOption(label: "Immediately", seconds: 0),
            LockGraceOption(label: "After 1 minute", seconds: 60),
            LockGraceOption(label: "After 5 minutes", seconds: 300),
            LockGraceOption(label: "After 15 minutes", seconds: 900)
        ]
    }
}

struct LockGraceOption: Identifiable, Hashable {
    let label: String
    let seconds: Double

    var id: Double { seconds }
}
