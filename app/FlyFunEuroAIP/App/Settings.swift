//
//  Settings.swift
//  FlyFunEuroAIP
//
//  Created by Brice Rosenzweig on 02/11/2025.
//

import Foundation

/// Legacy Settings struct - use SettingsDomain instead
/// Kept for API configuration constants
public struct Settings {
    /// API base URL loaded from secrets.json, defaults to production
    static var apiBaseURL: String {
        SecretsManager.shared.apiBaseURL
    }
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "net.ro-z.flyfun.euroaip"
}
