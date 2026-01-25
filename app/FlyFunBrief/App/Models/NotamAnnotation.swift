//
//  NotamAnnotation.swift
//  FlyFunBrief
//
//  User annotation model for NOTAMs - extensible for future features.
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

/// User annotations for a NOTAM - extensible for future features
struct NotamAnnotation: Codable, Identifiable {
    // MARK: - Identity

    /// NOTAM ID (e.g., "A1234/24")
    let notamId: String

    /// Which briefing this belongs to
    let briefingId: String

    // MARK: - Status tracking

    /// User-assigned status
    var status: NotamStatus

    /// When status was last changed
    var statusChangedAt: Date?

    // MARK: - User notes (extensible)

    /// Typed note
    var textNote: String?

    /// PencilKit drawing data (future feature)
    var handwrittenNote: Data?

    // MARK: - Timestamps

    /// When annotation was created
    let createdAt: Date

    /// When annotation was last updated
    var updatedAt: Date

    // MARK: - Identifiable

    var id: String { "\(briefingId)_\(notamId)" }

    // MARK: - Init

    init(
        notamId: String,
        briefingId: String,
        status: NotamStatus = .unread,
        textNote: String? = nil
    ) {
        self.notamId = notamId
        self.briefingId = briefingId
        self.status = status
        self.textNote = textNote
        self.statusChangedAt = nil
        self.handwrittenNote = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
