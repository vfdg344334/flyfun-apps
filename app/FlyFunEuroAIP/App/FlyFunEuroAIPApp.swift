//
//  FlyFunEuroAIPApp.swift
//  FlyFunEuroAIP
//
//  Created by Brice Rosenzweig on 26/10/2025.
//

import SwiftUI
import RZUtilsSwift
import RZFlight
import FMDB
import OSLog

extension Notification.Name {
    static let initializationCompleted = Notification.Name("initializationCompleted")
}

@main
struct FlyFunEuroAIPApp: App {
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - Swift Concurrency: Actor-based App Model
/// Actor isolates mutable state from concurrent access
/// All methods are implicitly async and isolated to the actor
final class AppModel{
    static let shared = AppModel()
   
    var db : FMDatabase?
    var knownAirports: KnownAirports?
    var isLoading = true
    var loadError: Error?
    
    private init() {
        // Start async initialization
        Task {
            await initializeResources()
        }
    }
   
    init(db: FMDatabase, knownAirports: KnownAirports) {
        self.db = db
        self.knownAirports = knownAirports
        self.isLoading = false
    }
    
    /// Async initialization runs off the main actor by default
    /// but we update @Published properties on MainActor
    private func initializeResources() async {
        Logger.app.info("Starting async initialization")
        
        do {
            // STEP 1: Initialize database on dedicated actor/queue
            let db = try await initializeDatabase()
            
            // STEP 2: Initialize KnownAirports using the database
            let airports = try await initializeKnownAirports(db: db)
            
            // Update UI on MainActor (this method is already @MainActor)
            self.db = db
            self.knownAirports = airports
            self.isLoading = false
            
            Logger.app.info("Async initialization complete")
            
            // Post notification AFTER initialization is complete
            NotificationCenter.default.post(name: .initializationCompleted, object: nil)
        } catch {
            Logger.app.error("Initialization error: \(error.localizedDescription)")
            self.loadError = error
            self.isLoading = false
        }
    }
    
    private func initializeDatabase() async throws -> FMDatabase {
        Logger.app.info("Initializing database...")
        
        let db = FMDatabase(path: Bundle.main.path(forResource: "airports", ofType: "db"))
        if !db.open() {
            throw AppInitError.badDatabaseFile
        }
        return db
    }
    
    /// Background task: Uses database actor for thread-safe access
    /// DEPENDS ON: Database must be initialized first
    private func initializeKnownAirports(db: FMDatabase) async throws -> KnownAirports {
        Logger.app.info("Loading KnownAirports...")
        let known = KnownAirports(db: db)
        return known
    }
}

// MARK: - Custom Error
enum AppInitError: Error, LocalizedError {
    case notImplemented(String)
    case databaseNotReady
    case badDatabaseFile
    
    var errorDescription: String? {
        switch self {
        case .notImplemented(let component):
            return "\(component) not yet implemented"
        case .databaseNotReady:
            return "Database not initialized"
        case .badDatabaseFile:
            return "Bad database file"
        }
    }
}
