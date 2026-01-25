//
//  BriefingDomain.swift
//  FlyFunBrief
//
//  Manages current briefing state, parsing, and import handling.
//

import Foundation
import RZFlight
import OSLog

/// Domain for briefing state management
@Observable
@MainActor
final class BriefingDomain {
    // MARK: - State

    /// Currently loaded briefing
    private(set) var currentBriefing: Briefing?

    /// Whether a briefing is being imported/parsed
    private(set) var isLoading = false

    /// Progress of current import (0-1)
    private(set) var importProgress: Double = 0

    /// Error from last import attempt
    private(set) var lastError: Error?

    /// Route summary for display
    var routeSummary: String? {
        guard let route = currentBriefing?.route else { return nil }
        return "\(route.departure) \u{2192} \(route.destination)"
    }

    /// Total NOTAM count
    var notamCount: Int {
        currentBriefing?.notams.count ?? 0
    }

    // MARK: - Callbacks

    /// Called when a briefing is successfully loaded
    var onBriefingLoaded: ((Briefing) -> Void)?

    /// Called when briefing is cleared
    var onBriefingCleared: (() -> Void)?

    // MARK: - Dependencies

    private let service: BriefingService

    // MARK: - Init

    init(service: BriefingService) {
        self.service = service
    }

    // MARK: - Actions

    /// Import a briefing from a PDF file URL
    func importBriefing(from url: URL) async {
        Logger.app.info("Importing briefing from: \(url.path)")

        isLoading = true
        importProgress = 0
        lastError = nil

        defer {
            isLoading = false
            importProgress = 1
        }

        do {
            // Read the file
            importProgress = 0.1
            let pdfData = try Data(contentsOf: url)

            // Parse via API
            importProgress = 0.3
            let briefing = try await service.parseBriefing(pdfData: pdfData, source: "foreflight")

            // Update state
            importProgress = 0.9
            currentBriefing = briefing
            onBriefingLoaded?(briefing)

            Logger.app.info("Successfully imported briefing with \(briefing.notams.count) NOTAMs")

        } catch {
            Logger.app.error("Failed to import briefing: \(error.localizedDescription)")
            lastError = error
        }
    }

    /// Import a briefing from PDF data (from share extension)
    func importBriefing(data: Data, source: String = "foreflight") async {
        Logger.app.info("Importing briefing from data (\(data.count) bytes)")

        isLoading = true
        importProgress = 0
        lastError = nil

        defer {
            isLoading = false
            importProgress = 1
        }

        do {
            importProgress = 0.3
            let briefing = try await service.parseBriefing(pdfData: data, source: source)

            importProgress = 0.9
            currentBriefing = briefing
            onBriefingLoaded?(briefing)

            Logger.app.info("Successfully imported briefing with \(briefing.notams.count) NOTAMs")

        } catch {
            Logger.app.error("Failed to import briefing: \(error.localizedDescription)")
            lastError = error
        }
    }

    /// Clear the current briefing
    func clearBriefing() {
        currentBriefing = nil
        lastError = nil
        onBriefingCleared?()
    }
}
