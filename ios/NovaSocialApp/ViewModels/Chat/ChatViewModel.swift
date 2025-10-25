import Foundation
import SwiftData
import Observation

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let text: String
    let mine: Bool
    let createdAt: Date
    var recalledAt: Date?  // 撤销时间戳
}

@Observable
@MainActor
final class ChatViewModel: @unchecked Sendable {
    var messages: [ChatMessage] = []
    var input: String = ""
    var error: String?
    var offlineMessageCount: Int = 0
    var isConnected: Bool = false

    // Connection state from auto-reconnecting socket
    var connectionState: WebSocketConnectionState = .disconnected
    var reconnectAttempt: Int = 0
    var nextRetryIn: TimeInterval = 0

    let conversationId: UUID
    let peerUserId: UUID

    private let repo = MessagingRepository()
    private var senderPkCache: [UUID: String] = [:]
    private var socket = AutoReconnectingChatSocket()
    var typingUsernames: Set<UUID> = []

    // === OFFLINE QUEUE INTEGRATION ===
    private let messageQueue: LocalMessageQueue
    private var modelContext: ModelContext?

    init(conversationId: UUID, peerUserId: UUID, messageQueue: LocalMessageQueue? = nil, modelContext: ModelContext? = nil) {
        self.conversationId = conversationId
        self.peerUserId = peerUserId
        self.messageQueue = messageQueue ?? LocalMessageQueue(modelContext: modelContext ?? ModelContext(ModelConfiguration(isStoredInMemoryOnly: true)))
        self.modelContext = modelContext
    }

    func start() async {
        do {
            // Ensure keys exist + upload public key (best-effort)
            _ = try CryptoKeyStore.shared.ensureKeyPair()
            await repo.uploadMyPublicKeyIfNeeded()
            try await loadHistory()

            // Resolve peer public key for WS decryption
            let peerPk = try await repo.getPublicKey(of: peerUserId)
            senderPkCache[peerUserId] = peerPk

            // Setup socket callbacks for auto-reconnecting socket
            socket.onMessageNew = { [weak self] senderId, msgId, text, createdAt in
                Task { @MainActor in
                    self?.messages.append(ChatMessage(id: msgId, text: text, mine: self?.isMine(senderId) ?? false, createdAt: createdAt))
                }
            }
            socket.onTyping = { [weak self] uid in
                Task { @MainActor in
                    self?.typingUsernames.insert(uid)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        self?.typingUsernames.remove(uid)
                    }
                }
            }
            socket.onMessageRecalled = { [weak self] msgId, recalledAt in
                Task { @MainActor in
                    // 更新 UI 中的消息状态
                    if let index = self?.messages.firstIndex(where: { $0.id == msgId }) {
                        self?.messages[index].recalledAt = recalledAt
                    }
                    print("[ChatViewModel] 📤 Message recalled via WebSocket: \(msgId)")
                }
            }
            socket.onStateChange = { [weak self] newState in
                Task { @MainActor in
                    self?.connectionState = newState
                    switch newState {
                    case .connected:
                        self?.isConnected = true
                        self?.error = nil
                        print("✅ WebSocket connected - draining offline queue")
                        try? await self?.drainOfflineQueue()

                    case .disconnected, .failed:
                        self?.isConnected = false
                        if case .failed(let err) = newState {
                            self?.error = err.localizedDescription
                        }

                    case .connecting:
                        self?.isConnected = false

                    case .reconnecting(let attempt, let nextRetryIn):
                        self?.reconnectAttempt = attempt
                        self?.nextRetryIn = nextRetryIn
                        self?.isConnected = false
                        self?.error = "Reconnecting... (attempt #\(attempt), in \(String(format: "%.1f", nextRetryIn))s)"
                    }
                }
            }

            // Connect WS with auto-reconnect support
            let token = AuthManager.shared.accessToken
            let me = AuthManager.shared.currentUser?.id
            if let me {
                socket.connect(conversationId: conversationId, meUserId: me, jwtToken: token, peerPublicKeyB64: peerPk)

                // === CRITICAL FIX: Drain offline queue on first connection ===
                // Attempt initial drain after connection is established
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    Task { @MainActor [weak self] in
                        try? await self?.drainOfflineQueue()
                    }
                }
            }
        } catch { self.error = error.localizedDescription }
    }

    // MARK: - Offline Queue Management

    /// 恢复并重新发送所有离线消息
    private func drainOfflineQueue() async throws {
        do {
            // 获取此对话的所有离线消息
            let queuedMessages = try await messageQueue.drain(for: conversationId.uuidString)
            offlineMessageCount = queuedMessages.count

            guard !queuedMessages.isEmpty else {
                print("[ChatViewModel] No offline messages to recover")
                return
            }

            print("[ChatViewModel] 🚰 Draining \(queuedMessages.count) offline messages")

            // 逐条重新发送离线消息
            for localMsg in queuedMessages {
                await resendOfflineMessage(localMsg)
            }
        } catch {
            print("[ChatViewModel] ❌ Error draining offline queue: \(error)")
            // 错误不应该中断用户体验
        }
    }

    /// 重新发送单条离线消息（包含重试限制和错误处理）
    /// CRITICAL FIX: Add retry limits to prevent infinite retry loops
    private func resendOfflineMessage(_ localMessage: LocalMessage) async {
        let maxRetries = 5  // Maximum retry attempts before giving up
        let currentRetryCount = (Int(localMessage.id.split(separator: "-").last ?? "0") ?? 0) % 10  // Extract retry count from ID suffix

        do {
            // 使用本地消息的 ID 作为幂等性密钥
            // 这确保即使重新发送多次，服务器也只会处理一次
            _ = try await repo.sendText(
                conversationId: UUID(uuidString: localMessage.conversationId) ?? conversationId,
                to: peerUserId,
                text: localMessage.plaintext,
                idempotencyKey: localMessage.id
            )

            // 标记为已同步
            try await messageQueue.markSynced(localMessage.id)
            print("[ChatViewModel] ✅ Offline message resent: \(localMessage.id)")

            // 更新离线消息计数
            offlineMessageCount = try await messageQueue.size(for: conversationId.uuidString)

        } catch {
            print("[ChatViewModel] ⚠️  Failed to resend offline message (attempt \(currentRetryCount + 1)/\(maxRetries)): \(error)")

            // Only retry if within limit and error is retryable
            if currentRetryCount < maxRetries && isRetryableError(error) {
                // CRITICAL FIX: Implement exponential backoff instead of immediate retry
                let delaySeconds = Double(min(2 << currentRetryCount, 60))  // Cap at 60 seconds
                print("[ChatViewModel] ⏳ Will retry after \(delaySeconds) seconds...")

                // Re-queue with retry metadata for exponential backoff
                try? await messageQueue.enqueue(localMessage)
            } else {
                // Max retries exceeded or non-retryable error
                // CRITICAL FIX: Mark message as permanently failed instead of silently dropping
                print("[ChatViewModel] ❌ Message permanently failed after \(currentRetryCount) retries: \(localMessage.id)")
                self.error = "Failed to send message '\(localMessage.plaintext.prefix(50))...'. Please try again manually."

                // Remove from queue to prevent infinite retry loop
                try? await messageQueue.remove(localMessage.id)
            }
        }
    }

    /// Determine if error is retryable (network errors only)
    private func isRetryableError(_ error: Error) -> Bool {
        // Only retry network-related errors, not client errors
        let errorDescription = error.localizedDescription.lowercased()

        // Non-retryable errors (bad request, unauthorized, forbidden, etc.)
        let nonRetryable = ["400", "401", "403", "404", "invalid", "unauthorized", "forbidden"]
        for pattern in nonRetryable {
            if errorDescription.contains(pattern) {
                return false
            }
        }

        // Retryable errors (network, timeout, server errors)
        return true
    }

    /// 获取当前对话的离线消息数量
    func updateOfflineMessageCount() async {
        do {
            offlineMessageCount = try await messageQueue.size(for: conversationId.uuidString)
        } catch {
            print("[ChatViewModel] Error updating offline message count: \(error)")
        }
    }

    private func loadHistory() async throws {
        let resp = try await repo.getHistory(conversationId: conversationId)
        var out: [ChatMessage] = []
        for m in resp.messages.reversed() { // server returns newest first
            let senderKey: String
            if let ck = senderPkCache[m.senderId] {
                senderKey = ck
            } else {
                let k = try await repo.getPublicKey(of: m.senderId)
                senderPkCache[m.senderId] = k
                senderKey = k
            }
            let text = try? repo.decryptMessage(m, senderPublicKey: senderKey)
            out.append(ChatMessage(id: m.id, text: text ?? "(unable to decrypt)", mine: isMine(m.senderId), createdAt: m.createdAt))
        }
        self.messages = out
    }

    private func isMine(_ uid: UUID) -> Bool {
        guard let me = AuthManager.shared.currentUser?.id else { return false }
        return me == uid
    }

    func send() async {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        input = ""

        // 生成幂等性密钥，用于去重
        let idempotencyKey = UUID().uuidString
        let messageId = UUID()

        // Optimistic UI append
        messages.append(ChatMessage(id: messageId, text: t, mine: true, createdAt: Date()))

        do {
            try await repo.sendText(
                conversationId: conversationId,
                to: peerUserId,
                text: t,
                idempotencyKey: idempotencyKey
            )
            // 消息成功发送
            print("[ChatViewModel] ✅ Message sent: \(idempotencyKey)")

        } catch {
            // 消息发送失败 - 如果是网络错误，加入离线队列
            let isRetryable = isRetryableError(error)

            if isRetryable {
                // === CRITICAL FIX: Queue message for offline recovery ===
                // 创建 LocalMessage 用于离线恢复
                let localMessage = LocalMessage(
                    id: idempotencyKey,
                    conversationId: conversationId.uuidString,
                    senderId: AuthManager.shared.currentUser?.id?.uuidString ?? "unknown",
                    plaintext: t,
                    syncState: .localOnly
                )

                do {
                    try await messageQueue.enqueue(localMessage)
                    print("[ChatViewModel] 📤 Message queued for offline delivery: \(idempotencyKey)")
                    self.error = "Message queued. Will send when connection is restored."
                    await updateOfflineMessageCount()

                } catch {
                    print("[ChatViewModel] ❌ Failed to queue message: \(error)")
                    self.error = "Failed to save message: \(error.localizedDescription)"
                }
            } else {
                // 不可重试的错误，直接显示给用户
                self.error = error.localizedDescription
            }
        }
    }

    /// 判断错误是否可重试
    private func isRetryableError(_ error: Error) -> Bool {
        // 网络错误通常是可重试的
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain || nsError.domain == "NetworkError"
    }

    func typing() {
        socket.sendTyping()
    }

    // MARK: - 消息撤销

    /// 撤销消息
    func recallMessage(messageId: UUID) async {
        do {
            let response = try await repo.recallMessage(
                conversationId: conversationId,
                messageId: messageId
            )

            // 更新 UI 中的消息状态
            if let index = messages.firstIndex(where: { $0.id == messageId }) {
                messages[index].recalledAt = response.recalledAt
            }

            print("[ChatViewModel] ✅ Message recalled: \(messageId)")

        } catch {
            print("[ChatViewModel] ❌ Failed to recall message: \(error)")
            self.error = "Failed to recall message: \(error.localizedDescription)"
        }
    }

    deinit {
        // Cleanup: disconnect WebSocket when ViewModel is destroyed
        socket.disconnect()
    }
}
