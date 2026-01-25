//
//  AppState.swift
//  FlyFunBrief
//
//  Single source of truth for all app state.
//  Composes domain objects following FlyFunEuroAIP patterns.
//

import Foundation
import SwiftUI
import RZFlight
import CoreData
import OSLog

/// Single source of truth for all FlyFunBrief state
/// Composes domain objects to avoid becoming a god-class
///
/// Usage:
/// ```swift
/// @Environment(\.appState) private var state
/// state.flights.createFlight(origin: "LFPG", destination: "EGLL")
/// state.briefing.importBriefing(from: url)
/// ```
@Observable
@MainActor
final class AppState {
    // MARK: - Composed Domains

    /// Flight management (create, edit, archive)
    let flights: FlightDomain

    /// Current briefing, parsing state, and import handling
    let briefing: BriefingDomain

    /// NOTAM list, filtering, user annotations
    let notams: NotamDomain

    /// Navigation state (tabs, sheets, detail selection)
    let navigation: NavigationDomain

    /// User preferences
    let settings: SettingsDomain

    // MARK: - Services

    /// Service for API communication
    let briefingService: BriefingService

    /// Global NOTAM ignore list manager
    let ignoreListManager: IgnoreListManager

    /// Core Data persistence controller with CloudKit sync
    let persistenceController: PersistenceController

    /// Flight repository for Core Data operations
    let flightRepository: FlightRepository

    // MARK: - Init

    init() {
        // Initialize persistence
        self.persistenceController = PersistenceController.shared
        self.flightRepository = FlightRepository(persistenceController: persistenceController)
        self.ignoreListManager = IgnoreListManager(persistenceController: persistenceController)

        // Initialize services
        self.briefingService = BriefingService()

        // Initialize domains
        self.flights = FlightDomain(repository: flightRepository)
        self.briefing = BriefingDomain(service: briefingService)
        self.notams = NotamDomain(flightRepository: flightRepository, ignoreListManager: ignoreListManager)
        self.navigation = NavigationDomain()
        self.settings = SettingsDomain()

        // Wire up cross-domain communication
        setupCrossDomainWiring()

        // Configure service URLs from secrets
        Task {
            await briefingService.configure(baseURL: SecretsManager.shared.apiBaseURL)
        }
    }

    // MARK: - Cross-Domain Wiring

    private func setupCrossDomainWiring() {
        // When briefing is parsed, offer to store in Core Data
        briefing.onBriefingParsed = { [weak self] parsedBriefing in
            guard let self = self,
                  let flight = self.flights.selectedFlight else {
                return nil
            }

            return await self.flights.importBriefing(parsedBriefing, for: flight)
        }

        // When briefing is loaded (from parsing or Core Data), update notams domain
        briefing.onBriefingLoaded = { [weak self] loadedBriefing in
            guard let self = self else { return }

            // Check if we have a Core Data briefing with status info
            if let cdBriefing = self.briefing.currentCDBriefing,
               let flight = cdBriefing.flight {
                let previousKeys = self.flights.getPreviousIdentityKeys(for: flight, excluding: cdBriefing)
                self.notams.setBriefing(loadedBriefing, cdBriefing: cdBriefing, previousKeys: previousKeys)
            } else {
                self.notams.setBriefing(loadedBriefing)
            }

            self.navigation.showNotamList()
        }

        // When briefing is cleared, clear notams
        briefing.onBriefingCleared = { [weak self] in
            self?.notams.clearBriefing()
        }

        // When a flight is selected, enter flight view mode and load its latest briefing
        flights.onFlightSelected = { [weak self] flight in
            guard let self = self else { return }

            // Enter flight view mode
            if let flightId = flight.id {
                self.navigation.enterFlightView(flightId: flightId)
            }

            // Load latest briefing if available
            if let latestBriefing = flight.latestBriefing {
                self.briefing.loadBriefing(latestBriefing)
            }
        }

        // When a briefing is imported to Core Data, notify briefing domain
        flights.onBriefingImported = { [weak self] cdBriefing in
            // Update the current CD briefing reference
            self?.briefing.currentCDBriefing = cdBriefing

            // If the briefing is already decoded, refresh the notams
            if let briefing = cdBriefing.decodedBriefing,
               let flight = cdBriefing.flight {
                let previousKeys = self?.flights.getPreviousIdentityKeys(for: flight, excluding: cdBriefing) ?? []
                self?.notams.setBriefing(briefing, cdBriefing: cdBriefing, previousKeys: previousKeys)
            }
        }
    }

    // MARK: - Lifecycle

    /// Called when app appears
    func onAppear() async {
        Logger.app.info("AppState.onAppear")

        // Load flights from Core Data
        await flights.loadFlights()

        // Restore settings
        settings.restore()

        // Cleanup expired ignores periodically
        try? ignoreListManager.cleanupExpired()

        Logger.app.info("AppState initialized successfully")
    }

    /// Called when app disappears
    func onDisappear() {
        Logger.app.info("AppState.onDisappear - saving state")
        settings.save()
        persistenceController.save()
    }
}

// MARK: - Environment Key

private struct AppStateKey: EnvironmentKey {
    static let defaultValue: AppState? = nil
}

extension EnvironmentValues {
    var appState: AppState? {
        get { self[AppStateKey.self] }
        set { self[AppStateKey.self] = newValue }
    }
}

// MARK: - Preview Helper

extension AppState {
    /// Create a preview AppState with mock data
    @MainActor
    static func preview() -> AppState {
        AppState()
    }
}
