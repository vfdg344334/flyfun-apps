//
//  AirportMapViewModel.swift
//  FlyFunEuroAIP
//
//  Created by Brice Rosenzweig on 02/11/2025.
//

import SwiftUI
import MapKit
import RZFlight
internal import Combine
import OSLog
import RZUtilsSwift

@MainActor
final class AirportMapViewModel: ObservableObject {
    // MARK: - Published Properties
    
    // Search state
    @Published var searchText: String = ""
    @Published var isSearchExpanded: Bool = false
    
    // Filter state
    @Published var isFilterExpanded: Bool = false
    @Published var showInternationalOnly: Bool = false
    @Published var minRunwayLength: Double = 0
    
    // Map state
    @Published var mapPosition: MapCameraPosition
    @Published var airports: [Airport] = []
    
    // MARK: - Dependencies
    private let appModel : AppModel
    private var notificationObserver: NSObjectProtocol?
    
    // MARK: - Initialization
    init(appModel : AppModel? = nil) {
        if let appModel {
            self.appModel = appModel
        }else{
            self.appModel = AppModel.shared
        }
        // Initialize map to show Europe
        self.mapPosition = .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 40.0, longitude: -30.0),
                span: MKCoordinateSpan(latitudeDelta: 60, longitudeDelta: 120)
            )
        )
        
        // Listen for initialization completion
        setupNotifications()
    }
    
    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Setup
    private func setupNotifications() {
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .initializationCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.loadAirports()
            }
        }
        
        // Also check if already initialized
        if !appModel.isLoading {
            Task { @MainActor in
                await loadAirports()
            }
        }
    }
    
    // MARK: - Computed Properties
    var filteredAirports: [Airport] {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return airports }
        return airports.filter { airport in
            airport.name.localizedCaseInsensitiveContains(text) ||
            airport.icao.localizedCaseInsensitiveContains(text)
        }
    }
    
    // MARK: - Public Methods
    
    /// Focus the map on a specific airport
    func focus(on airport: Airport) {
        withAnimation(.snappy) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: airport.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 2.0, longitudeDelta: 2.0)
                )
            )
        }
        isSearchExpanded = false
    }
    
    /// Reset all filters
    func resetFilters() {
        showInternationalOnly = false
        minRunwayLength = 0
    }
    
    // MARK: - Private Methods
    
    /// Load airports from AppModel
    private func loadAirports() async {
        let _ = Settings.shared
        guard let knownAirports = appModel.knownAirports else {
            Logger.app.warning("AppModel.knownAirports is nil, airports not loaded yet")
            return
        }
        
        Logger.app.info("Loading airports from KnownAirports")
        
        self.airports = knownAirports.airportsWithBorderCrossing().compactMap { airport in
            Airport(
                name: airport.name,
                icao: airport.icao,
                coordinate: airport.coord
            )
        }
        
        Logger.app.info("Loaded \(airports.count) airports")
    }
}

// MARK: - Airport Model
/// UI-friendly airport representation
struct Airport: Identifiable, Equatable, Hashable {
    let id = UUID()
    let name: String
    let icao: String
    let coordinate: CLLocationCoordinate2D
    
    static func == (lhs: Airport, rhs: Airport) -> Bool {
        lhs.icao == rhs.icao
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(icao)
    }
    
    // Convenience for display
    var iata: String {
        icao  // Using ICAO as the display code
    }
}



