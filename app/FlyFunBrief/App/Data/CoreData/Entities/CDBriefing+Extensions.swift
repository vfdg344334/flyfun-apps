//
//  CDBriefing+Extensions.swift
//  FlyFunBrief
//
//  Core Data CDBriefing entity convenience extensions.
//

import Foundation
import CoreData
import RZFlight
import OSLog

extension CDBriefing {
    // MARK: - Convenience Initializer

    /// Create a new briefing from a parsed RZFlight Briefing
    @discardableResult
    static func create(
        in context: NSManagedObjectContext,
        from briefing: Briefing,
        flight: CDFlight
    ) throws -> CDBriefing {
        let cdBriefing = CDBriefing(context: context)
        cdBriefing.id = UUID()
        cdBriefing.importedAt = Date()
        cdBriefing.source = briefing.source
        cdBriefing.isLatest = true
        cdBriefing.flight = flight

        // Encode the full briefing as JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        cdBriefing.jsonBlob = try encoder.encode(briefing)

        // Mark previous briefings as not latest
        if let existingBriefings = flight.briefings as? Set<CDBriefing> {
            for existing in existingBriefings where existing != cdBriefing {
                existing.isLatest = false
            }
        }

        Logger.persistence.info("Created CDBriefing with \(briefing.notams.count) NOTAMs")
        return cdBriefing
    }

    // MARK: - Computed Properties

    /// Decode the stored briefing JSON
    var decodedBriefing: Briefing? {
        guard let data = jsonBlob else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(Briefing.self, from: data)
        } catch {
            Logger.persistence.error("Failed to decode briefing JSON: \(error.localizedDescription)")
            return nil
        }
    }

    /// Route summary for display
    var routeSummary: String? {
        guard let briefing = decodedBriefing,
              let route = briefing.route else { return nil }
        return "\(route.departure) \u{2192} \(route.destination)"
    }

    /// NOTAM count
    var notamCount: Int {
        decodedBriefing?.notams.count ?? 0
    }

    /// Formatted import date
    var formattedImportDate: String {
        guard let date = importedAt else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// All NOTAM statuses keyed by NOTAM ID
    var statusesByNotamId: [String: CDNotamStatus] {
        guard let statusSet = notamStatuses as? Set<CDNotamStatus> else { return [:] }
        var result: [String: CDNotamStatus] = [:]
        for status in statusSet {
            if let notamId = status.notamId {
                result[notamId] = status
            }
        }
        return result
    }

    /// All NOTAM statuses keyed by identity key
    var statusesByIdentityKey: [String: CDNotamStatus] {
        guard let statusSet = notamStatuses as? Set<CDNotamStatus> else { return [:] }
        var result: [String: CDNotamStatus] = [:]
        for status in statusSet {
            if let key = status.identityKey {
                result[key] = status
            }
        }
        return result
    }

    // MARK: - Fetch Requests

    /// Find a briefing by ID
    static func find(id: UUID, in context: NSManagedObjectContext) -> CDBriefing? {
        let request = NSFetchRequest<CDBriefing>(entityName: "CDBriefing")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    /// Fetch briefings for a flight
    static func fetchRequest(for flight: CDFlight) -> NSFetchRequest<CDBriefing> {
        let request = NSFetchRequest<CDBriefing>(entityName: "CDBriefing")
        request.predicate = NSPredicate(format: "flight == %@", flight)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \CDBriefing.importedAt, ascending: false)
        ]
        return request
    }
}
