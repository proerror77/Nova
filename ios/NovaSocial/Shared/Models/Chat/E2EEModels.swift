import Foundation

// MARK: - E2EE Data Models

/// Device keys for E2EE
/// Maps to backend POST /api/v1/e2ee/devices response
struct DeviceKeys: Codable, Sendable {
    let deviceId: String
    let identityKey: String  // X25519 public key (base64)
    let signingKey: String   // Ed25519 signing key (base64, placeholder)

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case identityKey = "identity_key"
        case signingKey = "signing_key"
    }
}

/// Device key information for other users
/// Maps to backend POST /api/v1/e2ee/keys/query response
struct DeviceKeyInfo: Codable, Sendable {
    let deviceId: String
    let deviceName: String?
    let identityKey: String  // X25519 public key (base64)
    let signingKey: String   // Ed25519 signing key (base64)
    let verified: Bool

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case deviceName = "device_name"
        case identityKey = "identity_key"
        case signingKey = "signing_key"
        case verified
    }
}

/// Claimed one-time key
/// Maps to backend POST /api/v1/e2ee/keys/claim response
struct ClaimedKey: Codable, Sendable {
    let deviceId: String
    let keyId: String
    let key: String          // One-time prekey (base64)
    let identityKey: String  // X25519 identity key (base64)
    let signingKey: String   // Ed25519 signing key (base64)

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case keyId = "key_id"
        case key
        case identityKey = "identity_key"
        case signingKey = "signing_key"
    }
}

/// Session information for established E2EE sessions
struct SessionInfo: Codable {
    let userId: String
    let deviceId: String
    let sessionKey: Data     // Derived shared secret
    let createdAt: Date
    var lastUsedAt: Date
}

/// Encrypted message structure
struct EncryptedMessage: Codable, Sendable {
    let ciphertext: String   // Base64 encoded
    let nonce: String        // Base64 encoded (12 bytes for ChaCha20-Poly1305)
    let deviceId: String

    enum CodingKeys: String, CodingKey {
        case ciphertext
        case nonce
        case deviceId = "device_id"
    }
}

// MARK: - API Request/Response Models

/// Register device request
/// Maps to backend POST /api/v1/e2ee/devices
struct RegisterDeviceRequest: Codable {
    let deviceId: String
    let deviceName: String?

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case deviceName = "device_name"
    }
}

/// Upload one-time keys request
/// Maps to backend POST /api/v1/e2ee/keys/upload
struct UploadKeysRequest: Codable {
    let count: Int
}

/// Upload one-time keys response
struct UploadKeysResponse: Codable {
    let uploadedCount: Int
    let totalCount: Int

    enum CodingKeys: String, CodingKey {
        case uploadedCount = "uploaded_count"
        case totalCount = "total_count"
    }
}

/// Claim one-time keys request
/// Maps to backend POST /api/v1/e2ee/keys/claim
struct ClaimKeysRequest: Codable {
    let oneTimeKeys: [String: [String]]  // user_id -> [device_ids]

    enum CodingKeys: String, CodingKey {
        case oneTimeKeys = "one_time_keys"
    }
}

/// Claim one-time keys response
struct ClaimKeysResponse: Codable {
    let oneTimeKeys: [String: [String: ClaimedKey]]  // user_id -> device_id -> key
    let failures: [String]

    enum CodingKeys: String, CodingKey {
        case oneTimeKeys = "one_time_keys"
        case failures
    }
}

/// Query device keys request
/// Maps to backend POST /api/v1/e2ee/keys/query
struct QueryKeysRequest: Codable {
    let userIds: [String]

    enum CodingKeys: String, CodingKey {
        case userIds = "user_ids"
    }
}

/// Query device keys response
struct QueryKeysResponse: Codable {
    let deviceKeys: [String: [DeviceKeyInfo]]  // user_id -> [device_keys]

    enum CodingKeys: String, CodingKey {
        case deviceKeys = "device_keys"
    }
}

// MARK: - Local Storage Models

/// Stored device identity (private keys)
struct DeviceIdentity: Codable {
    let deviceId: String
    let publicKey: Data            // X25519 public key (32 bytes) - for key exchange
    let secretKey: Data            // X25519 secret key (32 bytes) - for key exchange
    let signingPublicKey: Data     // Ed25519 public key (32 bytes) - for signatures
    let signingPrivateKey: Data    // Ed25519 private key (32 bytes) - for signatures
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case publicKey = "public_key"
        case secretKey = "secret_key"
        case signingPublicKey = "signing_public_key"
        case signingPrivateKey = "signing_private_key"
        case createdAt = "created_at"
    }

    /// Initialize with optional signing keys (for backward compatibility)
    init(deviceId: String, publicKey: Data, secretKey: Data, signingPublicKey: Data? = nil, signingPrivateKey: Data? = nil, createdAt: Date) {
        self.deviceId = deviceId
        self.publicKey = publicKey
        self.secretKey = secretKey
        // Use provided signing keys or generate placeholder (will be regenerated properly)
        self.signingPublicKey = signingPublicKey ?? Data(count: 32)
        self.signingPrivateKey = signingPrivateKey ?? Data(count: 32)
        self.createdAt = createdAt
    }
}

/// Session cache for active E2EE sessions
struct SessionCache: Codable {
    var sessions: [String: SessionInfo]  // "userId:deviceId" -> SessionInfo
    var lastCleanup: Date

    init() {
        self.sessions = [:]
        self.lastCleanup = Date()
    }
}

// MARK: - Megolm Session Models

/// Megolm outbound session for encrypting messages in a conversation
/// Each session has a ratchet that advances with each message
struct MegolmOutboundSession: Codable {
    let sessionId: String           // Unique session identifier
    let conversationId: String      // Associated conversation
    var ratchetKey: Data            // Current ratchet key (32 bytes)
    var messageIndex: UInt32        // Current message index (increments per message)
    let createdAt: Date
    var lastUsedAt: Date

    /// Maximum number of messages before session rotation
    static let maxMessages: UInt32 = 100

    /// Check if session needs rotation
    var needsRotation: Bool {
        messageIndex >= MegolmOutboundSession.maxMessages
    }
}

/// Megolm inbound session for decrypting messages from other users
struct MegolmInboundSession: Codable {
    let sessionId: String           // Session ID (matches outbound session)
    let senderDeviceId: String      // Device that created this session
    let conversationId: String      // Associated conversation
    var ratchetKey: Data            // Current ratchet key
    var messageIndex: UInt32        // Current message index
    let createdAt: Date
    var lastUsedAt: Date
}

/// Storage for all Megolm sessions
struct MegolmSessionStore: Codable {
    /// Outbound sessions: conversationId -> session
    var outboundSessions: [String: MegolmOutboundSession]

    /// Inbound sessions: "sessionId:senderDeviceId" -> session
    var inboundSessions: [String: MegolmInboundSession]

    var lastCleanup: Date

    init() {
        self.outboundSessions = [:]
        self.inboundSessions = [:]
        self.lastCleanup = Date()
    }

    /// Get inbound session key
    static func inboundSessionKey(sessionId: String, senderDeviceId: String) -> String {
        return "\(sessionId):\(senderDeviceId)"
    }
}

/// Session key share for distributing session to other devices
struct MegolmSessionKey: Codable, Sendable {
    let sessionId: String
    let conversationId: String
    let ratchetKey: String          // Base64 encoded
    let messageIndex: UInt32
    let senderDeviceId: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case conversationId = "conversation_id"
        case ratchetKey = "ratchet_key"
        case messageIndex = "message_index"
        case senderDeviceId = "sender_device_id"
    }
}

/// Encrypted message with Megolm session info
struct MegolmEncryptedMessage: Codable, Sendable {
    let ciphertext: String          // Base64 encoded
    let nonce: String               // Base64 encoded (12 bytes)
    let sessionId: String           // Megolm session ID
    let messageIndex: UInt32        // Message index in session
    let senderDeviceId: String

    enum CodingKeys: String, CodingKey {
        case ciphertext
        case nonce
        case sessionId = "session_id"
        case messageIndex = "message_index"
        case senderDeviceId = "sender_device_id"
    }
}

// MARK: - Error Types

enum E2EEError: LocalizedError {
    case notInitialized
    case deviceNotRegistered
    case keychainError(String)
    case encryptionFailed(String)
    case decryptionFailed(String)
    case invalidKey(String)
    case networkError(APIError)
    case sessionNotFound(userId: String, deviceId: String)
    case megolmSessionNotFound(conversationId: String)
    case megolmInboundSessionNotFound(sessionId: String, deviceId: String)
    case megolmSessionExpired(sessionId: String)
    case megolmRatchetFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "E2EE not initialized. Call initializeDevice() first."
        case .deviceNotRegistered:
            return "Device keys not registered with server."
        case .keychainError(let msg):
            return "Keychain error: \(msg)"
        case .encryptionFailed(let msg):
            return "Encryption failed: \(msg)"
        case .decryptionFailed(let msg):
            return "Decryption failed: \(msg)"
        case .invalidKey(let msg):
            return "Invalid key: \(msg)"
        case .networkError(let error):
            return "Network error: \(error.userMessage)"
        case .sessionNotFound(let userId, let deviceId):
            return "No session found for user \(userId), device \(deviceId)"
        case .megolmSessionNotFound(let conversationId):
            return "No Megolm session found for conversation \(conversationId)"
        case .megolmInboundSessionNotFound(let sessionId, let deviceId):
            return "No inbound Megolm session found: \(sessionId) from device \(deviceId)"
        case .megolmSessionExpired(let sessionId):
            return "Megolm session expired: \(sessionId)"
        case .megolmRatchetFailed(let msg):
            return "Megolm ratchet failed: \(msg)"
        }
    }
}
