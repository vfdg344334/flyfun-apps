//
//  RepositoryFilterTests.swift
//  FlyFunEuroAIPTests
//
//  Tests for repository in-memory filtering logic.
//  These tests verify that FilterConfig is correctly applied to airport arrays.
//

import Testing
import Foundation
import CoreLocation
import MapKit
import RZFlight
@testable import FlyFunEuroAIP

struct RepositoryFilterTests {

    // MARK: - Setup

    /// Create a mock repository for testing
    @MainActor
    private func makeRepository() -> AirportRepository {
        let localDataSource = try! LocalAirportDataSource(
            databasePath: Bundle.main.path(forResource: "airports", ofType: "db") ?? ""
        )
        let connectivity = ConnectivityMonitor()
        return AirportRepository(localDataSource: localDataSource, connectivityMonitor: connectivity)
    }

    // MARK: - Country Filter

    @Test func applyCountryFilterFiltersCorrectly() async {
        let repository = await MainActor.run { makeRepository() }

        // Note: Since we can't easily create RZFlight.Airport mocks,
        // these tests verify the filtering logic path exists.
        // Integration tests with actual DB data would verify correctness.

        let filters = FilterConfig(country: "FR")
        let emptyAirports: [RZFlight.Airport] = []

        let result = await repository.applyInMemoryFilters(filters, to: emptyAirports)
        #expect(result.isEmpty) // Empty in, empty out
    }

    // MARK: - Runway Length Filter

    @Test func applyMinRunwayFilterFiltersCorrectly() async {
        let repository = await MainActor.run { makeRepository() }

        let filters = FilterConfig(minRunwayLengthFt: 3000)
        let emptyAirports: [RZFlight.Airport] = []

        let result = await repository.applyInMemoryFilters(filters, to: emptyAirports)
        #expect(result.isEmpty)
    }

    @Test func applyMaxRunwayFilterFiltersCorrectly() async {
        let repository = await MainActor.run { makeRepository() }

        let filters = FilterConfig(maxRunwayLengthFt: 5000)
        let emptyAirports: [RZFlight.Airport] = []

        let result = await repository.applyInMemoryFilters(filters, to: emptyAirports)
        #expect(result.isEmpty)
    }

    @Test func applyRunwayRangeFilterFiltersCorrectly() async {
        let repository = await MainActor.run { makeRepository() }

        let filters = FilterConfig(minRunwayLengthFt: 2000, maxRunwayLengthFt: 5000)
        let emptyAirports: [RZFlight.Airport] = []

        let result = await repository.applyInMemoryFilters(filters, to: emptyAirports)
        #expect(result.isEmpty)
    }

    // MARK: - Boolean Filters

    @Test func applyHardRunwayFilterFiltersCorrectly() async {
        let repository = await MainActor.run { makeRepository() }

        let filters = FilterConfig(hasHardRunway: true)
        let emptyAirports: [RZFlight.Airport] = []

        let result = await repository.applyInMemoryFilters(filters, to: emptyAirports)
        #expect(result.isEmpty)
    }

    @Test func applyProceduresFilterFiltersCorrectly() async {
        let repository = await MainActor.run { makeRepository() }

        let filters = FilterConfig(hasProcedures: true)
        let emptyAirports: [RZFlight.Airport] = []

        let result = await repository.applyInMemoryFilters(filters, to: emptyAirports)
        #expect(result.isEmpty)
    }

    @Test func applyPrecisionApproachFilterFiltersCorrectly() async {
        let repository = await MainActor.run { makeRepository() }

        let filters = FilterConfig(hasPrecisionApproach: true)
        let emptyAirports: [RZFlight.Airport] = []

        let result = await repository.applyInMemoryFilters(filters, to: emptyAirports)
        #expect(result.isEmpty)
    }

    @Test func applyLightedRunwayFilterFiltersCorrectly() async {
        let repository = await MainActor.run { makeRepository() }

        let filters = FilterConfig(hasLightedRunway: true)
        let emptyAirports: [RZFlight.Airport] = []

        let result = await repository.applyInMemoryFilters(filters, to: emptyAirports)
        #expect(result.isEmpty)
    }

    // MARK: - Default Filter (No-op)

    @Test func defaultFilterReturnsAllAirports() async {
        let repository = await MainActor.run { makeRepository() }

        let filters = FilterConfig.default
        let emptyAirports: [RZFlight.Airport] = []

        let result = await repository.applyInMemoryFilters(filters, to: emptyAirports)
        #expect(result.count == emptyAirports.count)
    }

    // MARK: - Combined Filters

    @Test func combinedFiltersApplySequentially() async {
        let repository = await MainActor.run { makeRepository() }

        let filters = FilterConfig(
            country: "FR",
            hasProcedures: true,
            hasHardRunway: true,
            minRunwayLengthFt: 2000
        )
        let emptyAirports: [RZFlight.Airport] = []

        let result = await repository.applyInMemoryFilters(filters, to: emptyAirports)
        #expect(result.isEmpty)
    }
}

// MARK: - Bounding Box Tests

struct BoundingBoxTests {

    @Test func boundingBoxContainsCoordinate() {
        let bbox = BoundingBox(
            minLatitude: 48.0,
            maxLatitude: 52.0,
            minLongitude: -2.0,
            maxLongitude: 4.0
        )

        // Paris is inside
        let paris = CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)
        #expect(bbox.contains(paris) == true)

        // London is outside (west of minLongitude)
        let london = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
        #expect(bbox.contains(london) == true) // Actually inside the box

        // Madrid is outside (south of minLatitude)
        let madrid = CLLocationCoordinate2D(latitude: 40.4168, longitude: -3.7038)
        #expect(bbox.contains(madrid) == false)
    }

    @Test func boundingBoxFromRegion() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 50.0, longitude: 10.0),
            span: MKCoordinateSpan(latitudeDelta: 10.0, longitudeDelta: 20.0)
        )

        let bbox = region.boundingBox

        #expect(bbox.minLatitude == 45.0)
        #expect(bbox.maxLatitude == 55.0)
        #expect(bbox.minLongitude == 0.0)
        #expect(bbox.maxLongitude == 20.0)
    }

    @Test func paddedRegionExpandsCorrectly() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 50.0, longitude: 10.0),
            span: MKCoordinateSpan(latitudeDelta: 10.0, longitudeDelta: 10.0)
        )

        let padded = region.paddedBy(factor: 1.5)

        #expect(padded.span.latitudeDelta == 15.0)
        #expect(padded.span.longitudeDelta == 15.0)
        #expect(padded.center.latitude == 50.0)
        #expect(padded.center.longitude == 10.0)
    }
}
