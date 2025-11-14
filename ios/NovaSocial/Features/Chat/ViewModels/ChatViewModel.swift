import Foundation
import SwiftUI

// MARK: - Chat View Model

@MainActor
class ChatViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var conversations: [Conversation] = []
    @Published var selectedConversation: Conversation?
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Temporary Model (TODO: Move to Shared/Models)

    struct Conversation: Identifiable {
        let id: String
        let userId: String
        let username: String
        let lastMessage: String
        let timestamp: Date
        let unreadCount: Int
    }

    // MARK: - Lifecycle

    func loadConversations() async {
        isLoading = true
        errorMessage = nil

        // TODO: Implement conversations loading from backend

        isLoading = false
    }

    // MARK: - Actions

    func selectConversation(_ conversation: Conversation) {
        selectedConversation = conversation
    }

    func sendMessage(_ text: String, to conversationId: String) async {
        // TODO: Implement message sending
    }
}
