//
//  ChatInputBar.swift
//  FlyFunEuroAIP
//
//  Input bar for sending chat messages.
//

import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Text field
            TextField("Ask about airports, routes, procedures...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isFocused)
                .disabled(isStreaming)
                .onSubmit {
                    if !text.isEmpty && !isStreaming {
                        onSend()
                    }
                }
            
            // Send button
            Button(action: onSend) {
                Group {
                    if isStreaming {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                    }
                }
                .frame(width: 32, height: 32)
            }
            .disabled(text.isEmpty || isStreaming)
            .foregroundStyle(text.isEmpty || isStreaming ? .gray : .blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        #if os(iOS)
        .background(Color(.systemBackground))
        #else
        .background(Color(nsColor: .windowBackgroundColor))
        #endif
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Spacer()
        Divider()
        ChatInputBar(
            text: .constant(""),
            isStreaming: false,
            onSend: {}
        )
        
        Divider()
        ChatInputBar(
            text: .constant("Find airports near Paris"),
            isStreaming: false,
            onSend: {}
        )
        
        Divider()
        ChatInputBar(
            text: .constant(""),
            isStreaming: true,
            onSend: {}
        )
    }
}

