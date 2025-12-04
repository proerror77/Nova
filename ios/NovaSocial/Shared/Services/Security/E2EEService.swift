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

    // Device ID generated from iOS device info
    private let deviceId: String

    // MARK: - Initialization

    init() {
        // Generate deterministic device ID from iOS device info
        let deviceName = UIDevice.current.name
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
    }

    // MARK: - Public API

    /// Initialize E2EE for this device
    /// Generates keypair, registers with server, uploads initial one-time keys
    @MainActor
    func initializeDevice() async throws {
        #if DEBUG
        print("[E2EEService] Initializing device...")
        #endif

        // Generate new keypair if not exists
        if deviceIdentity == nil {
            let (publicKey, secretKey) = try crypto.generateKeypair()

            deviceIdentity = DeviceIdentity(
                deviceId: deviceId,
                publicKey: publicKey,
                secretKey: secretKey,
                createdAt: Date()
            )

            // Store in keychain
            try saveDeviceIdentity()

            #if DEBUG
            print("[E2EEService] Generated new device identity")
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
        guard let oneTimeKey = Data(base64: claimedKey.key) else {
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

        let request = RegisterDeviceRequest(
            deviceId: identity.deviceId,
            deviceName: UIDevice.current.name
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

    /// Derive conversation-specific encryption key using HKDF
    /// Uses HKDF-SHA256 with proper salt and info for cryptographic key derivation
    /// Temporary solution - should use proper session keys per user/device in production
    private func deriveConversationKey(conversationId: UUID) throws -> Data {
        guard let identity = deviceIdentity else {
            throw E2EEError.notInitialized
        }

        // Use HKDF (HMAC-based Key Derivation Function) for secure key derivation
        // - IKM (Input Key Material): device secret key
        // - Salt: device ID (provides domain separation)
        // - Info: conversation ID (context binding)
        let ikm = SymmetricKey(data: identity.secretKey)
        let salt = identity.deviceId.data(using: .utf8)!
        let info = "conversation:\(conversationId.uuidString)".data(using: .utf8)!

        // Derive 32-byte key using HKDF-SHA256
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm,
            salt: salt,
            info: info,
            outputByteCount: 32
        )

        return derivedKey.withUnsafeBytes { Data($0) }
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
}
