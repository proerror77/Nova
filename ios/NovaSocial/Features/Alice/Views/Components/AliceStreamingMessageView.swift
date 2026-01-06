import SwiftUI

// MARK: - Alice Streaming Message View

/// Enhanced message view with improved streaming support for Alice chat
struct AliceStreamingMessageView: View {

    // MARK: - Properties

    @Bindable var message: AliceChatMessage
    var onToolCallComplete: (() -> Void)?

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isUser {
                Spacer()
                userMessageBubble
            } else {
                aiMessageView
                Spacer()
            }
        }
    }

    // MARK: - User Message

    private var userMessageBubble: some View {
        Text(message.content)
            .font(Font.custom("SFProDisplay-Regular", size: 14.f))
            .foregroundColor(DesignTokens.textPrimary)
            .padding(EdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 13))
            .background(DesignTokens.surface)
            .cornerRadius(43)
            .overlay(
                RoundedRectangle(cornerRadius: 43)
                    .inset(by: 0.50)
                    .stroke(DesignTokens.borderColor, lineWidth: 0.50)
            )
            .frame(maxWidth: 249, alignment: .trailing)
            .textSelection(.enabled)
    }

    // MARK: - AI Message

    private var aiMessageView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Tool call indicator (if applicable)
            if let toolName = message.toolCallName {
                AliceToolCallIndicator(
                    toolName: toolName,
                    isExecuting: message.isToolExecuting
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Message content
            if message.content.isEmpty && message.isStreaming {
                thinkingState
            } else {
                messageContent
            }

            // Streaming indicator
            if message.isStreaming && !message.content.isEmpty {
                streamingIndicator
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: message.isStreaming)
        .animation(.easeInOut(duration: 0.2), value: message.content)
        .animation(.easeInOut(duration: 0.2), value: message.toolCallName)
    }

    private var thinkingState: some View {
        HStack(spacing: 8) {
            StreamingIndicator(style: .thinking, color: DesignTokens.accentColor, size: 8)
        }
        .padding(.vertical, 8)
    }

    private var messageContent: some View {
        StreamingTextView(
            text: message.content,
            isStreaming: message.isStreaming,
            textStyle: .system(size: 14),
            textColor: DesignTokens.textPrimary,
            cursorColor: DesignTokens.accentColor
        )
        .textSelection(.enabled)
    }

    private var streamingIndicator: some View {
        StreamingIndicator(style: .dots, color: DesignTokens.accentColor, size: 5)
            .padding(.top, 4)
    }
}

// MARK: - Alice Tool Call Indicator

/// Indicator showing when Alice is using a tool to fetch data
struct AliceToolCallIndicator: View {

    let toolName: String
    let isExecuting: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isExecuting {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(DesignTokens.accentColor)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(Font.custom("SFProDisplay-Regular", size: 14.f))
            }

            Text(statusText)
                .font(Font.custom("SFProDisplay-Medium", size: 12.f))
                .foregroundColor(DesignTokens.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.tertiarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(DesignTokens.borderColor.opacity(0.5), lineWidth: 0.5)
        )
    }

    private var statusText: String {
        if isExecuting {
            return toolDisplayName
        } else {
            return "Found results"
        }
    }

    private var toolDisplayName: String {
        switch toolName {
        case "search_posts":
            return "Searching posts..."
        case "get_user_profile":
            return "Looking up user..."
        case "get_trending_topics":
            return "Fetching trends..."
        case "get_recommendations":
            return "Getting recommendations..."
        default:
            return "Processing..."
        }
    }
}

// MARK: - Alice Message Bubble

/// Standard message bubble for Alice chat
struct AliceMessageBubble: View {

    let content: String
    let isUser: Bool
    var isStreaming: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUser {
                Spacer(minLength: 60)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if isStreaming && content.isEmpty {
                    AIThinkingBubble(
                        color: Color(UIColor.secondarySystemBackground),
                        indicatorColor: DesignTokens.textSecondary
                    )
                } else {
                    Text(content)
                        .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                        .foregroundColor(DesignTokens.textPrimary)
                        .padding(EdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 13))
                        .background(bubbleBackground)
                        .cornerRadius(isUser ? 43 : 18)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: isUser ? 249 : .infinity, alignment: isUser ? .trailing : .leading)

            if !isUser {
                Spacer(minLength: 60)
            }
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if isUser {
            DesignTokens.surface
                .overlay(
                    RoundedRectangle(cornerRadius: 43)
                        .inset(by: 0.50)
                        .stroke(DesignTokens.borderColor, lineWidth: 0.50)
                )
        } else {
            Color(UIColor.secondarySystemBackground)
        }
    }
}

// MARK: - Previews

#Preview("Streaming Messages") {
    VStack(spacing: 16) {
        // User message
        AliceMessageBubble(
            content: "Can you search for trending fashion posts?",
            isUser: true
        )

        // AI thinking
        AliceMessageBubble(
            content: "",
            isUser: false,
            isStreaming: true
        )

        // AI with tool call
        VStack(alignment: .leading, spacing: 8) {
            AliceToolCallIndicator(
                toolName: "search_posts",
                isExecuting: true
            )

            AliceMessageBubble(
                content: "Let me search for that...",
                isUser: false,
                isStreaming: true
            )
        }

        // AI complete
        AliceMessageBubble(
            content: "I found 5 trending fashion posts! Here are the top ones...",
            isUser: false,
            isStreaming: false
        )
    }
    .padding()
}
