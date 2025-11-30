//
//  ChatBubble.swift
//  FlyFunEuroAIP
//
//  Message bubble for chat interface.
//

import SwiftUI

struct ChatBubble: View {
    let message: ChatMessage
    
    private var isUser: Bool {
        message.role == .user
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 40) }
            
            // Avatar
            if !isUser {
                AvatarView(isUser: false)
            }
            
            // Message content
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleBackground)
                    .foregroundStyle(isUser ? .white : .primary)
                    .clipShape(BubbleShape(isUser: isUser))
                
                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                // Streaming indicator
                if message.isStreaming {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Typing...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // User avatar
            if isUser {
                AvatarView(isUser: true)
            }
            
            if !isUser { Spacer(minLength: 40) }
        }
    }
    
    @ViewBuilder
    private var bubbleBackground: some View {
        if isUser {
            Color.blue
        } else {
            #if os(iOS)
            Color(.systemGray5)
            #else
            Color(nsColor: .controlBackgroundColor)
            #endif
        }
    }
}

// MARK: - Avatar View

struct AvatarView: View {
    let isUser: Bool
    
    var body: some View {
        Circle()
            .fill(isUser ? Color.blue.opacity(0.2) : Color.orange.opacity(0.2))
            .frame(width: 32, height: 32)
            .overlay {
                Image(systemName: isUser ? "person.fill" : "airplane")
                    .font(.system(size: 14))
                    .foregroundStyle(isUser ? .blue : .orange)
            }
    }
}

// MARK: - Bubble Shape

struct BubbleShape: Shape {
    let isUser: Bool
    
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 16
        let tailSize: CGFloat = 6
        
        var path = Path()
        
        if isUser {
            // User bubble - tail on right
            path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addArc(
                center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                radius: radius,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius - tailSize))
            // Tail
            path.addLine(to: CGPoint(x: rect.maxX + tailSize, y: rect.maxY - tailSize))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - tailSize))
            path.addArc(
                center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                radius: radius,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            path.addArc(
                center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
                radius: radius,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addArc(
                center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
                radius: radius,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
        } else {
            // Assistant bubble - tail on left
            path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addArc(
                center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                radius: radius,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addArc(
                center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                radius: radius,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            path.addArc(
                center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
                radius: radius,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - tailSize))
            // Tail
            path.addLine(to: CGPoint(x: rect.minX - tailSize, y: rect.maxY - tailSize))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius - tailSize))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addArc(
                center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
                radius: radius,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
        }
        
        path.closeSubpath()
        return path
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        ChatBubble(message: ChatMessage(
            role: .user,
            content: "Find airports with ILS near London"
        ))
        
        ChatBubble(message: ChatMessage(
            role: .assistant,
            content: "I found several airports with ILS approaches near London. Here are the top results:\n\n• EGLL - London Heathrow\n• EGKK - London Gatwick\n• EGLC - London City"
        ))
        
        ChatBubble(message: ChatMessage(
            role: .assistant,
            content: "Searching...",
            isStreaming: true
        ))
    }
    .padding()
}

