import Foundation
import UIKit
import LibSignalClient

// MARK: - Signal E2EE Service
//
// Complete Signal Protocol implementation for end-to-end encryption
// Uses official LibSignalClient library from Signal Foundation
//
// Architecture:
// - X3DH key agreement for session establishment
// - Double Ratchet for forward secrecy
// - PQXDH (Kyber) for post-quantum security
// - Sender Keys for efficient group messaging
//
// Store protocols implemented by SignalProtocolStore:
// - IdentityKeyStore, PreKeyStore, SignedPreKeyStore
// - KyberPreKeyStore, SessionStore, SenderKeyStore

@Observable
final class SignalE2EEService {
    // MARK: - Dependencies

    private let store = SignalProtocolStore.shared
    private let client = APIClient.shared
    private let keychain = KeychainService.shared

    // Current device address
    private var localAddress: ProtocolAddress?
    private let context = NullContext()

    // MARK: - Constants

    private enum Constants {
        static let preKeyBatchSize: UInt32 = 100
        static let preKeyRefreshThreshold: UInt32 = 20
        static let signedPreKeyRotationDays: TimeInterval = 7 * 24 * 60 * 60
    }

    // MARK: - Singleton

    static let shared = SignalE2EEService()

    private init() {}

    // MARK: - Initialization

    /// Initialize the Signal Protocol for this device
    /// Generates all required keys and registers with the server
    @MainActor
    func initialize(userId: String) async throws {
        #if DEBUG
        print("[SignalE2EE] Initializing for user: \(userId)")
        #endif

        // Generate device ID if not exists
        let deviceId = getOrCreateDeviceId()

        // Create local address
        localAddress = try ProtocolAddress(name: userId, deviceId: deviceId)

        // Identity key is already generated in SignalProtocolStore.init()

        // Generate signed prekey
        let signedPreKeyId = UInt32.random(in: 1...0xFFFFFF)
        let signedPreKey = try store.generateSignedPreKey(id: signedPreKeyId)

        // Generate one-time prekeys
        let preKeys = try store.generatePreKeys(start: 1, count: Constants.preKeyBatchSize)

        // Generate Kyber prekey (post-quantum)
        let kyberPreKeyId = UInt32.random(in: 1...0xFFFFFF)
        let kyberPreKey = try store.generateKyberPreKey(id: kyberPreKeyId)

        // Register keys with server
        try await registerKeys(
            signedPreKey: signedPreKey,
            signedPreKeyId: signedPreKeyId,
            preKeys: preKeys,
            kyberPreKey: kyberPreKey,
            kyberPreKeyId: kyberPreKeyId
        )

        #if DEBUG
        print("[SignalE2EE] Initialized successfully")
        #endif
    }

    // MARK: - Session Management

    /// Establish a session with another user's device
    /// Performs X3DH key agreement using their prekeys
    @MainActor
    func establishSession(with userId: String, deviceId: UInt32) async throws {
        guard localAddress != nil else {
            throw SignalError.notInitialized
        }

        let remoteAddress = try ProtocolAddress(name: userId, deviceId: deviceId)

        #if DEBUG
        print("[SignalE2EE] Establishing session with \(remoteAddress)")
        #endif

        // Check if session already exists
        if store.hasSession(for: remoteAddress) {
            #if DEBUG
            print("[SignalE2EE] Session already exists")
            #endif
            return
        }

        // Fetch prekey bundle from server
        let bundleData = try await fetchPreKeyBundle(userId: userId, deviceId: deviceId)

        // Create PreKeyBundle from fetched data
        let bundle = try createPreKeyBundle(from: bundleData)

        // Process bundle to establish session (X3DH key agreement)
        try processPreKeyBundle(
            bundle,
            for: remoteAddress,
            sessionStore: store,
            identityStore: store,
            context: context
        )

        #if DEBUG
        print("[SignalE2EE] Session established with \(remoteAddress)")
        #endif
    }

    /// Check if a session exists with a remote device
    func hasSession(with userId: String, deviceId: UInt32) -> Bool {
        guard let address = try? ProtocolAddress(name: userId, deviceId: deviceId) else {
            return false
        }
        return store.hasSession(for: address)
    }

    // MARK: - Message Encryption

    /// Encrypt a message for a specific user/device
    /// Uses the Double Ratchet algorithm for forward secrecy
    @MainActor
    func encrypt(message: String, for userId: String, deviceId: UInt32) async throws -> SignalEncryptedMessage {
        guard let local = localAddress else {
            throw SignalError.notInitialized
        }

        let remoteAddress = try ProtocolAddress(name: userId, deviceId: deviceId)

        // Ensure session exists
        if !hasSession(with: userId, deviceId: deviceId) {
            try await establishSession(with: userId, deviceId: deviceId)
        }

        // Convert message to data
        guard let messageData = message.data(using: .utf8) else {
            throw SignalError.encryptionFailed("Failed to encode message")
        }

        // Encrypt using Signal Protocol
        let ciphertextMessage = try signalEncrypt(
            message: messageData,
            for: remoteAddress,
            sessionStore: store,
            identityStore: store,
            context: context
        )

        // Determine message type
        let messageType: SignalMessageType = ciphertextMessage.messageType == .preKey ? .preKey : .signal

        #if DEBUG
        print("[SignalE2EE] Encrypted message (\(message.count) chars -> \(ciphertextMessage.serialize().count) bytes)")
        #endif

        return SignalEncryptedMessage(
            ciphertext: Data(ciphertextMessage.serialize()),
            messageType: messageType,
            senderDeviceId: local.deviceId,
            senderUserId: local.name,
            registrationId: store.getLocalRegistrationId()
        )
    }

    /// Encrypt a message for all devices of a user
    @MainActor
    func encryptForAllDevices(message: String, userId: String) async throws -> [SignalEncryptedMessage] {
        // Get all device IDs for user
        let deviceIds = try await fetchUserDevices(userId: userId)

        var encryptedMessages: [SignalEncryptedMessage] = []

        for deviceId in deviceIds {
            let encrypted = try await encrypt(message: message, for: userId, deviceId: deviceId)
            encryptedMessages.append(encrypted)
        }

        return encryptedMessages
    }

    // MARK: - Message Decryption

    /// Decrypt a received message
    /// Handles both PreKey messages (new session) and regular messages
    @MainActor
    func decrypt(_ encryptedMessage: SignalEncryptedMessage) async throws -> String {
        guard localAddress != nil else {
            throw SignalError.notInitialized
        }

        let senderAddress = try ProtocolAddress(
            name: encryptedMessage.senderUserId,
            deviceId: encryptedMessage.senderDeviceId
        )

        #if DEBUG
        print("[SignalE2EE] Decrypting message from \(senderAddress)")
        #endif

        let plaintext: Data

        // Check message type
        if encryptedMessage.messageType == .preKey {
            // PreKey message - new session establishment
            let preKeyMessage = try PreKeySignalMessage(bytes: encryptedMessage.ciphertext)

            plaintext = try signalDecryptPreKey(
                message: preKeyMessage,
                from: senderAddress,
                sessionStore: store,
                identityStore: store,
                preKeyStore: store,
                signedPreKeyStore: store,
                kyberPreKeyStore: store,
                context: context
            )
        } else {
            // Regular message - use existing session
            let signalMessage = try SignalMessage(bytes: encryptedMessage.ciphertext)

            plaintext = try signalDecrypt(
                message: signalMessage,
                from: senderAddress,
                sessionStore: store,
                identityStore: store,
                context: context
            )
        }

        guard let result = String(data: plaintext, encoding: .utf8) else {
            throw SignalError.decryptionFailed("Failed to decode plaintext")
        }

        return result
    }

    // MARK: - Group Messaging (Sender Keys)

    /// Create a sender key distribution message for a group
    func createSenderKeyDistribution(for groupId: String) throws -> Data {
        guard let local = localAddress else {
            throw SignalError.notInitialized
        }

        guard let distributionId = UUID(uuidString: groupId) ?? UUID(uuidString: groupId.sha256HexString()) else {
            throw SignalError.invalidKey("Invalid group ID")
        }

        // Create sender key distribution message
        let distributionMessage = try SenderKeyDistributionMessage(
            from: local,
            distributionId: distributionId,
            store: store,
            context: context
        )

        return Data(distributionMessage.serialize())
    }

    /// Process a received sender key distribution message
    func processSenderKeyDistribution(_ distribution: Data, from senderUserId: String, senderDeviceId: UInt32, groupId: String) throws {
        let sender = try ProtocolAddress(name: senderUserId, deviceId: senderDeviceId)
        let distributionMessage = try SenderKeyDistributionMessage(bytes: distribution)

        try processSenderKeyDistributionMessage(
            distributionMessage,
            from: sender,
            store: store,
            context: context
        )
    }

    /// Encrypt a message for a group using Sender Keys
    func encryptForGroup(message: String, groupId: String) throws -> Data {
        guard let local = localAddress else {
            throw SignalError.notInitialized
        }

        guard let distributionId = UUID(uuidString: groupId) ?? UUID(uuidString: groupId.sha256HexString()) else {
            throw SignalError.invalidKey("Invalid group ID")
        }

        guard let messageData = message.data(using: .utf8) else {
            throw SignalError.encryptionFailed("Failed to encode message")
        }

        let ciphertext = try groupEncrypt(
            messageData,
            from: local,
            distributionId: distributionId,
            store: store,
            context: context
        )

        return Data(ciphertext.serialize())
    }

    /// Decrypt a group message
    func decryptGroupMessage(_ ciphertext: Data, fromUserId: String, fromDeviceId: UInt32, groupId: String) throws -> String {
        let sender = try ProtocolAddress(name: fromUserId, deviceId: fromDeviceId)

        let plaintext = try groupDecrypt(
            ciphertext,
            from: sender,
            store: store,
            context: context
        )

        guard let result = String(data: Data(plaintext), encoding: .utf8) else {
            throw SignalError.decryptionFailed("Failed to decode group message")
        }

        return result
    }

    // MARK: - Key Management

    /// Refresh prekeys if running low
    @MainActor
    func refreshPreKeysIfNeeded() async throws {
        // Check server for remaining prekey count
        let count = try await getServerPreKeyCount()

        if count < Constants.preKeyRefreshThreshold {
            #if DEBUG
            print("[SignalE2EE] Prekey count low (\(count)), refreshing...")
            #endif

            // Find next available prekey ID
            let startId = UInt32.random(in: 10000...0xFFFFFF)

            // Generate new prekeys
            let newPreKeys = try store.generatePreKeys(
                start: startId,
                count: Constants.preKeyBatchSize
            )

            // Upload to server
            try await uploadPreKeys(newPreKeys)
        }
    }

    /// Rotate signed prekey (should be done periodically)
    @MainActor
    func rotateSignedPreKey() async throws {
        let newId = UInt32.random(in: 1...0xFFFFFF)
        let signedPreKey = try store.generateSignedPreKey(id: newId)

        try await uploadSignedPreKey(signedPreKey, id: newId)

        #if DEBUG
        print("[SignalE2EE] Rotated signed prekey to ID: \(newId)")
        #endif
    }

    /// Get the fingerprint for identity verification
    func getFingerprint(for userId: String, deviceId: UInt32) -> String? {
        guard let address = try? ProtocolAddress(name: userId, deviceId: deviceId),
              let identityKey = try? store.identity(for: address, context: context) else {
            return nil
        }

        // SHA256 hash of identity key as fingerprint
        let keyData = Data(identityKey.serialize())
        return keyData.sha256HexString()
    }

    /// Verify a user's identity (for manual verification)
    func verifyIdentity(userId: String, deviceId: UInt32, fingerprint: String) -> Bool {
        guard let computed = getFingerprint(for: userId, deviceId: deviceId) else {
            return false
        }
        return computed.lowercased() == fingerprint.lowercased()
    }

    // MARK: - Network Operations

    private func registerKeys(
        signedPreKey: SignedPreKeyRecord,
        signedPreKeyId: UInt32,
        preKeys: [PreKeyRecord],
        kyberPreKey: KyberPreKeyRecord,
        kyberPreKeyId: UInt32
    ) async throws {
        let identityKeyPair = try store.getIdentityKeyPair()
        let identityKey = identityKeyPair.publicKey

        let request = SignalRegisterKeysRequest(
            identityKey: Data(identityKey.serialize()).base64EncodedString(),
            signedPreKey: SignedPreKeyUpload(
                keyId: signedPreKeyId,
                publicKey: Data(try signedPreKey.publicKey().serialize()).base64EncodedString(),
                signature: Data(signedPreKey.signature).base64EncodedString()
            ),
            preKeys: try preKeys.map {
                PreKeyUpload(
                    keyId: $0.id,
                    publicKey: Data(try $0.publicKey().serialize()).base64EncodedString()
                )
            },
            kyberPreKey: KyberPreKeyUpload(
                keyId: kyberPreKeyId,
                publicKey: Data(try kyberPreKey.publicKey().serialize()).base64EncodedString()
            ),
            registrationId: store.getLocalRegistrationId(),
            deviceId: localAddress?.deviceId ?? 1
        )

        struct Response: Codable {
            let success: Bool
        }

        let _: Response = try await client.request(
            endpoint: "/api/v1/signal/keys/register",
            method: "POST",
            body: request
        )
    }

    private func fetchPreKeyBundle(userId: String, deviceId: UInt32) async throws -> PreKeyBundleData {
        let response: PreKeyBundleResponse = try await client.get(
            endpoint: "/api/v1/signal/keys/\(userId)/\(deviceId)"
        )

        guard let identityKey = Data(base64Encoded: response.identityKey),
              let signedPreKey = Data(base64Encoded: response.signedPreKey.publicKey),
              let signedPreKeySignature = Data(base64Encoded: response.signedPreKey.signature) else {
            throw SignalError.invalidKey("Invalid key encoding in bundle")
        }

        var preKey: Data?
        var preKeyId: UInt32?
        if let pk = response.preKey {
            preKey = Data(base64Encoded: pk.publicKey)
            preKeyId = pk.keyId
        }

        var kyberPreKey: Data?
        var kyberPreKeyId: UInt32?
        var kyberPreKeySignature: Data?
        if let kpk = response.kyberPreKey {
            kyberPreKey = Data(base64Encoded: kpk.publicKey)
            kyberPreKeyId = kpk.keyId
            kyberPreKeySignature = Data(base64Encoded: kpk.signature ?? "")
        }

        return PreKeyBundleData(
            registrationId: response.registrationId,
            deviceId: response.deviceId,
            identityKey: identityKey,
            signedPreKeyId: response.signedPreKey.keyId,
            signedPreKey: signedPreKey,
            signedPreKeySignature: signedPreKeySignature,
            preKeyId: preKeyId,
            preKey: preKey,
            kyberPreKeyId: kyberPreKeyId,
            kyberPreKey: kyberPreKey,
            kyberPreKeySignature: kyberPreKeySignature
        )
    }

    private func createPreKeyBundle(from data: PreKeyBundleData) throws -> PreKeyBundle {
        let identityKey = try IdentityKey(bytes: data.identityKey)
        let signedPreKey = try PublicKey(data.signedPreKey)

        // Kyber prekey is required by the API
        guard let kyberPreKeyData = data.kyberPreKey,
              let kyberPreKeyId = data.kyberPreKeyId,
              let kyberPreKeySignatureData = data.kyberPreKeySignature else {
            throw SignalError.invalidKey("Kyber prekey is required but missing from bundle")
        }

        let kyberPreKey = try KEMPublicKey(kyberPreKeyData)
        let kyberPreKeySignature = [UInt8](kyberPreKeySignatureData)

        // Check if we have a one-time prekey
        if let preKeyData = data.preKey, let preKeyId = data.preKeyId {
            let preKey = try PublicKey(preKeyData)
            // Use init with prekey
            return try PreKeyBundle(
                registrationId: data.registrationId,
                deviceId: data.deviceId,
                prekeyId: preKeyId,
                prekey: preKey,
                signedPrekeyId: data.signedPreKeyId,
                signedPrekey: signedPreKey,
                signedPrekeySignature: [UInt8](data.signedPreKeySignature),
                identity: identityKey,
                kyberPrekeyId: kyberPreKeyId,
                kyberPrekey: kyberPreKey,
                kyberPrekeySignature: kyberPreKeySignature
            )
        } else {
            // Use init without prekey
            return try PreKeyBundle(
                registrationId: data.registrationId,
                deviceId: data.deviceId,
                signedPrekeyId: data.signedPreKeyId,
                signedPrekey: signedPreKey,
                signedPrekeySignature: [UInt8](data.signedPreKeySignature),
                identity: identityKey,
                kyberPrekeyId: kyberPreKeyId,
                kyberPrekey: kyberPreKey,
                kyberPrekeySignature: kyberPreKeySignature
            )
        }
    }

    private func fetchUserDevices(userId: String) async throws -> [UInt32] {
        struct Response: Codable {
            let devices: [UInt32]
        }

        let response: Response = try await client.get(
            endpoint: "/api/v1/signal/devices/\(userId)"
        )

        return response.devices
    }

    private func getServerPreKeyCount() async throws -> UInt32 {
        struct Response: Codable {
            let count: UInt32
        }

        let response: Response = try await client.get(
            endpoint: "/api/v1/signal/keys/count"
        )

        return response.count
    }

    private func uploadPreKeys(_ preKeys: [PreKeyRecord]) async throws {
        let request = UploadPreKeysRequest(
            preKeys: try preKeys.map {
                PreKeyUpload(
                    keyId: $0.id,
                    publicKey: Data(try $0.publicKey().serialize()).base64EncodedString()
                )
            }
        )

        struct Response: Codable {
            let uploaded: Int
        }

        let _: Response = try await client.request(
            endpoint: "/api/v1/signal/keys/prekeys",
            method: "POST",
            body: request
        )
    }

    private func uploadSignedPreKey(_ signedPreKey: SignedPreKeyRecord, id: UInt32) async throws {
        let request = UploadSignedPreKeyRequest(
            signedPreKey: SignedPreKeyUpload(
                keyId: id,
                publicKey: Data(try signedPreKey.publicKey().serialize()).base64EncodedString(),
                signature: Data(signedPreKey.signature).base64EncodedString()
            )
        )

        struct Response: Codable {
            let success: Bool
        }

        let _: Response = try await client.request(
            endpoint: "/api/v1/signal/keys/signed",
            method: "PUT",
            body: request
        )
    }

    // MARK: - Helpers

    private func getOrCreateDeviceId() -> UInt32 {
        if let stored = keychain.get(.signalDeviceId),
           let deviceId = UInt32(stored) {
            return deviceId
        }

        let newDeviceId = UInt32.random(in: 1...0xFFFF)
        _ = keychain.save(String(newDeviceId), for: .signalDeviceId)
        return newDeviceId
    }
}

// MARK: - Signal Data Types

/// Signal Protocol encrypted message
struct SignalEncryptedMessage: Codable, Sendable {
    let ciphertext: Data
    let messageType: SignalMessageType
    let senderDeviceId: UInt32
    let senderUserId: String
    let registrationId: UInt32

    enum CodingKeys: String, CodingKey {
        case ciphertext
        case messageType = "message_type"
        case senderDeviceId = "sender_device_id"
        case senderUserId = "sender_user_id"
        case registrationId = "registration_id"
    }
}

/// Signal message types
enum SignalMessageType: Int, Codable, Sendable {
    case preKey = 1     // Initial message with prekey bundle
    case signal = 2     // Regular double ratchet message
    case senderKey = 3  // Group message using sender keys
}

/// PreKey bundle data from server
struct PreKeyBundleData {
    let registrationId: UInt32
    let deviceId: UInt32
    let identityKey: Data
    let signedPreKeyId: UInt32
    let signedPreKey: Data
    let signedPreKeySignature: Data
    let preKeyId: UInt32?
    let preKey: Data?
    let kyberPreKeyId: UInt32?
    let kyberPreKey: Data?
    let kyberPreKeySignature: Data?
}

// MARK: - API Request/Response Models

struct SignalRegisterKeysRequest: Codable {
    let identityKey: String
    let signedPreKey: SignedPreKeyUpload
    let preKeys: [PreKeyUpload]
    let kyberPreKey: KyberPreKeyUpload
    let registrationId: UInt32
    let deviceId: UInt32

    enum CodingKeys: String, CodingKey {
        case identityKey = "identity_key"
        case signedPreKey = "signed_pre_key"
        case preKeys = "pre_keys"
        case kyberPreKey = "kyber_pre_key"
        case registrationId = "registration_id"
        case deviceId = "device_id"
    }
}

struct SignedPreKeyUpload: Codable {
    let keyId: UInt32
    let publicKey: String
    let signature: String

    enum CodingKeys: String, CodingKey {
        case keyId = "key_id"
        case publicKey = "public_key"
        case signature
    }
}

struct PreKeyUpload: Codable {
    let keyId: UInt32
    let publicKey: String

    enum CodingKeys: String, CodingKey {
        case keyId = "key_id"
        case publicKey = "public_key"
    }
}

struct KyberPreKeyUpload: Codable {
    let keyId: UInt32
    let publicKey: String

    enum CodingKeys: String, CodingKey {
        case keyId = "key_id"
        case publicKey = "public_key"
    }
}

struct UploadPreKeysRequest: Codable {
    let preKeys: [PreKeyUpload]

    enum CodingKeys: String, CodingKey {
        case preKeys = "pre_keys"
    }
}

struct UploadSignedPreKeyRequest: Codable {
    let signedPreKey: SignedPreKeyUpload

    enum CodingKeys: String, CodingKey {
        case signedPreKey = "signed_pre_key"
    }
}

struct PreKeyBundleResponse: Codable {
    let registrationId: UInt32
    let deviceId: UInt32
    let identityKey: String
    let signedPreKey: SignedPreKeyResponse
    let preKey: PreKeyResponse?
    let kyberPreKey: KyberPreKeyResponse?

    enum CodingKeys: String, CodingKey {
        case registrationId = "registration_id"
        case deviceId = "device_id"
        case identityKey = "identity_key"
        case signedPreKey = "signed_pre_key"
        case preKey = "pre_key"
        case kyberPreKey = "kyber_pre_key"
    }
}

struct SignedPreKeyResponse: Codable {
    let keyId: UInt32
    let publicKey: String
    let signature: String

    enum CodingKeys: String, CodingKey {
        case keyId = "key_id"
        case publicKey = "public_key"
        case signature
    }
}

struct PreKeyResponse: Codable {
    let keyId: UInt32
    let publicKey: String

    enum CodingKeys: String, CodingKey {
        case keyId = "key_id"
        case publicKey = "public_key"
    }
}

struct KyberPreKeyResponse: Codable {
    let keyId: UInt32
    let publicKey: String
    let signature: String?

    enum CodingKeys: String, CodingKey {
        case keyId = "key_id"
        case publicKey = "public_key"
        case signature
    }
}

// MARK: - Errors

enum SignalError: LocalizedError {
    case notInitialized
    case sessionNotFound(address: String)
    case encryptionFailed(String)
    case decryptionFailed(String)
    case invalidKey(String)
    case networkError(String)
    case untrustedIdentity(address: String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Signal Protocol not initialized. Call initialize() first."
        case .sessionNotFound(let address):
            return "No session found for \(address)"
        case .encryptionFailed(let msg):
            return "Encryption failed: \(msg)"
        case .decryptionFailed(let msg):
            return "Decryption failed: \(msg)"
        case .invalidKey(let msg):
            return "Invalid key: \(msg)"
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .untrustedIdentity(let address):
            return "Untrusted identity for \(address). Verify fingerprint."
        }
    }
}

// MARK: - Data Extension

private extension Data {
    func sha256HexString() -> String {
        var hash = [UInt8](repeating: 0, count: 32)
        _ = self.withUnsafeBytes { ptr in
            CC_SHA256(ptr.baseAddress, CC_LONG(self.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

private extension String {
    func sha256HexString() -> String {
        guard let data = self.data(using: .utf8) else { return self }
        return data.sha256HexString()
    }
}

// Import CommonCrypto for SHA256
import CommonCrypto
