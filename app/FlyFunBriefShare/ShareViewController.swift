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

    // UI Elements
    private let containerView = UIView()
    private let iconImageView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let openAppButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .large)

    private var savedFileURL: URL?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        processSharedItems()
    }

    // MARK: - UI Setup

    private func setupUI() {
        // Semi-transparent background
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)

        // Container card
        containerView.backgroundColor = .systemBackground
        containerView.layer.cornerRadius = 16
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        // Icon
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.tintColor = .systemBlue
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(iconImageView)

        // Title
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(titleLabel)

        // Message
        messageLabel.font = .systemFont(ofSize: 15)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(messageLabel)

        // Open App button
        openAppButton.setTitle("Open FlyFunBrief", for: .normal)
        openAppButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        openAppButton.backgroundColor = .systemBlue
        openAppButton.setTitleColor(.white, for: .normal)
        openAppButton.layer.cornerRadius = 12
        openAppButton.translatesAutoresizingMaskIntoConstraints = false
        openAppButton.addTarget(self, action: #selector(openAppTapped), for: .touchUpInside)
        openAppButton.isHidden = true
        containerView.addSubview(openAppButton)

        // Done button
        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 17)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        doneButton.isHidden = true
        containerView.addSubview(doneButton)

        // Spinner
        spinner.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(spinner)

        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.widthAnchor.constraint(equalToConstant: 300),

            iconImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 24),
            iconImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 60),
            iconImageView.heightAnchor.constraint(equalToConstant: 60),

            titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),

            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            messageLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            messageLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),

            openAppButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 20),
            openAppButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            openAppButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            openAppButton.heightAnchor.constraint(equalToConstant: 50),

            doneButton.topAnchor.constraint(equalTo: openAppButton.bottomAnchor, constant: 12),
            doneButton.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            doneButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -20),

            spinner.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 20),
        ])

        // Initial state: loading
        showLoading()
    }

    private func showLoading() {
        iconImageView.image = UIImage(systemName: "doc.text")
        titleLabel.text = "Importing Briefing..."
        messageLabel.text = ""
        spinner.startAnimating()
        openAppButton.isHidden = true
        doneButton.isHidden = true
    }

    private func showSuccess() {
        spinner.stopAnimating()
        iconImageView.image = UIImage(systemName: "checkmark.circle.fill")
        iconImageView.tintColor = .systemGreen
        titleLabel.text = "Briefing Ready!"
        messageLabel.text = "Open FlyFunBrief to review your NOTAMs"
        openAppButton.isHidden = false
        doneButton.isHidden = false
    }

    private func showError(_ message: String) {
        spinner.stopAnimating()
        iconImageView.image = UIImage(systemName: "xmark.circle.fill")
        iconImageView.tintColor = .systemRed
        titleLabel.text = "Import Failed"
        messageLabel.text = message
        openAppButton.isHidden = true
        doneButton.setTitle("Close", for: .normal)
        doneButton.isHidden = false
    }

    // MARK: - Actions

    @objc private func openAppTapped() {
        guard let fileURL = savedFileURL else {
            completeSuccessfully()
            return
        }

        // Try to open the main app via URL scheme
        guard let encodedPath = fileURL.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "flyfunbrief://import?path=\(encodedPath)") else {
            completeSuccessfully()
            return
        }

        // Use responder chain to open URL (works in some iOS versions)
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                application.open(url, options: [:]) { [weak self] success in
                    self?.logger.info("Open app result: \(success)")
                    self?.completeSuccessfully()
                }
                return
            }
            responder = responder?.next
        }

        // Fallback: use extensionContext.open (may not work)
        extensionContext?.open(url) { [weak self] success in
            self?.logger.info("extensionContext.open result: \(success)")
            self?.completeSuccessfully()
        }
    }

    @objc private func doneTapped() {
        completeSuccessfully()
    }

    // MARK: - Processing

    private func processSharedItems() {
        guard let extensionContext = extensionContext,
              let inputItems = extensionContext.inputItems as? [NSExtensionItem] else {
            logger.error("No extension context or input items")
            DispatchQueue.main.async { self.showError("No items to share") }
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
        DispatchQueue.main.async { self.showError("No PDF file found") }
    }

    private func processPDFProvider(_ provider: NSItemProvider) {
        provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { [weak self] url, error in
            guard let self = self else { return }

            if let error = error {
                self.logger.error("Error loading PDF: \(error.localizedDescription)")
                DispatchQueue.main.async { self.showError("Failed to load PDF") }
                return
            }

            guard let url = url else {
                self.logger.error("No URL for PDF")
                DispatchQueue.main.async { self.showError("PDF file not accessible") }
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
            DispatchQueue.main.async { self.showError("Storage not available") }
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

            // Save for later
            savedFileURL = destinationURL

            // Save pending import path to shared UserDefaults
            savePendingImport(path: destinationURL.path)

            // Show success UI
            DispatchQueue.main.async {
                self.showSuccess()
            }

        } catch {
            logger.error("Failed to copy PDF: \(error.localizedDescription)")
            DispatchQueue.main.async { self.showError("Failed to save PDF") }
        }
    }

    /// Save the pending import path to shared UserDefaults
    private func savePendingImport(path: String) {
        guard let defaults = UserDefaults(suiteName: appGroupId) else {
            logger.warning("Could not access shared UserDefaults")
            return
        }

        defaults.set(path, forKey: pendingImportKey)
        defaults.synchronize()
        logger.info("Saved pending import path to UserDefaults")
    }

    // MARK: - Completion

    private func completeSuccessfully() {
        DispatchQueue.main.async {
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
}
