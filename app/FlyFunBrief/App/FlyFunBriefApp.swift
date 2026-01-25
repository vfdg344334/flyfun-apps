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
    private func handleOpenURL(_ url: URL) {
        Logger.app.info("Received deep link: \(url.absoluteString)")

        // Check if this is a briefing import request
        // URL format: flyfunbrief://import/<encoded-file-path>
        guard url.scheme == "flyfunbrief" else { return }

        // The path contains the file path (URL encoded)
        // Remove the leading "/import" or just "/" prefix
        var filePath = url.path
        if filePath.hasPrefix("/import") {
            filePath = String(filePath.dropFirst("/import".count))
        }

        // Decode percent encoding
        guard let decodedPath = filePath.removingPercentEncoding,
              !decodedPath.isEmpty else {
            Logger.app.error("Invalid deep link path: \(url.path)")
            return
        }

        let fileURL = URL(fileURLWithPath: decodedPath)
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
        }
    }
}

// MARK: - Logger Extension

extension Logger {
    static let app = Logger(subsystem: "com.ro-z.flyfunbrief", category: "app")
    static let network = Logger(subsystem: "com.ro-z.flyfunbrief", category: "network")
    static let ui = Logger(subsystem: "com.ro-z.flyfunbrief", category: "ui")
}
