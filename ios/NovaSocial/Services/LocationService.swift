import Foundation
import CoreLocation
import Observation

/// Service for managing real-time location sharing
@Observable
final class LocationService: @unchecked Sendable {
    private let apiClient: APIClient
    private let interceptor: RequestInterceptor
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

    init(
        apiClient: APIClient = APIClient(baseURL: APIConfig.baseURL)
    ) {
        self.apiClient = apiClient
        self.interceptor = RequestInterceptor(apiClient: apiClient)
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

        let endpoint = APIEndpoint(
            path: "/api/v1/conversations/\(conversationId)/location",
            method: .post,
            body: request
        )

        let location: SharedLocation = try await interceptor.executeWithRetry(endpoint)
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

        let endpoint = APIEndpoint(
            path: "/api/v1/conversations/\(conversationId)/location/stop",
            method: .post,
            body: request
        )

        _ = try await interceptor.executeWithRetry(endpoint) as EmptyResponse
        lock.withLock { _activeShare = nil }
    }

    /// Get all active locations in a conversation
    func getConversationLocations(conversationId: UUID) async throws -> ConversationLocations {
        let endpoint = APIEndpoint(
            path: "/api/v1/conversations/\(conversationId)/locations",
            method: .get
        )

        let locations: ConversationLocations = try await interceptor.executeWithRetry(endpoint)

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
            let endpoint = APIEndpoint(
                path: "/api/v1/conversations/\(conversationId)/location/\(userId)",
                method: .get
            )

            let location: SharedLocation = try await interceptor.executeWithRetry(endpoint)
            return location
        } catch {
            // Return nil for 404 errors
            return nil
        }
    }

    /// Get location sharing statistics
    func getStats(conversationId: UUID) async throws -> LocationStats {
        let endpoint = APIEndpoint(
            path: "/api/v1/conversations/\(conversationId)/location/stats",
            method: .get
        )

        return try await interceptor.executeWithRetry(endpoint)
    }

    // MARK: - Permissions

    /// Get current location permissions
    func getPermissions() async throws -> LocationPermissionResponse {
        let endpoint = APIEndpoint(
            path: "/api/v1/location/permissions",
            method: .get
        )

        return try await interceptor.executeWithRetry(endpoint)
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

        let endpoint = APIEndpoint(
            path: "/api/v1/location/permissions",
            method: .put,
            body: request
        )

        return try await interceptor.executeWithRetry(endpoint)
    }

    // MARK: - Location Permissions (CoreLocation)

    /// Request location permission
    func requestLocationPermission() async -> Bool {
        let status = locationManager.authorizationStatus

        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            // Wait for permission response
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            return locationManager.authorizationStatus != .denied
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
        let status = locationManager.authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }
}

// MARK: - Helper Types

struct EmptyResponse: Codable {}
