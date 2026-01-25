//
//  CDIgnoredNotam+Extensions.swift
//  FlyFunBrief
//
//  Core Data CDIgnoredNotam entity convenience extensions.
//

import Foundation
import CoreData
import RZFlight

extension CDIgnoredNotam {
    // MARK: - Convenience Initializer

    /// Create a new ignored NOTAM entry
    @discardableResult
    static func create(
        in context: NSManagedObjectContext,
        notam: Notam,
        reason: String? = nil
    ) -> CDIgnoredNotam {
        let ignored = CDIgnoredNotam(context: context)
        ignored.id = UUID()
        ignored.notamId = notam.id
        ignored.identityKey = NotamIdentity.key(for: notam)
        ignored.summary = notam.message.prefix(200).description
        ignored.reason = reason
        ignored.createdAt = Date()

        // Auto-expire when NOTAM effective date passes
        if let effectiveTo = notam.effectiveTo, !notam.isPermanent {
            ignored.expiresAt = effectiveTo
        }

        return ignored
    }

    // MARK: - Computed Properties

    /// Whether this ignore entry has expired
    var isExpired: Bool {
        guard let expires = expiresAt else { return false }
        return expires < Date()
    }

    /// Formatted expiration date
    var formattedExpiresAt: String? {
        guard let expires = expiresAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: expires)
    }

    /// Formatted creation date
    var formattedCreatedAt: String {
        guard let created = createdAt else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: created)
    }

    // MARK: - Fetch Requests

    /// Fetch request for all active (non-expired) ignored NOTAMs
    static func activeIgnoresFetchRequest() -> NSFetchRequest<CDIgnoredNotam> {
        let request = NSFetchRequest<CDIgnoredNotam>(entityName: "CDIgnoredNotam")
        // Fetch where expiresAt is nil OR expiresAt > now
        request.predicate = NSPredicate(format: "expiresAt == nil OR expiresAt > %@", Date() as NSDate)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \CDIgnoredNotam.createdAt, ascending: false)
        ]
        return request
    }

    /// Fetch request for all ignored NOTAMs (including expired)
    static func allIgnoresFetchRequest() -> NSFetchRequest<CDIgnoredNotam> {
        let request = NSFetchRequest<CDIgnoredNotam>(entityName: "CDIgnoredNotam")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \CDIgnoredNotam.createdAt, ascending: false)
        ]
        return request
    }

    /// Find if a NOTAM is in the ignore list
    static func find(
        identityKey: String,
        in context: NSManagedObjectContext
    ) -> CDIgnoredNotam? {
        let request = NSFetchRequest<CDIgnoredNotam>(entityName: "CDIgnoredNotam")
        request.predicate = NSPredicate(
            format: "identityKey == %@ AND (expiresAt == nil OR expiresAt > %@)",
            identityKey, Date() as NSDate
        )
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    /// Check if a NOTAM identity key is ignored
    static func isIgnored(
        identityKey: String,
        in context: NSManagedObjectContext
    ) -> Bool {
        find(identityKey: identityKey, in: context) != nil
    }

    /// Clean up expired ignore entries
    static func cleanupExpired(in context: NSManagedObjectContext) throws {
        let request = NSFetchRequest<CDIgnoredNotam>(entityName: "CDIgnoredNotam")
        request.predicate = NSPredicate(format: "expiresAt != nil AND expiresAt < %@", Date() as NSDate)

        let expired = try context.fetch(request)
        for item in expired {
            context.delete(item)
        }
    }
}
