import Foundation
import SwiftUI

// MARK: - Chat View Model

@MainActor
class ChatViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var conversations: [Conversation] = []
    @Published var selectedConversation: Conversation?
    @Published var messages: [Message] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Services

    private let communicationService = CommunicationService()

    // MARK: - Lifecycle

    func loadConversations() async {
        isLoading = true
        errorMessage = nil

        do {
            conversations = try await communicationService.getConversations(
                limit: 50,
                offset: 0
            )
        } catch {
            errorMessage = "Failed to load conversations: \(error.localizedDescription)"
            conversations = []
        }

        isLoading = false
    }

    // MARK: - Actions

    func selectConversation(_ conversation: Conversation) {
        selectedConversation = conversation
        // Load messages for this conversation
        Task {
            await loadMessages(for: conversation.id)
        }
    }

    func loadMessages(for conversationId: String) async {
        isLoading = true
        errorMessage = nil

        do {
            messages = try await communicationService.getMessages(
                conversationId: conversationId,
                limit: 100,
                offset: 0
            )
        } catch {
            errorMessage = "Failed to load messages: \(error.localizedDescription)"
            messages = []
        }

        isLoading = false
    }

    func sendMessage(_ text: String, to conversationId: String) async -> Bool {
        guard !text.isEmpty else { return false }

        do {
            let message = try await communicationService.sendMessage(
                conversationId: conversationId,
                content: text,
                mediaUrl: nil
            )

            // Optimistic update: append message to list
            messages.append(message)

            // Update conversation's last message
            if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
                var updatedConversation = conversations[index]
                conversations.remove(at: index)
                // Move to top of list
                conversations.insert(updatedConversation, at: 0)
            }

            return true
        } catch {
            errorMessage = "Failed to send message: \(error.localizedDescription)"
            return false
        }
    }
}
