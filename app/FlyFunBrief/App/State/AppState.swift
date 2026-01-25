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
import OSLog

/// Single source of truth for all FlyFunBrief state
/// Composes domain objects to avoid becoming a god-class
///
/// Usage:
/// ```swift
/// @Environment(\.appState) private var state
/// state.briefing.importBriefing(from: url)
/// ```
@Observable
@MainActor
final class AppState {
    // MARK: - Composed Domains

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

    /// Local storage for user annotations
    let annotationStore: AnnotationStore

    // MARK: - Init

    init() {
        // Initialize services
        self.briefingService = BriefingService()
        self.annotationStore = AnnotationStore()

        // Initialize domains
        self.briefing = BriefingDomain(service: briefingService)
        self.notams = NotamDomain(annotationStore: annotationStore)
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
        // When briefing is parsed, update notams domain
        briefing.onBriefingLoaded = { [weak self] loadedBriefing in
            self?.notams.setBriefing(loadedBriefing)
            self?.navigation.showNotamList()
        }

        // When briefing is cleared, clear notams
        briefing.onBriefingCleared = { [weak self] in
            self?.notams.clearBriefing()
        }
    }

    // MARK: - Lifecycle

    /// Called when app appears
    func onAppear() async {
        Logger.app.info("AppState.onAppear")

        // Initialize annotation store
        await annotationStore.initialize()

        // Restore settings
        settings.restore()

        Logger.app.info("AppState initialized successfully")
    }

    /// Called when app disappears
    func onDisappear() {
        Logger.app.info("AppState.onDisappear - saving state")
        settings.save()
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
