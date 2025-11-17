# iOS Client Integration Guide: Private Messaging

**Version**: 1.0
**Last Updated**: 2025-10-19
**Target**: Phase 7B Feature 2

## Overview

本指南说明如何在 iOS 客户端集成私密消息功能，包括端到端加密、WebSocket 实时通信和消息历史管理。

**核心原则**：
1. **客户端加密**：所有消息在发送前加密，服务端不可读
2. **密钥安全**：私钥永不离开设备，存储在 Keychain
3. **实时同步**：WebSocket 推送新消息、typing 指示器、已读回执

---

## Prerequisites

### 1. Install TweetNaCl

使用 Swift Package Manager 安装 TweetNaCl 加密库：

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/bitmark-inc/tweetnacl-swiftwrap", from: "1.1.0")
]
```

或在 Xcode 中：
1. File → Add Packages...
2. 输入 URL: `https://github.com/bitmark-inc/tweetnacl-swiftwrap`
3. 选择版本 `1.1.0`

### 2. Install Starscream (WebSocket)

```swift
dependencies: [
    .package(url: "https://github.com/daltoniam/Starscream.git", from: "4.0.0")
]
```

### 3. API Client Setup

```swift
import Foundation

struct APIClient {
    static let baseURL = "https://api.nova.app/api/v1"
    static var authToken: String?

    static func setAuthToken(_ token: String) {
        authToken = token
    }

    static func request<T: Decodable>(
        _ endpoint: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> T {
        guard let url = URL(string: baseURL + endpoint) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = authToken {
            request.setValue("Bearer \\(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            request.httpBody = body
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum NetworkError: Error {
    case invalidURL
    case serverError
    case decodingError
}
```

---

## Part 1: Encryption Setup

### 1.1 Generate Identity Key Pair

每个用户生成一次身份密钥对（首次登录时）：

```swift
import TweetNacl

class EncryptionManager {
    private let keychain = KeychainManager.shared

    /// Generate and store user's identity key pair
    func generateIdentityKeys() throws -> String {
        let keyPair = NaclBox.keyPair()

        // Store secret key in Keychain (NEVER upload)
        try keychain.save(
            key: "user_secret_key",
            data: keyPair.secretKey
        )

        // Return public key to upload to server
        return keyPair.publicKey.base64EncodedString()
    }

    /// Get user's secret key from Keychain
    func getSecretKey() throws -> Data {
        return try keychain.load(key: "user_secret_key")
    }
}

// Keychain wrapper (simplified)
class KeychainManager {
    static let shared = KeychainManager()

    func save(key: String, data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary) // Remove old value
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed
        }
    }

    func load(key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.loadFailed
        }

        return data
    }
}

enum KeychainError: Error {
    case saveFailed
    case loadFailed
}
```

### 1.2 Upload Public Key to Server

```swift
func uploadPublicKey() async throws {
    let encryptionManager = EncryptionManager()
    let publicKey = try encryptionManager.generateIdentityKeys()

    struct UploadPublicKeyRequest: Encodable {
        let public_key: String
    }

    let request = UploadPublicKeyRequest(public_key: publicKey)
    let body = try JSONEncoder().encode(request)

    let _: EmptyResponse = try await APIClient.request(
        "/users/me/public-key",
        method: "POST",
        body: body
    )
}

struct EmptyResponse: Decodable {}
```

### 1.3 Encrypt Message (1:1 Conversation)

```swift
extension EncryptionManager {
    /// Encrypt message for 1:1 conversation
    func encryptMessage(
        plaintext: String,
        recipientPublicKey: String
    ) throws -> EncryptedMessage {
        // Get user's secret key
        let secretKey = try getSecretKey()

        // Decode recipient's public key
        guard let recipientPubKey = Data(base64Encoded: recipientPublicKey) else {
            throw EncryptionError.invalidPublicKey
        }

        // Compute shared secret (Diffie-Hellman)
        let sharedSecret = NaclBox.before(
            publicKey: recipientPubKey,
            secretKey: secretKey
        )

        // Generate unique nonce
        let nonce = NaclBox.nonce()

        // Encrypt plaintext
        guard let plaintextData = plaintext.data(using: .utf8) else {
            throw EncryptionError.invalidPlaintext
        }

        let ciphertext = NaclBox.box(
            message: plaintextData,
            nonce: nonce,
            sharedSecret: sharedSecret
        )

        return EncryptedMessage(
            ciphertext: ciphertext.base64EncodedString(),
            nonce: nonce.base64EncodedString()
        )
    }

    /// Decrypt message from 1:1 conversation
    func decryptMessage(
        ciphertext: String,
        nonce: String,
        senderPublicKey: String
    ) throws -> String {
        // Get user's secret key
        let secretKey = try getSecretKey()

        // Decode inputs
        guard let ciphertextData = Data(base64Encoded: ciphertext),
              let nonceData = Data(base64Encoded: nonce),
              let senderPubKey = Data(base64Encoded: senderPublicKey) else {
            throw EncryptionError.invalidInput
        }

        // Compute shared secret
        let sharedSecret = NaclBox.before(
            publicKey: senderPubKey,
            secretKey: secretKey
        )

        // Decrypt
        guard let plaintext = NaclBox.open(
            ciphertext: ciphertextData,
            nonce: nonceData,
            sharedSecret: sharedSecret
        ) else {
            throw EncryptionError.decryptionFailed
        }

        return String(data: plaintext, encoding: .utf8) ?? ""
    }
}

struct EncryptedMessage {
    let ciphertext: String
    let nonce: String
}

enum EncryptionError: Error {
    case invalidPublicKey
    case invalidPlaintext
    case invalidInput
    case decryptionFailed
}
```

---

## Part 2: Conversation Management

### 2.1 Create Conversation

```swift
struct Conversation: Codable, Identifiable {
    let id: UUID
    let type: String  // "direct" or "group"
    let name: String?
    let createdBy: UUID
    let createdAt: Date
    let updatedAt: Date
    let members: [ConversationMember]?

    enum CodingKeys: String, CodingKey {
        case id, type, name
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case members
    }
}

struct ConversationMember: Codable {
    let userId: UUID
    let username: String
    let role: String
    let joinedAt: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username, role
        case joinedAt = "joined_at"
    }
}

class ConversationService {
    /// Create a direct conversation
    func createDirectConversation(with userId: UUID) async throws -> Conversation {
        struct CreateConversationRequest: Encodable {
            let type: String
            let participant_ids: [UUID]
        }

        let request = CreateConversationRequest(
            type: "direct",
            participant_ids: [userId]
        )

        let body = try JSONEncoder().encode(request)

        return try await APIClient.request(
            "/conversations",
            method: "POST",
            body: body
        )
    }

    /// Create a group conversation
    func createGroupConversation(
        name: String,
        participantIds: [UUID]
    ) async throws -> Conversation {
        struct CreateGroupRequest: Encodable {
            let type: String
            let name: String
            let participant_ids: [UUID]
        }

        let request = CreateGroupRequest(
            type: "group",
            name: name,
            participant_ids: participantIds
        )

        let body = try JSONEncoder().encode(request)

        return try await APIClient.request(
            "/conversations",
            method: "POST",
            body: body
        )
    }
}
```

### 2.2 List Conversations

```swift
struct ConversationListResponse: Decodable {
    let conversations: [ConversationWithMetadata]
    let total: Int
    let limit: Int
    let offset: Int
}

struct ConversationWithMetadata: Codable, Identifiable {
    let id: UUID
    let type: String
    let name: String?
    let lastMessage: MessagePreview?
    let unreadCount: Int
    let updatedAt: Date
    let isMuted: Bool
    let isArchived: Bool

    enum CodingKeys: String, CodingKey {
        case id, type, name
        case lastMessage = "last_message"
        case unreadCount = "unread_count"
        case updatedAt = "updated_at"
        case isMuted = "is_muted"
        case isArchived = "is_archived"
    }
}

struct MessagePreview: Codable {
    let id: UUID
    let senderId: UUID
    let encryptedContent: String
    let nonce: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case senderId = "sender_id"
        case encryptedContent = "encrypted_content"
        case nonce
        case createdAt = "created_at"
    }
}

extension ConversationService {
    func listConversations(
        limit: Int = 20,
        offset: Int = 0,
        includeArchived: Bool = false
    ) async throws -> ConversationListResponse {
        return try await APIClient.request(
            "/conversations?limit=\\(limit)&offset=\\(offset)&archived=\\(includeArchived)"
        )
    }
}
```

---

## Part 3: Messaging

### 3.1 Send Message

```swift
struct Message: Codable, Identifiable {
    let id: UUID
    let conversationId: UUID
    let senderId: UUID
    let encryptedContent: String
    let nonce: String
    let messageType: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case encryptedContent = "encrypted_content"
        case nonce
        case messageType = "message_type"
        case createdAt = "created_at"
    }
}

class MessageService {
    private let encryptionManager = EncryptionManager()

    func sendMessage(
        to conversationId: UUID,
        plaintext: String,
        recipientPublicKey: String
    ) async throws -> Message {
        // 1. Encrypt message
        let encrypted = try encryptionManager.encryptMessage(
            plaintext: plaintext,
            recipientPublicKey: recipientPublicKey
        )

        // 2. Send to server
        struct SendMessageRequest: Encodable {
            let conversation_id: UUID
            let encrypted_content: String
            let nonce: String
            let message_type: String
        }

        let request = SendMessageRequest(
            conversation_id: conversationId,
            encrypted_content: encrypted.ciphertext,
            nonce: encrypted.nonce,
            message_type: "text"
        )

        let body = try JSONEncoder().encode(request)

        return try await APIClient.request(
            "/messages",
            method: "POST",
            body: body
        )
    }
}
```

### 3.2 Get Message History

```swift
struct MessageHistoryResponse: Decodable {
    let messages: [Message]
    let hasMore: Bool
    let nextCursor: UUID?

    enum CodingKeys: String, CodingKey {
        case messages
        case hasMore = "has_more"
        case nextCursor = "next_cursor"
    }
}

extension MessageService {
    func getMessageHistory(
        conversationId: UUID,
        limit: Int = 50,
        before: UUID? = nil
    ) async throws -> MessageHistoryResponse {
        var url = "/conversations/\\(conversationId)/messages?limit=\\(limit)"
        if let before = before {
            url += "&before=\\(before)"
        }

        return try await APIClient.request(url)
    }
}
```

### 3.3 Mark as Read

```swift
extension MessageService {
    func markAsRead(
        conversationId: UUID,
        messageId: UUID
    ) async throws {
        struct MarkAsReadRequest: Encodable {
            let message_id: UUID
        }

        let request = MarkAsReadRequest(message_id: messageId)
        let body = try JSONEncoder().encode(request)

        let _: EmptyResponse = try await APIClient.request(
            "/conversations/\\(conversationId)/read",
            method: "POST",
            body: body
        )
    }
}
```

---

## Part 4: WebSocket Real-Time

### 4.1 WebSocket Connection

```swift
import Starscream

class MessagingWebSocketManager: WebSocketDelegate {
    private var socket: WebSocket?
    private let authToken: String

    init(authToken: String) {
        self.authToken = authToken
    }

    func connect() {
        let url = URL(string: "wss://api.nova.app/ws?token=\\(authToken)")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        socket = WebSocket(request: request)
        socket?.delegate = self
        socket?.connect()
    }

    func disconnect() {
        socket?.disconnect()
    }

    // MARK: - WebSocketDelegate

    func didReceive(event: WebSocketEvent, client: WebSocket) {
        switch event {
        case .connected(let headers):
            print("WebSocket connected: \\(headers)")

        case .disconnected(let reason, let code):
            print("WebSocket disconnected: \\(reason) with code: \\(code)")

        case .text(let string):
            handleMessage(string)

        case .binary(let data):
            print("Received binary data: \\(data.count) bytes")

        case .error(let error):
            print("WebSocket error: \\(error?.localizedDescription ?? "unknown")")

        case .cancelled:
            print("WebSocket cancelled")

        default:
            break
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "connection.established":
            handleConnectionEstablished(json)

        case "message.new":
            handleNewMessage(json)

        case "typing.indicator":
            handleTypingIndicator(json)

        case "message.read":
            handleReadReceipt(json)

        default:
            print("Unknown event type: \\(type)")
        }
    }

    private func handleConnectionEstablished(_ json: [String: Any]) {
        guard let data = json["data"] as? [String: Any],
              let userId = data["user_id"] as? String else {
            return
        }

        print("Connected as user: \\(userId)")
    }

    private func handleNewMessage(_ json: [String: Any]) {
        // Parse and decrypt message
        guard let data = json["data"] as? [String: Any],
              let idString = data["id"] as? String,
              let id = UUID(uuidString: idString),
              let conversationIdString = data["conversation_id"] as? String,
              let conversationId = UUID(uuidString: conversationIdString),
              let senderIdString = data["sender_id"] as? String,
              let senderId = UUID(uuidString: senderIdString),
              let encryptedContent = data["encrypted_content"] as? String,
              let nonce = data["nonce"] as? String else {
            return
        }

        // TODO: Get sender's public key
        // TODO: Decrypt message
        // TODO: Notify UI

        print("New message in conversation \\(conversationId)")
    }

    private func handleTypingIndicator(_ json: [String: Any]) {
        guard let data = json["data"] as? [String: Any],
              let conversationIdString = data["conversation_id"] as? String,
              let conversationId = UUID(uuidString: conversationIdString),
              let username = data["username"] as? String,
              let isTyping = data["is_typing"] as? Bool else {
            return
        }

        // Notify UI
        NotificationCenter.default.post(
            name: .userTypingStatusChanged,
            object: nil,
            userInfo: [
                "conversationId": conversationId,
                "username": username,
                "isTyping": isTyping
            ]
        )
    }

    private func handleReadReceipt(_ json: [String: Any]) {
        guard let data = json["data"] as? [String: Any],
              let conversationIdString = data["conversation_id"] as? String,
              let conversationId = UUID(uuidString: conversationIdString),
              let userIdString = data["user_id"] as? String,
              let userId = UUID(uuidString: userIdString),
              let lastReadMessageIdString = data["last_read_message_id"] as? String,
              let lastReadMessageId = UUID(uuidString: lastReadMessageIdString) else {
            return
        }

        // Notify UI to update read status
        NotificationCenter.default.post(
            name: .messageReadStatusChanged,
            object: nil,
            userInfo: [
                "conversationId": conversationId,
                "userId": userId,
                "lastReadMessageId": lastReadMessageId
            ]
        )
    }

    // MARK: - Send Events

    func sendTypingStart(conversationId: UUID) {
        let event: [String: Any] = [
            "type": "typing.start",
            "data": [
                "conversation_id": conversationId.uuidString
            ]
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: event),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            socket?.write(string: jsonString)
        }
    }

    func sendTypingStop(conversationId: UUID) {
        let event: [String: Any] = [
            "type": "typing.stop",
            "data": [
                "conversation_id": conversationId.uuidString
            ]
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: event),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            socket?.write(string: jsonString)
        }
    }
}

// Notification names
extension Notification.Name {
    static let userTypingStatusChanged = Notification.Name("userTypingStatusChanged")
    static let messageReadStatusChanged = Notification.Name("messageReadStatusChanged")
}
```

---

## Part 5: SwiftUI Integration

### 5.1 Conversation List View

```swift
import SwiftUI

struct ConversationListView: View {
    @StateObject private var viewModel = ConversationListViewModel()

    var body: some View {
        NavigationView {
            List(viewModel.conversations) { conversation in
                NavigationLink(destination: ChatView(conversationId: conversation.id)) {
                    ConversationRow(conversation: conversation)
                }
            }
            .navigationTitle("Messages")
            .refreshable {
                await viewModel.loadConversations()
            }
            .task {
                await viewModel.loadConversations()
            }
        }
    }
}

struct ConversationRow: View {
    let conversation: ConversationWithMetadata

    var body: some View {
        HStack {
            // Avatar
            Circle()
                .fill(Color.blue)
                .frame(width: 50, height: 50)

            VStack(alignment: .leading) {
                Text(conversation.name ?? "Direct Chat")
                    .font(.headline)

                if let lastMessage = conversation.lastMessage {
                    Text("Encrypted message")  // Can't show preview (encrypted)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }

            Spacer()

            if conversation.unreadCount > 0 {
                Text("\\(conversation.unreadCount)")
                    .font(.caption)
                    .padding(6)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Circle())
            }
        }
        .padding(.vertical, 4)
    }
}

@MainActor
class ConversationListViewModel: ObservableObject {
    @Published var conversations: [ConversationWithMetadata] = []
    private let conversationService = ConversationService()

    func loadConversations() async {
        do {
            let response = try await conversationService.listConversations()
            self.conversations = response.conversations
        } catch {
            print("Failed to load conversations: \\(error)")
        }
    }
}
```

---

## Summary

本指南涵盖了 iOS 客户端集成私密消息系统的核心功能：

1. ✅ **加密设置**：TweetNaCl 密钥生成、加密/解密
2. ✅ **对话管理**：创建、列表、设置
3. ✅ **消息发送**：加密、发送、历史查询
4. ✅ **WebSocket 实时**：连接、接收事件、发送 typing 指示器
5. ✅ **SwiftUI 集成**：对话列表 UI

**下一步**：
- 实现聊天界面 (ChatView)
- 添加消息气泡 UI
- 实现 typing 指示器动画
- 优化消息缓存和分页加载
