import UIKit

/// Haptic feedback, respecting the user preference.
@MainActor
enum Haptics {
    static var isEnabled = true

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func selection() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
