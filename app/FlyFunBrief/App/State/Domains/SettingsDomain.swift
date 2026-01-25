//
//  SettingsDomain.swift
//  FlyFunBrief
//
//  Manages user preferences and settings.
//

import Foundation
import OSLog

/// Domain for user settings
@Observable
@MainActor
final class SettingsDomain {
    // MARK: - Settings

    /// API base URL for briefing parsing
    var apiBaseURL: String {
        didSet {
            UserDefaults.standard.set(apiBaseURL, forKey: Keys.apiBaseURL)
        }
    }

    /// Default grouping for NOTAM list
    var defaultGrouping: NotamGrouping {
        didSet {
            UserDefaults.standard.set(defaultGrouping.rawValue, forKey: Keys.defaultGrouping)
        }
    }

    /// Whether to auto-mark NOTAMs as read when viewing
    var autoMarkAsRead: Bool {
        didSet {
            UserDefaults.standard.set(autoMarkAsRead, forKey: Keys.autoMarkAsRead)
        }
    }

    /// Whether to show raw NOTAM text in detail view
    var showRawText: Bool {
        didSet {
            UserDefaults.standard.set(showRawText, forKey: Keys.showRawText)
        }
    }

    /// Whether to show map in NOTAM detail (when coordinates available)
    var showNotamMap: Bool {
        didSet {
            UserDefaults.standard.set(showNotamMap, forKey: Keys.showNotamMap)
        }
    }

    // MARK: - Keys

    private enum Keys {
        static let apiBaseURL = "apiBaseURL"
        static let defaultGrouping = "defaultGrouping"
        static let autoMarkAsRead = "autoMarkAsRead"
        static let showRawText = "showRawText"
        static let showNotamMap = "showNotamMap"
    }

    // MARK: - Defaults

    private static let defaultAPIBaseURL = "http://localhost:8000"

    // MARK: - Init

    init() {
        // Load from UserDefaults with defaults
        self.apiBaseURL = UserDefaults.standard.string(forKey: Keys.apiBaseURL)
            ?? Self.defaultAPIBaseURL

        if let groupingRaw = UserDefaults.standard.string(forKey: Keys.defaultGrouping),
           let grouping = NotamGrouping(rawValue: groupingRaw) {
            self.defaultGrouping = grouping
        } else {
            self.defaultGrouping = .airport
        }

        self.autoMarkAsRead = UserDefaults.standard.bool(forKey: Keys.autoMarkAsRead)
        self.showRawText = UserDefaults.standard.object(forKey: Keys.showRawText) as? Bool ?? true
        self.showNotamMap = UserDefaults.standard.object(forKey: Keys.showNotamMap) as? Bool ?? true
    }

    // MARK: - Actions

    /// Restore settings from storage
    func restore() {
        Logger.app.info("Settings restored")
    }

    /// Save settings
    func save() {
        // Settings are auto-saved via didSet, but this can be used for explicit saves
        Logger.app.info("Settings saved")
    }

    /// Reset to defaults
    func resetToDefaults() {
        apiBaseURL = Self.defaultAPIBaseURL
        defaultGrouping = .airport
        autoMarkAsRead = false
        showRawText = true
        showNotamMap = true
        Logger.app.info("Settings reset to defaults")
    }
}
