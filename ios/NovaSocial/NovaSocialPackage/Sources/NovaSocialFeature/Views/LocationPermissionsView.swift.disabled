import SwiftUI
import CoreLocation

/// View for managing location sharing permissions
struct LocationPermissionsView: View {
    @Environment(LocationPermissionManager.self) private var permissionManager
    @State private var settings = LocationPermissionSettings(
        response: LocationPermissionResponse(
            allowConversations: true,
            allowSearch: false,
            blurLocation: false
        )
    )
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showingSuccess = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("System Location Access") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Location Services")
                            .font(.subheadline)
                        Text(permissionManager.isLocationServicesEnabled ? "Enabled" : "Disabled")
                            .font(.caption)
                            .foregroundColor(permissionManager.isLocationServicesEnabled ? .green : .red)
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Authorization Status")
                        .font(.subheadline)
                    AuthorizationStatusPicker(status: permissionManager.authorizationStatus)
                }

                if !permissionManager.canShareLocation {
                    Button(action: requestLocationPermission) {
                        Label("Request Location Permission", systemImage: "location.fill")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Section("Location Sharing Preferences") {
                Toggle("Allow in Conversations", isOn: $settings.allowConversations)
                    .disabled(!permissionManager.canShareLocation)
                    .help("Share your real-time location with conversation participants")

                Toggle("Allow in Search Results", isOn: $settings.allowSearch)
                    .disabled(!permissionManager.canShareLocation || !settings.allowConversations)
                    .help("Allow your location to be used in location-based search")

                Toggle("Blur Location", isOn: $settings.blurLocation)
                    .disabled(!permissionManager.canShareLocation || !settings.allowConversations)
                    .help("Show approximate location instead of exact coordinates")

                if settings.blurLocation {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Approximate Location")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Your location will be rounded to ±1000 meters")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section("Privacy Information") {
                VStack(alignment: .leading, spacing: 12) {
                    PrivacyInfoRow(
                        icon: "lock.circle",
                        title: "End-to-End Encrypted",
                        description: "Location data is encrypted before transmission"
                    )

                    PrivacyInfoRow(
                        icon: "clock.circle",
                        title: "Time-Limited",
                        description: "Stop sharing at any time with a single tap"
                    )

                    PrivacyInfoRow(
                        icon: "person.badge.shield.checkmark",
                        title: "Per-Conversation",
                        description: "Control sharing separately for each conversation"
                    )
                }
            }
        }
        .navigationTitle("Location Privacy")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button(action: saveChanges) {
                        Text("Save")
                    }
                    .disabled(!hasChanges)
                }
            }
        }
        .task { await loadPermissions() }
        .alert("Success", isPresented: $showingSuccess) {
            Button("OK") { showingSuccess = false }
        } message: {
            Text("Your location preferences have been updated.")
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
    }

    // MARK: - Computed Properties

    private var hasChanges: Bool {
        settings.allowConversations != (permissionManager.permissions?.allowConversations ?? true) ||
        settings.allowSearch != (permissionManager.permissions?.allowSearch ?? false) ||
        settings.blurLocation != (permissionManager.permissions?.blurLocation ?? false)
    }

    // MARK: - Actions

    private func requestLocationPermission() {
        let status = permissionManager.authorizationStatus

        switch status {
        case .notDetermined:
            permissionManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            // Open app settings
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        default:
            break
        }
    }

    private func loadPermissions() async {
        isLoading = true

        do {
            try await permissionManager.loadPermissions()

            if let permissions = permissionManager.permissions {
                settings = LocationPermissionSettings(response: permissions)
            }

            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func saveChanges() async {
        isSaving = true

        do {
            try await permissionManager.updatePreferences(
                allowConversations: settings.allowConversations,
                allowSearch: settings.allowSearch,
                blurLocation: settings.blurLocation
            )

            isSaving = false
            showingSuccess = true
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Authorization Status Picker

struct AuthorizationStatusPicker: View {
    let status: CLAuthorizationStatus

    var body: some View {
        HStack {
            statusIcon
                .font(.title3)

            Text(statusText)
                .font(.caption)

            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var statusIcon: some View {
        Group {
            switch status {
            case .notDetermined:
                Image(systemName: "questionmark.circle")
                    .foregroundColor(.gray)
            case .authorizedWhenInUse:
                Image(systemName: "location.circle.fill")
                    .foregroundColor(.blue)
            case .authorizedAlways:
                Image(systemName: "location.circle.fill")
                    .foregroundColor(.green)
            case .denied, .restricted:
                Image(systemName: "location.slash.circle.fill")
                    .foregroundColor(.red)
            @unknown default:
                Image(systemName: "questionmark.circle")
                    .foregroundColor(.gray)
            }
        }
    }

    private var statusText: String {
        switch status {
        case .notDetermined:
            return "Not Determined - Request permission to continue"
        case .authorizedWhenInUse:
            return "While Using App"
        case .authorizedAlways:
            return "Always"
        case .denied:
            return "Denied - Enable in Settings to share location"
        case .restricted:
            return "Restricted"
        @unknown default:
            return "Unknown"
        }
    }
}

// MARK: - Privacy Info Row

struct PrivacyInfoRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 32, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LocationPermissionsView()
            .environment(LocationPermissionManager(httpClient: PreviewHTTPClient()))
    }
}

// Mock for preview
class PreviewHTTPClient: HTTPClient {
    func get<T: Decodable>(_ path: String, responseType: T.Type) async throws -> T {
        throw URLError(.unknown)
    }

    func post<T: Encodable, R: Decodable>(_ path: String, body: T, responseType: R.Type) async throws -> R {
        throw URLError(.unknown)
    }

    func put<T: Encodable, R: Decodable>(_ path: String, body: T, responseType: R.Type) async throws -> R {
        throw URLError(.unknown)
    }

    func delete(_ path: String) async throws {
        throw URLError(.unknown)
    }
}
