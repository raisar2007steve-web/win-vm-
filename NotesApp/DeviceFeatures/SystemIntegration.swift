import Foundation
import CoreSpotlight
import UniformTypeIdentifiers
import UserNotifications

/// Indexes note titles and text in Spotlight so notes are findable system-wide.
enum SpotlightIndexer {
    static let domainIdentifier = "com.raisar2007steve.NotesApp.notes"

    static func index(_ notes: [Note]) {
        let items: [CSSearchableItem] = notes.map { note in
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = note.displayTitle
            attributes.contentDescription = String(note.previewText.prefix(200))
            attributes.keywords = note.tags.map(\.name) + ["note"]
            return CSSearchableItem(
                uniqueIdentifier: note.id.uuidString,
                domainIdentifier: domainIdentifier,
                attributeSet: attributes
            )
        }
        guard !items.isEmpty else { return }
        CSSearchableIndex.default().indexSearchableItems(items) { _ in }
    }

    static func remove(_ note: Note) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [note.id.uuidString]) { _ in }
    }

    static func removeAll() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { _ in }
    }
}

/// Local notifications for note reminders.
enum NotificationScheduler {
    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        @unknown default:
            return false
        }
    }

    static func scheduleReminder(for note: Note, at date: Date) async -> Bool {
        guard await requestAuthorizationIfNeeded() else { return false }
        let content = UNMutableNotificationContent()
        content.title = note.displayTitle
        content.body = "Reminder from Notes"
        content.sound = .default
        content.userInfo = ["noteID": note.id.uuidString]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: "note-reminder-\(note.id.uuidString)",
            content: content,
            trigger: trigger
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            return false
        }
    }

    static func cancelReminder(for note: Note) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["note-reminder-\(note.id.uuidString)"]
        )
    }
}
