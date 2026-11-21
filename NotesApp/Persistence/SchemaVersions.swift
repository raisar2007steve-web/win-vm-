import Foundation
import SwiftData

/// Versioned schema + migration plan. New model versions are appended here so
/// shipped stores migrate forward instead of being discarded.
enum NotesSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Note.self, Folder.self, Tag.self, Attachment.self]
    }
}

enum NotesMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [NotesSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

/// Builds the persistent container. iCloud/CloudKit is requested first and the
/// app degrades to a purely local store if the device has no account, no
/// entitlement or the container is unavailable — notes must always remain usable.
enum ModelContainerFactory {
    enum StorageMode: String {
        case local
        case cloud
    }

    static func make(
        inMemory: Bool = false,
        preferCloudKit: Bool = true
    ) throws -> (container: ModelContainer, mode: StorageMode) {
        let schema = Schema(versionedSchema: NotesSchemaV1.self)

        if !inMemory {
            // On a fresh install Application Support may not exist yet, and SwiftData
            // will fail to create its store there. Creating it up front keeps the app
            // on disk instead of silently falling back to an in-memory store.
            if let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first {
                try? FileManager.default.createDirectory(
                    at: applicationSupport,
                    withIntermediateDirectories: true
                )
            }
        }

        if preferCloudKit && !inMemory {
            let cloudConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
            if let container = try? ModelContainer(
                for: schema,
                migrationPlan: NotesMigrationPlan.self,
                configurations: cloudConfiguration
            ) {
                return (container, .cloud)
            }
        }

        let localConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: NotesMigrationPlan.self,
            configurations: localConfiguration
        )
        return (container, inMemory ? .local : .local)
    }
}
