//
//  LiveActivityManager.swift
//  FlyFunEuroAIP
//
//  Manages the offline mode Live Activity for Dynamic Island display.
//

import Foundation
import ActivityKit
import Combine
import RZUtilsSwift
import OSLog

/// Manages Live Activities for the app
@MainActor
final class LiveActivityManager: ObservableObject {
    
    static let shared = LiveActivityManager()
    
    @Published private(set) var isActivityActive = false
    
    private var currentActivity: Activity<OfflineModeActivityAttributes>?
    
    private init() {}
    
    // MARK: - Public API
    
    /// Start the offline mode Live Activity
    func startOfflineActivity(modelName: String) {
        // DISABLED: Dynamic Island Live Activity - using in-app banner instead
        // The in-app orange banner provides a cleaner UX without system UI overlap
        Logger.app.info("LiveActivityManager: Live Activity disabled, using in-app banner")
        return
        
        /* Original implementation disabled:
        Logger.app.info("LiveActivityManager: startOfflineActivity called for model: \(modelName)")
        
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Logger.app.warning("Live Activities are not enabled on this device")
            return
        }
        */
        
        Logger.app.info("LiveActivityManager: Activities are enabled, proceeding...")
        
        // Stop any existing activity first
        stopOfflineActivity()
        
        let attributes = OfflineModeActivityAttributes(
            modelName: modelName,
            startTime: Date()
        )
        
        let initialState = OfflineModeActivityAttributes.ContentState(
            isProcessing: false,
            statusMessage: "Ready",
            progress: nil
        )
        
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            currentActivity = activity
            isActivityActive = true
            Logger.app.info("Started offline mode Live Activity: \(activity.id)")
        } catch {
            Logger.app.error("Failed to start Live Activity: \(error.localizedDescription)")
        }
    }
    
    /// Stop the offline mode Live Activity
    func stopOfflineActivity() {
        guard let activity = currentActivity else { return }
        
        Task {
            let finalState = OfflineModeActivityAttributes.ContentState(
                isProcessing: false,
                statusMessage: "Offline mode ended",
                progress: nil
            )
            
            await activity.end(
                .init(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
            
            currentActivity = nil
            isActivityActive = false
            Logger.app.info("Stopped offline mode Live Activity")
        }
    }
    
    /// Update the activity to show processing state
    func updateProcessing(message: String, progress: Double? = nil) {
        guard let activity = currentActivity else { return }
        
        let state = OfflineModeActivityAttributes.ContentState(
            isProcessing: true,
            statusMessage: message,
            progress: progress
        )
        
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }
    
    /// Update the activity to show ready state
    func updateReady(message: String = "Ready") {
        guard let activity = currentActivity else { return }
        
        let state = OfflineModeActivityAttributes.ContentState(
            isProcessing: false,
            statusMessage: message,
            progress: nil
        )
        
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }
    
    /// End all activities (cleanup)
    func endAllActivities() {
        Task.detached(priority: .userInitiated) {
            for activity in Activity<OfflineModeActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
                Logger.app.info("Ended stale Live Activity: \(activity.id)")
            }
            await MainActor.run {
                self.currentActivity = nil
                self.isActivityActive = false
            }
        }
    }
}
