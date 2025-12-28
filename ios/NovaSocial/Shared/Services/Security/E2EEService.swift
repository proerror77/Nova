import Foundation
import UIKit
import CryptoKit

// MARK: - E2EE Service
//
// High-level E2EE service for end-to-end encrypted messaging
// Manages device keys, sessions, and message encryption/decryption
// Architecture: X25519 key agreement + ChaCha20-Poly1305 AEAD

@Observable
final class E2EEService {
    // MARK: - Properties

    private let crypto = CryptoCore.shared
    private let keychain = KeychainService.shared
    private let client = APIClient.shared

    private var deviceIdentity: DeviceIdentity?
    private var sessionCache = SessionCache()
    private var megolmStore = MegolmSessionStore()

    // Device ID generated from iOS device info
    private let deviceId: String

    // MARK: - Initialization

    init() {
        // Generate deterministic device ID from iOS device info
        let _ = UIDevice.current.name
        let systemVersion = UIDevice.current.systemVersion
        let modelName = UIDevice.current.model
        let uuid = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

        // Create device ID (e.g., "iPhone-ABC123-iOS17")
        self.deviceId = "\(modelName)-\(uuid.prefix(6))-iOS\(systemVersion.replacingOccurrences(of: ".", with: ""))"

        #if DEBUG
        print("[E2EEService] Initialized with device ID: \(deviceId)")
        #endif

        // Try to load existing identity from keychain
        loadDeviceIdentity()

        // Load Megolm sessions from keychain
        loadMegolmSessions()
    }

    // MARK: - Public API

    /// Initialize E2EE for this device
    /// Generates keypair, registers with server, uploads initial one-time keys
    @MainActor
    func initializeDevice() async throws {
        #if DEBUG
        print("[E2EEService] Initializing device...")
        #endif

        // Generate new keypair if not exists or missing signing keys
        if deviceIdentity == nil || deviceIdentity?.signingPublicKey.count != 32 || deviceIdentity?.signingPublicKey == Data(count: 32) {
            let (publicKey, secretKey) = try crypto.generateKeypair()

            // Generate Ed25519 signing keypair using CryptoKit
            let signingKey = Curve25519.Signing.PrivateKey()
            let signingPublicKey = signingKey.publicKey.rawRepresentation
            let signingPrivateKey = signingKey.rawRepresentation

            deviceIdentity = DeviceIdentity(
                deviceId: deviceId,
                publicKey: publicKey,
                secretKey: secretKey,
                signingPublicKey: signingPublicKey,
                signingPrivateKey: signingPrivateKey,
                createdAt: Date()
            )

            // Store in keychain
            try saveDeviceIdentity()

            #if DEBUG
            print("[E2EEService] Generated new device identity with Ed25519 signing key")
            #endif
        }

        // Register device with server
        try await registerDevice()

        // Upload initial batch of one-time keys (50 keys)
        try await uploadOneTimeKeys(count: 50)

        #if DEBUG
        print("[E2EEService] Device initialized successfully")
        #endif
    }

    /// Encrypt message for a conversation
    /// - Parameters:
    ///   - conversationId: Target conversation
    ///   - plaintext: Message to encrypt
    /// - Returns: Encrypted message with nonce
    @MainActor
    func encryptMessage(for conversationId: UUID, plaintext: String) async throws -> EncryptedMessage {
        guard let identity = deviceIdentity else {
            throw E2EEError.notInitialized
        }

        // For now, use a simple session key derived from conversation ID
        // TODO: Implement proper per-user session establishment
        let sessionKey = try deriveConversationKey(conversationId: conversationId)

        // Convert plaintext to data
        guard let plaintextData = plaintext.data(using: .utf8) else {
            throw E2EEError.encryptionFailed("Failed to encode plaintext")
        }

        // Encrypt
        let (ciphertext, nonce) = try crypto.encrypt(key: sessionKey, plaintext: plaintextData)

        #if DEBUG
        print("[E2EEService] Encrypted message (\(plaintext.count) chars -> \(ciphertext.count) bytes)")
        #endif

        return EncryptedMessage(
            ciphertext: ciphertext.toBase64(),
            nonce: nonce.toBase64(),
            deviceId: identity.deviceId
        )
    }

    /// Decrypt received message
    /// - Parameter message: Encrypted message
    /// - Returns: Decrypted plaintext
    @MainActor
    func decryptMessage(_ message: EncryptedMessage, conversationId: UUID) async throws -> String {
        guard deviceIdentity != nil else {
            throw E2EEError.notInitialized
        }

        // Derive session key
        let sessionKey = try deriveConversationKey(conversationId: conversationId)

        // Decode base64
        guard let ciphertext = Data(base64: message.ciphertext) else {
            throw E2EEError.decryptionFailed("Invalid ciphertext encoding")
        }
        guard let nonce = Data(base64: message.nonce) else {
            throw E2EEError.decryptionFailed("Invalid nonce encoding")
        }

        // Decrypt
        let plaintextData = try crypto.decrypt(key: sessionKey, ciphertext: ciphertext, nonce: nonce)

        guard let plaintext = String(data: plaintextData, encoding: .utf8) else {
            throw E2EEError.decryptionFailed("Failed to decode plaintext")
        }

        #if DEBUG
        print("[E2EEService] Decrypted message (\(ciphertext.count) bytes -> \(plaintext.count) chars)")
        #endif

        return plaintext
    }

    /// Establish session with another user's device
    /// Claims their one-time key and derives shared secret
    @MainActor
    func establishSession(with userId: UUID, deviceId: String) async throws {
        guard let identity = deviceIdentity else {
            throw E2EEError.notInitialized
        }

        #if DEBUG
        print("[E2EEService] Establishing session with user \(userId), device \(deviceId)")
        #endif

        // Claim one-time key from target device
        let request = ClaimKeysRequest(
            oneTimeKeys: [userId.uuidString: [deviceId]]
        )

        let response: ClaimKeysResponse = try await client.request(
            endpoint: "/api/v1/e2ee/keys/claim",
            method: "POST",
            body: request
        )

        guard let userKeys = response.oneTimeKeys[userId.uuidString],
              let claimedKey = userKeys[deviceId] else {
            throw E2EEError.sessionNotFound(userId: userId.uuidString, deviceId: deviceId)
        }

        // Decode peer's keys
        guard let peerPublicKey = Data(base64: claimedKey.identityKey) else {
            throw E2EEError.invalidKey("Invalid peer public key encoding")
        }
        guard Data(base64: claimedKey.key) != nil else {
            throw E2EEError.invalidKey("Invalid one-time key encoding")
        }

        // Derive shared secret using X25519 ECDH
        let sharedSecret = try crypto.deriveSharedSecret(
            secretKey: identity.secretKey,
            peerPublicKey: peerPublicKey
        )

        // Store session
        let sessionKey = "\(userId.uuidString):\(deviceId)"
        sessionCache.sessions[sessionKey] = SessionInfo(
            userId: userId.uuidString,
            deviceId: deviceId,
            sessionKey: sharedSecret,
            createdAt: Date(),
            lastUsedAt: Date()
        )

        #if DEBUG
        print("[E2EEService] Session established successfully")
        #endif
    }

    /// Query device keys for users (for discovery)
    @MainActor
    func queryDeviceKeys(for userIds: [UUID]) async throws -> [String: [DeviceKeyInfo]] {
        let request = QueryKeysRequest(userIds: userIds.map { $0.uuidString })

        let response: QueryKeysResponse = try await client.request(
            endpoint: "/api/v1/e2ee/keys/query",
            method: "POST",
            body: request
        )

        #if DEBUG
        print("[E2EEService] Queried device keys for \(userIds.count) users")
        #endif

        return response.deviceKeys
    }

    // MARK: - Private Methods

    /// Register device with server
    private func registerDevice() async throws {
        guard let identity = deviceIdentity else {
            throw E2EEError.notInitialized
        }

        let deviceName = await MainActor.run { UIDevice.current.name }
        let request = RegisterDeviceRequest(
            deviceId: identity.deviceId,
            deviceName: deviceName
        )

        // Add X-Device-ID header
        var urlRequest = URLRequest(url: URL(string: "\(client.session.configuration.identifier ?? "")/api/v1/e2ee/devices")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(identity.deviceId, forHTTPHeaderField: "X-Device-ID")

        if let token = client.getAuthToken() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await client.session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw E2EEError.networkError(.invalidResponse)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let deviceKeys = try decoder.decode(DeviceKeys.self, from: data)

        #if DEBUG
        print("[E2EEService] Device registered: \(deviceKeys.deviceId)")
        #endif
    }

    /// Upload one-time keys to server
    private func uploadOneTimeKeys(count: Int) async throws {
        guard let identity = deviceIdentity else {
            throw E2EEError.notInitialized
        }

        let request = UploadKeysRequest(count: count)

        // Build URLRequest with X-Device-ID header
        var urlRequest = URLRequest(url: URL(string: "\(APIConfig.current.baseURL)/api/v1/e2ee/keys/upload")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(identity.deviceId, forHTTPHeaderField: "X-Device-ID")

        if let token = client.getAuthToken() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await client.session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw E2EEError.networkError(.invalidResponse)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let uploadResponse = try decoder.decode(UploadKeysResponse.self, from: data)

        #if DEBUG
        print("[E2EEService] Uploaded \(uploadResponse.uploadedCount) keys (total: \(uploadResponse.totalCount))")
        #endif
    }

    /// Derive conversation-specific encryption key
    /// Temporary solution - should use proper session keys per user/device
    private func deriveConversationKey(conversationId: UUID) throws -> Data {
        guard let identity = deviceIdentity else {
            throw E2EEError.notInitialized
        }

        // Simple derivation: SHA256(secret_key || conversation_id)
        var hasher = SHA256Hasher()
        hasher.update(data: identity.secretKey)
        hasher.update(data: conversationId.uuidString.data(using: .utf8)!)
        let hash = hasher.finalize()

        return Data(hash)
    }

    // MARK: - Keychain Storage

    private func loadDeviceIdentity() {
        guard let identityJSON = keychain.get(.e2eeDeviceIdentity),
              let identityData = identityJSON.data(using: .utf8) else {
            #if DEBUG
            print("[E2EEService] No stored device identity found")
            #endif
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            deviceIdentity = try decoder.decode(DeviceIdentity.self, from: identityData)

            #if DEBUG
            print("[E2EEService] Loaded device identity: \(deviceIdentity!.deviceId)")
            #endif
        } catch {
            #if DEBUG
            print("[E2EEService] Failed to decode device identity: \(error)")
            #endif
        }
    }

    private func saveDeviceIdentity() throws {
        guard let identity = deviceIdentity else {
            throw E2EEError.notInitialized
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let identityData = try encoder.encode(identity)

        guard let identityJSON = String(data: identityData, encoding: .utf8) else {
            throw E2EEError.keychainError("Failed to encode identity")
        }

        guard keychain.save(identityJSON, for: .e2eeDeviceIdentity) else {
            throw E2EEError.keychainError("Failed to save identity to keychain")
        }

        #if DEBUG
        print("[E2EEService] Saved device identity to keychain")
        #endif
    }

    // MARK: - Megolm Session Management

    /// Get or create Megolm outbound session for a conversation
    /// - Parameter conversationId: Target conversation ID
    /// - Returns: The outbound session (creates new if needed)
    @MainActor
    func getOrCreateOutboundSession(for conversationId: String) async throws -> MegolmOutboundSession {
        guard let identity = deviceIdentity else {
            throw E2EEError.notInitialized
        }

        // Check if we have an existing valid session
        if let existingSession = megolmStore.outboundSessions[conversationId],
           !existingSession.needsRotation {
            #if DEBUG
            print("[E2EEService] Using existing Megolm session: \(existingSession.sessionId)")
            #endif
            return existingSession
        }

        // Create new session
        let sessionId = UUID().uuidString
        let ratchetKey = try crypto.randomBytes(count: 32)

        let session = MegolmOutboundSession(
            sessionId: sessionId,
            conversationId: conversationId,
            ratchetKey: ratchetKey,
            messageIndex: 0,
            createdAt: Date(),
            lastUsedAt: Date()
        )

        megolmStore.outboundSessions[conversationId] = session
        try saveMegolmSessions()

        #if DEBUG
        print("[E2EEService] Created new Megolm session: \(sessionId) for conversation: \(conversationId)")
        #endif

        return session
    }

    /// Encrypt message using Megolm session
    /// - Parameters:
    ///   - conversationId: Target conversation
    ///   - plaintext: Message to encrypt
    /// - Returns: Encrypted message with session info
    @MainActor
    func encryptWithMegolm(conversationId: String, plaintext: String) async throws -> MegolmEncryptedMessage {
        guard let identity = deviceIdentity else {
            throw E2EEError.notInitialized
        }

        // Get or create outbound session
        var session = try await getOrCreateOutboundSession(for: conversationId)

        // Derive message key from ratchet key and message index
        let messageKey = try deriveMessageKey(ratchetKey: session.ratchetKey, messageIndex: session.messageIndex)

        // Convert plaintext to data
        guard let plaintextData = plaintext.data(using: .utf8) else {
            throw E2EEError.encryptionFailed("Failed to encode plaintext")
        }

        // Encrypt
        let (ciphertext, nonce) = try crypto.encrypt(key: messageKey, plaintext: plaintextData)

        // Create encrypted message
        let encryptedMessage = MegolmEncryptedMessage(
            ciphertext: ciphertext.toBase64(),
            nonce: nonce.toBase64(),
            sessionId: session.sessionId,
            messageIndex: session.messageIndex,
            senderDeviceId: identity.deviceId
        )

        // Advance the ratchet
        session.messageIndex += 1
        session.ratchetKey = try advanceRatchet(currentKey: session.ratchetKey)
        session.lastUsedAt = Date()

        // Update stored session
        megolmStore.outboundSessions[conversationId] = session
        try saveMegolmSessions()

        #if DEBUG
        print("[E2EEService] Encrypted with Megolm, index: \(session.messageIndex - 1)")
        #endif

        return encryptedMessage
    }

    /// Decrypt message using Megolm inbound session
    /// - Parameter message: Encrypted Megolm message
    /// - Returns: Decrypted plaintext
    @MainActor
    func decryptWithMegolm(_ message: MegolmEncryptedMessage, conversationId: String) async throws -> String {
        guard deviceIdentity != nil else {
            throw E2EEError.notInitialized
        }

        let sessionKey = MegolmSessionStore.inboundSessionKey(
            sessionId: message.sessionId,
            senderDeviceId: message.senderDeviceId
        )

        guard var inboundSession = megolmStore.inboundSessions[sessionKey] else {
            throw E2EEError.megolmInboundSessionNotFound(
                sessionId: message.sessionId,
                deviceId: message.senderDeviceId
            )
        }

        // Check message index
        guard message.messageIndex >= inboundSession.messageIndex else {
            throw E2EEError.decryptionFailed("Message index too old: \(message.messageIndex) < \(inboundSession.messageIndex)")
        }

        // Advance ratchet to match message index if needed
        var currentKey = inboundSession.ratchetKey
        var currentIndex = inboundSession.messageIndex

        while currentIndex < message.messageIndex {
            currentKey = try advanceRatchet(currentKey: currentKey)
            currentIndex += 1
        }

        // Derive message key
        let messageKey = try deriveMessageKey(ratchetKey: currentKey, messageIndex: message.messageIndex)

        // Decode ciphertext and nonce
        guard let ciphertext = Data(base64: message.ciphertext) else {
            throw E2EEError.decryptionFailed("Invalid ciphertext encoding")
        }
        guard let nonce = Data(base64: message.nonce) else {
            throw E2EEError.decryptionFailed("Invalid nonce encoding")
        }

        // Decrypt
        let plaintextData = try crypto.decrypt(key: messageKey, ciphertext: ciphertext, nonce: nonce)

        guard let plaintext = String(data: plaintextData, encoding: .utf8) else {
            throw E2EEError.decryptionFailed("Failed to decode plaintext")
        }

        // Update session state (advance one past this message)
        inboundSession.ratchetKey = try advanceRatchet(currentKey: currentKey)
        inboundSession.messageIndex = message.messageIndex + 1
        inboundSession.lastUsedAt = Date()

        megolmStore.inboundSessions[sessionKey] = inboundSession
        try saveMegolmSessions()

        #if DEBUG
        print("[E2EEService] Decrypted Megolm message, index: \(message.messageIndex)")
        #endif

        return plaintext
    }

    /// Import inbound session from session key share
    /// - Parameter sessionKey: Session key received from another device
    @MainActor
    func importInboundSession(_ sessionKey: MegolmSessionKey) throws {
        guard let ratchetKeyData = Data(base64: sessionKey.ratchetKey) else {
            throw E2EEError.invalidKey("Invalid ratchet key encoding")
        }

        let inboundSession = MegolmInboundSession(
            sessionId: sessionKey.sessionId,
            senderDeviceId: sessionKey.senderDeviceId,
            conversationId: sessionKey.conversationId,
            ratchetKey: ratchetKeyData,
            messageIndex: sessionKey.messageIndex,
            createdAt: Date(),
            lastUsedAt: Date()
        )

        let key = MegolmSessionStore.inboundSessionKey(
            sessionId: sessionKey.sessionId,
            senderDeviceId: sessionKey.senderDeviceId
        )

        megolmStore.inboundSessions[key] = inboundSession
        try saveMegolmSessions()

        #if DEBUG
        print("[E2EEService] Imported inbound session: \(sessionKey.sessionId) from device: \(sessionKey.senderDeviceId)")
        #endif
    }

    /// Export outbound session as session key for sharing
    /// - Parameter conversationId: Conversation ID
    /// - Returns: Session key for sharing with other devices
    @MainActor
    func exportSessionKey(for conversationId: String) throws -> MegolmSessionKey? {
        guard let identity = deviceIdentity else {
            throw E2EEError.notInitialized
        }

        guard let session = megolmStore.outboundSessions[conversationId] else {
            return nil
        }

        return MegolmSessionKey(
            sessionId: session.sessionId,
            conversationId: session.conversationId,
            ratchetKey: session.ratchetKey.toBase64(),
            messageIndex: session.messageIndex,
            senderDeviceId: identity.deviceId
        )
    }

    /// Get current message index for a conversation
    /// - Parameter conversationId: Conversation ID
    /// - Returns: Current message index, or nil if no session exists
    func getMessageIndex(for conversationId: String) -> UInt32? {
        return megolmStore.outboundSessions[conversationId]?.messageIndex
    }

    /// Check if we have an inbound session for decryption
    /// - Parameters:
    ///   - sessionId: Session ID
    ///   - deviceId: Sender device ID
    /// - Returns: True if session exists
    func hasInboundSession(sessionId: String, deviceId: String) -> Bool {
        let key = MegolmSessionStore.inboundSessionKey(sessionId: sessionId, senderDeviceId: deviceId)
        return megolmStore.inboundSessions[key] != nil
    }

    // MARK: - Megolm Ratchet

    /// Derive message key from ratchet key and message index
    private func deriveMessageKey(ratchetKey: Data, messageIndex: UInt32) throws -> Data {
        // HKDF-like derivation: SHA256(ratchet_key || message_index_bytes)
        var hasher = SHA256Hasher()
        hasher.update(data: ratchetKey)

        // Add message index as 4 bytes (big endian)
        var indexBytes = messageIndex.bigEndian
        let indexData = Data(bytes: &indexBytes, count: 4)
        hasher.update(data: indexData)

        let hash = hasher.finalize()
        return Data(hash)
    }

    /// Advance ratchet key by one step
    private func advanceRatchet(currentKey: Data) throws -> Data {
        // Ratchet advancement: SHA256(current_key || 0x01)
        var hasher = SHA256Hasher()
        hasher.update(data: currentKey)
        hasher.update(data: Data([0x01]))

        let hash = hasher.finalize()
        return Data(hash)
    }

    // MARK: - Megolm Session Storage

    private func loadMegolmSessions() {
        guard let sessionsJSON = keychain.get(.megolmSessions),
              let sessionsData = sessionsJSON.data(using: .utf8) else {
            #if DEBUG
            print("[E2EEService] No stored Megolm sessions found")
            #endif
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            megolmStore = try decoder.decode(MegolmSessionStore.self, from: sessionsData)

            #if DEBUG
            print("[E2EEService] Loaded \(megolmStore.outboundSessions.count) outbound, \(megolmStore.inboundSessions.count) inbound Megolm sessions")
            #endif
        } catch {
            #if DEBUG
            print("[E2EEService] Failed to decode Megolm sessions: \(error)")
            #endif
        }
    }

    private func saveMegolmSessions() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let sessionsData = try encoder.encode(megolmStore)

        guard let sessionsJSON = String(data: sessionsData, encoding: .utf8) else {
            throw E2EEError.keychainError("Failed to encode Megolm sessions")
        }

        guard keychain.save(sessionsJSON, for: .megolmSessions) else {
            throw E2EEError.keychainError("Failed to save Megolm sessions to keychain")
        }

        #if DEBUG
        print("[E2EEService] Saved Megolm sessions to keychain")
        #endif
    }

    // MARK: - Ed25519 Signing

    /// Get the Ed25519 signing public key (Base64 encoded)
    func getSigningPublicKey() -> String? {
        return deviceIdentity?.signingPublicKey.base64EncodedString()
    }

    /// Sign data with Ed25519 private key
    /// - Parameter data: Data to sign
    /// - Returns: Base64 encoded signature
    func sign(data: Data) throws -> String {
        guard let identity = deviceIdentity else {
            throw E2EEError.notInitialized
        }

        // Recreate the signing key from stored raw representation
        let signingKey = try Curve25519.Signing.PrivateKey(rawRepresentation: identity.signingPrivateKey)

        // Sign the data
        let signature = try signingKey.signature(for: data)

        return signature.base64EncodedString()
    }

    /// Sign a string message with Ed25519
    /// - Parameter message: Message to sign
    /// - Returns: Base64 encoded signature
    func signMessage(_ message: String) throws -> String {
        guard let messageData = message.data(using: .utf8) else {
            throw E2EEError.encryptionFailed("Failed to encode message")
        }
        return try sign(data: messageData)
    }

    /// Verify Ed25519 signature
    /// - Parameters:
    ///   - signature: Base64 encoded signature
    ///   - data: Original data that was signed
    ///   - publicKey: Base64 encoded Ed25519 public key
    /// - Returns: True if signature is valid
    func verifySignature(_ signature: String, for data: Data, publicKey: String) throws -> Bool {
        guard let signatureData = Data(base64Encoded: signature),
              let publicKeyData = Data(base64Encoded: publicKey) else {
            throw E2EEError.invalidKey("Invalid signature or public key encoding")
        }

        do {
            let verifyingKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
            return verifyingKey.isValidSignature(signatureData, for: data)
        } catch {
            throw E2EEError.invalidKey("Invalid Ed25519 public key: \(error)")
        }
    }

    /// Sign device keys for upload
    /// Creates a canonical JSON representation and signs it
    func signDeviceKeys() throws -> (signature: String, signedData: String) {
        guard let identity = deviceIdentity else {
            throw E2EEError.notInitialized
        }

        // Create canonical representation of device keys
        let keysDict: [String: String] = [
            "device_id": identity.deviceId,
            "identity_key": identity.publicKey.base64EncodedString(),
            "signing_key": identity.signingPublicKey.base64EncodedString()
        ]

        // Sort keys for canonical representation
        let sortedKeys = keysDict.keys.sorted()
        let canonicalParts = sortedKeys.map { key in
            "\"\(key)\":\"\(keysDict[key]!)\""
        }
        let canonicalJSON = "{" + canonicalParts.joined(separator: ",") + "}"

        // Sign the canonical JSON
        let signature = try signMessage(canonicalJSON)

        return (signature, canonicalJSON)
    }
}

// MARK: - SHA256 Helper

private struct SHA256Hasher {
    private var hasher = CryptoKit.SHA256()

    mutating func update(data: Data) {
        hasher.update(data: data)
    }

    func finalize() -> CryptoKit.SHA256.Digest {
        return hasher.finalize()
    }
}
