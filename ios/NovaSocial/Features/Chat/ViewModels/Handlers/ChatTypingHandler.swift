import Foundation
import Combine

/// Handles typing indicator management for chat
/// Extracted from ChatViewModel to follow Single Responsibility Principle
@MainActor
final class ChatTypingHandler: ObservableObject {
    // MARK: - Observable State

    /// Whether the other user is currently typing
    @Published var isOtherUserTyping = false

    /// Name of the user who is typing
    @Published var typingUserName = ""

    // MARK: - Callback (for non-SwiftUI consumers like ChatViewModel)

    /// Callback when typing state changes (for backward compatibility)
    var onTypingStateChanged: ((Bool, String) -> Void)?

    // MARK: - Dependencies

    private let chatService: ChatService
    private let conversationId: String
    private let currentUserId: String

    // MARK: - Timer

    // Use nonisolated(unsafe) for timer to allow invalidation in deinit
    nonisolated(unsafe) private var typingTimer: Timer?

    // MARK: - Init

    init(chatService: ChatService, conversationId: String, currentUserId: String) {
        self.chatService = chatService
        self.conversationId = conversationId
        self.currentUserId = currentUserId
    }

    // MARK: - Outgoing Typing Indicators

    /// Send typing start indicator to other users
    func sendTypingStart() {
        chatService.sendTypingStart(conversationId: conversationId)
    }

    /// Send typing stop indicator to other users
    func sendTypingStop() {
        chatService.sendTypingStop(conversationId: conversationId)
    }

    // MARK: - Incoming Typing Indicators

    /// Handle incoming typing indicator from WebSocket
    /// - Parameter typingData: The typing data received
    func handleTypingIndicator(_ typingData: WebSocketTypingData) {
        // Only show if it's for this conversation and not from me
        guard typingData.conversationId == conversationId,
              typingData.userId != currentUserId else { return }

        if typingData.isTyping {
            startTypingIndicator(userName: typingData.username)
        } else {
            stopTypingIndicator()
        }
    }

    /// Handle incoming typing indicator from Matrix
    /// - Parameter userIds: Array of user IDs who are typing
    func handleMatrixTypingIndicator(userIds: [String]) {
        guard !userIds.contains(currentUserId) else { return }

        if !userIds.isEmpty {
            startTypingIndicator()
        } else {
            stopTypingIndicator()
        }
    }

    // MARK: - Private Methods

    /// Start typing indicator with auto-hide timer
    /// - Parameter userName: Optional username to display
    private func startTypingIndicator(userName: String? = nil) {
        isOtherUserTyping = true
        if let userName = userName {
            typingUserName = userName
        }
        onTypingStateChanged?(isOtherUserTyping, typingUserName)

        // Cancel existing timer and start new one
        typingTimer?.invalidate()
        typingTimer = nil
        typingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stopTypingIndicator()
            }
        }
    }

    /// Stop typing indicator and cancel timer
    func stopTypingIndicator() {
        isOtherUserTyping = false
        typingUserName = ""
        onTypingStateChanged?(isOtherUserTyping, typingUserName)
        typingTimer?.invalidate()
        typingTimer = nil
    }

    // MARK: - Cleanup

    /// Clean up resources
    func cleanup() {
        typingTimer?.invalidate()
        typingTimer = nil
    }

    deinit {
        typingTimer?.invalidate()
    }
}
