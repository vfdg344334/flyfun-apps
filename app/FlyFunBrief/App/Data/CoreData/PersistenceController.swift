//
//  PersistenceController.swift
//  FlyFunBrief
//
//  Core Data stack with CloudKit sync via NSPersistentCloudKitContainer.
//

import Foundation
import CoreData
import OSLog

/// Manages the Core Data stack with CloudKit synchronization
@MainActor
final class PersistenceController {
    // MARK: - Shared Instance

    static let shared = PersistenceController()

    // MARK: - Properties

    let container: NSPersistentCloudKitContainer

    /// Main view context for UI operations
    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    /// Background context for bulk operations
    func newBackgroundContext() -> NSManagedObjectContext {
        container.newBackgroundContext()
    }

    // MARK: - Initialization

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "FlyFunBrief")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Failed to retrieve persistent store description")
        }

        // Enable CloudKit sync (only in production)
        if !inMemory {
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: "iCloud.com.ro-z.flyfunbrief"
            )
        }

        // Enable history tracking for CloudKit sync
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                // In production, handle this more gracefully
                Logger.persistence.error("Failed to load Core Data store: \(error), \(error.userInfo)")
                fatalError("Failed to load Core Data store: \(error)")
            }

            Logger.persistence.info("Core Data store loaded: \(storeDescription.url?.absoluteString ?? "unknown")")
        }

        // Configure view context
        viewContext.automaticallyMergesChangesFromParent = true
        viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Listen for remote changes
        setupRemoteChangeNotifications()
    }

    // MARK: - Remote Change Handling

    private func setupRemoteChangeNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteChange),
            name: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator
        )
    }

    @objc private func handleRemoteChange(_ notification: Notification) {
        Logger.persistence.info("Remote change notification received")
        // The viewContext automatically merges changes, but we can notify UI if needed
        Task { @MainActor in
            // Post a notification for any views that want to respond to sync
            NotificationCenter.default.post(name: .coreDataRemoteChangesReceived, object: nil)
        }
    }

    // MARK: - Save Helpers

    /// Save the view context if there are changes
    func save() {
        guard viewContext.hasChanges else { return }

        do {
            try viewContext.save()
            Logger.persistence.debug("View context saved successfully")
        } catch {
            Logger.persistence.error("Failed to save view context: \(error.localizedDescription)")
        }
    }

    /// Perform a background save operation
    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        container.performBackgroundTask { context in
            block(context)

            guard context.hasChanges else { return }

            do {
                try context.save()
                Logger.persistence.debug("Background context saved successfully")
            } catch {
                Logger.persistence.error("Failed to save background context: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Preview Support

    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        // Add sample data for previews if needed
        return controller
    }()
}

// MARK: - Notifications

extension Notification.Name {
    static let coreDataRemoteChangesReceived = Notification.Name("coreDataRemoteChangesReceived")
}

// MARK: - Logger Extension

extension Logger {
    static let persistence = Logger(subsystem: "com.ro-z.flyfunbrief", category: "persistence")
}
