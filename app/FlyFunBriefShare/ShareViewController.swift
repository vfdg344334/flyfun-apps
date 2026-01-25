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

    /// App Group identifier for sharing data between app and extension
    private let appGroupId = "group.net.ro-z.flyfunbrief"

    /// UserDefaults key for pending import path
    private let pendingImportKey = "pendingBriefingImportPath"

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // Set up minimal UI - show brief loading indicator
        view.backgroundColor = .systemBackground

        let spinner = UIActivityIndicatorView(style: .large)
        spinner.center = view.center
        spinner.startAnimating()
        view.addSubview(spinner)

        // Process the shared items
        processSharedItems()
    }

    // MARK: - Processing

    private func processSharedItems() {
        guard let extensionContext = extensionContext,
              let inputItems = extensionContext.inputItems as? [NSExtensionItem] else {
            logger.error("No extension context or input items")
            completeWithError("No items to share")
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
        completeWithError("No PDF file found")
    }

    private func processPDFProvider(_ provider: NSItemProvider) {
        provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { [weak self] url, error in
            guard let self = self else { return }

            if let error = error {
                self.logger.error("Error loading PDF: \(error.localizedDescription)")
                self.completeWithError("Failed to load PDF")
                return
            }

            guard let url = url else {
                self.logger.error("No URL for PDF")
                self.completeWithError("PDF file not accessible")
                return
            }

            // Copy to shared container
            self.copyToSharedContainer(from: url)
        }
    }

    private func copyToSharedContainer(from url: URL) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) else {
            logger.error("Could not access app group container")
            completeWithError("Storage not available")
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

            // Save pending import path to shared UserDefaults (reliable fallback)
            savePendingImport(path: destinationURL.path)

            // Try to open main app with deep link
            openMainApp(with: destinationURL)

        } catch {
            logger.error("Failed to copy PDF: \(error.localizedDescription)")
            completeWithError("Failed to save PDF")
        }
    }

    /// Save the pending import path to shared UserDefaults
    /// This ensures the main app can find the file even if deep link fails
    private func savePendingImport(path: String) {
        guard let defaults = UserDefaults(suiteName: appGroupId) else {
            logger.warning("Could not access shared UserDefaults")
            return
        }

        defaults.set(path, forKey: pendingImportKey)
        defaults.synchronize()
        logger.info("Saved pending import path to UserDefaults")
    }

    private func openMainApp(with fileURL: URL) {
        // Construct deep link URL with proper format: scheme://host/path
        // Use "import" as host and file path as the URL path
        guard let encodedPath = fileURL.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "flyfunbrief://import?path=\(encodedPath)") else {
            logger.error("Failed to create deep link URL")
            // Still complete successfully - app will find file via UserDefaults
            completeSuccessfully()
            return
        }

        logger.info("Attempting deep link: \(url.absoluteString)")

        // Open URL via extensionContext
        DispatchQueue.main.async { [weak self] in
            self?.extensionContext?.open(url) { success in
                if success {
                    self?.logger.info("Opened main app via deep link")
                } else {
                    // Deep link failed - app will find file via UserDefaults on next launch
                    self?.logger.warning("Deep link failed - file saved for next app launch")
                }
                self?.completeSuccessfully()
            }
        }
    }

    // MARK: - Completion

    private func completeSuccessfully() {
        DispatchQueue.main.async {
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    private func completeWithError(_ message: String) {
        DispatchQueue.main.async {
            let error = NSError(
                domain: "com.ro-z.flyfunbrief.share",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
            self.extensionContext?.cancelRequest(withError: error)
        }
    }
}
