import SwiftUI
import MapKit
import CoreLocation

/// View displaying real-time location sharing on a map
struct LocationSharingMapView: View {
    let conversationId: UUID
    @Environment(LocationService.self) private var locationService
    @State private var region: MKCoordinateRegion = .init(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var selectedUser: SharedLocation?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingPermissionAlert = false
    @State private var refreshTimer: Timer?

    var body: some View {
        ZStack {
            // Map
            Map(position: .constant(.region(region))) {
                // User location markers
                ForEach(locationService.conversationLocations[conversationId] ?? [], id: \.id) { location in
                    Annotation("", coordinate: location.coordinate) {
                        UserLocationMarker(
                            location: location,
                            isSelected: selectedUser?.id == location.id
                        )
                        .onTapGesture {
                            selectedUser = location
                            centerOnLocation(location)
                        }
                    }
                }
            }
            .mapStyle(.standard)
            .onAppear { setupMap() }

            // Controls overlay
            VStack(spacing: 12) {
                // Top bar
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Live Locations")
                            .font(.headline)
                        Text("\(locationService.conversationLocations[conversationId]?.count ?? 0) sharing")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: refreshLocations) {
                        Image(systemName: "arrow.clockwise")
                            .font(.title3)
                    }
                    .disabled(isLoading)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(.bar)
                .cornerRadius(8)

                Spacer()

                // Selected user info
                if let selected = selectedUser {
                    UserLocationCard(location: selected)
                        .transition(.move(edge: .bottom))
                }

                // Action buttons
                HStack(spacing: 12) {
                    Button(action: fitToAllLocations) {
                        Label("Fit All", systemImage: "map.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(action: { /* Start sharing */ }) {
                        Label("Share", systemImage: "location.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
            .padding(.vertical)

            // Loading overlay
            if isLoading {
                ProgressView()
                    .scaleEffect(1.5)
            }

            // Error alert
            if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text(error)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                    Button("Dismiss") { errorMessage = nil }
                        .buttonStyle(.bordered)
                }
                .padding()
                .background(.bar)
                .cornerRadius(8)
                .padding()
            }
        }
        .alert("Location Permission Required", isPresented: $showingPermissionAlert) {
            Button("Settings") { openSettings() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This app needs location access to share your location with others.")
        }
        .task { await loadLocations() }
        .onDisappear { refreshTimer?.invalidate() }
    }

    // MARK: - Private Methods

    private func setupMap() {
        Task {
            let hasPermission = await locationService.requestLocationPermission()
            if !hasPermission {
                showingPermissionAlert = true
            }
        }
    }

    private func loadLocations() async {
        isLoading = true
        errorMessage = nil

        do {
            let locations = try await locationService.getConversationLocations(conversationId: conversationId)

            if !locations.locations.isEmpty {
                fitToAllLocations()
            }

            isLoading = false

            // Setup auto-refresh every 5 seconds
            startAutoRefresh()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func refreshLocations() async {
        do {
            let _ = try await locationService.getConversationLocations(conversationId: conversationId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task {
                await refreshLocations()
            }
        }
    }

    private func centerOnLocation(_ location: SharedLocation) {
        withAnimation {
            region.center = location.coordinate
        }
    }

    private func fitToAllLocations() {
        guard let locations = locationService.conversationLocations[conversationId], !locations.isEmpty else { return }

        let latitudes = locations.map { $0.latitude }
        let longitudes = locations.map { $0.longitude }

        let minLat = latitudes.min() ?? 0
        let maxLat = latitudes.max() ?? 0
        let minLon = longitudes.min() ?? 0
        let maxLon = longitudes.max() ?? 0

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.2, 0.05),
            longitudeDelta: max((maxLon - minLon) * 1.2, 0.05)
        )

        withAnimation {
            region = MKCoordinateRegion(center: center, span: span)
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - User Location Marker

struct UserLocationMarker: View {
    let location: SharedLocation
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "location.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(isSelected ? .blue : .red)
                .scaleEffect(isSelected ? 1.2 : 1.0)

            if isSelected {
                VStack(spacing: 2) {
                    Text(location.userId.uuidString.prefix(8))
                        .font(.caption2)
                        .fontWeight(.semibold)
                    Text("±\(location.accuracyMeters)m")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.white)
                .cornerRadius(4)
                .offset(y: 8)
            }
        }
        .shadow(color: .black.opacity(0.2), radius: 4)
    }
}

// MARK: - User Location Card

struct UserLocationCard: View {
    let location: SharedLocation
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("User Location")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(location.userId.uuidString.prefix(12))
                        .font(.caption)
                        .monospaced()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("±\(location.accuracyMeters)m")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(location.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Latitude")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.6f", location.latitude))
                        .font(.caption)
                        .monospaced()
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Longitude")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.6f", location.longitude))
                        .font(.caption)
                        .monospaced()
                }

                Spacer()
            }

            Button(action: copyCoordinates) {
                Label("Copy Coords", systemImage: "doc.on.doc")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.bar)
        .cornerRadius(8)
        .padding(.horizontal)
    }

    private func copyCoordinates() {
        let coords = "\(location.latitude), \(location.longitude)"
        UIPasteboard.general.string = coords
    }
}

// MARK: - Preview

#Preview {
    LocationSharingMapView(conversationId: UUID())
        .environment(LocationService(httpClient: MockHTTPClient(), wsManager: MockWebSocketManager()))
}

// Mock implementations for preview
class MockHTTPClient {
    // Mock implementation
}

class MockWebSocketManager {
    // Mock implementation
}
