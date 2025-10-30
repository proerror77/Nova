import Foundation
import CoreLocation
import Observation

/// Service for managing real-time location sharing
@Observable
final class LocationService: Sendable {
    private let httpClient: HTTPClient
    private let wsManager: WebSocketManager
    private let locationManager: CLLocationManager

    nonisolated private let lock = NSLock()
    private var _conversationLocations: [UUID: [SharedLocation]] = [:]
    private var _activeShare: SharedLocation?
    private var _sharingEnabled: Bool = false

    @ObservationIgnored
    var conversationLocations: [UUID: [SharedLocation]] {
        lock.withLock { _conversationLocations }
    }

    @ObservationIgnored
    var activeShare: SharedLocation? {
        lock.withLock { _activeShare }
    }

    @ObservationIgnored
    var sharingEnabled: Bool {
        lock.withLock { _sharingEnabled }
    }

    init(httpClient: HTTPClient, wsManager: WebSocketManager) {
        self.httpClient = httpClient
        self.wsManager = wsManager
        self.locationManager = CLLocationManager()
        setupLocationManager()
    }

    private func setupLocationManager() {
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10 // 10 meters
        locationManager.pausesLocationUpdatesAutomatically = true
    }

    // MARK: - Location Sharing

    /// Start sharing location in a conversation
    func startSharing(
        conversationId: UUID,
        latitude: Double,
        longitude: Double,
        accuracy: Int
    ) async throws -> SharedLocation {
        let request = ShareLocationRequest(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            accuracy: accuracy
        )

        let location = try await httpClient.post(
            "/api/v1/conversations/\(conversationId)/location",
            body: request,
            responseType: SharedLocation.self
        )

        lock.withLock { _activeShare = location }
        return location
    }

    /// Stop sharing location
    func stopSharing(
        conversationId: UUID,
        durationSeconds: Int? = nil,
        distanceMeters: Int? = nil
    ) async throws {
        let request = StopSharingRequest(duration: durationSeconds, distance: distanceMeters)

        try await httpClient.post(
            "/api/v1/conversations/\(conversationId)/location/stop",
            body: request,
            responseType: EmptyResponse.self
        )

        lock.withLock { _activeShare = nil }
    }

    /// Get all active locations in a conversation
    func getConversationLocations(conversationId: UUID) async throws -> ConversationLocations {
        let locations = try await httpClient.get(
            "/api/v1/conversations/\(conversationId)/locations",
            responseType: ConversationLocations.self
        )

        lock.withLock {
            _conversationLocations[conversationId] = locations.locations
        }

        return locations
    }

    /// Get specific user's location in a conversation
    func getUserLocation(
        conversationId: UUID,
        userId: UUID
    ) async throws -> SharedLocation? {
        do {
            let location = try await httpClient.get(
                "/api/v1/conversations/\(conversationId)/location/\(userId)",
                responseType: SharedLocation.self
            )
            return location
        } catch {
            if case .httpError(404, _) = error as? HTTPError {
                return nil
            }
            throw error
        }
    }

    /// Get location sharing statistics
    func getStats(conversationId: UUID) async throws -> LocationStats {
        try await httpClient.get(
            "/api/v1/conversations/\(conversationId)/location/stats",
            responseType: LocationStats.self
        )
    }

    // MARK: - Permissions

    /// Get current location permissions
    func getPermissions() async throws -> LocationPermissionResponse {
        try await httpClient.get(
            "/api/v1/location/permissions",
            responseType: LocationPermissionResponse.self
        )
    }

    /// Update location permissions
    func updatePermissions(
        allowConversations: Bool? = nil,
        allowSearch: Bool? = nil,
        blurLocation: Bool? = nil
    ) async throws -> LocationPermissionResponse {
        let request = UpdateLocationPermissionsRequest(
            allowConversations: allowConversations,
            allowSearch: allowSearch,
            blurLocation: blurLocation
        )

        let response = try await httpClient.put(
            "/api/v1/location/permissions",
            body: request,
            responseType: LocationPermissionResponse.self
        )

        return response
    }

    // MARK: - WebSocket Events

    /// Handle incoming WebSocket location events
    func handleWebSocketEvent(_ event: WebSocketEvent) {
        switch event {
        case .locationShared(let payload):
            handleLocationShared(payload)
        case .locationUpdated(let payload):
            handleLocationUpdated(payload)
        case .locationStopped(let payload):
            handleLocationStopped(payload)
        default:
            break
        }
    }

    private func handleLocationShared(_ event: LocationSharedEvent) {
        let location = SharedLocation(
            id: UUID(),
            userId: event.userId,
            latitude: event.latitude,
            longitude: event.longitude,
            accuracyMeters: event.accuracyMeters,
            timestamp: Date()
        )
        updateConversationLocations(userId: event.userId, location: location)
    }

    private func handleLocationUpdated(_ event: LocationUpdatedEvent) {
        let location = SharedLocation(
            id: UUID(),
            userId: event.userId,
            latitude: event.latitude,
            longitude: event.longitude,
            accuracyMeters: event.accuracyMeters,
            timestamp: Date()
        )
        updateConversationLocations(userId: event.userId, location: location)
    }

    private func handleLocationStopped(_ event: LocationStoppedEvent) {
        lock.withLock {
            for (conversationId, _) in _conversationLocations {
                _conversationLocations[conversationId]?.removeAll { $0.userId == event.userId }
            }
        }
    }

    private func updateConversationLocations(userId: UUID, location: SharedLocation) {
        lock.withLock {
            for (conversationId, _) in _conversationLocations {
                if let index = _conversationLocations[conversationId]?.firstIndex(where: { $0.userId == userId }) {
                    _conversationLocations[conversationId]?[index] = location
                } else {
                    _conversationLocations[conversationId]?.append(location)
                }
            }
        }
    }

    // MARK: - Location Permissions (CoreLocation)

    /// Request location permission
    func requestLocationPermission() async -> Bool {
        let status = CLLocationManager.authorizationStatus()

        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            // Wait for permission response
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            return CLLocationManager.authorizationStatus() != .denied
        case .denied, .restricted:
            return false
        case .authorizedWhenInUse, .authorizedAlways:
            return true
        @unknown default:
            return false
        }
    }

    /// Check if location sharing is authorized
    var isLocationAuthorized: Bool {
        let status = CLLocationManager.authorizationStatus()
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }
}

// MARK: - WebSocket Event Models

struct LocationSharedEvent: Sendable {
    let userId: UUID
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Int
}

struct LocationUpdatedEvent: Sendable {
    let userId: UUID
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Int
}

struct LocationStoppedEvent: Sendable {
    let userId: UUID
}

// MARK: - Helper Types

struct EmptyResponse: Codable {}

enum WebSocketEvent {
    case locationShared(LocationSharedEvent)
    case locationUpdated(LocationUpdatedEvent)
    case locationStopped(LocationStoppedEvent)
    case other
}
