//
//  CDNotamStatus+Extensions.swift
//  FlyFunBrief
//
//  Core Data CDNotamStatus entity convenience extensions.
//

import Foundation
import CoreData
import RZFlight

extension CDNotamStatus {
    // MARK: - Convenience Initializer

    /// Create a new NOTAM status entry
    @discardableResult
    static func create(
        in context: NSManagedObjectContext,
        notam: Notam,
        briefing: CDBriefing,
        status: NotamStatus = .unread
    ) -> CDNotamStatus {
        let cdStatus = CDNotamStatus(context: context)
        cdStatus.id = UUID()
        cdStatus.notamId = notam.id
        cdStatus.identityKey = NotamIdentity.key(for: notam)
        cdStatus.status = status.rawValue
        cdStatus.updatedAt = Date()
        cdStatus.briefing = briefing
        return cdStatus
    }

    /// Create from an existing status (for copying to new briefing)
    @discardableResult
    static func copy(
        from existing: CDNotamStatus,
        to newBriefing: CDBriefing,
        notamId: String,
        in context: NSManagedObjectContext
    ) -> CDNotamStatus {
        let cdStatus = CDNotamStatus(context: context)
        cdStatus.id = UUID()
        cdStatus.notamId = notamId
        cdStatus.identityKey = existing.identityKey
        cdStatus.status = existing.status
        cdStatus.textNote = existing.textNote
        cdStatus.updatedAt = existing.updatedAt
        cdStatus.briefing = newBriefing
        return cdStatus
    }

    // MARK: - Computed Properties

    /// The status as a NotamStatus enum
    var statusEnum: NotamStatus {
        get {
            guard let rawValue = status else { return .unread }
            return NotamStatus(rawValue: rawValue) ?? .unread
        }
        set {
            status = newValue.rawValue
            updatedAt = Date()
        }
    }

    /// Whether this NOTAM has a note attached
    var hasNote: Bool {
        guard let note = textNote else { return false }
        return !note.isEmpty
    }

    // MARK: - Fetch Requests

    /// Find status for a specific NOTAM in a briefing
    static func find(
        notamId: String,
        briefing: CDBriefing,
        in context: NSManagedObjectContext
    ) -> CDNotamStatus? {
        let request = NSFetchRequest<CDNotamStatus>(entityName: "CDNotamStatus")
        request.predicate = NSPredicate(format: "notamId == %@ AND briefing == %@", notamId, briefing)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    /// Find status by identity key in a briefing
    static func find(
        identityKey: String,
        briefing: CDBriefing,
        in context: NSManagedObjectContext
    ) -> CDNotamStatus? {
        let request = NSFetchRequest<CDNotamStatus>(entityName: "CDNotamStatus")
        request.predicate = NSPredicate(format: "identityKey == %@ AND briefing == %@", identityKey, briefing)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    /// Find all statuses with a specific identity key across all briefings for a flight
    static func findAll(
        identityKey: String,
        flight: CDFlight,
        in context: NSManagedObjectContext
    ) -> [CDNotamStatus] {
        let request = NSFetchRequest<CDNotamStatus>(entityName: "CDNotamStatus")
        request.predicate = NSPredicate(format: "identityKey == %@ AND briefing.flight == %@", identityKey, flight)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDNotamStatus.updatedAt, ascending: false)]
        return (try? context.fetch(request)) ?? []
    }
}
