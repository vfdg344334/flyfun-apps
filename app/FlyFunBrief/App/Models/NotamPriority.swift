//
//  NotamPriority.swift
//  FlyFunBrief
//
//  NOTAM priority levels and rule-based priority evaluation.
//

import Foundation
import CoreLocation
import RZFlight

// MARK: - Priority Level

/// Priority level for a NOTAM based on flight context evaluation.
///
/// Priority is computed dynamically based on the NOTAM's relevance to the
/// current flight (distance, altitude, time, type). This is independent of
/// user-assigned status (read/important/ignored).
enum NotamPriority: Int, Comparable, CaseIterable {
    /// Low priority - far from route, irrelevant altitude, or filtered types
    case low = 0

    /// Normal priority - default for NOTAMs without specific relevance signals
    case normal = 1

    /// High priority - close to route at relevant altitude, or critical types
    case high = 2

    static func < (lhs: NotamPriority, rhs: NotamPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// SF Symbol name for this priority level
    var iconName: String? {
        switch self {
        case .high: return "exclamationmark.triangle.fill"
        case .normal: return nil  // No icon for normal
        case .low: return "arrow.down.circle"
        }
    }

    /// Display color for priority indicator
    var displayColor: String {
        switch self {
        case .high: return "orange"
        case .normal: return "primary"
        case .low: return "secondary"
        }
    }
}

// MARK: - Priority Rule Protocol

/// Protocol for NOTAM priority rules.
///
/// Rules are evaluated in order. Each rule can return a priority level
/// or nil to defer to subsequent rules. First non-nil result wins.
///
/// Design note: Currently hardcoded, but protocol allows future extension
/// to user-configurable rules loaded from JSON/plist.
protocol NotamPriorityRule {
    /// Unique identifier for this rule
    var id: String { get }

    /// Human-readable name for settings UI (future)
    var name: String { get }

    /// Evaluate the rule for a NOTAM in the given flight context.
    /// - Returns: Priority level if rule applies, nil to defer to next rule
    func evaluate(notam: Notam, distanceNm: Double?, context: FlightContext) -> NotamPriority?
}

// MARK: - Priority Evaluator

/// Evaluates NOTAM priority using a chain of rules.
///
/// Usage:
/// ```swift
/// let evaluator = NotamPriorityEvaluator.shared
/// let priority = evaluator.evaluate(notam: notam, distanceNm: 5.0, context: flightContext)
/// ```
final class NotamPriorityEvaluator {
    /// Shared instance with default rules
    static let shared = NotamPriorityEvaluator()

    /// Ordered list of rules to evaluate
    private let rules: [NotamPriorityRule]

    init(rules: [NotamPriorityRule]? = nil) {
        self.rules = rules ?? Self.defaultRules
    }

    /// Evaluate priority for a NOTAM.
    /// Rules are evaluated in order; first non-nil result wins.
    /// Returns `.normal` if no rule matches.
    func evaluate(notam: Notam, distanceNm: Double?, context: FlightContext) -> NotamPriority {
        for rule in rules {
            if let priority = rule.evaluate(notam: notam, distanceNm: distanceNm, context: context) {
                return priority
            }
        }
        return .normal
    }

    /// Default rules in evaluation order
    static let defaultRules: [NotamPriorityRule] = [
        // High priority rules first
        HighPriorityCloseAndRelevantAltitude(),
        HighPriorityRunwayClosureAtAirport(),

        // Low priority rules
        LowPriorityObstaclesFarFromAirports(),
        LowPriorityHelicopterNotams(),

        // Default: normal priority (implicit if no rule matches)
    ]
}

// MARK: - High Priority Rules

/// High priority: NOTAM is within 10nm of route AND altitude overlaps cruise ±2000ft
struct HighPriorityCloseAndRelevantAltitude: NotamPriorityRule {
    let id = "high_close_altitude"
    let name = "Close to route at flight altitude"

    /// Distance threshold in nautical miles
    let distanceThresholdNm: Double = 10.0

    func evaluate(notam: Notam, distanceNm: Double?, context: FlightContext) -> NotamPriority? {
        // Need both distance and altitude info
        guard let distance = distanceNm,
              distance <= distanceThresholdNm else {
            return nil
        }

        // Check altitude overlap
        guard let cruiseRange = context.cruiseAltitudeRange else {
            // No cruise altitude set - can't evaluate altitude relevance
            // Still consider close NOTAMs as potentially high priority
            return distance <= 5.0 ? .high : nil
        }

        // Get NOTAM altitude range
        let notamLower = notam.lowerLimit ?? 0
        let notamUpper = notam.upperLimit ?? 99999

        // Skip surface-to-unlimited (always includes all altitudes, not useful signal)
        if notamLower == 0 && notamUpper >= 99900 {
            return nil
        }

        // Check if ranges overlap
        let overlaps = cruiseRange.lowerBound <= notamUpper && cruiseRange.upperBound >= notamLower
        return overlaps ? .high : nil
    }
}

/// High priority: Runway/taxiway closure at departure or destination
struct HighPriorityRunwayClosureAtAirport: NotamPriorityRule {
    let id = "high_runway_closure"
    let name = "Runway closure at departure/destination"

    func evaluate(notam: Notam, distanceNm: Double?, context: FlightContext) -> NotamPriority? {
        // Check if NOTAM is at departure or destination
        let isAtDepDest = notam.location == context.departureICAO ||
                          notam.location == context.destinationICAO

        guard isAtDepDest else { return nil }

        // Check for closure indicators
        let isClosure = isClosureNotam(notam)
        return isClosure ? .high : nil
    }

    private func isClosureNotam(_ notam: Notam) -> Bool {
        // Check Q-code condition for closure (C = closed, LC = limited closed, etc.)
        // The last character 'C' in the condition code indicates closure
        if let conditionCode = notam.qCodeInfo?.conditionCode,
           conditionCode.hasSuffix("C") {
            return true
        }

        // Check custom tags
        if notam.customTags.contains("closed") {
            return true
        }

        // Check category + tags
        if let primary = notam.primaryCategory?.lowercased() {
            if (primary == "runway" || primary == "taxiway") &&
               notam.customTags.contains(where: { $0.contains("closed") || $0.contains("clsd") }) {
                return true
            }
        }

        return false
    }
}

// MARK: - Low Priority Rules

/// Low priority: Obstacle NOTAMs beyond 2nm from departure/destination
struct LowPriorityObstaclesFarFromAirports: NotamPriorityRule {
    let id = "low_obstacle_far"
    let name = "Obstacles far from airports"

    /// Distance threshold from departure/destination in nm
    let airportDistanceThresholdNm: Double = 2.0

    func evaluate(notam: Notam, distanceNm: Double?, context: FlightContext) -> NotamPriority? {
        // Only apply to obstacle NOTAMs
        guard isObstacleNotam(notam) else { return nil }

        // If no distance info, can't evaluate
        guard let distance = distanceNm else { return nil }

        // Check if near departure or destination
        // For now, use route distance as proxy (could be enhanced with per-airport distance)
        let isNearAirport = notam.location == context.departureICAO ||
                           notam.location == context.destinationICAO ||
                           distance <= airportDistanceThresholdNm

        return isNearAirport ? nil : .low
    }

    private func isObstacleNotam(_ notam: Notam) -> Bool {
        // Check Q-code subject (OB = obstacle, OL = obstacle light)
        if let subject = notam.qCodeSubject {
            if subject == "OB" || subject == "OL" {
                return true
            }
        }

        // Check category
        if notam.primaryCategory?.lowercased() == "obstacle" {
            return true
        }

        if notam.icaoCategory == .otherInfo {
            // Check message for obstacle keywords
            let message = notam.message.lowercased()
            if message.contains("crane") || message.contains("tower") ||
               message.contains("obstacle") || message.contains("mast") {
                return true
            }
        }

        return false
    }
}

/// Low priority: Helicopter-related NOTAMs (for fixed-wing operations)
struct LowPriorityHelicopterNotams: NotamPriorityRule {
    let id = "low_helicopter"
    let name = "Helicopter NOTAMs"

    func evaluate(notam: Notam, distanceNm: Double?, context: FlightContext) -> NotamPriority? {
        guard isHelicopterNotam(notam) else { return nil }
        return .low
    }

    private func isHelicopterNotam(_ notam: Notam) -> Bool {
        // Q-code subjects for helicopter: FH (heliport), FP (heliport procedures), LH/LU/LW (heli lighting)
        if let subject = notam.qCodeSubject {
            if subject == "FH" || subject == "LH" || subject == "FP" ||
               subject == "LU" || subject == "LW" {
                return true
            }
        }

        // Check message for helicopter keywords
        let message = notam.message.lowercased()
        if message.contains("heliport") || message.contains("helipad") ||
           message.contains("fato") || message.contains("helicopter") {
            return true
        }

        return false
    }
}
