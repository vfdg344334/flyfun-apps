//
//  LocationManager.swift
//  FlyFunEuroAIP
//
//  Manages location services and permission requests.
//

import Foundation
import CoreLocation
import OSLog

/// Simple location manager to handle location permissions and user location
@MainActor
@Observable
final class LocationManager: NSObject {
    
    // MARK: - Published State
    
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var userLocation: CLLocation?
    
    // MARK: - Private
    
    private let locationManager = CLLocationManager()
    private let logger = Logger(subsystem: "net.ro-z.FlyFunEuroAIP", category: "LocationManager")
    
    // MARK: - Init
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = locationManager.authorizationStatus
        logger.info("LocationManager initialized with status: \(self.authorizationStatus.rawValue)")
    }
    
    // MARK: - Public Methods
    
    /// Request location permission (when in use)
    func requestPermission() {
        logger.info("Requesting location permission")
        locationManager.requestWhenInUseAuthorization()
    }
    
    /// Start updating location
    func startUpdatingLocation() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            logger.warning("Cannot start location updates - not authorized")
            requestPermission()
            return
        }
        locationManager.startUpdatingLocation()
    }
    
    /// Stop updating location
    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }
    
    /// Request a single location update
    func requestLocation() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            logger.warning("Cannot request location - not authorized")
            requestPermission()
            return
        }
        locationManager.requestLocation()
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            if let location = locations.last {
                userLocation = location
                logger.info("Location updated: \(location.coordinate.latitude), \(location.coordinate.longitude)")
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            logger.error("Location error: \(error.localizedDescription)")
        }
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            logger.info("Authorization changed to: \(self.authorizationStatus.rawValue)")
            
            // Auto-start location updates if authorized
            if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
                startUpdatingLocation()
            }
        }
    }
}
