import Foundation
import Combine

@MainActor
final class MessagingViewModel: ObservableObject {
    @Published private(set) var messages: [MessageDto] = []
    @Published private(set) var typingUsers: Set<UUID> = []

    private let repo: MessagingRepository
    private let ws: WebSocketMessagingClient
    private let storage: LocalStorageManager
    private let sync: SyncManager

    private var conversationId: UUID?
    private var userId: UUID?

    init(
        repo: MessagingRepository = MessagingRepository(),
        ws: WebSocketMessagingClient = WebSocketMessagingClient(),
        storage: LocalStorageManager = .shared,
        sync: SyncManager = .shared
    ) {
        self.repo = repo
        self.ws = ws
        self.storage = storage
        self.sync = sync
    }

    func load(conversationId: UUID) async {
        self.conversationId = conversationId
        do {
            let list = try await repo.fetchMessages(conversationId: conversationId)
            self.messages = list
        } catch {
            Logger.log("Failed to load messages: \(error)", level: .error)
        }
    }

    func connect(conversationId: UUID, userId: UUID) {
        self.userId = userId
        ws.onMessage = { [weak self] m in self?._receiveMessage(m) }
        ws.onTyping = { [weak self] _, uid in self?._receiveTyping(uid) }
        ws.onOpen = { Logger.log("WS open", level: .debug) }
        ws.onClose = { Logger.log("WS closed", level: .debug) }
        ws.connect(baseURL: AppConfig.messagingWebSocketBaseURL, conversationId: conversationId, userId: userId, token: AuthManager.shared.accessToken)

        // 嘗試重播離線消息
        Task { await replayOfflineMessages() }
    }

    func disconnect() {
        ws.disconnect()
    }

    func sendTyping() {
        guard let cid = conversationId, let uid = userId else { return }
        ws.sendTyping(conversationId: cid, userId: uid)
    }

    func sendMessage(_ text: String) async {
        guard let cid = conversationId, let uid = userId, !text.isEmpty else { return }
        do {
            let payload: String
            if FeatureFlags.enableStrictE2E,
               let peerPk = KeyManager.shared.getPeerPublicKey(for: uid) {
                let myKeys = KeyManager.shared.getOrCreateMyKeypair()
                let nonce = CryptoCoreProvider.shared.generateNonce()
                let ct = try CryptoCoreProvider.shared.encrypt(
                    plaintext: Data(text.utf8),
                    recipientPublicKey: peerPk,
                    senderSecretKey: myKeys.secretKey,
                    nonce: nonce
                )
                payload = "ENC:v1:\(nonce.base64EncodedString()):\(ct.base64EncodedString())"
            } else {
                payload = text
            }
            let _ = try await repo.sendMessage(conversationId: cid, senderId: uid, plaintext: payload)
            // 乐观更新由 WS 回显来完成
        } catch {
            Logger.log("Failed to send: \(error) -> queue offline", level: .warning)
            // 入隊離線消息（使用 idempotency_key 作為臨時 ID）
            let tempId = UUID().uuidString
            let local = LocalMessage(
                id: tempId,
                conversationId: cid.uuidString,
                senderId: uid.uuidString,
                plaintext: text,
                sequenceNumber: nil,
                syncState: .localOnly
            )
            try? await storage.save(local)
            // 本地樂觀追加（待 WS 回放時再以正式 ID 出現）
            self.messages.append(MessageDto(id: UUID(uuidString: tempId)!, senderId: uid, sequenceNumber: (self.messages.last?.sequenceNumber ?? 0) + 1, createdAt: nil))
        }
    }

    /// 在網路恢復 / 連線建立時重播離線消息
    private func replayOfflineMessages() async {
        guard let cid = conversationId, let uid = userId else { return }
        do {
            let pending = try await storage.fetch(
                LocalMessage.self,
                predicate: #Predicate { $0.conversationId == cid.uuidString && ($0.syncState == .localOnly || $0.syncState == .localModified) },
                sortBy: [SortDescriptor(\.createdAt, order: .forward)]
            )
            for item in pending {
                let idKey = UUID(uuidString: item.id) ?? UUID()
                do {
                    let resp = try await repo.sendMessage(conversationId: cid, senderId: uid, plaintext: item.plaintext, idempotencyKey: idKey)
                    // 標記同步完成，更新臨時記錄或刪除
                    try await storage.delete(item)
                    Logger.log("Replayed offline message -> seq #\(resp.sequenceNumber)", level: .info)
                } catch {
                    Logger.log("Replay failed: \(error)", level: .error)
                }
            }
        } catch {
            Logger.log("Fetch offline messages failed: \(error)", level: .error)
        }
    }

    // MARK: - Internal hooks for testability
    func _receiveMessage(_ m: MessageDto) {
        Task { @MainActor in
            if !self.messages.contains(where: { $0.id == m.id || $0.sequenceNumber == m.sequenceNumber }) {
                self.messages = (self.messages + [m]).sorted { $0.sequenceNumber < $1.sequenceNumber }
            }
        }
    }

    func _receiveTyping(_ uid: UUID) {
        Task { @MainActor in
            self.typingUsers.insert(uid)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self.typingUsers.remove(uid)
            }
        }
    }
}
