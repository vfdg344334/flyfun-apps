//
//  PreviewFactory.swift
//  FlyFunEuroAIP
//
//  Factory for creating preview-ready AppState and components.
//  Used by SwiftUI previews and can also be used for testing.
//

import SwiftUI
import RZFlight
import MapKit
import CoreLocation

/// Factory for creating preview-ready AppState and components
@MainActor
enum PreviewFactory {

    // MARK: - AppState Variations

    /// Create a basic AppState with default data for previews
    static func makeAppState() -> AppState {
        let repository = MockAirportRepository()
        let connectivity = ConnectivityMonitor()

        let state = AppState(
            repository: repository,
            connectivityMonitor: connectivity
        )

        // Pre-populate with sample data
        state.airports.airports = TestFixtures.sampleAirports
        state.airports.mapPosition = .region(.europe)

        return state
    }

    /// Create AppState with a selected airport
    static func makeAppStateWithSelectedAirport() -> AppState {
        let state = makeAppState()
        if let airport = TestFixtures.sampleAirports.first {
            state.airports.selectedAirport = airport
            state.navigation.showBottomTabBar()
        }
        return state
    }

    /// Create AppState with chat messages
    static func makeAppStateWithChat() -> AppState {
        let state = makeAppState()

        state.chat.messages = TestFixtures.sampleChatMessages

        return state
    }

    /// Create AppState with active route
    static func makeAppStateWithRoute() -> AppState {
        let state = makeAppState()

        // Set up route between two airports
        state.airports.activeRoute = RouteVisualization(
            coordinates: [
                CLLocationCoordinate2D(latitude: 51.3481, longitude: -0.5589),  // EGTF
                CLLocationCoordinate2D(latitude: 43.5420, longitude: 6.9533)    // LFMD
            ],
            departure: "EGTF",
            destination: "LFMD"
        )

        // Add highlights for route airports
        state.airports.highlights = [
            "route-LFPG": MapHighlight(
                id: "route-LFPG",
                coordinate: CLLocationCoordinate2D(latitude: 49.0097, longitude: 2.5478),
                color: .blue,
                radius: 20000,
                popup: "Paris CDG"
            ),
            "route-LFLY": MapHighlight(
                id: "route-LFLY",
                coordinate: CLLocationCoordinate2D(latitude: 45.7256, longitude: 5.0811),
                color: .blue,
                radius: 20000,
                popup: "Lyon"
            )
        ]

        // Focus map on route
        state.airports.mapPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 47.0, longitude: 3.0),
            span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)
        ))

        return state
    }

    /// Create AppState in loading state
    static func makeAppStateLoading() -> AppState {
        let state = makeAppState()
        state.system.setLoading(true)
        return state
    }

    /// Create AppState in offline mode
    static func makeAppStateOffline() -> AppState {
        let state = makeAppState()
        state.system.connectivityMode = .offline
        return state
    }

    /// Create AppState with active filters
    static func makeAppStateWithFilters() -> AppState {
        let state = makeAppState()
        state.airports.filters = FilterConfig(
            country: "FR",
            hasProcedures: true,
            minRunwayLengthFt: 2000
        )
        return state
    }

    // MARK: - Individual Sample Data

    /// A sample airport for single-view previews
    static var sampleAirport: RZFlight.Airport? {
        TestFixtures.sampleAirports.first
    }

    /// A sample airport with procedures
    static var sampleAirportWithProcedures: RZFlight.Airport? {
        TestFixtures.sampleAirports.first { !$0.procedures.isEmpty }
    }

    /// Sample chat messages
    static var sampleChatMessages: [ChatMessage] {
        TestFixtures.sampleChatMessages
    }
}

// MARK: - Test Fixtures

/// Sample data for previews and tests
enum TestFixtures {

    /// Sample airports with varied properties
    /// Note: These are simplified - RZFlight.Airport requires specific initialization
    static var sampleAirports: [RZFlight.Airport] {
        // For previews, we need to use actual RZFlight airport loading
        // or create a mock. Since RZFlight.Airport has complex initialization,
        // we return an empty array here and rely on the app's actual data loading.
        //
        // In a real preview, you would either:
        // 1. Load from a bundled preview database
        // 2. Use a MockAirport if RZFlight supports it
        // 3. Have RZFlight provide a preview() method
        []
    }

    /// Sample ICAOs for testing
    static let sampleICAOs = ["EGLL", "EGKK", "EGTF", "LFPG", "LFMD"]

    /// Sample chat conversation
    static var sampleChatMessages: [ChatMessage] {
        [
            ChatMessage(role: .user, content: "What's EGLL?"),
            ChatMessage(
                role: .assistant,
                content: """
                **London Heathrow (EGLL)** is the busiest airport in the UK and one of the busiest in the world.

                - **Location:** London, United Kingdom
                - **Elevation:** 83 ft
                - **Runways:** 2 (09L/27R, 09R/27L)
                - **Procedures:** Multiple ILS approaches available
                """
            ),
            ChatMessage(role: .user, content: "Show me airports between EGTF and LFMD"),
            ChatMessage(
                role: .assistant,
                content: "Here are airports along your route from Fairoaks (EGTF) to Cannes (LFMD)...",
                isStreaming: true
            )
        ]
    }
}

// MARK: - Mock Repository

/// Mock repository for previews - returns empty/minimal data
final class MockAirportRepository: AirportRepositoryProtocol, @unchecked Sendable {

    func airportsInRegion(
        boundingBox: BoundingBox,
        filters: FilterConfig,
        limit: Int
    ) async throws -> [RZFlight.Airport] {
        []
    }

    func airports(matching filters: FilterConfig, limit: Int) async throws -> [RZFlight.Airport] {
        []
    }

    func searchAirports(query: String, limit: Int) async throws -> [RZFlight.Airport] {
        []
    }

    func airportDetail(icao: String) async throws -> RZFlight.Airport? {
        nil
    }

    func airportsNearRoute(
        from: String,
        to: String,
        distanceNm: Int,
        filters: FilterConfig
    ) async throws -> RouteResult {
        RouteResult(airports: [], departure: from, destination: to)
    }

    func airportsNearLocation(
        center: CLLocationCoordinate2D,
        radiusNm: Int,
        filters: FilterConfig
    ) async throws -> [RZFlight.Airport] {
        []
    }

    func applyInMemoryFilters(
        _ filters: FilterConfig,
        to airports: [RZFlight.Airport]
    ) -> [RZFlight.Airport] {
        airports
    }

    func availableCountries() async throws -> [String] {
        ["GB", "FR", "DE", "IT", "ES", "CH", "AT", "NL", "BE"]
    }

    func borderCrossingICAOs() async throws -> Set<String> {
        Set(["LFPG", "LFPO", "EGLL", "EGKK", "EHAM", "EDDF", "LSZH"])
    }
}

// Note: ConnectivityMonitor is final, so we use a real instance for previews.
// It won't actually monitor network changes in preview context, which is fine.

// MARK: - Mock Chatbot Service

/// Mock chatbot service for previews
final class MockChatbotService: ChatbotService {
    nonisolated func isAvailable() async -> Bool {
        true
    }

    nonisolated func sendMessage(
        _ message: String,
        history: [ChatMessage]
    ) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.message(content: "This is a mock response for: \(message)"))
            continuation.yield(.done(sessionId: "preview-session", tokens: nil))
            continuation.finish()
        }
    }
}
