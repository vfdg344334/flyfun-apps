//
//  FilterPanelView.swift
//  FlyFunBrief
//
//  Smart filter panel for NOTAM filtering with route corridor support.
//

import SwiftUI
import RZFlight

/// Panel for configuring NOTAM filters
struct FilterPanelView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                routeSection
                timeSection
                smartFiltersSection
                categorySection
                statusSection
                visibilitySection
                groupingSection
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        appState?.notams.resetFilters()
                    }
                }
            }
        }
    }

    // MARK: - Route Section

    private var routeSection: some View {
        Section {
            Toggle("Filter by Route", isOn: routeEnabledBinding)

            if appState?.notams.routeFilter.isEnabled == true {
                TextField("ICAO codes (e.g., LFPG EGLL)", text: routeStringBinding)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())

                VStack(alignment: .leading, spacing: 8) {
                    Text("Corridor Width: \(Int(appState?.notams.routeFilter.corridorWidthNm ?? 25)) nm")
                        .font(.subheadline)

                    Picker("Distance", selection: corridorWidthBinding) {
                        Text("10 nm").tag(10.0)
                        Text("25 nm").tag(25.0)
                        Text("50 nm").tag(50.0)
                        Text("100 nm").tag(100.0)
                    }
                    .pickerStyle(.segmented)
                }

                if let codes = appState?.notams.routeFilter.icaoCodes, !codes.isEmpty {
                    HStack {
                        Text("Route:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(codes.joined(separator: " → "))
                            .font(.caption.monospaced())
                    }
                }
            }
        } header: {
            Label("Route Corridor", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
        } footer: {
            Text("Show only NOTAMs within the corridor distance of your route.")
        }
    }

    // MARK: - Time Section

    private var timeSection: some View {
        Section {
            Toggle("Active at Flight Time", isOn: timeEnabledBinding)

            if appState?.notams.timeFilter.isEnabled == true {
                if let route = appState?.briefing.currentBriefing?.route,
                   let depTime = route.departureTime {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(formatDateTime(depTime), systemImage: "airplane.departure")
                            .font(.subheadline)
                        if let arrTime = route.arrivalTime {
                            Label(formatDateTime(arrTime), systemImage: "airplane.arrival")
                                .font(.subheadline)
                        }
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Text("No flight time available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("Time Filter", systemImage: "clock")
        } footer: {
            Text("Show only NOTAMs that are active during the flight time window.")
        }
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM HH:mm 'UTC'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    // MARK: - Smart Filters Section

    private var smartFiltersSection: some View {
        Section {
            // Helicopter filter
            Toggle("Hide Helicopter NOTAMs", isOn: hideHelicopterBinding)

            // Obstacle filter
            Toggle("Smart Obstacle Filter", isOn: filterObstaclesBinding)

            if appState?.notams.smartFilters.filterObstacles == true {
                HStack {
                    Text("Show within")
                    Picker("Distance", selection: obstacleDistanceBinding) {
                        Text("1 nm").tag(1.0)
                        Text("2 nm").tag(2.0)
                        Text("5 nm").tag(5.0)
                        Text("10 nm").tag(10.0)
                    }
                    .pickerStyle(.menu)
                    Text("of airports")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            // Scope filter
            Picker("Scope", selection: scopeFilterBinding) {
                ForEach(ScopeFilter.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
        } header: {
            Label("Smart Filters", systemImage: "sparkles")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if appState?.notams.smartFilters.hideHelicopter == true {
                    Text("Helicopter NOTAMs (heliports, FATO, windsocks) are hidden")
                }
                if appState?.notams.smartFilters.filterObstacles == true {
                    Text("Obstacles shown only near departure/destination")
                }
            }
            .font(.caption)
        }
    }

    // MARK: - Category Section

    private var categorySection: some View {
        Section {
            // AGA Categories (Aerodrome Ground Aids)
            DisclosureGroup("AGA - Ground") {
                CategoryToggleRow(label: "Movement Area", systemImage: NotamCategory.agaMovement.icon, isOn: categoryBinding(\.showMovement))
                CategoryToggleRow(label: "Lighting", systemImage: NotamCategory.agaLighting.icon, isOn: categoryBinding(\.showLighting))
                CategoryToggleRow(label: "Facilities", systemImage: NotamCategory.agaFacilities.icon, isOn: categoryBinding(\.showFacilities))
            }

            // CNS Categories (Communications, Navigation, Surveillance)
            DisclosureGroup("CNS - Navigation") {
                CategoryToggleRow(label: "Navigation", systemImage: NotamCategory.navigation.icon, isOn: categoryBinding(\.showNavigation))
                CategoryToggleRow(label: "ILS/MLS", systemImage: NotamCategory.cnsILS.icon, isOn: categoryBinding(\.showILS))
                CategoryToggleRow(label: "GNSS", systemImage: NotamCategory.cnsGNSS.icon, isOn: categoryBinding(\.showGNSS))
                CategoryToggleRow(label: "Communications", systemImage: NotamCategory.cnsCommunications.icon, isOn: categoryBinding(\.showCommunications))
            }

            // ATM Categories (Air Traffic Management)
            DisclosureGroup("ATM - Traffic") {
                CategoryToggleRow(label: "Airspace", systemImage: NotamCategory.atmAirspace.icon, isOn: categoryBinding(\.showAirspace))
                CategoryToggleRow(label: "Procedures", systemImage: NotamCategory.atmProcedures.icon, isOn: categoryBinding(\.showProcedures))
                CategoryToggleRow(label: "Services", systemImage: NotamCategory.atmServices.icon, isOn: categoryBinding(\.showServices))
                CategoryToggleRow(label: "Restrictions", systemImage: NotamCategory.airspaceRestrictions.icon, isOn: categoryBinding(\.showRestrictions))
            }

            // Other
            CategoryToggleRow(label: "Other Info", systemImage: NotamCategory.otherInfo.icon, isOn: categoryBinding(\.showOther))
        } header: {
            HStack {
                Label("ICAO Categories", systemImage: "tag")
                Spacer()
                if appState?.notams.categoryFilter.allEnabled == false {
                    Button("All") {
                        appState?.notams.categoryFilter.enableAll()
                    }
                    .font(.caption)
                }
            }
        } footer: {
            Text("Categories based on ICAO Q-code subject classification")
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        Section {
            Picker("Status", selection: statusFilterBinding) {
                ForEach(StatusFilter.allCases) { status in
                    Text(status.rawValue).tag(status)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Label("Status Filter", systemImage: "checklist")
        }
    }

    // MARK: - Visibility Section

    private var visibilitySection: some View {
        Section {
            Toggle("Show Read", isOn: showReadBinding)
            Toggle("Show Ignored", isOn: showIgnoredBinding)
        } header: {
            Label("Visibility", systemImage: "eye")
        }
    }

    // MARK: - Grouping Section

    private var groupingSection: some View {
        Section {
            Picker("Group By", selection: groupingBinding) {
                ForEach(NotamGrouping.allCases) { grouping in
                    Label(grouping.rawValue, systemImage: grouping.icon)
                        .tag(grouping)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Label("Grouping", systemImage: "rectangle.3.group")
        } footer: {
            if appState?.notams.grouping == .routeOrder {
                Text("NOTAMs sorted by position along your route: Departure → En Route → Destination → Alternates → Distant → No Coordinates")
            }
        }
    }

    // MARK: - Bindings

    private var routeEnabledBinding: Binding<Bool> {
        Binding(
            get: { appState?.notams.routeFilter.isEnabled ?? false },
            set: { appState?.notams.routeFilter.isEnabled = $0 }
        )
    }

    private var routeStringBinding: Binding<String> {
        Binding(
            get: { appState?.notams.routeFilter.routeString ?? "" },
            set: { appState?.notams.routeFilter.routeString = $0 }
        )
    }

    private var corridorWidthBinding: Binding<Double> {
        Binding(
            get: { appState?.notams.routeFilter.corridorWidthNm ?? 25 },
            set: { appState?.notams.routeFilter.corridorWidthNm = $0 }
        )
    }

    private var timeEnabledBinding: Binding<Bool> {
        Binding(
            get: { appState?.notams.timeFilter.isEnabled ?? false },
            set: { appState?.notams.timeFilter.isEnabled = $0 }
        )
    }

    private func categoryBinding(_ keyPath: WritableKeyPath<CategoryFilter, Bool>) -> Binding<Bool> {
        Binding(
            get: { appState?.notams.categoryFilter[keyPath: keyPath] ?? true },
            set: { appState?.notams.categoryFilter[keyPath: keyPath] = $0 }
        )
    }

    private var statusFilterBinding: Binding<StatusFilter> {
        Binding(
            get: { appState?.notams.statusFilter ?? .all },
            set: { appState?.notams.statusFilter = $0 }
        )
    }

    private var showReadBinding: Binding<Bool> {
        Binding(
            get: { appState?.notams.visibilityFilter.showRead ?? true },
            set: { appState?.notams.visibilityFilter.showRead = $0 }
        )
    }

    private var showIgnoredBinding: Binding<Bool> {
        Binding(
            get: { appState?.notams.visibilityFilter.showIgnored ?? false },
            set: { appState?.notams.visibilityFilter.showIgnored = $0 }
        )
    }

    private var groupingBinding: Binding<NotamGrouping> {
        Binding(
            get: { appState?.notams.grouping ?? .airport },
            set: { appState?.notams.grouping = $0 }
        )
    }

    // MARK: - Smart Filter Bindings

    private var hideHelicopterBinding: Binding<Bool> {
        Binding(
            get: { appState?.notams.smartFilters.hideHelicopter ?? true },
            set: { appState?.notams.smartFilters.hideHelicopter = $0 }
        )
    }

    private var filterObstaclesBinding: Binding<Bool> {
        Binding(
            get: { appState?.notams.smartFilters.filterObstacles ?? true },
            set: { appState?.notams.smartFilters.filterObstacles = $0 }
        )
    }

    private var obstacleDistanceBinding: Binding<Double> {
        Binding(
            get: { appState?.notams.smartFilters.obstacleDistanceNm ?? 2.0 },
            set: { appState?.notams.smartFilters.obstacleDistanceNm = $0 }
        )
    }

    private var scopeFilterBinding: Binding<ScopeFilter> {
        Binding(
            get: { appState?.notams.smartFilters.scopeFilter ?? .all },
            set: { appState?.notams.smartFilters.scopeFilter = $0 }
        )
    }
}

// MARK: - Category Toggle Row

struct CategoryToggleRow: View {
    let label: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label(label, systemImage: systemImage)
        }
    }
}

// MARK: - Compact Filter Bar (for inline use)

struct CompactFilterBar: View {
    @Environment(\.appState) private var appState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Active filter chips
                if appState?.notams.routeFilter.isEnabled == true {
                    FilterChip(
                        label: "Route: \(Int(appState?.notams.routeFilter.corridorWidthNm ?? 25))nm",
                        isActive: true
                    ) {
                        appState?.notams.routeFilter.isEnabled = false
                    }
                }

                if appState?.notams.statusFilter != .all {
                    FilterChip(
                        label: appState?.notams.statusFilter.rawValue ?? "",
                        isActive: true
                    ) {
                        appState?.notams.statusFilter = .all
                    }
                }

                if appState?.notams.categoryFilter.allEnabled == false {
                    FilterChip(
                        label: "Categories",
                        isActive: true
                    ) {
                        appState?.notams.categoryFilter.enableAll()
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

struct FilterChip: View {
    let label: String
    let isActive: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isActive ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
        .foregroundStyle(isActive ? .primary : .secondary)
        .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview {
    FilterPanelView()
        .environment(\.appState, AppState.preview())
}
