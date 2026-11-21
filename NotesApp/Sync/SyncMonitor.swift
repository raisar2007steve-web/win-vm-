import Foundation
import Network
import SwiftUI

/// Reports whether notes are syncing through iCloud and whether the device is
/// online. The app stays fully usable in every state it reports.
@MainActor
@Observable
final class SyncMonitor {
    enum SyncState: Equatable {
        case cloud(fallback: Bool)
        case localOnly

        var label: String {
            switch self {
            case .cloud(let fallback):
                return fallback ? "iCloud (retrying)" : "iCloud"
            case .localOnly:
                return "On My iPhone"
            }
        }

        var symbol: String {
            switch self {
            case .cloud(let fallback):
                return fallback ? "icloud.slash" : "icloud"
            case .localOnly:
                return "internaldrive"
            }
        }
    }

    private(set) var state: SyncState = .localOnly
    private(set) var isOnline = true
    private(set) var lastEventDescription = "Ready"

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.raisar2007steve.notes.network")
    private var started = false

    var iCloudAccountAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    func configure(storageMode: ModelContainerFactory.StorageMode, settings: AppSettings) {
        if storageMode == .cloud {
            state = .cloud(fallback: false)
        } else if settings.cloudSyncEnabled && iCloudAccountAvailable {
            state = .cloud(fallback: true)
        } else {
            state = .localOnly
        }
        startNetworkMonitoring()
    }

    private func startNetworkMonitoring() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    func noteSyncActivity(_ description: String) {
        lastEventDescription = description
    }

    deinit {
        monitor.cancel()
    }
}
