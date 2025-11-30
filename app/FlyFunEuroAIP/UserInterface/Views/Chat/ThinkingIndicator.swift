//
//  ThinkingIndicator.swift
//  FlyFunEuroAIP
//
//  Shows thinking/processing state during chat.
//

import SwiftUI

struct ThinkingIndicator: View {
    let thinking: String?
    let toolCall: String?
    
    @State private var dots = ""
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Avatar
            AvatarView(isUser: false)
            
            // Content
            VStack(alignment: .leading, spacing: 8) {
                // Tool call indicator
                if let tool = toolCall {
                    HStack(spacing: 6) {
                        Image(systemName: toolIcon(for: tool))
                            .font(.caption)
                        Text(toolName(for: tool))
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.15))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
                }
                
                // Thinking text
                if let text = thinking {
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                
                // Animated dots
                HStack(spacing: 4) {
                    TypingDots()
                    Text("Thinking")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer(minLength: 40)
        }
        .padding(.horizontal)
    }
    
    private func toolIcon(for tool: String) -> String {
        switch tool {
        case "search_airports", "find_airports_near_route", "get_airports_near":
            return "magnifyingglass"
        case "get_airport_info":
            return "info.circle"
        case "get_airport_procedures":
            return "doc.text"
        case "get_airport_runways":
            return "road.lanes"
        default:
            return "gearshape"
        }
    }
    
    private func toolName(for tool: String) -> String {
        switch tool {
        case "search_airports":
            return "Searching airports..."
        case "get_airport_info":
            return "Getting airport info..."
        case "find_airports_near_route":
            return "Finding route airports..."
        case "get_airport_procedures":
            return "Getting procedures..."
        case "get_airport_runways":
            return "Getting runways..."
        case "get_airports_near":
            return "Finding nearby airports..."
        default:
            return "Processing..."
        }
    }
}

// MARK: - Typing Dots Animation

struct TypingDots: View {
    @State private var animating = false
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(index) * 0.2),
                        value: animating
                    )
            }
        }
        .onAppear {
            animating = true
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        ThinkingIndicator(thinking: nil, toolCall: nil)
        
        ThinkingIndicator(
            thinking: "Looking for airports with ILS approaches in the London area...",
            toolCall: "search_airports"
        )
        
        ThinkingIndicator(
            thinking: nil,
            toolCall: "get_airport_info"
        )
    }
    .padding()
}

