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
    var searchResults: [ChatMessage] = []
    var isSearchInFlight: Bool = false

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
                    guard let self else { return }
                    self.typingUsernames.insert(uid)

                    try? await Task.sleep(nanoseconds: 3_000_000_000)

                    if !Task.isCancelled {
                        self.typingUsernames.remove(uid)
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
                    guard let self else { return }
                    self.connectionState = newState
                    switch newState {
                    case .connected:
                        self.isConnected = true
                        self.reconnectAttempt = 0
                        self.nextRetryIn = 0
                        self.error = nil
                        print("✅ WebSocket connected - draining offline queue")
                        do {
                            try await self.drainOfflineQueue()
                            await self.updateOfflineMessageCount()
                        } catch {
                            self.error = error.localizedDescription
                        }

                    case .connecting:
                        self.isConnected = false
                        self.error = nil

                    case .disconnected:
                        self.isConnected = false

                    case .failed(let err):
                        self.isConnected = false
                        self.error = err.localizedDescription

                    case .reconnecting(let attempt, let nextRetryIn):
                        self.reconnectAttempt = attempt
                        self.nextRetryIn = nextRetryIn
                        self.isConnected = false
                        let formattedDelay = String(format: "%.1f", nextRetryIn)
                        self.error = "Reconnecting... (attempt #\(attempt), in \(formattedDelay)s)"
                    }
                }
            }

            // Connect WS with auto-reconnect support
            let token = AuthManager.shared.accessToken
            let me = AuthManager.shared.currentUser?.id
            if let me {
                socket.connect(conversationId: conversationId, meUserId: me, jwtToken: token, peerPublicKeyB64: peerPk)
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
        let currentRetryCount = localMessage.retryCount

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
                // 标准指数退避：1s, 2s, 4s, 8s, 16s, 32s, 60s (capped)
                let delays = [1, 2, 4, 8, 16, 32, 60]
                let delaySeconds = Double(delays[min(currentRetryCount, delays.count - 1)])
                print("[ChatViewModel] ⏳ Will retry after \(delaySeconds) seconds...")

                // 更新消息的重试状态，等待下一次 drain
                let nextRetryAt = Date().addingTimeInterval(delaySeconds)
                try? await messageQueue.updateRetryState(
                    messageId: localMessage.id,
                    retryCount: currentRetryCount + 1,
                    nextRetryAt: nextRetryAt
                )
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
        for dto in resp.messages.reversed() { // server returns newest first
            out.append(await makeChatMessage(from: dto))
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
        let nsError = error as NSError

        // 网络层错误默认可重试
        if nsError.domain == NSURLErrorDomain || nsError.domain == "NetworkError" {
            return true
        }

        // 常见不可重试状态码或描述
        let description = nsError.localizedDescription.lowercased()
        let nonRetryableKeywords = ["400", "401", "403", "404", "invalid", "unauthorized", "forbidden"]
        if nonRetryableKeywords.contains(where: { description.contains($0) }) {
            return false
        }

        return true
    }

    func typing() {
        socket.sendTyping()
    }

    func searchMessages(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearSearchResults()
            return
        }

        isSearchInFlight = true
        do {
            let results = try await repo.searchMessages(conversationId: conversationId, query: trimmed, limit: 50)
            var mapped: [ChatMessage] = []
            for dto in results {
                mapped.append(await makeChatMessage(from: dto))
            }
            searchResults = mapped
        } catch {
            searchResults = []
            self.error = error.localizedDescription
        }
        isSearchInFlight = false
    }

    func clearSearchResults() {
        searchResults = []
        isSearchInFlight = false
    }

    // MARK: - 消息编辑

    /// 编辑消息（客户端更新本地消息，服务器会通过 WebSocket 广播更新）
    func editMessage(messageId: UUID, newText: String) async {
        do {
            // 先乐观更新 UI
            if let index = messages.firstIndex(where: { $0.id == messageId }) {
                messages[index].text = newText
            }

            // 调用 API 更新消息
            let response = try await repo.updateMessage(
                messageId: messageId,
                text: newText,
                peerUserId: peerUserId
            )

            print("[ChatViewModel] ✅ Message edited: \(messageId)")

        } catch {
            print("[ChatViewModel] ❌ Failed to edit message: \(error)")
            self.error = "Failed to edit message: \(error.localizedDescription)"
        }
    }

    // MARK: - 消息反应

    /// 添加 Emoji 反应
    func addReaction(messageId: UUID, emoji: String) async {
        do {
            _ = try await repo.addReaction(messageId: messageId, emoji: emoji)
            print("[ChatViewModel] ✅ Reaction added: \(emoji) to \(messageId)")
        } catch {
            print("[ChatViewModel] ❌ Failed to add reaction: \(error)")
            self.error = "Failed to add reaction: \(error.localizedDescription)"
        }
    }

    /// 移除 Emoji 反应
    func removeReaction(messageId: UUID, emoji: String) async {
        do {
            try await repo.removeReaction(messageId: messageId, emoji: emoji)
            print("[ChatViewModel] ✅ Reaction removed: \(emoji) from \(messageId)")
        } catch {
            print("[ChatViewModel] ❌ Failed to remove reaction: \(error)")
            self.error = "Failed to remove reaction: \(error.localizedDescription)"
        }
    }

    // MARK: - 文件/图片分享

    /// 上传附件（图片、文件等）
    func uploadAttachment(
        fileName: String,
        contentType: String,
        fileData: Data
    ) async {
        let messageId = UUID()
        let attachmentMessage = ChatMessage(
            id: messageId,
            text: "📎 \(fileName)",
            mine: true,
            createdAt: Date()
        )

        // 乐观更新 UI
        messages.append(attachmentMessage)

        do {
            let attachment = try await repo.uploadAttachment(
                conversationId: conversationId,
                messageId: messageId,
                fileName: fileName,
                contentType: contentType,
                fileData: fileData
            )

            print("[ChatViewModel] ✅ File uploaded: \(fileName)")
        } catch {
            print("[ChatViewModel] ❌ Failed to upload file: \(error)")
            self.error = "Failed to upload file: \(error.localizedDescription)"

            // 从消息列表中移除失败的消息
            if let index = messages.firstIndex(where: { $0.id == messageId }) {
                messages.remove(at: index)
            }
        }
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

    // MARK: - Private Helpers

    private func resolveSenderPublicKey(_ senderId: UUID) async throws -> String {
        if let cached = senderPkCache[senderId] {
            return cached
        }
        let key = try await repo.getPublicKey(of: senderId)
        senderPkCache[senderId] = key
        return key
    }

    private func makeChatMessage(from dto: MessageDTO) async -> ChatMessage {
        let text: String
        do {
            let senderKey = try await resolveSenderPublicKey(dto.senderId)
            text = try repo.decryptMessage(dto, senderPublicKey: senderKey)
        } catch {
            text = "(unable to decrypt)"
        }

        return ChatMessage(
            id: dto.id,
            text: text,
            mine: isMine(dto.senderId),
            createdAt: dto.createdAt,
            recalledAt: dto.deletedAt
        )
    }
}
