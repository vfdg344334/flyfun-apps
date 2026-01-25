//
//  EnrichedNotam.swift
//  FlyFunBrief
//
//  Display model combining NOTAM data with user status and annotations.
//

import Foundation
import RZFlight

/// NOTAM enriched with user status information for display
struct EnrichedNotam: Identifiable {
    // MARK: - Core NOTAM

    /// The underlying NOTAM from RZFlight
    let notam: Notam

    // MARK: - Identity

    /// Identity key for matching across briefings
    let identityKey: String

    // MARK: - User Status

    /// User-assigned status (read, important, etc.)
    var status: NotamStatus

    /// User's text note
    var textNote: String?

    /// When the status was last changed
    var statusChangedAt: Date?

    // MARK: - New NOTAM Indicator

    /// Whether this NOTAM is new (not seen in previous briefings)
    let isNew: Bool

    // MARK: - Ignored Status

    /// Whether this NOTAM matches a global ignore entry
    let isGloballyIgnored: Bool

    // MARK: - Identifiable

    var id: String { notam.id }

    // MARK: - Initialization

    init(
        notam: Notam,
        status: NotamStatus = .unread,
        textNote: String? = nil,
        statusChangedAt: Date? = nil,
        isNew: Bool = false,
        isGloballyIgnored: Bool = false
    ) {
        self.notam = notam
        self.identityKey = NotamIdentity.key(for: notam)
        self.status = status
        self.textNote = textNote
        self.statusChangedAt = statusChangedAt
        self.isNew = isNew
        self.isGloballyIgnored = isGloballyIgnored
    }

    // MARK: - Convenience Accessors

    /// NOTAM ID (e.g., "A1234/24")
    var notamId: String { notam.id }

    /// Location ICAO
    var location: String { notam.location }

    /// NOTAM message text
    var message: String { notam.message }

    /// Category from ICAO Q-code
    var category: NotamCategory? { notam.category }

    /// ICAO category derived from Q-code (preferred over category)
    var icaoCategory: NotamCategory? { notam.icaoCategory }

    /// Whether the NOTAM is permanent
    var isPermanent: Bool { notam.isPermanent }

    /// Effective from date
    var effectiveFrom: Date? { notam.effectiveFrom }

    /// Effective to date
    var effectiveTo: Date? { notam.effectiveTo }

    /// Whether active now
    var isActiveNow: Bool { notam.isActiveNow }

    /// Check if active during a time window
    func isActive(during start: Date, to end: Date) -> Bool {
        notam.isActive(during: start, to: end)
    }

    /// Has user note attached
    var hasNote: Bool {
        guard let note = textNote else { return false }
        return !note.isEmpty
    }
}

// MARK: - Array Extensions

extension Array where Element == EnrichedNotam {
    /// Filter by status
    func withStatus(_ status: NotamStatus) -> [EnrichedNotam] {
        filter { $0.status == status }
    }

    /// Filter to only new NOTAMs
    func onlyNew() -> [EnrichedNotam] {
        filter { $0.isNew }
    }

    /// Exclude globally ignored NOTAMs
    func excludingIgnored() -> [EnrichedNotam] {
        filter { !$0.isGloballyIgnored }
    }

    /// Group by airport
    func groupedByAirport() -> [String: [EnrichedNotam]] {
        Dictionary(grouping: self) { $0.location }
    }

    /// Group by category
    func groupedByCategory() -> [NotamCategory: [EnrichedNotam]] {
        var result: [NotamCategory: [EnrichedNotam]] = [:]
        for enriched in self {
            let key = enriched.icaoCategory ?? .otherInfo
            result[key, default: []].append(enriched)
        }
        return result
    }

    /// Sort by importance: new > important > unread > rest
    func sortedByImportance() -> [EnrichedNotam] {
        sorted { lhs, rhs in
            // New NOTAMs first
            if lhs.isNew != rhs.isNew {
                return lhs.isNew
            }
            // Then by status priority
            let priority: [NotamStatus: Int] = [
                .important: 0,
                .followUp: 1,
                .unread: 2,
                .read: 3,
                .ignore: 4
            ]
            let lhsPriority = priority[lhs.status] ?? 5
            let rhsPriority = priority[rhs.status] ?? 5
            return lhsPriority < rhsPriority
        }
    }

    /// Count of new NOTAMs
    var newCount: Int {
        filter { $0.isNew }.count
    }

    /// Count of unread NOTAMs
    var unreadCount: Int {
        filter { $0.status == .unread }.count
    }

    /// Count of important NOTAMs
    var importantCount: Int {
        filter { $0.status == .important }.count
    }
}

// MARK: - Builder from Core Data

extension EnrichedNotam {
    /// Create enriched NOTAMs from a briefing with statuses
    static func enrich(
        notams: [Notam],
        statuses: [String: CDNotamStatus],
        previousIdentityKeys: Set<String>,
        ignoredKeys: Set<String>
    ) -> [EnrichedNotam] {
        notams.map { notam in
            let identityKey = NotamIdentity.key(for: notam)
            let cdStatus = statuses[notam.id]

            return EnrichedNotam(
                notam: notam,
                status: cdStatus?.statusEnum ?? .unread,
                textNote: cdStatus?.textNote,
                statusChangedAt: cdStatus?.updatedAt,
                isNew: !previousIdentityKeys.contains(identityKey),
                isGloballyIgnored: ignoredKeys.contains(identityKey)
            )
        }
    }
}
