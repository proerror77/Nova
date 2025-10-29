import Foundation
import MapKit

/// User location data
@Codable
struct UserLocation: Identifiable, Sendable, Hashable {
    let id: UUID
    let userId: UUID
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Int
    let altitudeMeters: Int?
    let headingDegrees: Int?
    let speedMps: Double?
    let updatedAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Distance between two locations in meters using Haversine formula
    static func distance(from: UserLocation, to: UserLocation) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let deltaLat = (to.latitude - from.latitude) * .pi / 180
        let deltaLon = (to.longitude - from.longitude) * .pi / 180

        let a = sin(deltaLat / 2) * sin(deltaLat / 2) +
                cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))

        return 6371000 * c // Earth radius in meters
    }
}

/// Request to start sharing location
struct ShareLocationRequest: Codable, Sendable {
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Int
    let altitudeMeters: Int?
    let headingDegrees: Int?
    let speedMps: Double?

    init(coordinate: CLLocationCoordinate2D, accuracy: Int, altitude: Int? = nil, heading: Int? = nil, speed: Double? = nil) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.accuracyMeters = accuracy
        self.altitudeMeters = altitude
        self.headingDegrees = heading
        self.speedMps = speed
    }
}

/// Response with shared location
struct SharedLocation: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let userId: UUID
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Int
    let timestamp: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// All active locations in a conversation
struct ConversationLocations: Codable, Sendable {
    let conversationId: UUID
    let locations: [SharedLocation]
    let timestamp: String
}

/// Request to stop sharing location
struct StopSharingRequest: Codable, Sendable {
    let durationSeconds: Int?
    let distanceMeters: Int?

    init(duration: Int? = nil, distance: Int? = nil) {
        self.durationSeconds = duration
        self.distanceMeters = distance
    }
}

/// Location permissions/privacy settings
struct LocationPermission: Codable, Sendable, Hashable {
    let id: UUID
    let userId: UUID
    let allowConversations: Bool
    let allowSearch: Bool
    let blurLocation: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, userId
        case allowConversations = "allow_conversations"
        case allowSearch = "allow_search"
        case blurLocation = "blur_location"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Response for location permissions
struct LocationPermissionResponse: Codable, Sendable {
    let allowConversations: Bool
    let allowSearch: Bool
    let blurLocation: Bool

    enum CodingKeys: String, CodingKey {
        case allowConversations = "allow_conversations"
        case allowSearch = "allow_search"
        case blurLocation = "blur_location"
    }
}

/// Request to update location permissions
struct UpdateLocationPermissionsRequest: Codable, Sendable {
    let allowConversations: Bool?
    let allowSearch: Bool?
    let blurLocation: Bool?

    enum CodingKeys: String, CodingKey {
        case allowConversations = "allow_conversations"
        case allowSearch = "allow_search"
        case blurLocation = "blur_location"
    }
}

/// Location sharing statistics
struct LocationStats: Codable, Sendable {
    let activeSharers: Int
    let lastUpdate: Date?

    enum CodingKeys: String, CodingKey {
        case activeSharers = "active_sharers"
        case lastUpdate = "last_update"
    }
}
