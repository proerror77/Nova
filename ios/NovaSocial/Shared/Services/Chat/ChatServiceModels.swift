import Foundation

// MARK: - Call Response Models

/// Response from initiating a call
struct CallResponse: Codable, Sendable {
    let callId: String
    let conversationId: String
    let initiatorId: String
    let isVideo: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case callId = "call_id"
        case conversationId = "conversation_id"
        case initiatorId = "initiator_id"
        case isVideo = "is_video"
        case createdAt = "created_at"
    }
}

/// ICE server configuration for WebRTC
struct IceServer: Codable, Sendable {
    let urls: [String]
    let username: String?
    let credential: String?
}

/// Response containing ICE servers configuration
struct IceServersResponse: Codable, Sendable {
    let iceServers: [IceServer]

    enum CodingKeys: String, CodingKey {
        case iceServers = "ice_servers"
    }
}

// MARK: - Location Response Models

/// Nearby user information
struct NearbyUser: Codable, Sendable {
    let userId: String
    let username: String
    let displayName: String
    let avatarUrl: String?
    let distance: Double  // Distance in meters

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case distance
    }
}

/// Response containing nearby users
struct NearbyUsersResponse: Codable, Sendable {
    let users: [NearbyUser]
    let totalCount: Int

    enum CodingKeys: String, CodingKey {
        case users
        case totalCount = "total_count"
    }
}

// MARK: - Helper Types

/// Wrapper for decoding DeviceIdentity from keychain
/// Matches the DeviceIdentity struct stored by E2EEService
struct DeviceIdentityWrapper: Codable {
    let deviceId: String
    let publicKey: Data
    let secretKey: Data
    let createdAt: Date
}
