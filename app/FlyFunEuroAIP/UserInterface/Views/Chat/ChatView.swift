//
//  ChatView.swift
//  FlyFunEuroAIP
//
//  Main chat interface for the aviation agent.
//

import SwiftUI

struct ChatView: View {
    @Environment(\.appState) private var state

    /// Callback to show settings (replaces chat in sidebar)
    var onShowSettings: (() -> Void)?

    var body: some View {
        // Use shared ChatContent for the actual chat UI
        ChatContent(compactWelcome: false)
            // Only show navigation title/toolbar when in a NavigationStack (not in overlay)
            .navigationTitle("Assistant")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                // Offline mode indicator
                Label(
                    state?.chat.isOfflineMode == true ? "Offline" : "Online",
                    systemImage: state?.chat.isOfflineMode == true ? "airplane.circle.fill" : "cloud.fill"
                )
                .font(.caption)
                .foregroundStyle(state?.chat.isOfflineMode == true ? .orange : .blue)
            }

            ToolbarItem(placement: .topBarTrailing) {
                // Settings - replaces chat with settings in sidebar
                Button {
                    onShowSettings?()
                } label: {
                    Image(systemName: "gear")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    state?.chat.clear()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(state?.chat.messages.isEmpty ?? true)
            }
        }
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "airplane.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
            
            Text("Aviation Assistant")
                .font(.title2.bold())
            
            Text("Ask me about airports, procedures, routes, and more!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            // Example queries
            VStack(alignment: .leading, spacing: 8) {
                Text("Try asking:")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                
                ExampleQueryButton(text: "Find airports with ILS near London")
                ExampleQueryButton(text: "Border crossing airports in France")
                ExampleQueryButton(text: "Show me airports along EGLL to LFPG")
            }
            .padding(.top, 8)
        }
        .padding()
    }
}

struct ExampleQueryButton: View {
    @Environment(\.appState) private var state
    let text: String
    
    var body: some View {
        Button {
            state?.chat.input = text
        } label: {
            HStack {
                Image(systemName: "text.bubble")
                    .font(.caption)
                Text(text)
                    .font(.caption)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.1))
            .foregroundStyle(.blue)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chat Settings View

struct ChatSettingsView: View {
    @Environment(\.appState) private var state
    @Environment(AuthenticationService.self) private var authService
    @StateObject private var modelManager = ModelManager()
    @State private var showModelDownload = false

    /// Callback to show chat (replaces settings in sidebar)
    var onShowChat: (() -> Void)?

    /// Callback to show offline maps (replaces settings in sidebar)
    var onShowOfflineMaps: (() -> Void)?

    var body: some View {
        List {
            // Offline Mode Section
            Section {
                Toggle(isOn: offlineModeBinding) {
                    Label("Offline Mode", systemImage: "airplane.circle")
                }

                // Model status row
                HStack {
                    Label("AI Model", systemImage: "cube.box")
                    Spacer()
                    if modelManager.isModelAvailable {
                        Label("Ready", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Button("Download") {
                            showModelDownload = true
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                }

                Button {
                    onShowOfflineMaps?()
                } label: {
                    Label("Manage Offline Maps", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Offline")
            } footer: {
                if modelManager.isModelAvailable {
                    Text("Offline mode uses on-device AI and cached map tiles. Download maps for areas you plan to visit.")
                } else {
                    Text("Download the AI model (~1.5 GB) to enable offline chat. Maps can be downloaded separately.")
                }
            }

            // Chat History Section
            Section("Chat") {
                Button(role: .destructive) {
                    state?.chat.clear()
                } label: {
                    Label("Clear Chat History", systemImage: "trash")
                }
                .disabled(state?.chat.messages.isEmpty ?? true)
            }

            // Account Section
            Section("Account") {
                if authService.isAuthenticated {
                    if let user = authService.currentUser {
                        HStack {
                            Label("Signed in as", systemImage: "person.circle.fill")
                            Spacer()
                            Text(user.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Button(role: .destructive) {
                        authService.signOut()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } else {
                    HStack {
                        Label("Not signed in", systemImage: "person.circle")
                        Spacer()
                        Text("Sign in from home screen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Back to chat
                Button {
                    onShowChat?()
                } label: {
                    Image(systemName: "bubble.left.and.bubble.right")
                }
            }
        }
        .sheet(isPresented: $showModelDownload) {
            ModelDownloadView()
        }
    }

    private var offlineModeBinding: Binding<Bool> {
        Binding(
            get: { state?.chat.isOfflineMode ?? false },
            set: { newValue in
                // If enabling offline mode and no model, show download prompt
                if newValue && !modelManager.isModelAvailable {
                    showModelDownload = true
                    // Don't actually enable offline mode yet
                } else {
                    state?.chat.setOfflineMode(newValue)
                }
            }
        )
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ChatView()
    }
}

#Preview("Chat Settings") {
    NavigationStack {
        ChatSettingsView()
    }
}

