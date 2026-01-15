//
//  LegendConfig.swift
//  FlyFunEuroAIP
//
//  Centralized configuration for legend colors and thresholds.
//  This provides a single source of truth for iOS legend configuration,
//  matching the web app's LEGEND_DESIGN.md specification.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Legend Colors

/// Centralized color definitions for all legend modes.
/// Hex values match the web app for visual consistency.
enum LegendColors {
    // MARK: - Notification Legend Colors
    /// Green for easy access: H24, ≤12h notice, AD hours (#28a745)
    static let notificationGreen = Color(red: 40/255, green: 167/255, blue: 69/255)

    /// Yellow for moderate: 13-24h notice, on-request (#ffc107)
    static let notificationYellow = Color(red: 255/255, green: 193/255, blue: 7/255)

    /// Blue for hassle: 25-48h notice, business day (#007bff)
    static let notificationBlue = Color(red: 0/255, green: 123/255, blue: 255/255)

    /// Red for difficult: >48h notice, not available (#dc3545)
    static let notificationRed = Color(red: 220/255, green: 53/255, blue: 69/255)

    /// Gray for unknown: no notification data (#95a5a6)
    static let notificationGray = Color(red: 149/255, green: 165/255, blue: 166/255)

    /// Dark gray for secondary/muted elements (#6c757d)
    static let grayDark = Color(red: 108/255, green: 117/255, blue: 125/255)

    // MARK: - Airport Type Colors
    /// Border crossing / customs point
    static let borderCrossing = Color.purple

    /// IFR-capable airport
    static let ifrAirport = Color.blue

    /// VFR-only airport
    static let vfrAirport = Color.green

    // MARK: - Runway Length Colors
    /// Long runway (>8000ft) - major airport
    static let runwayLong = Color.red

    /// Medium runway (4000-8000ft)
    static let runwayMedium = Color.orange

    /// Short runway (<4000ft)
    static let runwayShort = Color.green

    // MARK: - Procedure Colors
    /// ILS/Precision approach
    static let procedurePrecision = Color.yellow

    /// RNAV/GPS approach
    static let procedureRNAV = Color(red: 0.0, green: 0.5, blue: 1.0)

    /// Non-precision approach
    static let procedureNonPrecision = Color.orange

    /// VFR only (no procedures)
    static let procedureVFR = Color.gray
}

// MARK: - Legend Thresholds

/// Threshold values for legend categorization.
/// These should match the web app to ensure consistent classification.
enum LegendThresholds {
    // MARK: - Runway Length Thresholds (feet)
    /// Threshold for long runways (major airports)
    static let runwayLongFt = 8000

    /// Threshold for medium runways
    static let runwayMediumFt = 4000

    // MARK: - Notification Hour Thresholds
    /// Easy: notice required up to this many hours
    static let notificationEasyHours = 12

    /// Moderate: notice required up to this many hours
    static let notificationModerateHours = 24

    /// Hassle: notice required up to this many hours
    static let notificationHassleHours = 48

    // MARK: - Marker Size Thresholds
    /// Size for large/prominent markers
    static let markerSizeLarge: CGFloat = 20

    /// Size for medium markers
    static let markerSizeMedium: CGFloat = 16

    /// Size for small markers
    static let markerSizeSmall: CGFloat = 12

    /// Size for tiny/minimal markers
    static let markerSizeTiny: CGFloat = 8
}

// MARK: - UIColor Extensions for MapKit

#if canImport(UIKit)
extension LegendColors {
    /// UIColor versions for MapKit compatibility (offline map)
    enum UIKit {
        static var notificationGreen: UIColor {
            UIColor(red: 40/255, green: 167/255, blue: 69/255, alpha: 1.0)
        }

        static var notificationYellow: UIColor {
            UIColor(red: 255/255, green: 193/255, blue: 7/255, alpha: 1.0)
        }

        static var notificationBlue: UIColor {
            UIColor(red: 0/255, green: 123/255, blue: 255/255, alpha: 1.0)
        }

        static var notificationRed: UIColor {
            UIColor(red: 220/255, green: 53/255, blue: 69/255, alpha: 1.0)
        }

        static var notificationGray: UIColor {
            UIColor(red: 149/255, green: 165/255, blue: 166/255, alpha: 1.0)
        }
    }
}
#endif
