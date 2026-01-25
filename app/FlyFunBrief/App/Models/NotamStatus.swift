//
//  NotamStatus.swift
//  FlyFunBrief
//
//  User-managed status for a NOTAM.
//

import Foundation

/// User-managed status for a NOTAM
enum NotamStatus: String, Codable, CaseIterable, Identifiable {
    case unread
    case read
    case important
    case ignore
    case followUp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unread: return "Unread"
        case .read: return "Read"
        case .important: return "Important"
        case .ignore: return "Ignored"
        case .followUp: return "Follow Up"
        }
    }

    var icon: String {
        switch self {
        case .unread: return "circle"
        case .read: return "checkmark.circle"
        case .important: return "star.fill"
        case .ignore: return "xmark.circle"
        case .followUp: return "flag.fill"
        }
    }

    var color: String {
        switch self {
        case .unread: return "gray"
        case .read: return "green"
        case .important: return "yellow"
        case .ignore: return "secondary"
        case .followUp: return "orange"
        }
    }
}
