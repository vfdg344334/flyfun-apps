import SwiftUI

struct ModelDownloadView: View {
    @StateObject private var modelManager = ModelManager()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Model info
                VStack(spacing: 12) {
                    Image(systemName: "cube.box.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)
                    
                    Text("Offline Model")
                        .font(.title2.bold())
                    
                    Text("Download the AI model for offline use")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                
                // Status section
                VStack(alignment: .leading, spacing: 16) {
                    statusView
                    
                    if case .downloading = modelManager.modelState {
                        progressView
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                Spacer()
                
                // Action button
                actionButton
            }
            .padding()
            .navigationTitle("Model Download")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var statusView: some View {
        switch modelManager.modelState {
        case .checking:
            HStack {
                ProgressView()
                Text("Checking...")
            }
            
        case .notDownloaded:
            VStack(alignment: .leading, spacing: 8) {
                Label("Model Size", systemImage: "internaldrive")
                    .font(.subheadline.bold())
                Text("~\(String(format: "%.1f", Double(ModelManager.modelSizeBytes) / 1_000_000_000)) GB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Divider().padding(.vertical, 4)
                
                Label("Storage Available", systemImage: "externaldrive")
                    .font(.subheadline.bold())
                Text(formatBytes(modelManager.availableStorage))
                    .font(.caption)
                    .foregroundStyle(modelManager.hasEnoughStorage ? Color.secondary : Color.red)
            }
            
        case .downloading(let progress, let downloaded, let total):
            VStack(alignment: .leading, spacing: 8) {
                Label("Downloading...", systemImage: "arrow.down.circle")
                    .font(.subheadline.bold())
                Text("\(formatBytes(downloaded)) / \(formatBytes(total))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
        case .ready:
            Label("Model Ready", systemImage: "checkmark.circle.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.green)
            
        case .error(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label("Error", systemImage: "exclamationmark.triangle")
                    .font(.subheadline.bold())
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
        case .deviceNotSupported(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label("Device Not Supported", systemImage: "exclamationmark.triangle")
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
        default:
            EmptyView()
        }
    }
    
    @ViewBuilder
    private var progressView: some View {
        if case .downloading(let progress, _, _) = modelManager.modelState {
            ProgressView(value: Double(progress))
                .padding(.top, 8)
        }
    }
    
    @ViewBuilder
    private var actionButton: some View {
        switch modelManager.modelState {
        case .notDownloaded:
            Button {
                Task {
                    for try await _ in modelManager.downloadModel(from: ModelManager.downloadURL) {
                        // Progress updates are handled by modelState
                    }
                }
            } label: {
                Text("Download Model")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(modelManager.hasEnoughStorage ? Color.blue : Color.gray)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!modelManager.hasEnoughStorage)
            
        case .downloading:
            Button {
                modelManager.cancelDownload()
            } label: {
                Text("Cancel Download")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
        case .ready:
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
        case .error:
            Button {
                Task {
                    for try await _ in modelManager.downloadModel(from: ModelManager.downloadURL) {
                        // Retry download
                    }
                }
            } label: {
                Text("Retry Download")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
        default:
            EmptyView()
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else if bytes < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
        } else {
            return String(format: "%.2f GB", Double(bytes) / 1024 / 1024 / 1024)
        }
    }
}

#Preview {
    ModelDownloadView()
}
