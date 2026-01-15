//
//  NavigationDomain.swift
//  FlyFunEuroAIP
//
//  Created by Brice Rosenzweig on 28/11/2025.
//
//  Simplified for modern SwiftUI (iOS 17+):
//  - NavigationSplitView handles sidebar visibility
//  - .inspector() handles airport detail presentation
//  - .searchable() handles search UI
//

import Foundation
import SwiftUI

/// Domain: Navigation state (tabs, sheets, paths)
/// This is a composed part of AppState, not a standalone ViewModel.
///
/// Note: Most navigation is now handled by SwiftUI's built-in components:
/// - NavigationSplitView for sidebar/detail layout
/// - .inspector() for airport detail panel
/// - .searchable() for search interface
@Observable
@MainActor
final class NavigationDomain {
    // MARK: - Inspector Tab State
    /// Selected tab in airport inspector (Airport Info, AIP, Rules)
    var selectedBottomTab: BottomTab = .airportInfo

    // MARK: - Modal Sheet State
    var showingSettings: Bool = false

    // MARK: - Navigation Path (for programmatic navigation within sidebar)
    var path = NavigationPath()

    // MARK: - Types

    enum BottomTab: String, CaseIterable, Identifiable, Sendable {
        case airportInfo = "Airport"
        case aip = "AIP"
        case rules = "Rules"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .airportInfo: return "airplane"
            case .aip: return "doc.text"
            case .rules: return "book"
            }
        }

        var displayName: String {
            rawValue
        }
    }

    // MARK: - Init

    init() {}

    // MARK: - Inspector Tab Actions

    func selectBottomTab(_ tab: BottomTab) {
        selectedBottomTab = tab
    }

    // MARK: - Settings Sheet

    func showSettings() {
        showingSettings = true
    }

    func hideSettings() {
        showingSettings = false
    }

    // MARK: - Navigation Path

    func push<T: Hashable>(_ value: T) {
        path.append(value)
    }

    func pop() {
        if !path.isEmpty {
            path.removeLast()
        }
    }

    func popToRoot() {
        path = NavigationPath()
    }
}

