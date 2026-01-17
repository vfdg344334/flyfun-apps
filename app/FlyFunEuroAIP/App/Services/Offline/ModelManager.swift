//
//  ModelManager.swift
//  FlyFunEuroAIP
//
//  Manages the offline model lifecycle: download, storage, and capability checking.
//  Matches Android ModelManager implementation.
//

import Foundation
import OSLog
import RZUtilsSwift
import UIKit
import Combine

/// Manages the offline model lifecycle: download, storage, and capability checking.
@MainActor
final class ModelManager: ObservableObject {
    
    // MARK: - Configuration
    
    static let modelFilename = "Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.task"
    static let modelSizeBytes: Int64 = 1_500_000_000  // ~1.5 GB for Qwen 2.5 Instruct
    static let modelDir = "models"
    
    // Download configuration - loaded from secrets.json
    static var downloadURL: URL {
        SecretsManager.shared.modelDownloadURLValue ?? URL(string: "http://localhost:8000/api/models/download/model.task")!
    }
    static let apiKeyHeader = "X-Model-API-Key"
    static var apiKey: String {
        SecretsManager.shared.modelAPIKey
    }
    
    // Device requirements
    static let minRAMMB: UInt64 = 3072  // 3 GB minimum (model is ~1.5GB)
    static let recommendedRAMMB: UInt64 = 6144  // 6 GB recommended
    
    // MARK: - Published State
    
    @Published var modelState: ModelState = .checking
    
    // MARK: - Private
    
    private var deviceCapability: DeviceCapability?
    private var externalModelPath: String?
    private var currentDownloadTask: URLSessionDownloadTask?
    
    // MARK: - Init
    
    init() {
        checkInitialState()
    }
    
    // MARK: - Model State
    
    enum ModelState: Equatable {
        case checking
        case notDownloaded
        case downloading(progress: Float, downloadedBytes: Int64, totalBytes: Int64)
        case ready
        case loading
        case loaded
        case error(String)
        case deviceNotSupported(String)
    }
    
    // MARK: - Device Capability
    
    struct DeviceCapability {
        let totalRAMMB: UInt64
        let availableRAMMB: UInt64
        let isSupported: Bool
        let isRecommended: Bool
        let warningMessage: String?
    }
    
    // MARK: - Public API
    
    /// Set an external model path for testing purposes.
    func setExternalModelPath(_ path: String) {
        externalModelPath = path
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: path) {
            Logger.app.info("External model path set: \(path)")
            modelState = .ready
        } else {
            Logger.app.warning("External model file not found: \(path)")
        }
    }
    
    /// Get the model file path - finds any .task file in the models directory
    var modelFile: URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelDir = documentsDir.appendingPathComponent(Self.modelDir)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        
        // Look for any existing .task file in the directory
        if let existingModel = findExistingModelFile(in: modelDir) {
            return existingModel
        }
        
        // Default to the configured filename for new downloads
        return modelDir.appendingPathComponent(Self.modelFilename)
    }
    
    /// Find any existing .task model file in the directory
    private func findExistingModelFile(in directory: URL) -> URL? {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return nil
        }
        
        // Find .task files that are large enough to be a model
        for file in files where file.pathExtension == "task" {
            if let attributes = try? fileManager.attributesOfItem(atPath: file.path),
               let fileSize = attributes[.size] as? Int64,
               fileSize > 100_000_000 { // At least 100MB
                Logger.app.info("Found existing model file: \(file.lastPathComponent) (\(fileSize / 1_000_000) MB)")
                return file
            }
        }
        return nil
    }
    
    /// Get model path as string - returns external path if set and exists
    var modelPath: String {
        if let externalPath = externalModelPath,
           FileManager.default.fileExists(atPath: externalPath) {
            return externalPath
        }
        return modelFile.path
    }
    
    /// Check if model file exists and is complete
    var isModelAvailable: Bool {
        // Check external path first
        if let externalPath = externalModelPath,
           FileManager.default.fileExists(atPath: externalPath) {
            return true
        }
        
        let fileManager = FileManager.default
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelDir = documentsDir.appendingPathComponent(Self.modelDir)
        
        // Look for any .task file in the models directory
        if let existingModel = findExistingModelFile(in: modelDir) {
            // Check file size (allow some tolerance)
            if let attributes = try? fileManager.attributesOfItem(atPath: existingModel.path),
               let fileSize = attributes[.size] as? Int64 {
                let isAvailable = fileSize > 100_000_000  // At least 100MB for any model
                if isAvailable {
                    Logger.app.info("Model available: \(existingModel.lastPathComponent) (\(fileSize / 1_000_000) MB)")
                }
                return isAvailable
            }
        }
        return false
    }
    
    /// Check device capability for running the model
    func checkDeviceCapability() -> DeviceCapability {
        if let cached = deviceCapability {
            return cached
        }
        
        let totalRAM = ProcessInfo.processInfo.physicalMemory
        let totalRAMMB = totalRAM / (1024 * 1024)
        
        // Estimate available RAM (iOS doesn't expose this directly)
        let availableRAMMB = totalRAMMB / 2  // Conservative estimate
        
        let isSupported = totalRAMMB >= Self.minRAMMB
        let isRecommended = totalRAMMB >= Self.recommendedRAMMB
        
        let warningMessage: String?
        if !isSupported {
            warningMessage = "Your device has \(totalRAMMB)MB RAM. The model requires at least \(Self.minRAMMB)MB."
        } else if !isRecommended {
            warningMessage = "Your device meets minimum requirements but may experience slower performance."
        } else {
            warningMessage = nil
        }
        
        let capability = DeviceCapability(
            totalRAMMB: totalRAMMB,
            availableRAMMB: availableRAMMB,
            isSupported: isSupported,
            isRecommended: isRecommended,
            warningMessage: warningMessage
        )
        
        deviceCapability = capability
        Logger.app.info("Device capability: \(totalRAMMB)MB RAM, supported: \(isSupported)")
        
        return capability
    }
    
    /// Check if offline mode should be available
    var isOfflineModeAvailable: Bool {
        let capability = checkDeviceCapability()
        return capability.isSupported && isModelAvailable
    }
    
    /// Download the model from the given URL with progress updates
    func downloadModel(from url: URL) -> AsyncThrowingStream<DownloadProgress, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                Logger.app.info("Starting model download from: \(url.absoluteString)")
                
                let capability = checkDeviceCapability()
                if !capability.isSupported {
                    modelState = .deviceNotSupported(capability.warningMessage ?? "Device not supported")
                    continuation.finish(throwing: ModelError.deviceNotSupported)
                    return
                }
                
                modelState = .downloading(progress: 0, downloadedBytes: 0, totalBytes: Self.modelSizeBytes)
                continuation.yield(.started)
                
                // Create authenticated request with X-Model-API-Key header
                var request = URLRequest(url: url)
                request.setValue(Self.apiKey, forHTTPHeaderField: Self.apiKeyHeader)
                
                // Create delegate for progress tracking
                let delegate = DownloadDelegate(
                    onProgress: { [weak self] downloaded, total in
                        guard let self = self else { return }
                        let progress = total > 0 ? Float(downloaded) / Float(total) : 0
                        DispatchQueue.main.async {
                            self.modelState = .downloading(progress: progress, downloadedBytes: downloaded, totalBytes: total)
                            continuation.yield(.inProgress(progress: progress, downloadedBytes: downloaded, totalBytes: total))
                        }
                    },
                    onComplete: { [weak self] tempURL in
                        guard let self = self else { return }
                        
                        // CRITICAL: Must copy file IMMEDIATELY before returning from delegate
                        // The temp file will be deleted as soon as this callback returns
                        let fileManager = FileManager.default
                        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
                        let modelDir = documentsDir.appendingPathComponent(Self.modelDir)
                        
                        do {
                            // Create directory synchronously
                            try fileManager.createDirectory(at: modelDir, withIntermediateDirectories: true, attributes: nil)
                            
                            let finalPath = modelDir.appendingPathComponent(Self.modelFilename)
                            
                            // Remove existing file if present
                            if fileManager.fileExists(atPath: finalPath.path) {
                                try fileManager.removeItem(at: finalPath)
                            }
                            
                            // Copy immediately (synchronously) before temp file is deleted
                            try fileManager.copyItem(at: tempURL, to: finalPath)
                            
                            Logger.app.info("Model file copied successfully to: \(finalPath.path)")
                            
                            // Update UI state asynchronously
                            Task { @MainActor in
                                self.modelState = .ready
                                continuation.yield(.completed(finalPath))
                                continuation.finish()
                            }
                        } catch {
                            Logger.app.error("Failed to copy model file: \(error.localizedDescription)")
                            Task { @MainActor in
                                self.modelState = .error(error.localizedDescription)
                                continuation.finish(throwing: error)
                            }
                        }
                    },
                    onError: { [weak self] error in
                        guard let self = self else { return }
                        Task { @MainActor in
                            Logger.app.error("Download error: \(error.localizedDescription)")
                            self.modelState = .error(error.localizedDescription)
                            continuation.finish(throwing: error)
                        }
                    }
                )
                
                // Create URLSession with delegate
                let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
                let task = session.downloadTask(with: request)
                self.currentDownloadTask = task
                task.resume()  
            }
        }
    }
    
    /// Cancel the current download
    func cancelDownload() {
        currentDownloadTask?.cancel()
        currentDownloadTask = nil
        modelState = .notDownloaded
        Logger.app.info("Download cancelled")
    }
    
    // MARK: - Download Delegate
    
    private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
        let onProgress: (Int64, Int64) -> Void
        let onComplete: (URL) -> Void
        let onError: (Error) -> Void
        
        init(onProgress: @escaping (Int64, Int64) -> Void, 
             onComplete: @escaping (URL) -> Void,
             onError: @escaping (Error) -> Void) {
            self.onProgress = onProgress
            self.onComplete = onComplete
            self.onError = onError
        }
        
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            onComplete(location)
        }
        
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            onProgress(totalBytesWritten, totalBytesExpectedToWrite)
        }
        
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error = error {
                onError(error)
            }
        }
    }
    
    /// Delete the downloaded model file
    func deleteModel() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: modelFile.path) {
            try fileManager.removeItem(at: modelFile)
            Logger.app.info("Model deleted")
            modelState = .notDownloaded
        } else {
            modelState = .notDownloaded
        }
    }
    
    /// Get available storage space in bytes
    var availableStorage: Int64 {
        let fileManager = FileManager.default
        if let attributes = try? fileManager.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let freeSpace = attributes[.systemFreeSize] as? Int64 {
            return freeSpace
        }
        return 0
    }
    
    /// Check if there's enough storage for the model
    var hasEnoughStorage: Bool {
        // Require extra 500MB buffer
        return availableStorage > Self.modelSizeBytes + (500 * 1024 * 1024)
    }
    
    // MARK: - Private
    
    private func checkInitialState() {
        modelState = .checking
        
        // Check external path first
        if let externalPath = externalModelPath,
           FileManager.default.fileExists(atPath: externalPath) {
            Logger.app.info("External model found: \(externalPath)")
            modelState = .ready
            return
        }
        
        if isModelAvailable {
            Logger.app.info("Model found: \(modelFile.path)")
            modelState = .ready
        } else {
            Logger.app.info("Model not found")
            modelState = .notDownloaded
        }
    }
}

// MARK: - Download Progress

enum DownloadProgress {
    case started
    case inProgress(progress: Float, downloadedBytes: Int64, totalBytes: Int64)
    case completed(URL)
    case error(String)
}

// MARK: - Errors

enum ModelError: LocalizedError {
    case deviceNotSupported
    case downloadFailed(String)
    case insufficientStorage
    
    var errorDescription: String? {
        switch self {
        case .deviceNotSupported:
            return "Device does not meet minimum requirements for offline mode"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .insufficientStorage:
            return "Not enough storage space for the model"
        }
    }
}
