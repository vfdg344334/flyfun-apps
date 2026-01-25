//
//  NavigationDomain.swift
//  FlyFunBrief
//
//  Manages navigation state (tabs, sheets, paths).
//

import Foundation
import SwiftUI
import OSLog

/// Main tabs in the app
enum AppTab: String, CaseIterable, Identifiable {
    case briefing = "Briefing"
    case notams = "NOTAMs"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .briefing: return "doc.text"
        case .notams: return "list.bullet.rectangle"
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

    var id: String {
        switch self {
        case .importBriefing: return "import"
        case .notamDetail(let id): return "notam-\(id)"
        case .filterOptions: return "filters"
        case .settings: return "settings"
        }
    }
}

/// Domain for navigation state
@Observable
@MainActor
final class NavigationDomain {
    // MARK: - State

    /// Currently selected tab
    var selectedTab: AppTab = .briefing

    /// Currently presented sheet
    var presentedSheet: AppSheet?

    /// Navigation path for iPhone drill-down navigation
    var navigationPath = NavigationPath()

    /// Whether to show the filter panel (iPad)
    var showFilterPanel = false

    /// Column visibility for NavigationSplitView (iPad)
    var columnVisibility: NavigationSplitViewVisibility = .all

    // MARK: - Actions

    /// Show the import briefing sheet
    func showImportSheet() {
        presentedSheet = .importBriefing
    }

    /// Show NOTAM detail
    func showNotamDetail(notamId: String) {
        presentedSheet = .notamDetail(notamId: notamId)
    }

    /// Dismiss current sheet
    func dismissSheet() {
        presentedSheet = nil
    }

    /// Navigate to NOTAM list
    func showNotamList() {
        selectedTab = .notams
    }

    /// Navigate to briefing tab
    func showBriefing() {
        selectedTab = .briefing
    }

    /// Toggle filter panel visibility
    func toggleFilterPanel() {
        showFilterPanel.toggle()
    }

    /// Reset navigation state
    func reset() {
        selectedTab = .briefing
        presentedSheet = nil
        navigationPath = NavigationPath()
        showFilterPanel = false
    }
}
