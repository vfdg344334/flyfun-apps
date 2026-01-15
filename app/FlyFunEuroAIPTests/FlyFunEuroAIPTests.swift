//
//  FlyFunEuroAIPTests.swift
//  FlyFunEuroAIPTests
//
//  Created by Brice Rosenzweig on 26/10/2025.
//
//  Test organization:
//  - FilterConfigTests.swift - FilterConfig computed properties
//  - RepositoryFilterTests.swift - Repository filtering and BoundingBox
//  - VisualizationTests.swift - Chat visualization and map state
//  - ChatDomainTests.swift - Chat message and event handling
//

import Testing
@testable import FlyFunEuroAIP

/// Smoke tests to verify the test target is configured correctly
struct FlyFunEuroAIPTests {

    @Test func appStateCanBeCreatedForPreview() async throws {
        let state = await PreviewFactory.makeAppState()
        let airportCount = await state.airports.airports.count
        #expect(airportCount >= 0) // Just verify it doesn't crash
    }

    @Test func filterConfigDefaultIsValid() {
        let config = FilterConfig.default
        #expect(config.hasActiveFilters == false)
    }

    @Test func connectivityModesExist() {
        let offline = ConnectivityMode.offline
        let online = ConnectivityMode.online
        let hybrid = ConnectivityMode.hybrid

        #expect(offline.rawValue == "offline")
        #expect(online.rawValue == "online")
        #expect(hybrid.rawValue == "hybrid")
    }
}
