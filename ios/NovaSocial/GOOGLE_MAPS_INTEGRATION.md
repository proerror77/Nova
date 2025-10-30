# Google Maps Integration for Location Sharing

## Overview

This document explains how to integrate **Google Maps SDK for iOS** instead of using native MapKit for location sharing display.

## When to Use Google Maps vs MapKit

### Use Google Maps If:
- You need advanced map features (traffic, public transit, satellite view)
- You want consistent behavior across iOS and Android
- You need Street View support
- You require custom map styling
- You're already using Google services

### Use MapKit If:
- You want zero external dependencies
- You need minimal setup and maintenance
- You only need basic mapping features
- You want to avoid API key management
- You're focused on privacy (no external calls for tiles)

## Prerequisites

1. **Google Cloud Project** with Maps SDK for iOS enabled
2. **API Key** from Google Cloud Console
3. **CocoaPods** package manager
4. **iOS 12.0+** deployment target

## Step-by-Step Setup

### 1. Create Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create a new project
3. Enable these APIs:
   - Maps SDK for iOS
   - Places API (optional, for location autocomplete)

### 2. Generate API Key

1. Go to Credentials → Create Credentials → API Key
2. Restrict key to iOS apps only
3. Add your bundle identifier

### 3. Install via CocoaPods

Create/Update `Podfile`:

```ruby
platform :ios, '12.0'

target 'NovaSocial' do
  pod 'GoogleMaps'
  pod 'GooglePlaces', '~> 7.0.0'  # Optional
end
```

Run `pod install`:
```bash
cd ios/NovaSocial
pod install
```

### 4. Add API Key to App

In `NovaSocialApp.swift`:

```swift
import GoogleMaps

@main
struct NovaSocialApp: App {
    init() {
        GMSServices.provideAPIKey("YOUR_API_KEY_HERE")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

**Better approach - use Config/environment:**

Store API key in `Config/Keys.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>GOOGLE_MAPS_API_KEY</key>
    <string>YOUR_API_KEY_HERE</string>
</dict>
</dict>
</plist>
```

Load from plist:
```swift
func loadGoogleMapsAPIKey() -> String? {
    guard let path = Bundle.main.path(forResource: "Keys", ofType: "plist"),
          let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
          let apiKey = dict["GOOGLE_MAPS_API_KEY"] as? String else {
        return nil
    }
    return apiKey
}

@main
struct NovaSocialApp: App {
    init() {
        if let apiKey = loadGoogleMapsAPIKey() {
            GMSServices.provideAPIKey(apiKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### 5. Update Entitlements

Add to `Config/NovaSocial.entitlements`:

```xml
<key>com.apple.developer.maps</key>
<true/>

<key>NSLocalNetworkUsageDescription</key>
<string>This app uses local network to display maps</string>

<key>NSBonjourServices</key>
<array>
    <string>_maps._tcp</string>
</array>
```

## Implementation

### Create Google Maps View

```swift
import SwiftUI
import GoogleMaps

struct GoogleMapsLocationView: UIViewRepresentable {
    let conversationId: UUID
    @Environment(LocationService.self) private var locationService

    func makeUIView(context: Context) -> GMSMapView {
        let map = GMSMapView(frame: .zero)
        map.delegate = context.coordinator
        updateMapWithLocations(map, coordinator: context.coordinator)
        return map
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        updateMapWithLocations(mapView, coordinator: context.coordinator)
    }

    private func updateMapWithLocations(_ mapView: GMSMapView, coordinator: Coordinator) {
        mapView.clear()

        let locations = locationService.conversationLocations[conversationId] ?? []

        for location in locations {
            let marker = GMSMarker(position: location.coordinate)
            marker.title = location.userId.uuidString.prefix(8)
            marker.snippet = "±\(location.accuracyMeters)m"
            marker.map = mapView

            // Custom marker image
            marker.icon = createMarkerImage()
        }

        fitBounds(mapView, locations: locations)
    }

    private func createMarkerImage() -> UIImage {
        let size = CGSize(width: 40, height: 40)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        UIColor.systemBlue.setFill()
        UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return image
    }

    private func fitBounds(_ mapView: GMSMapView, locations: [SharedLocation]) {
        guard !locations.isEmpty else { return }

        let bounds = GMSCoordinateBounds(
            coordinates: locations.map { $0.coordinate }
        )
        let camera = mapView.camera(for: bounds, insets: UIEdgeInsets(top: 100, left: 100, bottom: 100, right: 100))
        mapView.animate(to: camera ?? mapView.camera)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: GoogleMapsLocationView

        init(_ parent: GoogleMapsLocationView) {
            self.parent = parent
        }

        func mapView(_ mapView: GMSMapView, didTapMarker marker: GMSMarker) -> Bool {
            // Handle marker tap
            return true
        }
    }
}

// Usage in your view:
struct LocationMapScreen: View {
    let conversationId: UUID

    var body: some View {
        GoogleMapsLocationView(conversationId: conversationId)
            .ignoresSafeArea()
    }
}
```

### Advanced: Custom Map Styling

```swift
struct StyledGoogleMapsView: UIViewRepresentable {
    func makeUIView(context: Context) -> GMSMapView {
        let map = GMSMapView(frame: .zero)

        // Apply custom style
        do {
            let style = try GMSMapStyle(contentsOfFileURL: styleUrl)
            map.mapStyle = style
        } catch {
            NSLog("One or more of the map styles failed to load: \(error)")
        }

        return map
    }

    private var styleUrl: URL {
        Bundle.main.url(forResource: "map_style", withExtension: "json")!
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {}
}
```

### Add Location Clustering

For 10+ locations, use clustering:

```swift
import GoogleMapsUtils

struct ClusteredGoogleMapsView: UIViewRepresentable {
    let locations: [SharedLocation]
    var clusterManager: GMUClusterManager?

    func makeUIView(context: Context) -> GMSMapView {
        let mapView = GMSMapView(frame: .zero)

        let clusterManager = GMUClusterManager(map: mapView, didTapClusterBlock: { cluster in
            // Handle cluster tap
            let bounds = GMSCoordinateBounds(cluster: cluster)
            let camera = mapView.camera(for: bounds, insets: UIEdgeInsets(top: 100, left: 100, bottom: 100, right: 100))
            mapView.animate(to: camera!)
            return true
        })

        // Add markers
        for location in locations {
            let marker = GMSMarker(position: location.coordinate)
            marker.title = location.userId.uuidString.prefix(8)
            clusterManager.add(marker)
        }

        clusterManager.cluster()
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {}
}
```

## API Key Security Best Practices

### Never Hardcode API Keys

✅ **Good:**
```swift
// Load from Info.plist
if let apiKey = Bundle.main.infoDictionary?["GOOGLE_MAPS_API_KEY"] as? String {
    GMSServices.provideAPIKey(apiKey)
}
```

❌ **Bad:**
```swift
GMSServices.provideAPIKey("AIzaSyDx...") // Never do this!
```

### Use API Key Restrictions

1. **Application restrictions**: iOS apps only
2. **API restrictions**: Maps SDK for iOS only
3. **User restrictions**: Your bundle ID only

### Rotate Keys Regularly

- Generate new keys monthly
- Disable old keys immediately
- Monitor usage in Google Cloud Console

## Cost Management

### Monitor Usage

1. Google Cloud Console → Billing
2. Set up alerts: Budget Alerts → Manage notifications
3. Review API calls daily

### Optimize API Calls

```swift
// Cache location data
private var cachedLocations: [SharedLocation] = []
private var lastFetchTime: Date = .distantPast

func getConversationLocations(conversationId: UUID) async throws -> [SharedLocation] {
    let now = Date()
    if now.timeIntervalSince(lastFetchTime) < 30 { // Cache for 30 seconds
        return cachedLocations
    }

    let locations = try await locationService.getConversationLocations(conversationId: conversationId).locations
    cachedLocations = locations
    lastFetchTime = now
    return locations
}
```

## Migration from MapKit to Google Maps

If you're switching from MapKit:

```swift
// MapKit coordinate
let mapKitCoordinate = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)

// Google Maps coordinate
let googleMapsCoordinate = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
// Same format! Just swap the map implementation
```

## Troubleshooting

### Invalid API Key
```
MapsInitializationError: Google Maps SDK for iOS: The provided API key is invalid.
Please check that your bundle identifier matches that of the API key.
```

**Solution:**
1. Verify bundle ID matches in Google Cloud Console
2. Check API key has Maps SDK enabled
3. Wait 5-10 minutes for key provisioning

### Missing GMSServices
```
'GMSServices' file not found
```

**Solution:**
```bash
pod install
# Then close Xcode and reopen .xcworkspace
```

### Map Not Rendering
- Check internet connection
- Verify API key validity
- Enable Maps SDK in Cloud Console
- Check device location services

## Performance Considerations

| Aspect | MapKit | Google Maps |
|--------|--------|------------|
| Bundle Size | +5MB | +80MB |
| Tile Loading | Fast | Slower (network) |
| Memory Usage | Low | Medium |
| API Cost | Free | Paid (after free tier) |
| Customization | Limited | Extensive |
| Real-time Data | Limited | Good (traffic, transit) |

## Conclusion

**Use Google Maps if:**
- You need advanced features beyond basic location display
- Cost is not a concern
- You want consistency with Android implementation
- You need custom map styling

**Use MapKit if:**
- You want simplicity and zero dependencies
- Privacy is important
- You want zero API cost
- You only need basic map display

See [LOCATION_SHARING_INTEGRATION.md](./LOCATION_SHARING_INTEGRATION.md) for the MapKit implementation.
