//
//  ImportBriefingView.swift
//  FlyFunBrief
//
//  View for importing briefing PDFs via file picker.
//

import SwiftUI
import UniformTypeIdentifiers
import RZFlight

/// Sheet view for importing a briefing PDF
struct ImportBriefingView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showingFilePicker = false
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Icon
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)

                // Title
                Text("Import Briefing")
                    .font(.title2.bold())

                // Description
                Text("Select a ForeFlight briefing PDF to import and parse NOTAMs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Import button
                Button {
                    showingFilePicker = true
                } label: {
                    Label("Choose PDF File", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)

                // Error message
                if let error = importError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding()
                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }

                Spacer()

                // Info
                VStack(spacing: 8) {
                    Text("Supported Sources")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    HStack(spacing: 16) {
                        Label("ForeFlight", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Label("SkyDemon", systemImage: "circle.dashed")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                .padding()
            }
            .padding()
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [UTType.pdf],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            // Start import
            Task {
                do {
                    // Get secure access to the file
                    guard url.startAccessingSecurityScopedResource() else {
                        importError = "Unable to access file"
                        return
                    }
                    defer { url.stopAccessingSecurityScopedResource() }

                    // Read file data
                    let data = try Data(contentsOf: url)

                    // Import via app state
                    await appState?.briefing.importBriefing(data: data, source: "foreflight")

                    // Check for errors
                    if let error = appState?.briefing.lastError {
                        importError = error.localizedDescription
                    } else {
                        dismiss()
                    }
                } catch {
                    importError = error.localizedDescription
                }
            }

        case .failure(let error):
            importError = error.localizedDescription
        }
    }
}

/// Progress view during import
struct ImportProgressView: View {
    @Environment(\.appState) private var appState

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)

            Text("Parsing Briefing...")
                .font(.headline)

            if let progress = appState?.briefing.importProgress, progress > 0 {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
            }
        }
        .padding()
    }
}

/// Empty state when no briefing is loaded
struct EmptyBriefingView: View {
    @Environment(\.appState) private var appState

    var body: some View {
        ContentUnavailableView {
            Label("No Briefing", systemImage: "doc.badge.plus")
        } description: {
            Text("Import a ForeFlight briefing PDF to review NOTAMs.")
        } actions: {
            Button {
                appState?.navigation.showImportSheet()
            } label: {
                Label("Import Briefing", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// Summary view for loaded briefing
struct BriefingSummaryView: View {
    @Environment(\.appState) private var appState
    let briefing: Briefing

    var body: some View {
        List {
            // Route Section
            Section("Route") {
                if let route = briefing.route {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Departure")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(route.departure)
                                .font(.title3.bold())
                        }

                        Spacer()

                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)

                        Spacer()

                        VStack(alignment: .trailing) {
                            Text("Destination")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(route.destination)
                                .font(.title3.bold())
                        }
                    }
                    .padding(.vertical, 8)

                    if !route.alternates.isEmpty {
                        HStack {
                            Text("Alternates")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(route.alternates.joined(separator: ", "))
                        }
                    }
                }
            }

            // NOTAM Summary Section
            Section("NOTAMs") {
                HStack {
                    Text("Total")
                    Spacer()
                    Text("\(briefing.notams.count)")
                        .bold()
                }

                if let unread = appState?.notams.unreadCount, unread > 0 {
                    HStack {
                        Text("Unread")
                        Spacer()
                        Text("\(unread)")
                            .foregroundStyle(.blue)
                    }
                }

                if let important = appState?.notams.importantCount, important > 0 {
                    HStack {
                        Text("Important")
                        Spacer()
                        Text("\(important)")
                            .foregroundStyle(.yellow)
                    }
                }

                Button {
                    appState?.navigation.showNotamList()
                } label: {
                    Label("View All NOTAMs", systemImage: "list.bullet.rectangle")
                }
            }

            // Actions Section
            Section {
                Button(role: .destructive) {
                    appState?.briefing.clearBriefing()
                } label: {
                    Label("Clear Briefing", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Import View") {
    ImportBriefingView()
        .environment(\.appState, AppState.preview())
}

#Preview("Progress View") {
    ImportProgressView()
        .environment(\.appState, AppState.preview())
}

#Preview("Empty State") {
    EmptyBriefingView()
        .environment(\.appState, AppState.preview())
}
