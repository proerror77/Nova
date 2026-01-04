import SwiftUI

// MARK: - AI Response State

/// States for AI response generation
enum AIResponseState: Equatable {
    case idle
    case thinking
    case streaming
    case complete
    case error(String)

    static func == (lhs: AIResponseState, rhs: AIResponseState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.thinking, .thinking), (.streaming, .streaming), (.complete, .complete):
            return true
        case (.error(let lhsMsg), .error(let rhsMsg)):
            return lhsMsg == rhsMsg
        default:
            return false
        }
    }
}

// MARK: - AI Response Container

/// Container view for AI responses with state management
struct AIResponseContainer<Content: View>: View {

    let state: AIResponseState
    @ViewBuilder let content: () -> Content

    var indicatorStyle: StreamingIndicator.Style = .thinking
    var indicatorColor: Color = .accentColor
    var errorColor: Color = .red

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch state {
            case .idle:
                EmptyView()

            case .thinking:
                thinkingView

            case .streaming:
                streamingView

            case .complete:
                content()

            case .error(let message):
                errorView(message: message)
            }
        }
    }

    // MARK: - State Views

    private var thinkingView: some View {
        HStack(spacing: 8) {
            StreamingIndicator(style: indicatorStyle, color: indicatorColor)
            Spacer()
        }
        .padding(.vertical, 8)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private var streamingView: some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
            StreamingIndicator(style: .dots, color: indicatorColor, size: 6)
                .padding(.top, 4)
        }
        .transition(.opacity)
    }

    private func errorView(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(errorColor)
                .font(Font.custom("SFProDisplay-Regular", size: 14.f))

            Text(message)
                .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.vertical, 8)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - AI Message Container

/// Styled container for AI chat messages
struct AIMessageContainer<Content: View>: View {

    let isUser: Bool
    let isStreaming: Bool
    @ViewBuilder let content: () -> Content

    var userBubbleColor: Color = Color(UIColor.systemGray5)
    var aiBubbleColor: Color = Color(UIColor.secondarySystemBackground)

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUser {
                Spacer(minLength: 60)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                content()

                if isStreaming && !isUser {
                    StreamingIndicator(style: .dots, size: 5)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isUser ? userBubbleColor : aiBubbleColor)
            )

            if !isUser {
                Spacer(minLength: 60)
            }
        }
    }
}

// MARK: - Streaming Message View

/// A complete streaming message view with avatar and content
struct StreamingMessageView: View {

    let content: String
    let isUser: Bool
    let isStreaming: Bool
    var avatarImage: Image?
    var userName: String = "AI"

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !isUser {
                avatarView
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if !isUser {
                    Text(userName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                AIMessageContainer(isUser: isUser, isStreaming: isStreaming) {
                    if content.isEmpty && isStreaming {
                        StreamingIndicator(style: .typing, size: 6)
                    } else {
                        StreamingTextView(
                            text: content,
                            isStreaming: isStreaming,
                            textStyle: .body,
                            textColor: .primary
                        )
                    }
                }
            }

            if isUser {
                avatarView
            }
        }
    }

    private var avatarView: some View {
        Group {
            if let image = avatarImage {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: isUser ? "person.circle.fill" : "sparkles")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(isUser ? .secondary : .accentColor)
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
    }
}

// MARK: - Previews

#Preview("AI Response States") {
    VStack(spacing: 20) {
        AIResponseContainer(state: .thinking) {
            Text("Content")
        }

        AIResponseContainer(state: .streaming) {
            Text("Partial response text that is still being generated...")
        }

        AIResponseContainer(state: .complete) {
            Text("Complete response text here.")
        }

        AIResponseContainer(state: .error("Failed to generate response")) {
            EmptyView()
        }
    }
    .padding()
}

#Preview("Streaming Messages") {
    VStack(spacing: 16) {
        StreamingMessageView(
            content: "Hello! How can I help you today?",
            isUser: false,
            isStreaming: false,
            userName: "Alice"
        )

        StreamingMessageView(
            content: "Can you search for trending topics?",
            isUser: true,
            isStreaming: false
        )

        StreamingMessageView(
            content: "Let me search for that...",
            isUser: false,
            isStreaming: true,
            userName: "Alice"
        )
    }
    .padding()
}
