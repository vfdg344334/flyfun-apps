//
//  NavigationDomain.swift
//  FlyFunBrief
//
//  Manages navigation state (tabs, sheets, paths).
//

import Foundation
import SwiftUI
import OSLog

/// Main tabs in the app (when not viewing a flight)
enum AppTab: String, CaseIterable, Identifiable {
    case flights = "Flights"
    case ignored = "Ignored"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .flights: return "airplane"
        case .ignored: return "xmark.circle"
        case .settings: return "gearshape"
        }
    }
}

/// Sheet presentations
enum AppSheet: Identifiable {
    case importBriefing
    case notamDetail(notamId: String)
    case filterOptions
    case settings
    case newFlight
    case editFlight(flightId: UUID)
    case flightPicker  // For selecting which flight to import briefing to

    var id: String {
        switch self {
        case .importBriefing: return "import"
        case .notamDetail(let id): return "notam-\(id)"
        case .filterOptions: return "filters"
        case .settings: return "settings"
        case .newFlight: return "newFlight"
        case .editFlight(let id): return "editFlight-\(id)"
        case .flightPicker: return "flightPicker"
        }
    }
}

/// Domain for navigation state
@Observable
@MainActor
final class NavigationDomain {
    // MARK: - State

    /// Currently selected tab (when not viewing a flight)
    var selectedTab: AppTab = .flights

    /// Currently presented sheet
    var presentedSheet: AppSheet?

    /// Navigation path for iPhone drill-down navigation
    var navigationPath = NavigationPath()

    /// Whether we're in "flight view" mode (viewing NOTAMs for a selected flight)
    var isViewingFlight: Bool = false

    /// Whether to show the filter panel (iPad)
    var showFilterPanel = false

    /// Column visibility for NavigationSplitView (iPad)
    var columnVisibility: NavigationSplitViewVisibility = .all

    /// Selected flight ID (for navigation persistence)
    var selectedFlightId: UUID?

    // MARK: - Actions

    /// Enter flight view mode (viewing NOTAMs for a flight)
    func enterFlightView(flightId: UUID) {
        selectedFlightId = flightId
        isViewingFlight = true
        Logger.app.info("Entered flight view for \(flightId)")
    }

    /// Exit flight view mode (back to flight list)
    func exitFlightView() {
        isViewingFlight = false
        selectedFlightId = nil
        Logger.app.info("Exited flight view")
    }

    /// Show the import briefing sheet
    func showImportSheet() {
        presentedSheet = .importBriefing
    }

    /// Show flight picker for import
    func showFlightPicker() {
        presentedSheet = .flightPicker
    }

    /// Show new flight form
    func showNewFlight() {
        presentedSheet = .newFlight
    }

    /// Show edit flight form
    func showEditFlight(flightId: UUID) {
        presentedSheet = .editFlight(flightId: flightId)
    }

    /// Show NOTAM detail
    func showNotamDetail(notamId: String) {
        presentedSheet = .notamDetail(notamId: notamId)
    }

    /// Dismiss current sheet
    func dismissSheet() {
        presentedSheet = nil
    }

    /// Navigate to NOTAM list (enter flight view if a flight is selected)
    func showNotamList() {
        if selectedFlightId != nil {
            isViewingFlight = true
        }
    }

    /// Navigate to flights tab
    func showFlights() {
        selectedTab = .flights
        isViewingFlight = false
    }

    /// Navigate to ignored tab
    func showIgnored() {
        selectedTab = .ignored
        isViewingFlight = false
    }

    /// Toggle filter panel visibility
    func toggleFilterPanel() {
        showFilterPanel.toggle()
    }

    /// Show the filter options sheet
    func showFilterOptions() {
        presentedSheet = .filterOptions
    }

    /// Reset navigation state
    func reset() {
        selectedTab = .flights
        presentedSheet = nil
        navigationPath = NavigationPath()
        showFilterPanel = false
        selectedFlightId = nil
        isViewingFlight = false
    }
}
