# Real-Time Location Sharing Integration Guide

## Overview

This guide explains how to integrate real-time location sharing in conversations using MapKit and CoreLocation.

## Architecture

### Components

```
┌─────────────────────────────────────────────────────┐
│                  SwiftUI Views                       │
├─────────────────────────────────────────────────────┤
│ LocationSharingMapView   │  LocationPermissionsView │
└──────────────┬──────────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────────┐
│            LocationService                          │
│   (API calls + WebSocket events)                    │
├─────────────────────────────────────────────────────┤
│ • startSharing()          • getConversationLocations()
│ • stopSharing()           • getUserLocation()
│ • getStats()              • handleWebSocketEvent()
└──────────────┬──────────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────────┐
│       LocationPermissionManager                     │
│   (CoreLocation + Server permissions)               │
├─────────────────────────────────────────────────────┤
│ • requestWhenInUseAuthorization()
│ • loadPermissions()
│ • updatePreferences()
└─────────────────────────────────────────────────────┘
```

### Data Models

- **UserLocation**: Database representation of a user's location
- **SharedLocation**: API response model for active locations
- **ConversationLocations**: All locations in a conversation
- **LocationPermissionResponse**: User's privacy settings
- **LocationStats**: Analytics data about location sharing

## Implementation Steps

### 1. Add MapKit Capability

Edit `Config/NovaSocial.entitlements`:

```xml
<key>com.apple.developer.maps</key>
<true/>
```

### 2. Add Location Services Permission

Edit `Info.plist` (or use Xcode UI):

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location to share with conversation participants</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>We need your location to share with conversation participants</string>

<key>NSLocationAlwaysUsageDescription</key>
<string>We need your location to share with conversation participants</string>
```

### 3. Integrate into ConversationDetailView

```swift
import SwiftUI
import MapKit

struct ConversationDetailView: View {
    let conversationId: UUID
    @Environment(LocationService.self) private var locationService
    @Environment(LocationPermissionManager.self) private var permissionManager
    @State private var showingLocationMap = false
    @State private var showingLocationSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Existing message list...

            // Location sharing toggle
            if permissionManager.canShareLocation {
                HStack {
                    Button(action: { showingLocationMap = true }) {
                        Label("Locations", systemImage: "location.fill")
                    }

                    Button(action: { showingLocationSettings = true }) {
                        Image(systemName: "gear")
                    }
                }
                .padding()
                .background(.bar)
            }
        }
        .sheet(isPresented: $showingLocationMap) {
            NavigationStack {
                LocationSharingMapView(conversationId: conversationId)
            }
        }
        .sheet(isPresented: $showingLocationSettings) {
            NavigationStack {
                LocationPermissionsView()
            }
        }
    }
}
```

### 4. Set Up Environment

In your app's main view:

```swift
@main
struct NovaSocialApp: App {
    @State private var locationService: LocationService
    @State private var permissionManager: LocationPermissionManager
    @State private var httpClient: HTTPClient
    @State private var wsManager: WebSocketManager

    init() {
        let httpClient = HTTPClient()
        let wsManager = WebSocketManager()

        self.httpClient = httpClient
        self.wsManager = wsManager
        self._locationService = State(initialValue: LocationService(
            httpClient: httpClient,
            wsManager: wsManager
        ))
        self._permissionManager = State(initialValue: LocationPermissionManager(
            httpClient: httpClient
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(locationService)
                .environment(permissionManager)
        }
    }
}
```

## API Endpoints

### Start/Update Location

**POST** `/api/v1/conversations/{id}/location`

```json
{
    "latitude": 37.7749,
    "longitude": -122.4194,
    "accuracy_meters": 65,
    "altitude_meters": 10,
    "heading_degrees": 45,
    "speed_mps": 2.5
}
```

### Get All Locations in Conversation

**GET** `/api/v1/conversations/{id}/locations`

Response:
```json
{
    "conversation_id": "uuid",
    "locations": [
        {
            "id": "uuid",
            "user_id": "uuid",
            "latitude": 37.7749,
            "longitude": -122.4194,
            "accuracy_meters": 65,
            "timestamp": "2025-10-29T15:30:00Z"
        }
    ],
    "timestamp": "2025-10-29T15:30:00Z"
}
```

### Get Specific User Location

**GET** `/api/v1/conversations/{id}/location/{user_id}`

### Stop Sharing Location

**POST** `/api/v1/conversations/{id}/location/stop`

```json
{
    "duration_seconds": 300,
    "distance_meters": 1500
}
```

### Get Location Statistics

**GET** `/api/v1/conversations/{id}/location/stats`

Response:
```json
{
    "active_sharers": 3,
    "last_update": "2025-10-29T15:30:00Z"
}
```

### Manage Permissions

**GET** `/api/v1/location/permissions`

**PUT** `/api/v1/location/permissions`

```json
{
    "allow_conversations": true,
    "allow_search": false,
    "blur_location": false
}
```

## WebSocket Events

### LocationShared
```json
{
    "type": "location.shared",
    "timestamp": "2025-10-29T15:30:00Z",
    "user_id": "uuid",
    "conversation_id": "uuid",
    "latitude": 37.7749,
    "longitude": -122.4194,
    "accuracy_meters": 65
}
```

### LocationUpdated
```json
{
    "type": "location.updated",
    "timestamp": "2025-10-29T15:30:00Z",
    "user_id": "uuid",
    "conversation_id": "uuid",
    "latitude": 37.7749,
    "longitude": -122.4194,
    "accuracy_meters": 65
}
```

### LocationStopped
```json
{
    "type": "location.stopped",
    "timestamp": "2025-10-29T15:30:00Z",
    "user_id": "uuid",
    "conversation_id": "uuid"
}
```

## Usage Examples

### Start Sharing Location

```swift
@State private var currentLocation: CLLocationCoordinate2D?

func startSharingLocation(coordinate: CLLocationCoordinate2D) async {
    do {
        let location = try await locationService.startSharing(
            conversationId: conversationId,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            accuracy: 65
        )
        print("Started sharing: \(location.id)")
    } catch {
        print("Error: \(error)")
    }
}
```

### Get Conversation Locations and Display on Map

```swift
func loadLocations() async {
    do {
        let locations = try await locationService.getConversationLocations(
            conversationId: conversationId
        )

        // Update map with locations
        for location in locations.locations {
            addAnnotation(at: location.coordinate)
        }
    } catch {
        print("Error: \(error)")
    }
}
```

### Listen for Location Updates via WebSocket

```swift
// In your WebSocket handler:
func handleWebSocketMessage(_ message: WebSocketMessage) {
    if message.type == "location.updated" {
        let event = LocationUpdatedEvent(...)
        locationService.handleWebSocketEvent(.locationUpdated(event))
    }
}
```

### Update Privacy Settings

```swift
func updatePrivacy() async {
    do {
        let updated = try await permissionManager.updatePreferences(
            allowConversations: true,
            allowSearch: false,
            blurLocation: true
        )
        print("Preferences updated: \(updated)")
    } catch {
        print("Error: \(error)")
    }
}
```

## Security Considerations

1. **End-to-End Encryption**: All location data is encrypted before transmission
2. **Permission Scoping**: Users can enable/disable sharing per-conversation
3. **Time-Limited**: Sharing stops automatically after a set duration
4. **Accuracy Control**: Users can blur location to ±1km
5. **Audit Logging**: All location events are logged server-side for compliance

## Performance Optimization

1. **Location Updates**: Throttled to 1 update every 10 seconds on mobile
2. **Map Rendering**: Uses efficient clustering for 10+ locations
3. **WebSocket Updates**: Real-time events batched to reduce bandwidth
4. **Memory Management**: Locations older than 24 hours are archived

## Testing

### Unit Tests

```swift
@Test
func testLocationSharingStartAndStop() async throws {
    let service = LocationService(httpClient: MockHTTPClient(), wsManager: MockWebSocketManager())

    let location = try await service.startSharing(
        conversationId: UUID(),
        latitude: 37.7749,
        longitude: -122.4194,
        accuracy: 65
    )

    #expect(location.latitude == 37.7749)
    #expect(location.longitude == -122.4194)
}
```

### Manual Testing Checklist

- [ ] Request location permission
- [ ] Start sharing in a conversation
- [ ] Map displays user's location marker
- [ ] Location updates in real-time
- [ ] Stop sharing removes marker
- [ ] Multiple users' locations display correctly
- [ ] Adjust privacy settings
- [ ] Verify blur location works
- [ ] Test on actual device with GPS

## Troubleshooting

### Map Not Showing Locations
- Check location permissions in Settings
- Verify location service is enabled
- Ensure WebSocket is connected
- Check server is returning location data

### Permission Denied
- Verify Info.plist has correct keys
- Check entitlements file
- Test on iOS 17+ device/simulator

### High Battery Usage
- Disable continuous sharing if not needed
- Increase location update interval
- Use significant location change monitoring

## Next Steps

1. **Google Maps Integration**: If you need Google Maps instead of MapKit, see [GOOGLE_MAPS_INTEGRATION.md](./GOOGLE_MAPS_INTEGRATION.md)
2. **Advanced Features**: History, heatmaps, custom markers
3. **Offline Support**: Queue location updates when offline
4. **Analytics**: Track location sharing adoption and patterns
