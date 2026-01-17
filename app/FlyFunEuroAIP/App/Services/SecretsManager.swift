//
//  SecretsManager.swift
//  FlyFunEuroAIP
//
//  Loads configuration from secrets.json file.
//  This file is gitignored - copy secrets.json.sample to secrets.json and fill in values.
//

import Foundation
import OSLog
import RZUtilsSwift

/// Manages loading secrets from secrets.json
/// Usage:
///   1. Copy secrets.json.sample to secrets.json
///   2. Fill in your actual values
///   3. secrets.json is gitignored and won't be committed
struct SecretsManager {
    
    // MARK: - Singleton
    
    static let shared = SecretsManager()
    
    // MARK: - Configuration Values
    
    /// Base URL for API requests (e.g., "http://localhost:8000")
    let apiBaseURL: String
    
    /// URL for authentication endpoint
    let authURL: String
    
    /// URL for model download
    let modelDownloadURL: String
    
    /// API key for model download authentication
    let modelAPIKey: String
    
    // MARK: - Defaults (used when secrets.json is missing)
    
    private static let defaults: [String: String] = [
        "api_base_url": "http://localhost:8000",
        "auth_url": "http://localhost:8000/api/auth/google/token",
        "model_download_url": "http://localhost:8000/api/models/download/model.task",
        "model_api_key": ""
    ]
    
    // MARK: - Init
    
    private init() {
        let secrets = Self.loadSecrets()
        
        self.apiBaseURL = secrets["api_base_url"] ?? Self.defaults["api_base_url"]!
        self.authURL = secrets["auth_url"] ?? Self.defaults["auth_url"]!
        self.modelDownloadURL = secrets["model_download_url"] ?? Self.defaults["model_download_url"]!
        self.modelAPIKey = secrets["model_api_key"] ?? Self.defaults["model_api_key"]!
        
        Logger.app.info("SecretsManager loaded - API: \(self.apiBaseURL)")
    }
    
    // MARK: - Loading
    
    private static func loadSecrets() -> [String: String] {
        // Try to load from bundle first (secrets.json)
        if let url = Bundle.main.url(forResource: "secrets", withExtension: "json") {
            do {
                let data = try Data(contentsOf: url)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: String] {
                    Logger.app.info("Loaded secrets from secrets.json")
                    return json
                }
            } catch {
                Logger.app.warning("Failed to parse secrets.json: \(error.localizedDescription)")
            }
        }
        
        // Fallback: try secrets.json.sample (for development)
        if let url = Bundle.main.url(forResource: "secrets.json", withExtension: "sample") {
            do {
                let data = try Data(contentsOf: url)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: String] {
                    Logger.app.warning("Using secrets.json.sample - copy to secrets.json for production")
                    return json
                }
            } catch {
                Logger.app.warning("Failed to parse secrets.json.sample: \(error.localizedDescription)")
            }
        }
        
        Logger.app.warning("No secrets.json found - using defaults")
        return [:]
    }
    
    // MARK: - Convenience URLs
    
    var apiBaseURLValue: URL? {
        URL(string: apiBaseURL)
    }
    
    var authURLValue: URL? {
        URL(string: authURL)
    }
    
    var modelDownloadURLValue: URL? {
        URL(string: modelDownloadURL)
    }
}
