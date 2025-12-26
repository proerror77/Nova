import Foundation

/// Handles WebSocket and Matrix callback management for chat
/// Extracted from ChatViewModel to follow Single Responsibility Principle
@MainActor
final class ChatWebSocketHandler {
    // MARK: - Dependencies

    private let chatService: ChatService
    private let conversationId: String
    private let currentUserId: String

    // MARK: - State

    /// Whether Matrix E2EE is enabled
    private(set) var isMatrixE2EEEnabled = false

    // MARK: - Callbacks

    /// Called when a new message is received
    var onMessageReceived: ((Message) -> Void)?

    /// Called when typing indicator is received
    var onTypingReceived: ((WebSocketTypingData) -> Void)?

    /// Called when Matrix typing indicator is received
    var onMatrixTypingReceived: (([String]) -> Void)?

    /// Called when read receipt is received
    var onReadReceiptReceived: ((WebSocketReadReceiptData) -> Void)?

    /// Called when connection status changes
    var onConnectionStatusChanged: ((Bool) -> Void)?

    /// Called when Matrix E2EE state changes
    var onMatrixE2EEStateChanged: ((Bool) -> Void)?

    // MARK: - Init

    init(chatService: ChatService, conversationId: String, currentUserId: String) {
        self.chatService = chatService
        self.conversationId = conversationId
        self.currentUserId = currentUserId
    }

    // MARK: - Setup

    /// Enable Matrix E2EE and setup callbacks
    func setupConnections() {
        // Enable Matrix E2EE
        chatService.enableMatrixE2EE()
        isMatrixE2EEEnabled = MatrixBridgeService.shared.isInitialized
        onMatrixE2EEStateChanged?(isMatrixE2EEEnabled)

        #if DEBUG
        print("[ChatWebSocketHandler] Matrix E2EE enabled: \(isMatrixE2EEEnabled)")
        #endif

        // Setup WebSocket callbacks
        setupWebSocketCallbacks()

        // Setup Matrix handler if enabled
        if isMatrixE2EEEnabled {
            setupMatrixMessageHandler()
        }
    }

    /// Connect WebSocket
    func connect() {
        chatService.connectWebSocket(conversationId: conversationId, userId: currentUserId)
    }

    /// Disconnect WebSocket
    func disconnect() {
        chatService.disconnectWebSocket()
    }

    // MARK: - WebSocket Callbacks

    /// Setup WebSocket event callbacks
    private func setupWebSocketCallbacks() {
        // New message received
        chatService.onMessageReceived = { [weak self] newMessage in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                // 跳過自己發送的訊息（避免與 optimistic update 重複）
                if newMessage.senderId == self.currentUserId {
                    #if DEBUG
                    print("[ChatWebSocketHandler] Skipping own message from WebSocket: \(newMessage.id)")
                    #endif
                    return
                }

                self.onMessageReceived?(newMessage)
            }
        }

        // Typing indicator received
        chatService.onTypingIndicator = { [weak self] typingData in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Only process if it's for this conversation
                guard typingData.conversationId == self.conversationId else { return }

                self.onTypingReceived?(typingData)
            }
        }

        // Read receipt received
        chatService.onReadReceipt = { [weak self] readData in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard readData.conversationId == self.conversationId else { return }

                self.onReadReceiptReceived?(readData)

                #if DEBUG
                print("[ChatWebSocketHandler] Read receipt: \(readData.userId) read up to \(readData.lastReadMessageId)")
                #endif
            }
        }

        // Connection status
        chatService.onConnectionStatusChanged = { [weak self] isConnected in
            Task { @MainActor [weak self] in
                self?.onConnectionStatusChanged?(isConnected)
            }
        }
    }

    // MARK: - Matrix Callbacks

    /// Setup Matrix Bridge message handler for E2EE messages
    private func setupMatrixMessageHandler() {
        MatrixBridgeService.shared.onMatrixMessage = { [weak self] conversationId, matrixMessage in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // 只處理當前會話的訊息
                guard conversationId == self.conversationId else { return }

                // 跳過自己發送的訊息（避免與 optimistic update 重複）
                let myMatrixId = MatrixBridgeService.shared.matrixUserId
                #if DEBUG
                print("[ChatWebSocketHandler] Matrix message received - senderId: \(matrixMessage.senderId), myMatrixId: \(myMatrixId ?? "nil"), messageId: \(matrixMessage.id)")
                #endif

                if let myId = myMatrixId, matrixMessage.senderId == myId {
                    #if DEBUG
                    print("[ChatWebSocketHandler] ✅ Skipping own message from Matrix sync: \(matrixMessage.id)")
                    #endif
                    return
                }

                // 轉換 Matrix 訊息為 Nova 訊息格式
                let novaMessage = MatrixBridgeService.shared.convertToNovaMessage(
                    matrixMessage,
                    conversationId: conversationId
                )

                self.onMessageReceived?(novaMessage)
            }
        }

        // Matrix 打字指示器
        MatrixBridgeService.shared.onTypingIndicator = { [weak self] conversationId, userIds in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard conversationId == self.conversationId else { return }

                self.onMatrixTypingReceived?(userIds)
            }
        }

        #if DEBUG
        print("[ChatWebSocketHandler] Matrix message handler setup complete")
        #endif
    }

    // MARK: - Cleanup

    /// Clean up all callbacks and connections
    func cleanup() {
        // Clear all WebSocket callbacks
        chatService.onMessageReceived = nil
        chatService.onTypingIndicator = nil
        chatService.onReadReceipt = nil
        chatService.onConnectionStatusChanged = nil

        // Clear Matrix callbacks
        MatrixBridgeService.shared.onMatrixMessage = nil
        MatrixBridgeService.shared.onTypingIndicator = nil

        // Disconnect WebSocket
        chatService.disconnectWebSocket()

        #if DEBUG
        print("[ChatWebSocketHandler] Cleanup completed for conversation \(conversationId)")
        #endif
    }
}
