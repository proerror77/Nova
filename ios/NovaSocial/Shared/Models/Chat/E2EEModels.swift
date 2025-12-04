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
    let publicKey: Data      // X25519 public key (32 bytes)
    let secretKey: Data      // X25519 secret key (32 bytes)
    let createdAt: Date
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
        }
    }
}
