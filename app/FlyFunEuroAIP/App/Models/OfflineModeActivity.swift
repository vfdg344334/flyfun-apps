//
//  OfflineModeActivity.swift
//  FlyFunEuroAIP
//
//  Live Activity attributes for offline mode Dynamic Island display.
//  This file should be included in BOTH the main app and widget extension targets.
//

import ActivityKit
import Foundation

/// Attributes for the offline mode Live Activity
/// This struct is shared between the main app and widget extension
public struct OfflineModeActivityAttributes: ActivityAttributes {
    
    /// Content state that can change during the activity
    public struct ContentState: Codable, Hashable {
        /// Whether currently processing a query
        public var isProcessing: Bool
        /// Current status message
        public var statusMessage: String
        /// Progress (0.0 to 1.0) for model loading or query processing
        public var progress: Double?
        
        public init(isProcessing: Bool, statusMessage: String, progress: Double? = nil) {
            self.isProcessing = isProcessing
            self.statusMessage = statusMessage
            self.progress = progress
        }
    }
    
    /// Static attributes that don't change
    public var modelName: String
    public var startTime: Date
    
    public init(modelName: String, startTime: Date) {
        self.modelName = modelName
        self.startTime = startTime
    }
}
