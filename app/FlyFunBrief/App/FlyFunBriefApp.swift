//
//  FlyFunBriefApp.swift
//  FlyFunBrief
//
//  iOS app for reviewing ForeFlight briefings with NOTAM management.
//

import SwiftUI
import OSLog

@main
struct FlyFunBriefApp: App {

    @State private var appState = AppState()

    /// App Group identifier for sharing data with extension
    private let appGroupId = "group.net.ro-z.flyfunbrief"

    /// UserDefaults key for pending import path
    private let pendingImportKey = "pendingBriefingImportPath"

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.appState, appState)
                .onOpenURL { url in
                    handleOpenURL(url)
                }
        }
    }

    /// Handle deep links from share extension
    /// URL format: flyfunbrief://import?path=<encoded-file-path>
    private func handleOpenURL(_ url: URL) {
        Logger.app.info("Received deep link: \(url.absoluteString)")

        guard url.scheme == "flyfunbrief" else { return }

        // Parse query parameter for file path
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let pathParam = components.queryItems?.first(where: { $0.name == "path" })?.value,
              !pathParam.isEmpty else {
            Logger.app.error("Invalid deep link - missing path parameter: \(url.absoluteString)")
            return
        }

        importBriefing(fromPath: pathParam)
    }

    /// Check for pending imports from share extension (fallback mechanism)
    func checkForPendingImports() {
        guard let defaults = UserDefaults(suiteName: appGroupId) else {
            Logger.app.warning("Could not access shared UserDefaults")
            return
        }

        guard let pendingPath = defaults.string(forKey: pendingImportKey),
              !pendingPath.isEmpty else {
            return
        }

        Logger.app.info("Found pending import: \(pendingPath)")

        // Clear the pending import immediately to prevent double-import
        defaults.removeObject(forKey: pendingImportKey)
        defaults.synchronize()

        importBriefing(fromPath: pendingPath)
    }

    /// Import briefing from a file path
    private func importBriefing(fromPath path: String) {
        let fileURL = URL(fileURLWithPath: path)

        // Verify file exists
        guard FileManager.default.fileExists(atPath: path) else {
            Logger.app.error("Briefing file not found: \(path)")
            return
        }

        Logger.app.info("Importing briefing from: \(fileURL.path)")

        Task {
            await appState.briefing.importBriefing(from: fileURL)
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @Environment(\.appState) private var appState
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// App Group identifier for sharing data with extension
    private let appGroupId = "group.net.ro-z.flyfunbrief"

    /// UserDefaults key for pending import path
    private let pendingImportKey = "pendingBriefingImportPath"

    var body: some View {
        Group {
            if sizeClass == .compact {
                iPhoneLayoutView()
            } else {
                iPadLayoutView()
            }
        }
        .task {
            await appState?.onAppear()

            // Check for pending imports from share extension
            checkForPendingImports()
        }
    }

    /// Check for pending imports from share extension (fallback mechanism)
    private func checkForPendingImports() {
        guard let defaults = UserDefaults(suiteName: appGroupId) else {
            Logger.app.warning("Could not access shared UserDefaults")
            return
        }

        guard let pendingPath = defaults.string(forKey: pendingImportKey),
              !pendingPath.isEmpty else {
            return
        }

        Logger.app.info("Found pending import: \(pendingPath)")

        // Clear the pending import immediately to prevent double-import
        defaults.removeObject(forKey: pendingImportKey)
        defaults.synchronize()

        // Verify file exists
        guard FileManager.default.fileExists(atPath: pendingPath) else {
            Logger.app.error("Briefing file not found: \(pendingPath)")
            return
        }

        let fileURL = URL(fileURLWithPath: pendingPath)
        Logger.app.info("Importing briefing from: \(fileURL.path)")

        Task {
            await appState?.briefing.importBriefing(from: fileURL)
        }
    }
}

// MARK: - Logger Extension

extension Logger {
    static let app = Logger(subsystem: "com.ro-z.flyfunbrief", category: "app")
    static let network = Logger(subsystem: "com.ro-z.flyfunbrief", category: "network")
    static let ui = Logger(subsystem: "com.ro-z.flyfunbrief", category: "ui")
}
