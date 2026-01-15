//
//  NotificationInfo.swift
//  FlyFunEuroAIP
//
//  Notification requirements for an airport.
//  Data comes from bundled ga_notifications.db
//

import Foundation
import SwiftUI

/// Notification requirements for an airport
struct NotificationInfo: Sendable, Equatable {
    /// Type of notification requirement
    enum NotificationType: String, Sendable, CaseIterable {
        case h24 = "h24"                    // 24/7 available, no notice needed
        case hours = "hours"                 // Requires X hours notice
        case onRequest = "on_request"        // Available on request
        case businessDay = "business_day"    // Business day notice required
        case asAdHours = "as_ad_hours"       // Available during AD hours (no notice)
        case notAvailable = "not_available"  // Not available
        case unknown = "unknown"             // Could not parse

        var displayName: String {
            switch self {
            case .h24: return "24/7"
            case .hours: return "Notice Required"
            case .onRequest: return "On Request"
            case .businessDay: return "Business Day"
            case .asAdHours: return "AD Hours"
            case .notAvailable: return "Unavailable"
            case .unknown: return "Unknown"
            }
        }

        var iconName: String {
            switch self {
            case .h24: return "checkmark.circle.fill"
            case .hours: return "clock.fill"
            case .onRequest: return "phone.fill"
            case .businessDay: return "calendar"
            case .asAdHours: return "clock"
            case .notAvailable: return "xmark.circle.fill"
            case .unknown: return "questionmark.circle"
            }
        }
    }

    /// Notification bucket for legend coloring (matches web cascade)
    enum NotificationBucket: String, Sendable, CaseIterable {
        case h24         // 24/7 - green
        case easy        // ≤12h notice or AD hours - green
        case moderate    // 13-24h notice or on request - yellow
        case hassle      // 25-48h notice or business day - blue
        case difficult   // >48h notice or not available - red
        case unknown     // No data - gray

        var color: Color {
            switch self {
            case .h24, .easy:
                return Color(red: 40/255, green: 167/255, blue: 69/255)   // #28a745 green
            case .moderate:
                return Color(red: 255/255, green: 193/255, blue: 7/255)  // #ffc107 yellow
            case .hassle:
                return Color(red: 0/255, green: 123/255, blue: 255/255)  // #007bff blue
            case .difficult:
                return Color(red: 220/255, green: 53/255, blue: 69/255)  // #dc3545 red
            case .unknown:
                return Color(red: 149/255, green: 165/255, blue: 166/255) // #95a5a6 gray
            }
        }

        var displayName: String {
            switch self {
            case .h24: return "24/7"
            case .easy: return "Easy (≤12h)"
            case .moderate: return "Moderate (13-24h)"
            case .hassle: return "Hassle (25-48h)"
            case .difficult: return "Difficult (>48h)"
            case .unknown: return "Unknown"
            }
        }

        /// Sort order for comparing buckets (lower = easier access)
        var sortOrder: Int {
            switch self {
            case .h24: return 0
            case .easy: return 1
            case .moderate: return 2
            case .hassle: return 3
            case .difficult: return 4
            case .unknown: return 5
            }
        }
    }

    /// Type of rule (customs, immigration, etc.)
    enum RuleType: String, Sendable {
        case customs
        case immigration
        case ppr
        case pn
        case handling
    }

    let icao: String
    let ruleType: RuleType
    let notificationType: NotificationType
    let hoursNotice: Int?
    let operatingHoursStart: String?
    let operatingHoursEnd: String?
    let weekdayRules: [String: String]?
    let summary: String
    let confidence: Double
    let contactPhone: String?
    let contactEmail: String?

    // MARK: - Computed Properties

    /// Whether no prior notice is required
    var isH24: Bool {
        notificationType == .h24
    }

    /// Whether notification is on request / by arrangement
    var isOnRequest: Bool {
        notificationType == .onRequest
    }

    /// Display summary (truncated if needed)
    var displaySummary: String {
        if summary.count > 150 {
            return String(summary.prefix(150)) + "..."
        }
        return summary
    }

    /// Operating hours as formatted string
    var operatingHours: String? {
        guard let start = operatingHoursStart, let end = operatingHoursEnd else {
            return nil
        }
        return "\(start)-\(end)"
    }

    /// Maximum hours notice required (checking weekday rules too)
    var maxNoticeHours: Int? {
        if isH24 { return 0 }
        if isOnRequest { return nil }

        var maxHours = hoursNotice

        // Check weekday rules for higher values
        if let rules = weekdayRules {
            for (_, value) in rules {
                if let hours = parseHoursFromString(value) {
                    if maxHours == nil || hours > maxHours! {
                        maxHours = hours
                    }
                }
            }
        }

        return maxHours
    }

    /// Easiness score from 0-100 (higher = easier to access)
    @available(*, deprecated, message: "Use bucket property instead for web-aligned classification")
    var easinessScore: Double {
        switch notificationType {
        case .h24:
            return 100.0  // 24/7, no notice needed
        case .notAvailable:
            return 0.0    // Not available at all
        case .unknown:
            return 50.0   // Truly unknown
        case .onRequest:
            return 70.0   // Available but need to call ahead
        case .businessDay:
            // Business day notice - treat as ~24h
            return 55.0
        case .asAdHours:
            return 85.0   // Available during AD hours, no advance notice
        case .hours:
            // Has operating hours - check if advance notice is also required
            guard let maxHours = maxNoticeHours, maxHours > 0 else {
                // Operating hours only, no advance notice needed = easy
                return 85.0
            }
            // Advance notice required - score by hours
            switch maxHours {
            case 1...2: return 90.0
            case 3...12: return 80.0
            case 13...24: return 60.0
            case 25...48: return 40.0
            case 49...72: return 20.0
            default: return 10.0
            }
        }
    }

    /// Color for legend mode based on easiness
    @available(*, deprecated, message: "Use bucket.color instead for web-aligned legend coloring")
    var legendColor: Color {
        bucket.color
    }

    /// Notification bucket using 12-condition cascade (matches web exactly)
    /// See LEGEND_DESIGN.md for full cascade specification
    var bucket: NotificationBucket {
        // 1. is_h24 === true → green (h24 bucket)
        if isH24 {
            return .h24
        }

        // 2. type='not_available' → red (difficult bucket)
        if notificationType == .notAvailable {
            return .difficult
        }

        // 3. is_on_request === true → yellow (moderate bucket)
        if isOnRequest {
            return .moderate
        }

        // 4. type='business_day' → blue (hassle bucket)
        if notificationType == .businessDay {
            return .hassle
        }

        // 5. type='as_ad_hours' → green (easy bucket)
        if notificationType == .asAdHours {
            return .easy
        }

        // 6. type='hours' with no hours_notice → green (easy bucket)
        if notificationType == .hours && hoursNotice == nil {
            return .easy
        }

        // 7. hours null/undefined → gray (unknown bucket)
        guard let hours = hoursNotice else {
            return .unknown
        }

        // 8. hours ≤ 12 → green (easy bucket)
        if hours <= 12 {
            return .easy
        }

        // 9. hours 13-24 → yellow (moderate bucket)
        if hours <= 24 {
            return .moderate
        }

        // 10. hours 25-48 → blue (hassle bucket)
        if hours <= 48 {
            return .hassle
        }

        // 11. hours > 48 → red (difficult bucket)
        return .difficult
    }

    // MARK: - Private Helpers

    private func parseHoursFromString(_ value: String) -> Int? {
        // Parse strings like "24h notice", "48h", etc.
        let pattern = #"(\d+)\s*h"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return Int(value[range])
    }
}

// MARK: - Initialization from DB Row

extension NotificationInfo {
    /// Create from database row dictionary
    init?(from row: [String: Any]) {
        guard let icao = row["icao"] as? String else { return nil }

        self.icao = icao

        // Parse rule type
        if let ruleTypeStr = row["rule_type"] as? String,
           let ruleType = RuleType(rawValue: ruleTypeStr) {
            self.ruleType = ruleType
        } else {
            self.ruleType = .ppr
        }

        // Parse notification type
        if let notifTypeStr = row["notification_type"] as? String,
           let notifType = NotificationType(rawValue: notifTypeStr) {
            self.notificationType = notifType
        } else {
            self.notificationType = .unknown
        }

        self.hoursNotice = row["hours_notice"] as? Int
        self.operatingHoursStart = row["operating_hours_start"] as? String
        self.operatingHoursEnd = row["operating_hours_end"] as? String
        self.summary = row["summary"] as? String ?? ""
        self.confidence = row["confidence"] as? Double ?? 0.0

        // Parse weekday rules JSON
        if let weekdayJson = row["weekday_rules"] as? String,
           let data = weekdayJson.data(using: .utf8),
           let rules = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            self.weekdayRules = rules
        } else {
            self.weekdayRules = nil
        }

        // Parse contact info JSON
        if let contactJson = row["contact_info"] as? String,
           let data = contactJson.data(using: .utf8),
           let contact = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            self.contactPhone = contact["phone"] as? String
            self.contactEmail = contact["email"] as? String
        } else {
            self.contactPhone = nil
            self.contactEmail = nil
        }
    }
}
