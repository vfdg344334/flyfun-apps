//
//  NotamDomain.swift
//  FlyFunBrief
//
//  Manages NOTAM list, filtering, and user annotations.
//

import Foundation
import RZFlight
import CoreLocation
import OSLog

/// Status filter options
enum StatusFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case unread = "Unread"
    case important = "Important"
    case followUp = "Follow Up"

    var id: String { rawValue }
}

/// Grouping options for NOTAM list
enum NotamGrouping: String, CaseIterable, Identifiable {
    case none = "None"
    case airport = "Airport"
    case category = "Category"
    case routeOrder = "Route Order"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .none: return "list.bullet"
        case .airport: return "building.2"
        case .category: return "folder"
        case .routeOrder: return "point.topleft.down.to.point.bottomright.curvepath"
        }
    }
}

/// Route corridor filter configuration
struct RouteFilter: Equatable {
    /// Space-separated ICAO codes defining the route
    var routeString: String = ""

    /// Corridor half-width in nautical miles
    var corridorWidthNm: Double = 25

    /// Whether route filtering is enabled
    var isEnabled: Bool = false

    /// Parsed ICAO codes
    var icaoCodes: [String] {
        routeString
            .uppercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && $0.count <= 4 }
    }
}

/// Category filter - which NOTAM categories to show
struct CategoryFilter: Equatable {
    var showRunway: Bool = true
    var showNavigation: Bool = true
    var showAirspace: Bool = true
    var showObstacle: Bool = true
    var showProcedure: Bool = true
    var showLighting: Bool = true
    var showServices: Bool = true
    var showOther: Bool = true

    /// Returns enabled categories
    var enabledCategories: Set<NotamCategory> {
        var categories: Set<NotamCategory> = []
        if showRunway { categories.insert(.runway) }
        if showNavigation { categories.insert(.navigation) }
        if showAirspace { categories.insert(.airspace) }
        if showObstacle { categories.insert(.obstacle) }
        if showProcedure { categories.insert(.procedure) }
        if showLighting { categories.insert(.lighting) }
        if showServices { categories.insert(.services) }
        if showOther { categories.insert(.other) }
        return categories
    }

    /// Whether all categories are enabled
    var allEnabled: Bool {
        showRunway && showNavigation && showAirspace && showObstacle &&
        showProcedure && showLighting && showServices && showOther
    }

    /// Enable all categories
    mutating func enableAll() {
        showRunway = true
        showNavigation = true
        showAirspace = true
        showObstacle = true
        showProcedure = true
        showLighting = true
        showServices = true
        showOther = true
    }
}

/// Visibility filter - which statuses to show/hide
struct VisibilityFilter: Equatable {
    var showIgnored: Bool = false
    var showRead: Bool = true
}

/// Time filter - filter NOTAMs by validity at flight time
struct TimeFilter: Equatable {
    /// Whether time filtering is enabled
    var isEnabled: Bool = false

    /// Buffer time before departure (minutes)
    var preFlightBufferMinutes: Int = 60

    /// Buffer time after arrival (minutes)
    var postFlightBufferMinutes: Int = 60
}

/// Domain for NOTAM list management
@Observable
@MainActor
final class NotamDomain {
    // MARK: - State

    /// All NOTAMs from current briefing
    private(set) var allNotams: [Notam] = []

    /// Enriched NOTAMs with status (for display)
    private(set) var enrichedNotams: [EnrichedNotam] = []

    /// Current route from briefing (for spatial filtering)
    private(set) var currentRoute: Route?

    /// Briefing ID for current set of NOTAMs
    private(set) var briefingId: String?

    /// Current Core Data briefing (if available)
    private(set) var currentCDBriefing: CDBriefing?

    /// Currently selected NOTAM for detail view
    var selectedNotam: Notam?

    /// Currently selected enriched NOTAM
    var selectedEnrichedNotam: EnrichedNotam?

    /// Current grouping
    var grouping: NotamGrouping = .airport

    /// Text search query
    var searchQuery: String = ""

    /// User annotations keyed by NOTAM ID (legacy FMDB storage)
    private(set) var annotations: [String: NotamAnnotation] = [:]

    /// Identity keys from previous briefings (for new NOTAM detection)
    private(set) var previousIdentityKeys: Set<String> = []

    /// Globally ignored identity keys
    private(set) var ignoredIdentityKeys: Set<String> = []

    // MARK: - Filter State

    /// Route corridor filter
    var routeFilter = RouteFilter()

    /// Category filter
    var categoryFilter = CategoryFilter()

    /// Status filter
    var statusFilter: StatusFilter = .all

    /// Visibility filter
    var visibilityFilter = VisibilityFilter()

    /// Time filter - filter by validity at flight time
    var timeFilter = TimeFilter()

    /// Airport coordinates for route filtering (populated from briefing or external source)
    var airportCoordinates: [String: CLLocationCoordinate2D] = [:]

    // MARK: - Computed Properties

    /// Whether any filters are active
    var hasActiveFilters: Bool {
        routeFilter.isEnabled ||
        !categoryFilter.allEnabled ||
        statusFilter != .all ||
        !visibilityFilter.showRead ||
        visibilityFilter.showIgnored ||
        timeFilter.isEnabled ||
        !searchQuery.isEmpty
    }

    /// Filtered and sorted NOTAMs based on current settings
    var filteredNotams: [Notam] {
        var notams = allNotams

        // 1. Apply route corridor filter
        if routeFilter.isEnabled && !routeFilter.icaoCodes.isEmpty {
            if let route = currentRoute {
                // Use route from briefing
                notams = notams.alongRoute(route, withinNm: routeFilter.corridorWidthNm)
            } else if !airportCoordinates.isEmpty {
                // Use manually entered route with coordinates
                notams = notams.alongRoute(
                    icaoCodes: routeFilter.routeString,
                    withinNm: routeFilter.corridorWidthNm,
                    airportCoordinates: airportCoordinates
                )
            }
        }

        // 2. Apply category filter
        if !categoryFilter.allEnabled {
            let enabled = categoryFilter.enabledCategories
            notams = notams.filter { notam in
                guard let category = notam.category else { return categoryFilter.showOther }
                return enabled.contains(category)
            }
        }

        // 3. Apply text search
        if !searchQuery.isEmpty {
            notams = notams.containing(searchQuery)
        }

        // 4. Apply status filter
        switch statusFilter {
        case .all:
            break
        case .unread:
            notams = notams.filter { annotation(for: $0)?.status == .unread }
        case .important:
            notams = notams.filter { annotation(for: $0)?.status == .important }
        case .followUp:
            notams = notams.filter { annotation(for: $0)?.status == .followUp }
        }

        // 5. Apply visibility filter
        if !visibilityFilter.showIgnored {
            notams = notams.filter { annotation(for: $0)?.status != .ignore }
        }
        if !visibilityFilter.showRead {
            notams = notams.filter { annotation(for: $0)?.status != .read }
        }

        return notams
    }

    /// Filtered enriched NOTAMs based on current settings
    var filteredEnrichedNotams: [EnrichedNotam] {
        var notams = enrichedNotams

        // 1. Apply global ignore filter first (unless showing ignored)
        if !visibilityFilter.showIgnored {
            notams = notams.excludingIgnored()
        }

        // 2. Apply route corridor filter (filter underlying Notam objects)
        if routeFilter.isEnabled && !routeFilter.icaoCodes.isEmpty {
            let routeFilteredIds: Set<String>
            if let route = currentRoute {
                routeFilteredIds = Set(allNotams.alongRoute(route, withinNm: routeFilter.corridorWidthNm).map { $0.id })
            } else if !airportCoordinates.isEmpty {
                routeFilteredIds = Set(allNotams.alongRoute(
                    icaoCodes: routeFilter.routeString,
                    withinNm: routeFilter.corridorWidthNm,
                    airportCoordinates: airportCoordinates
                ).map { $0.id })
            } else {
                routeFilteredIds = Set(allNotams.map { $0.id })
            }
            notams = notams.filter { routeFilteredIds.contains($0.notamId) }
        }

        // 3. Apply time filter (filter by validity at flight time)
        if timeFilter.isEnabled, let route = currentRoute, let depTime = route.departureTime {
            let preBuffer = TimeInterval(timeFilter.preFlightBufferMinutes * 60)
            let postBuffer = TimeInterval(timeFilter.postFlightBufferMinutes * 60)
            let windowStart = depTime.addingTimeInterval(-preBuffer)
            let windowEnd = (route.arrivalTime ?? depTime).addingTimeInterval(postBuffer)

            notams = notams.filter { enriched in
                enriched.isActive(during: windowStart, to: windowEnd)
            }
        }

        // 4. Apply category filter
        if !categoryFilter.allEnabled {
            let enabled = categoryFilter.enabledCategories
            notams = notams.filter { enriched in
                guard let category = enriched.category else { return categoryFilter.showOther }
                return enabled.contains(category)
            }
        }

        // 5. Apply text search
        if !searchQuery.isEmpty {
            let searchLower = searchQuery.lowercased()
            notams = notams.filter { enriched in
                enriched.message.lowercased().contains(searchLower) ||
                enriched.notamId.lowercased().contains(searchLower) ||
                enriched.location.lowercased().contains(searchLower)
            }
        }

        // 6. Apply status filter
        switch statusFilter {
        case .all:
            break
        case .unread:
            notams = notams.filter { $0.status == .unread }
        case .important:
            notams = notams.filter { $0.status == .important }
        case .followUp:
            notams = notams.filter { $0.status == .followUp }
        }

        // 7. Apply visibility filter (local ignore status)
        if !visibilityFilter.showIgnored {
            notams = notams.filter { $0.status != .ignore }
        }
        if !visibilityFilter.showRead {
            notams = notams.filter { $0.status != .read }
        }

        return notams
    }

    /// NOTAMs grouped by airport
    var notamsGroupedByAirport: [String: [Notam]] {
        filteredNotams.groupedByAirport()
    }

    /// Enriched NOTAMs grouped by airport
    var enrichedNotamsGroupedByAirport: [String: [EnrichedNotam]] {
        filteredEnrichedNotams.groupedByAirport()
    }

    /// NOTAMs grouped by category
    var notamsGroupedByCategory: [NotamCategory: [Notam]] {
        filteredNotams.groupedByCategory()
    }

    /// Enriched NOTAMs grouped by category
    var enrichedNotamsGroupedByCategory: [NotamCategory: [EnrichedNotam]] {
        filteredEnrichedNotams.groupedByCategory()
    }

    /// Enriched NOTAMs grouped by route segment
    ///
    /// Returns NOTAMs organized by: Departure, En Route (sorted by distance), Destination,
    /// Alternates, Distant (>50nm), No Coordinates
    var enrichedNotamsGroupedByRouteSegment: [(segment: NotamRouteClassification.RouteSegment, notams: [EnrichedNotam])] {
        guard let route = currentRoute else {
            // No route - put everything in noCoordinate segment
            return [(.noCoordinate, filteredEnrichedNotams)]
        }

        // Classify underlying NOTAMs
        let notamArray = filteredEnrichedNotams.map { $0.notam }
        let classified = notamArray.groupedByRouteSegment(route: route, distantThresholdNm: 50.0)

        // Map back to EnrichedNotam, preserving order
        let enrichedById = Dictionary(uniqueKeysWithValues: filteredEnrichedNotams.map { ($0.notamId, $0) })

        var result: [(NotamRouteClassification.RouteSegment, [EnrichedNotam])] = []

        // Add segments in display order
        for segment in NotamRouteClassification.RouteSegment.allCases {
            guard let items = classified[segment], !items.isEmpty else { continue }
            let enrichedItems = items.compactMap { enrichedById[$0.notam.id] }
            if !enrichedItems.isEmpty {
                result.append((segment, enrichedItems))
            }
        }

        return result
    }

    /// Count of unread NOTAMs
    var unreadCount: Int {
        enrichedNotams.unreadCount
    }

    /// Count of important NOTAMs
    var importantCount: Int {
        enrichedNotams.importantCount
    }

    /// Count of new NOTAMs (not seen in previous briefings)
    var newNotamCount: Int {
        enrichedNotams.newCount
    }

    // MARK: - Dependencies

    private let annotationStore: AnnotationStore
    private var ignoreListManager: IgnoreListManager?

    // MARK: - Init

    init(annotationStore: AnnotationStore, ignoreListManager: IgnoreListManager? = nil) {
        self.annotationStore = annotationStore
        self.ignoreListManager = ignoreListManager
    }

    /// Update the ignore list manager reference
    func setIgnoreListManager(_ manager: IgnoreListManager) {
        self.ignoreListManager = manager
    }

    // MARK: - Actions

    /// Set NOTAMs from a loaded briefing (legacy flow without Core Data)
    func setBriefing(_ briefing: Briefing) {
        self.briefingId = briefing.id
        self.allNotams = briefing.notams
        self.currentRoute = briefing.route
        self.currentCDBriefing = nil
        self.selectedNotam = nil
        self.selectedEnrichedNotam = nil
        self.previousIdentityKeys = []

        // Pre-populate route filter from briefing route
        if let route = briefing.route {
            var routeAirports = [route.departure, route.destination]
            routeAirports.append(contentsOf: route.alternates)
            routeFilter.routeString = routeAirports.joined(separator: " ")

            // Extract coordinates from route for filtering
            if let depCoord = route.departureCoordinate {
                airportCoordinates[route.departure.uppercased()] = depCoord
            }
            if let destCoord = route.destinationCoordinate {
                airportCoordinates[route.destination.uppercased()] = destCoord
            }
        }

        // Load annotations for this briefing (legacy FMDB storage)
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

            // Build enriched NOTAMs (legacy mode - no Core Data status)
            await loadIgnoredKeys()
            buildEnrichedNotams()
        }

        Logger.app.info("NotamDomain loaded \(briefing.notams.count) NOTAMs")
    }

    /// Set NOTAMs from a Core Data briefing with status tracking
    func setBriefing(_ briefing: Briefing, cdBriefing: CDBriefing, previousKeys: Set<String>) {
        self.briefingId = briefing.id
        self.allNotams = briefing.notams
        self.currentRoute = briefing.route
        self.currentCDBriefing = cdBriefing
        self.selectedNotam = nil
        self.selectedEnrichedNotam = nil
        self.previousIdentityKeys = previousKeys

        // Pre-populate route filter from briefing route
        if let route = briefing.route {
            var routeAirports = [route.departure, route.destination]
            routeAirports.append(contentsOf: route.alternates)
            routeFilter.routeString = routeAirports.joined(separator: " ")

            // Extract coordinates from route for filtering
            if let depCoord = route.departureCoordinate {
                airportCoordinates[route.departure.uppercased()] = depCoord
            }
            if let destCoord = route.destinationCoordinate {
                airportCoordinates[route.destination.uppercased()] = destCoord
            }
        }

        // Build enriched NOTAMs from Core Data statuses
        Task {
            await loadIgnoredKeys()
            buildEnrichedNotamsFromCoreData()
        }

        Logger.app.info("NotamDomain loaded \(briefing.notams.count) NOTAMs from Core Data")
    }

    /// Load globally ignored identity keys
    private func loadIgnoredKeys() async {
        guard let manager = ignoreListManager else {
            ignoredIdentityKeys = []
            return
        }

        do {
            ignoredIdentityKeys = try manager.getIgnoredIdentityKeys()
        } catch {
            Logger.app.error("Failed to load ignored keys: \(error.localizedDescription)")
            ignoredIdentityKeys = []
        }
    }

    /// Build enriched NOTAMs from legacy annotations
    private func buildEnrichedNotams() {
        enrichedNotams = allNotams.map { notam in
            let annotation = annotations[notam.id]
            let identityKey = NotamIdentity.key(for: notam)
            return EnrichedNotam(
                notam: notam,
                status: annotation?.status ?? .unread,
                textNote: annotation?.textNote,
                statusChangedAt: annotation?.statusChangedAt,
                isNew: !previousIdentityKeys.contains(identityKey),
                isGloballyIgnored: ignoredIdentityKeys.contains(identityKey)
            )
        }
    }

    /// Build enriched NOTAMs from Core Data statuses
    private func buildEnrichedNotamsFromCoreData() {
        guard let cdBriefing = currentCDBriefing else {
            buildEnrichedNotams()
            return
        }

        let statuses = cdBriefing.statusesByNotamId

        enrichedNotams = EnrichedNotam.enrich(
            notams: allNotams,
            statuses: statuses,
            previousIdentityKeys: previousIdentityKeys,
            ignoredKeys: ignoredIdentityKeys
        )
    }

    /// Refresh enriched NOTAMs (call after status changes)
    func refreshEnrichedNotams() {
        if currentCDBriefing != nil {
            buildEnrichedNotamsFromCoreData()
        } else {
            buildEnrichedNotams()
        }
    }

    /// Clear all NOTAMs
    func clearBriefing() {
        allNotams = []
        enrichedNotams = []
        currentRoute = nil
        briefingId = nil
        currentCDBriefing = nil
        selectedNotam = nil
        selectedEnrichedNotam = nil
        annotations = [:]
        airportCoordinates = [:]
        previousIdentityKeys = []
    }

    /// Reset all filters to defaults
    func resetFilters() {
        routeFilter = RouteFilter()
        categoryFilter = CategoryFilter()
        statusFilter = .all
        visibilityFilter = VisibilityFilter()
        timeFilter = TimeFilter()
        searchQuery = ""

        // Re-populate route from briefing if available
        if let route = currentRoute {
            var routeAirports = [route.departure, route.destination]
            routeAirports.append(contentsOf: route.alternates)
            routeFilter.routeString = routeAirports.joined(separator: " ")
        }
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

    /// Mark NOTAM as ignored (local status)
    func markAsIgnored(_ notam: Notam) {
        setStatus(.ignore, for: notam)
    }

    /// Add NOTAM to the global ignore list
    func addToGlobalIgnoreList(_ notam: Notam, reason: String? = nil) async {
        guard let manager = ignoreListManager else {
            Logger.app.warning("IgnoreListManager not available")
            return
        }

        do {
            _ = try manager.addToIgnoreList(notam, reason: reason)

            // Refresh ignored keys and enriched NOTAMs
            await loadIgnoredKeys()
            refreshEnrichedNotams()

            Logger.app.info("Added NOTAM \(notam.id) to global ignore list")
        } catch {
            Logger.app.error("Failed to add to ignore list: \(error.localizedDescription)")
        }
    }

    /// Remove NOTAM from the global ignore list
    func removeFromGlobalIgnoreList(_ notam: Notam) async {
        guard let manager = ignoreListManager else { return }

        let identityKey = NotamIdentity.key(for: notam)

        do {
            try manager.removeFromIgnoreList(identityKey: identityKey)

            // Refresh ignored keys and enriched NOTAMs
            await loadIgnoredKeys()
            refreshEnrichedNotams()

            Logger.app.info("Removed NOTAM \(notam.id) from global ignore list")
        } catch {
            Logger.app.error("Failed to remove from ignore list: \(error.localizedDescription)")
        }
    }

    /// Check if a NOTAM is globally ignored
    func isGloballyIgnored(_ notam: Notam) -> Bool {
        let identityKey = NotamIdentity.key(for: notam)
        return ignoredIdentityKeys.contains(identityKey)
    }
}
