import Foundation

/// Debounced autosave. Typing schedules one save after a quiet period; changing
/// scenes or leaving the editor flushes immediately so content is never lost.
@MainActor
final class AutosaveEngine {
    private var task: Task<Void, Never>?
    private var pendingWork: (() -> Void)?
    private let debounce: Duration

    private(set) var lastSaveDate: Date?
    private(set) var isPending = false

    init(debounceMilliseconds: Int = 650) {
        self.debounce = .milliseconds(debounceMilliseconds)
    }

    var statusText: String {
        guard let lastSaveDate else { return "Not saved yet" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Saved " + formatter.localizedString(for: lastSaveDate, relativeTo: Date())
    }

    func schedule(_ work: @escaping @MainActor () -> Void) {
        pendingWork = work
        isPending = true
        task?.cancel()
        task = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled, let self else { return }
            self.runPending()
        }
    }

    /// Runs any queued work immediately (scene phase changes, editor dismissal).
    func flush() {
        task?.cancel()
        task = nil
        runPending()
    }

    func cancel() {
        task?.cancel()
        task = nil
        pendingWork = nil
        isPending = false
    }

    private func runPending() {
        guard let work = pendingWork else {
            isPending = false
            return
        }
        pendingWork = nil
        isPending = false
        work()
        lastSaveDate = Date()
    }
}
