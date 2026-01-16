//
//  ChatContent.swift
//  FlyFunEuroAIP
//
//  Chat content without navigation chrome - for embedding in overlays.
//  Used by ChatView (full screen) and IPhoneChatOverlay (bottom sheet).
//

import SwiftUI

/// Chat content without navigation bar - for embedding in overlays
struct ChatContent: View {
    @Environment(\.appState) private var state
    @FocusState private var isInputFocused: Bool

    /// Use compact welcome view (for overlays with limited space)
    var compactWelcome: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Welcome message if empty
                        if let chat = state?.chat, chat.messages.isEmpty {
                            if compactWelcome {
                                CompactWelcomeView()
                            } else {
                                WelcomeView()
                                    .padding(.top, 40)
                            }
                        }

                        // Messages
                        if let messages = state?.chat.messages {
                            ForEach(messages) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
                            }
                        }

                        // Thinking indicator
                        if let chat = state?.chat {
                            if chat.isStreaming {
                                ThinkingIndicator(
                                    thinking: chat.currentThinking,
                                    toolCall: chat.currentToolCall
                                )
                                .id("thinking")
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: state?.chat.messages.count) { _, _ in
                    // Scroll to bottom when new messages arrive
                    withAnimation {
                        if let lastMessage = state?.chat.messages.last {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: state?.chat.isStreaming) { _, isStreaming in
                    if isStreaming == true {
                        withAnimation {
                            proxy.scrollTo("thinking", anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Suggested queries (show after response, hide during streaming)
            if let queries = state?.chat.suggestedQueries,
               !queries.isEmpty,
               !(state?.chat.isStreaming ?? false) {
                SuggestedQueriesView(queries: queries) { query in
                    Task {
                        await state?.chat.useSuggestion(query)
                    }
                }
                .padding(.top, 8)
            }

            // Input bar
            ChatInputBar(
                text: Binding(
                    get: { state?.chat.input ?? "" },
                    set: { state?.chat.input = $0 }
                ),
                isStreaming: state?.chat.isStreaming ?? false,
                onSend: {
                    Task {
                        await state?.chat.send()
                    }
                }
            )
            .focused($isInputFocused)
        }
    }
}

// MARK: - Compact Welcome View

/// Compact welcome for overlay (smaller than full-screen)
struct CompactWelcomeView: View {
    @Environment(\.appState) private var state

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "airplane.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text("Aviation Assistant")
                .font(.headline)

            Text("Ask about airports, routes, procedures...")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Quick example buttons
            HStack(spacing: 8) {
                CompactExampleButton(text: "Airports near me")
                CompactExampleButton(text: "IFR in France")
            }
        }
        .padding()
    }
}

struct CompactExampleButton: View {
    @Environment(\.appState) private var state
    let text: String

    var body: some View {
        Button {
            state?.chat.input = text
        } label: {
            Text(text)
                .font(.caption2)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .foregroundStyle(.blue)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Chat Content") {
    ChatContent()
}

#Preview("Chat Content Compact") {
    ChatContent(compactWelcome: true)
        .frame(height: 400)
}
