import Foundation
import SwiftData
import Observation

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let text: String
    let mine: Bool
    let createdAt: Date
}

@Observable
@MainActor
final class ChatViewModel: @unchecked Sendable {
    var messages: [ChatMessage] = []
    var input: String = ""
    var error: String?
    var offlineMessageCount: Int = 0
    var isConnected: Bool = false

    let conversationId: UUID
    let peerUserId: UUID

    private let repo = MessagingRepository()
    private var senderPkCache: [UUID: String] = [:]
    private var socket = ChatSocket()
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

            // Setup socket callbacks
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
            socket.onError = { [weak self] err in
                Task { @MainActor in self?.error = err.localizedDescription }
            }
            // Connect WS
            let token = AuthManager.shared.accessToken
            let me = AuthManager.shared.currentUser?.id
            if let me {
                socket.connect(conversationId: conversationId, meUserId: me, jwtToken: token, peerPublicKeyB64: peerPk)

                // === CRITICAL FIX: Drain offline queue on connection ===
                // WebSocket 连接成功时，立即触发离线队列恢复
                try await drainOfflineQueue()
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

    /// 重新发送单条离线消息
    private func resendOfflineMessage(_ localMessage: LocalMessage) async {
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
            print("[ChatViewModel] ⚠️  Failed to resend offline message: \(error)")
            // 重新入队以便下次重试
            try? await messageQueue.enqueue(localMessage)
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
}
