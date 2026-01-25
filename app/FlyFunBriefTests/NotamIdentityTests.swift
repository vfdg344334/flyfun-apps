//
//  NotamIdentityTests.swift
//  FlyFunBriefTests
//
//  Tests for NotamIdentity key generation and matching.
//

import Testing
import Foundation
@testable import FlyFunBrief
@testable import RZFlight

struct NotamIdentityTests {

    // MARK: - Test Data

    /// Create a test NOTAM from JSON
    private func makeNotam(
        id: String = "A1234/24",
        location: String = "LFPG",
        qCode: String? = "QMRLC",
        effectiveFrom: Date? = nil
    ) throws -> Notam {
        let effectiveFromISO = effectiveFrom.map {
            ISO8601DateFormatter().string(from: $0)
        } ?? "2024-01-15T00:00:00Z"

        let json = """
        {
            "id": "\(id)",
            "location": "\(location)",
            "raw_text": "TEST NOTAM",
            "message": "Test message",
            "q_code": \(qCode.map { "\"\($0)\"" } ?? "null"),
            "is_permanent": false,
            "effective_from": "\(effectiveFromISO)",
            "parsed_at": "2024-01-15T12:00:00Z",
            "parse_confidence": 1.0,
            "custom_categories": [],
            "custom_tags": []
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Notam.self, from: json.data(using: .utf8)!)
    }

    // MARK: - Key Generation Tests

    @Test func keyIncludesNotamId() throws {
        let notam = try makeNotam(id: "A1234/24")
        let key = NotamIdentity.key(for: notam)

        #expect(key.contains("A1234/24"))
    }

    @Test func keyIncludesQCode() throws {
        let notam = try makeNotam(qCode: "QMRLC")
        let key = NotamIdentity.key(for: notam)

        #expect(key.contains("QMRLC"))
    }

    @Test func keyIncludesLocation() throws {
        let notam = try makeNotam(location: "EGLL")
        let key = NotamIdentity.key(for: notam)

        #expect(key.contains("EGLL"))
    }

    @Test func keyIncludesEffectiveDate() throws {
        let date = ISO8601DateFormatter().date(from: "2024-06-15T08:00:00Z")!
        let notam = try makeNotam(effectiveFrom: date)
        let key = NotamIdentity.key(for: notam)

        #expect(key.contains("2024-06-15"))
    }

    @Test func keyUsesCorrectSeparator() throws {
        let notam = try makeNotam(id: "B5678/24", location: "KJFK", qCode: "QMXLC")
        let key = NotamIdentity.key(for: notam)

        let components = key.split(separator: "|")
        #expect(components.count >= 3)
        #expect(components[0] == "B5678/24")
    }

    @Test func keyHandlesNilQCode() throws {
        let notam = try makeNotam(qCode: nil)
        let key = NotamIdentity.key(for: notam)

        // Should still produce a valid key without Q-code
        #expect(!key.isEmpty)
        #expect(key.contains("A1234/24"))
    }

    // MARK: - Equality Tests

    @Test func identicalNotamsAreEqual() throws {
        let date = Date()
        let notam1 = try makeNotam(id: "A1234/24", location: "LFPG", qCode: "QMRLC", effectiveFrom: date)
        let notam2 = try makeNotam(id: "A1234/24", location: "LFPG", qCode: "QMRLC", effectiveFrom: date)

        #expect(NotamIdentity.areEqual(notam1, notam2))
    }

    @Test func differentIdsAreNotEqual() throws {
        let date = Date()
        let notam1 = try makeNotam(id: "A1234/24", effectiveFrom: date)
        let notam2 = try makeNotam(id: "B5678/24", effectiveFrom: date)

        #expect(!NotamIdentity.areEqual(notam1, notam2))
    }

    @Test func differentLocationsAreNotEqual() throws {
        let date = Date()
        let notam1 = try makeNotam(location: "LFPG", effectiveFrom: date)
        let notam2 = try makeNotam(location: "EGLL", effectiveFrom: date)

        #expect(!NotamIdentity.areEqual(notam1, notam2))
    }

    @Test func differentQCodesAreNotEqual() throws {
        let date = Date()
        let notam1 = try makeNotam(qCode: "QMRLC", effectiveFrom: date)
        let notam2 = try makeNotam(qCode: "QMXLC", effectiveFrom: date)

        #expect(!NotamIdentity.areEqual(notam1, notam2))
    }

    // MARK: - Matching Tests

    @Test func findMatchReturnsMatchingNotam() throws {
        let date = Date()
        let target = try makeNotam(id: "A1234/24", location: "LFPG", effectiveFrom: date)
        let collection = [
            try makeNotam(id: "B5678/24", location: "EGLL", effectiveFrom: date),
            try makeNotam(id: "A1234/24", location: "LFPG", effectiveFrom: date),
            try makeNotam(id: "C9999/24", location: "KJFK", effectiveFrom: date)
        ]

        let match = NotamIdentity.findMatch(for: target, in: collection)

        #expect(match != nil)
        #expect(match?.id == "A1234/24")
    }

    @Test func findMatchReturnsNilWhenNoMatch() throws {
        let target = try makeNotam(id: "X0000/24", location: "XXXX")
        let collection = [
            try makeNotam(id: "A1234/24", location: "LFPG"),
            try makeNotam(id: "B5678/24", location: "EGLL")
        ]

        let match = NotamIdentity.findMatch(for: target, in: collection)

        #expect(match == nil)
    }

    // MARK: - Lookup Tests

    @Test func createLookupBuildsCorrectDictionary() throws {
        let notams = [
            try makeNotam(id: "A1234/24", location: "LFPG"),
            try makeNotam(id: "B5678/24", location: "EGLL")
        ]

        let lookup = NotamIdentity.createLookup(for: notams)

        #expect(lookup.count == 2)

        let key1 = NotamIdentity.key(for: notams[0])
        let key2 = NotamIdentity.key(for: notams[1])

        #expect(lookup[key1]?.id == "A1234/24")
        #expect(lookup[key2]?.id == "B5678/24")
    }

    // MARK: - Status Transfer Tests

    @Test func transferStatusesCarriesOverMatchingStatuses() throws {
        let date = Date()
        let previousStatuses: [String: NotamStatus] = [
            NotamIdentity.key(for: try makeNotam(id: "A1234/24", location: "LFPG", effectiveFrom: date)): .read,
            NotamIdentity.key(for: try makeNotam(id: "B5678/24", location: "EGLL", effectiveFrom: date)): .important
        ]

        let newNotams = [
            try makeNotam(id: "A1234/24", location: "LFPG", effectiveFrom: date),
            try makeNotam(id: "C9999/24", location: "KJFK", effectiveFrom: date)
        ]

        let transferred = NotamIdentity.transferStatuses(from: previousStatuses, to: newNotams)

        #expect(transferred["A1234/24"] == .read)
        #expect(transferred["C9999/24"] == nil) // New NOTAM, no status transferred
    }

    // MARK: - New NOTAM Detection Tests

    @Test func findNewNotamsIdentifiesNewOnes() throws {
        let oldDate = ISO8601DateFormatter().date(from: "2024-01-01T00:00:00Z")!
        let newDate = ISO8601DateFormatter().date(from: "2024-06-01T00:00:00Z")!

        let previousKeys: Set<String> = [
            NotamIdentity.key(for: try makeNotam(id: "A1234/24", location: "LFPG", effectiveFrom: oldDate))
        ]

        let currentNotams = [
            try makeNotam(id: "A1234/24", location: "LFPG", effectiveFrom: oldDate), // Existing
            try makeNotam(id: "B5678/24", location: "EGLL", effectiveFrom: newDate)  // New
        ]

        let newNotams = NotamIdentity.findNewNotams(in: currentNotams, notIn: previousKeys)

        #expect(newNotams.count == 1)
        #expect(newNotams[0].id == "B5678/24")
    }

    @Test func identityKeysReturnsCorrectSet() throws {
        let notams = [
            try makeNotam(id: "A1234/24", location: "LFPG"),
            try makeNotam(id: "B5678/24", location: "EGLL"),
            try makeNotam(id: "C9999/24", location: "KJFK")
        ]

        let keys = NotamIdentity.identityKeys(for: notams)

        #expect(keys.count == 3)
        #expect(keys.contains(NotamIdentity.key(for: notams[0])))
        #expect(keys.contains(NotamIdentity.key(for: notams[1])))
        #expect(keys.contains(NotamIdentity.key(for: notams[2])))
    }
}
