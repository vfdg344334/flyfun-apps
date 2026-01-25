//
//  IgnoreListManager.swift
//  FlyFunBrief
//
//  Manages the global NOTAM ignore list via Core Data.
//

import Foundation
import CoreData
import RZFlight
import OSLog

/// Manager for the global NOTAM ignore list
@MainActor
final class IgnoreListManager {
    // MARK: - Properties

    private let persistenceController: PersistenceController

    private var viewContext: NSManagedObjectContext {
        persistenceController.viewContext
    }

    /// Cache of ignored identity keys for fast lookup
    private var ignoredKeysCache: Set<String>?

    // MARK: - Initialization

    init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }

    // MARK: - Ignore Operations

    /// Add a NOTAM to the global ignore list
    @discardableResult
    func addToIgnoreList(_ notam: Notam, reason: String? = nil) throws -> CDIgnoredNotam {
        let ignored = CDIgnoredNotam.create(in: viewContext, notam: notam, reason: reason)
        try viewContext.save()

        // Invalidate cache
        invalidateCache()

        Logger.persistence.info("Added NOTAM \(notam.id) to ignore list")
        return ignored
    }

    /// Remove a NOTAM from the ignore list
    func removeFromIgnoreList(_ ignored: CDIgnoredNotam) throws {
        let notamId = ignored.notamId ?? "unknown"
        viewContext.delete(ignored)
        try viewContext.save()

        // Invalidate cache
        invalidateCache()

        Logger.persistence.info("Removed NOTAM \(notamId) from ignore list")
    }

    /// Remove a NOTAM from the ignore list by identity key
    func removeFromIgnoreList(identityKey: String) throws {
        guard let ignored = CDIgnoredNotam.find(identityKey: identityKey, in: viewContext) else {
            return
        }
        try removeFromIgnoreList(ignored)
    }

    /// Check if a NOTAM is in the ignore list
    func isIgnored(_ notam: Notam) -> Bool {
        let identityKey = NotamIdentity.key(for: notam)
        return isIgnored(identityKey: identityKey)
    }

    /// Check if an identity key is in the ignore list
    func isIgnored(identityKey: String) -> Bool {
        // Use cache for performance
        if let cache = ignoredKeysCache {
            return cache.contains(identityKey)
        }

        return CDIgnoredNotam.isIgnored(identityKey: identityKey, in: viewContext)
    }

    // MARK: - Fetch

    /// Fetch all active (non-expired) ignored NOTAMs
    func fetchActiveIgnores() throws -> [CDIgnoredNotam] {
        try viewContext.fetch(CDIgnoredNotam.activeIgnoresFetchRequest())
    }

    /// Fetch all ignored NOTAMs including expired
    func fetchAllIgnores() throws -> [CDIgnoredNotam] {
        try viewContext.fetch(CDIgnoredNotam.allIgnoresFetchRequest())
    }

    /// Get all active ignored identity keys as a set (for filtering)
    func getIgnoredIdentityKeys() throws -> Set<String> {
        // Return cached if available
        if let cache = ignoredKeysCache {
            return cache
        }

        let ignores = try fetchActiveIgnores()
        let keys = Set(ignores.compactMap { $0.identityKey })

        // Update cache
        ignoredKeysCache = keys

        return keys
    }

    // MARK: - Cleanup

    /// Remove expired ignore entries
    func cleanupExpired() throws {
        try CDIgnoredNotam.cleanupExpired(in: viewContext)
        try viewContext.save()

        // Invalidate cache
        invalidateCache()

        Logger.persistence.info("Cleaned up expired ignore entries")
    }

    // MARK: - Cache Management

    /// Invalidate the ignored keys cache
    func invalidateCache() {
        ignoredKeysCache = nil
    }

    /// Refresh the cache
    func refreshCache() throws {
        let ignores = try fetchActiveIgnores()
        ignoredKeysCache = Set(ignores.compactMap { $0.identityKey })
    }
}
