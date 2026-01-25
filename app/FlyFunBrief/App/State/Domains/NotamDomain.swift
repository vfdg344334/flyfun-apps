//
//  NotamDomain.swift
//  FlyFunBrief
//
//  Manages NOTAM list, filtering, and user annotations.
//

import Foundation
import RZFlight
import OSLog

/// Filter options for NOTAM list
enum NotamFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case unread = "Unread"
    case important = "Important"
    case critical = "Critical"

    var id: String { rawValue }
}

/// Grouping options for NOTAM list
enum NotamGrouping: String, CaseIterable, Identifiable {
    case none = "None"
    case airport = "Airport"
    case category = "Category"

    var id: String { rawValue }
}

/// Domain for NOTAM list management
@Observable
@MainActor
final class NotamDomain {
    // MARK: - State

    /// All NOTAMs from current briefing
    private(set) var allNotams: [Notam] = []

    /// Briefing ID for current set of NOTAMs
    private(set) var briefingId: String?

    /// Currently selected NOTAM for detail view
    var selectedNotam: Notam?

    /// Current filter
    var filter: NotamFilter = .all

    /// Current grouping
    var grouping: NotamGrouping = .airport

    /// Text search query
    var searchQuery: String = ""

    /// User annotations keyed by NOTAM ID
    private(set) var annotations: [String: NotamAnnotation] = [:]

    // MARK: - Computed Properties

    /// Filtered and sorted NOTAMs based on current settings
    var filteredNotams: [Notam] {
        var notams = allNotams

        // Apply text search
        if !searchQuery.isEmpty {
            notams = notams.containing(searchQuery)
        }

        // Apply status filter
        switch filter {
        case .all:
            break
        case .unread:
            notams = notams.filter { annotation(for: $0)?.status == .unread }
        case .important:
            notams = notams.filter { annotation(for: $0)?.status == .important }
        case .critical:
            notams = notams.filter {
                $0.category == .runway || $0.category == .airspace
            }
        }

        return notams
    }

    /// NOTAMs grouped by airport
    var notamsGroupedByAirport: [String: [Notam]] {
        filteredNotams.groupedByAirport()
    }

    /// NOTAMs grouped by category
    var notamsGroupedByCategory: [NotamCategory: [Notam]] {
        filteredNotams.groupedByCategory()
    }

    /// Count of unread NOTAMs
    var unreadCount: Int {
        allNotams.filter { annotation(for: $0)?.status == .unread }.count
    }

    /// Count of important NOTAMs
    var importantCount: Int {
        allNotams.filter { annotation(for: $0)?.status == .important }.count
    }

    // MARK: - Dependencies

    private let annotationStore: AnnotationStore

    // MARK: - Init

    init(annotationStore: AnnotationStore) {
        self.annotationStore = annotationStore
    }

    // MARK: - Actions

    /// Set NOTAMs from a loaded briefing
    func setBriefing(_ briefing: Briefing) {
        self.briefingId = briefing.id
        self.allNotams = briefing.notams
        self.selectedNotam = nil

        // Load annotations for this briefing
        Task {
            annotations = await annotationStore.loadAnnotations(forBriefingId: briefing.id)
            // Initialize unread annotations for new NOTAMs
            for notam in briefing.notams {
                if annotations[notam.id] == nil {
                    annotations[notam.id] = NotamAnnotation(
                        notamId: notam.id,
                        briefingId: briefing.id,
                        status: .unread
                    )
                }
            }
        }

        Logger.app.info("NotamDomain loaded \(briefing.notams.count) NOTAMs")
    }

    /// Clear all NOTAMs
    func clearBriefing() {
        allNotams = []
        briefingId = nil
        selectedNotam = nil
        annotations = [:]
    }

    /// Get annotation for a NOTAM
    func annotation(for notam: Notam) -> NotamAnnotation? {
        annotations[notam.id]
    }

    /// Update annotation status for a NOTAM
    func setStatus(_ status: NotamStatus, for notam: Notam) {
        guard let briefingId else { return }

        var annotation = annotations[notam.id] ?? NotamAnnotation(
            notamId: notam.id,
            briefingId: briefingId,
            status: status
        )
        annotation.status = status
        annotation.statusChangedAt = Date()
        annotation.updatedAt = Date()

        annotations[notam.id] = annotation

        // Persist
        Task {
            await annotationStore.saveAnnotation(annotation)
        }
    }

    /// Add a text note to a NOTAM
    func setNote(_ note: String?, for notam: Notam) {
        guard let briefingId else { return }

        var annotation = annotations[notam.id] ?? NotamAnnotation(
            notamId: notam.id,
            briefingId: briefingId,
            status: .unread
        )
        annotation.textNote = note
        annotation.updatedAt = Date()

        annotations[notam.id] = annotation

        // Persist
        Task {
            await annotationStore.saveAnnotation(annotation)
        }
    }

    /// Mark a NOTAM as read
    func markAsRead(_ notam: Notam) {
        if annotation(for: notam)?.status == .unread {
            setStatus(.read, for: notam)
        }
    }

    /// Toggle important status
    func toggleImportant(_ notam: Notam) {
        let current = annotation(for: notam)?.status ?? .unread
        let newStatus: NotamStatus = (current == .important) ? .read : .important
        setStatus(newStatus, for: notam)
    }

    /// Mark NOTAM as ignored
    func markAsIgnored(_ notam: Notam) {
        setStatus(.ignore, for: notam)
    }
}
