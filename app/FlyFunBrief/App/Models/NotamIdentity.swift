//
//  NotamIdentity.swift
//  FlyFunBrief
//
//  NOTAM identity matching for detecting the same NOTAM across briefings.
//
//  A NOTAM's identity is determined by:
//  - NOTAM ID (e.g., "A1234/24")
//  - Q-code (operational meaning)
//  - Location (ICAO)
//  - Effective dates
//
//  This allows matching NOTAMs even when IDs change between briefings.
//

import Foundation
import RZFlight

/// Utility for computing NOTAM identity keys
enum NotamIdentity {
    // MARK: - Identity Key Generation

    /// Generate a unique identity key for a NOTAM
    ///
    /// The key combines multiple factors to uniquely identify a NOTAM
    /// across different briefings, even if the NOTAM ID changes.
    ///
    /// Components:
    /// 1. NOTAM ID (primary identifier, e.g., "A1234/24")
    /// 2. Q-code (if available, defines operational meaning)
    /// 3. Location (ICAO code)
    /// 4. Effective from date (ISO8601 format)
    ///
    /// - Parameter notam: The NOTAM to generate a key for
    /// - Returns: A stable identity key string
    static func key(for notam: Notam) -> String {
        var components: [String] = []

        // Primary: NOTAM ID
        components.append(notam.id)

        // Q-code for operational context
        if let qCode = notam.qCode {
            components.append(qCode)
        }

        // Location
        components.append(notam.location)

        // Effective date for uniqueness
        if let from = notam.effectiveFrom {
            components.append(ISO8601DateFormatter().string(from: from))
        }

        return components.joined(separator: "|")
    }

    // MARK: - Matching

    /// Check if two NOTAMs have the same identity
    static func areEqual(_ notam1: Notam, _ notam2: Notam) -> Bool {
        key(for: notam1) == key(for: notam2)
    }

    /// Find a NOTAM with matching identity in a collection
    static func findMatch(for notam: Notam, in collection: [Notam]) -> Notam? {
        let targetKey = key(for: notam)
        return collection.first { key(for: $0) == targetKey }
    }

    /// Create a lookup dictionary for fast identity matching
    static func createLookup(for notams: [Notam]) -> [String: Notam] {
        var lookup: [String: Notam] = [:]
        for notam in notams {
            lookup[key(for: notam)] = notam
        }
        return lookup
    }

    // MARK: - Status Transfer

    /// Transfer status from previous briefing NOTAMs to new briefing
    ///
    /// This method takes statuses from a previous briefing and maps them
    /// to NOTAMs in a new briefing based on identity matching.
    ///
    /// - Parameters:
    ///   - previousStatuses: Dictionary of identity key -> status from previous briefing
    ///   - newNotams: NOTAMs in the new briefing
    /// - Returns: Dictionary of NOTAM ID -> status for the new briefing
    static func transferStatuses(
        from previousStatuses: [String: NotamStatus],
        to newNotams: [Notam]
    ) -> [String: NotamStatus] {
        var result: [String: NotamStatus] = [:]

        for notam in newNotams {
            let identityKey = key(for: notam)
            if let existingStatus = previousStatuses[identityKey] {
                // Carry over the status
                result[notam.id] = existingStatus
            }
            // If no match found, the NOTAM is "new" (status will default to unread)
        }

        return result
    }

    // MARK: - New NOTAM Detection

    /// Identify NOTAMs in a new briefing that weren't in the previous briefing
    ///
    /// - Parameters:
    ///   - newNotams: NOTAMs from the new briefing
    ///   - previousIdentityKeys: Set of identity keys from previous briefing
    /// - Returns: NOTAMs that are new (not seen before)
    static func findNewNotams(
        in newNotams: [Notam],
        notIn previousIdentityKeys: Set<String>
    ) -> [Notam] {
        newNotams.filter { !previousIdentityKeys.contains(key(for: $0)) }
    }

    /// Get identity keys for a collection of NOTAMs
    static func identityKeys(for notams: [Notam]) -> Set<String> {
        Set(notams.map { key(for: $0) })
    }
}
