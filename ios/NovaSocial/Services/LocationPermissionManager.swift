import Foundation
import CoreLocation
import Observation

/// Manages location permissions and privacy settings
@Observable
final class LocationPermissionManager: NSObject, @unchecked Sendable {
    private let apiClient: APIClient
    private let interceptor: RequestInterceptor
    private let locationManager: CLLocationManager

    nonisolated private let lock = NSLock()
    private var _authorizationStatus: CLAuthorizationStatus = .notDetermined
    private var _permissions: LocationPermissionResponse?
    private var _isLoading = false

    @ObservationIgnored
    var authorizationStatus: CLAuthorizationStatus {
        lock.withLock { _authorizationStatus }
    }

    @ObservationIgnored
    var permissions: LocationPermissionResponse? {
        lock.withLock { _permissions }
    }

    @ObservationIgnored
    var isLoading: Bool {
        lock.withLock { _isLoading }
    }

    init(
        apiClient: APIClient = APIClient(baseURL: APIConfig.baseURL)
    ) {
        self.apiClient = apiClient
        self.interceptor = RequestInterceptor(apiClient: apiClient)
        self.locationManager = CLLocationManager()
        super.init()

        locationManager.delegate = self
        updateAuthorizationStatus()
    }

    // MARK: - Authorization

    /// Request when-in-use location authorization
    func requestWhenInUseAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Request always location authorization
    func requestAlwaysAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }

    /// Check if location access is available
    var isLocationServicesEnabled: Bool {
        CLLocationManager.locationServicesEnabled()
    }

    /// Check if user can share location
    var canShareLocation: Bool {
        guard isLocationServicesEnabled else { return false }
        let status = authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }

    // MARK: - Permissions Management

    /// Load current permissions from server
    func loadPermissions() async throws {
        lock.withLock { _isLoading = true }

        defer {
            lock.withLock { _isLoading = false }
        }

        let endpoint = APIEndpoint(
            path: "/api/v1/location/permissions",
            method: .get
        )

        let response: LocationPermissionResponse = try await interceptor.executeWithRetry(endpoint)
        lock.withLock { _permissions = response }
    }

    /// Update location sharing preferences
    func updatePreferences(
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

        let response: LocationPermissionResponse = try await interceptor.executeWithRetry(endpoint)
        lock.withLock { _permissions = response }
        return response
    }

    /// Check if location sharing is enabled for conversations
    var allowConversations: Bool {
        lock.withLock { _permissions?.allowConversations ?? false }
    }

    /// Check if location can be used in search
    var allowSearch: Bool {
        lock.withLock { _permissions?.allowSearch ?? false }
    }

    /// Check if location should be blurred
    var blurLocation: Bool {
        lock.withLock { _permissions?.blurLocation ?? false }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationPermissionManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.updateAuthorizationStatus()
        }
    }

    // MARK: - Private Methods

    @MainActor
    private func updateAuthorizationStatus() {
        let status = locationManager.authorizationStatus
        lock.withLock { _authorizationStatus = status }
    }
}

// MARK: - Location Permission View Models

/// View state for location permissions screen
enum LocationPermissionViewState {
    case loading
    case loaded(LocationPermissionResponse)
    case error(String)
}

/// Location permission settings form
struct LocationPermissionSettings {
    var allowConversations: Bool
    var allowSearch: Bool
    var blurLocation: Bool

    init(response: LocationPermissionResponse) {
        self.allowConversations = response.allowConversations
        self.allowSearch = response.allowSearch
        self.blurLocation = response.blurLocation
    }
}
