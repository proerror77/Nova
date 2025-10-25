import Foundation

final class MessagingRepository {
    private let apiClient: APIClient
    private let interceptor: RequestInterceptor

    init(apiClient: APIClient? = nil) {
        self.apiClient = apiClient ?? APIClient(baseURL: AppConfig.baseURL)
        self.interceptor = RequestInterceptor(apiClient: self.apiClient)
    }

    // MARK: - Public Keys

    func uploadMyPublicKeyIfNeeded() async {
        guard let pk = CryptoKeyStore.shared.getPublicKey() else { return }
        let endpoint = APIEndpoint(
            path: "/api/v1/users/me/public-key",
            method: .put,
            body: ["public_key": pk]
        )
        do { try await interceptor.executeNoResponseWithRetry(endpoint) } catch { /* best-effort */ }
    }

    func getPublicKey(of userId: UUID) async throws -> String {
        let endpoint = APIEndpoint(
            path: "/api/v1/users/\(userId.uuidString)/public-key",
            method: .get
        )
        let resp: PublicKeyResponseDTO = try await interceptor.executeWithRetry(endpoint, authenticated: false)
        return resp.publicKey
    }

    // MARK: - Messages

    func getHistory(conversationId: UUID, before: UUID? = nil, limit: Int = 50) async throws -> MessageHistoryResponseDTO {
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let b = before { items.append(URLQueryItem(name: "before", value: b.uuidString)) }
        let ep = APIEndpoint(path: "/api/v1/conversations/\(conversationId.uuidString)/messages", method: .get, queryItems: items)
        return try await interceptor.executeWithRetry(ep)
    }

    func sendText(conversationId: UUID, to peerUserId: UUID, text: String) async throws {
        do {
            // Ensure my keys
            let (myPk, mySk) = try CryptoKeyStore.shared.ensureKeyPair()
            // Best-effort upload
            await uploadMyPublicKeyIfNeeded()
            // Fetch peer's PK
            let peerPk = try await getPublicKey(of: peerUserId)
            // Encrypt
            let data = Data(text.utf8)
            let enc = try NaClCrypto.encrypt(plaintext: data, mySecretKeyB64: mySk, recipientPublicKeyB64: peerPk)
            let req = SendMessageRequestDTO(
                conversationId: conversationId,
                encryptedContent: enc.ciphertextB64,
                nonce: enc.nonceB64,
                messageType: "text",
                searchText: nil
            )
            let ep = APIEndpoint(path: "/api/v1/messages", method: .post, body: req)
            let _: MessageDTO = try await interceptor.executeWithRetry(ep)
            // Note: server publishes WS event for real-time delivery via messaging-service
        } catch {
            // 如果发送失败，添加到离线队列
            if NetworkMonitor.shared.isConnected == false {
                OfflineMessageQueue.shared.enqueue(
                    conversationId: conversationId,
                    peerUserId: peerUserId,
                    text: text
                )
            }
            throw error
        }
    }

    func decryptMessage(_ m: MessageDTO, senderPublicKey: String) throws -> String {
        guard let mySk = CryptoKeyStore.shared.getSecretKey() else { throw NSError(domain: "no-secret-key", code: -1) }
        let data = try NaClCrypto.decrypt(ciphertextB64: m.encryptedContent, nonceB64: m.nonce, senderPublicKeyB64: senderPublicKey, mySecretKeyB64: mySk)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Conversations
    private struct CreateConversationRequestDTO: Codable {
        let conv_type: String
        let name: String? = nil
        let participant_ids: [UUID]
    }
    private struct CreateConversationResponseDTO: Codable { let id: UUID }

    func createDirectConversation(with peerUserId: UUID) async throws -> UUID {
        let body = CreateConversationRequestDTO(conv_type: "direct", participant_ids: [peerUserId])
        let ep = APIEndpoint(path: "/api/v1/conversations", method: .post, body: body)
        let resp: CreateConversationResponseDTO = try await interceptor.executeWithRetry(ep)
        return resp.id
    }
}
