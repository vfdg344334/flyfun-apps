//
//  ShareViewController.swift
//  FlyFunBriefShare
//
//  Share extension for receiving PDF briefings from ForeFlight and other apps.
//

import UIKit
import UniformTypeIdentifiers
import OSLog

/// Share extension view controller for receiving PDF briefings
class ShareViewController: UIViewController {

    private let logger = Logger(subsystem: "com.ro-z.flyfunbrief.share", category: "share")

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // Set up minimal UI
        view.backgroundColor = .systemBackground

        // Process the shared items
        processSharedItems()
    }

    // MARK: - Processing

    private func processSharedItems() {
        guard let extensionContext = extensionContext,
              let inputItems = extensionContext.inputItems as? [NSExtensionItem] else {
            logger.error("No extension context or input items")
            completeWithError()
            return
        }

        // Find PDF attachments
        for item in inputItems {
            guard let attachments = item.attachments else { continue }

            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                    processPDFProvider(provider)
                    return
                }
            }
        }

        logger.error("No PDF found in shared items")
        completeWithError()
    }

    private func processPDFProvider(_ provider: NSItemProvider) {
        provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { [weak self] url, error in
            guard let self = self else { return }

            if let error = error {
                self.logger.error("Error loading PDF: \(error.localizedDescription)")
                self.completeWithError()
                return
            }

            guard let url = url else {
                self.logger.error("No URL for PDF")
                self.completeWithError()
                return
            }

            // Copy to shared container
            self.copyToSharedContainer(from: url)
        }
    }

    private func copyToSharedContainer(from url: URL) {
        // App Group identifier for sharing data between app and extension
        let appGroupId = "group.net.ro-z.flyfunbrief"

        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) else {
            logger.error("Could not access app group container")
            completeWithError()
            return
        }

        // Create inbox directory if needed
        let inboxURL = containerURL.appendingPathComponent("Inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)

        // Generate unique filename
        let filename = "briefing_\(UUID().uuidString).pdf"
        let destinationURL = inboxURL.appendingPathComponent(filename)

        do {
            // Copy file to shared container
            try FileManager.default.copyItem(at: url, to: destinationURL)
            logger.info("Copied PDF to shared container: \(filename)")

            // Open main app with deep link
            openMainApp(with: destinationURL)

        } catch {
            logger.error("Failed to copy PDF: \(error.localizedDescription)")
            completeWithError()
        }
    }

    private func openMainApp(with fileURL: URL) {
        // Construct deep link URL
        guard let encodedPath = fileURL.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "flyfunbrief://import\(encodedPath)") else {
            logger.error("Failed to create deep link URL")
            completeWithError()
            return
        }

        // Open URL via extensionContext
        DispatchQueue.main.async { [weak self] in
            self?.extensionContext?.open(url) { success in
                if success {
                    self?.logger.info("Opened main app via deep link")
                    self?.completeSuccessfully()
                } else {
                    // If deep link fails, still complete - user can open app manually
                    self?.logger.warning("Deep link failed, completing anyway")
                    self?.completeSuccessfully()
                }
            }
        }
    }

    // MARK: - Completion

    private func completeSuccessfully() {
        DispatchQueue.main.async {
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    private func completeWithError() {
        DispatchQueue.main.async {
            let error = NSError(
                domain: "com.ro-z.flyfunbrief.share",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to process briefing"]
            )
            self.extensionContext?.cancelRequest(withError: error)
        }
    }
}
