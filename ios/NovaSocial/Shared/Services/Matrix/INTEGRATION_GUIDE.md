# Matrix Rust SDK Integration Guide for Nova iOS

This document describes how to integrate the Matrix Rust SDK into the Nova iOS app for end-to-end encrypted chat messaging.

## Overview

Nova uses Matrix Synapse as its chat backend, with the Matrix Rust SDK providing E2EE (end-to-end encryption) on the iOS client. The integration bridges Nova's existing chat API with Matrix rooms.

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Nova iOS App  │────▶│  Matrix Bridge   │────▶│  Matrix Synapse │
│   (SwiftUI)     │     │    Service       │     │    (Backend)    │
└─────────────────┘     └──────────────────┘     └─────────────────┘
        │                        │                        │
        │                        ▼                        │
        │               ┌──────────────────┐              │
        │               │  MatrixRustSDK   │              │
        │               │  (Swift FFI)     │──────────────┘
        │               └──────────────────┘
        │                        │
        ▼                        ▼
┌─────────────────┐     ┌──────────────────┐
│  ChatService    │     │  E2EE Crypto     │
│  (REST/WS)      │     │  (Megolm/Olm)    │
└─────────────────┘     └──────────────────┘
```

## Prerequisites

- Xcode 15.0+
- iOS 15.0+ deployment target
- Swift 5.9+
- Matrix Synapse backend with sliding sync support

## Step 1: Add Swift Package Dependency

### Using Xcode

1. Open `ICERED.xcodeproj` in Xcode
2. Go to **File** → **Add Package Dependencies...**
3. Enter the package URL:
   ```
   https://github.com/matrix-org/matrix-rust-components-swift
   ```
4. Select version: `25.11.11` or later (check for latest stable release)
5. Click **Add Package**
6. Select **MatrixRustSDK** library and add to the ICERED target

### Using Package.swift (if converting to SPM)

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ICERED",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    dependencies: [
        .package(
            url: "https://github.com/matrix-org/matrix-rust-components-swift",
            from: "25.11.11"
        )
    ],
    targets: [
        .target(
            name: "ICERED",
            dependencies: [
                .product(name: "MatrixRustSDK", package: "matrix-rust-components-swift")
            ]
        )
    ]
)
```

## Step 2: Enable MatrixService Implementation

After adding the package, uncomment the SDK imports and implementations in:

1. **MatrixService.swift** - Main Matrix client wrapper
   - Uncomment `import MatrixRustSDK`
   - Uncomment `client: ClientProtocol` property
   - Uncomment SDK method implementations

2. **MatrixBridgeService.swift** - Nova-Matrix bridge
   - No changes needed, uses MatrixService

## Step 3: Initialize Matrix on App Launch

In `App.swift` or your app delegate:

```swift
import SwiftUI

@main
struct ICEREDApp: App {
    init() {
        // Initialize Matrix bridge after authentication
        NotificationCenter.default.addObserver(
            forName: .userDidLogin,
            object: nil,
            queue: .main
        ) { _ in
            Task {
                try? await MatrixBridgeService.shared.initialize()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

## Step 4: Update ChatService for Matrix Integration

The ChatService can optionally route E2EE messages through Matrix:

```swift
extension ChatService {
    /// Send message with E2EE via Matrix (if available)
    @MainActor
    func sendSecureMessage(
        conversationId: String,
        content: String,
        type: ChatMessageType = .text,
        mediaUrl: String? = nil
    ) async throws -> Message {
        // Use Matrix for E2EE if bridge is initialized
        if MatrixBridgeService.shared.isInitialized {
            let eventId = try await MatrixBridgeService.shared.sendMessage(
                conversationId: conversationId,
                content: content
            )

            // Return message with Matrix event ID
            return Message(
                id: eventId,
                conversationId: conversationId,
                senderId: AuthenticationManager.shared.currentUser?.id ?? "",
                content: content,
                type: type,
                createdAt: Date(),
                status: .sent
            )
        }

        // Fallback to regular API
        return try await sendMessage(
            conversationId: conversationId,
            content: content,
            type: type,
            mediaUrl: mediaUrl
        )
    }
}
```

## ID Mapping

### User IDs
- **Nova Format**: `uuid-string` (e.g., `550e8400-e29b-41d4-a716-446655440000`)
- **Matrix Format**: `@nova-<uuid>:staging.nova.internal`

### Room/Conversation IDs
- **Nova Format**: `uuid-string` (conversation ID)
- **Matrix Format**: `!<random>:staging.nova.internal` (room ID)
- Mapping stored in backend `matrix_room_mappings` table

## Configuration

### MatrixConfiguration.swift

```swift
struct MatrixConfiguration {
    // Staging
    static let stagingHomeserver = "https://matrix.staging.nova.internal"

    // Production
    static let productionHomeserver = "https://matrix.nova.social"

    // Session storage
    static var sessionPath: String {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("matrix_session")
            .path
    }
}
```

## Backend Requirements

The Nova backend must:

1. **Run Matrix Synapse** - Homeserver for Matrix protocol
2. **Mint Matrix Access Tokens** - Issue tokens for authenticated Nova users
3. **Store Room Mappings** - conversation_id ↔ matrix_room_id table
4. **Bridge Events** (optional) - Forward Matrix events to Nova WebSocket

## Testing

### Unit Tests

```swift
import XCTest
@testable import ICERED

class MatrixServiceTests: XCTestCase {
    func testUserIdConversion() {
        let matrixService = MatrixService.shared

        let novaId = "550e8400-e29b-41d4-a716-446655440000"
        let matrixId = "@nova-550e8400-e29b-41d4-a716-446655440000:staging.nova.internal"

        // Test conversion
        XCTAssertEqual(
            matrixService.convertToNovaUserId(matrixUserId: matrixId),
            novaId
        )
    }
}
```

### Integration Tests

1. Login with test account
2. Create conversation
3. Verify Matrix room created
4. Send E2EE message
5. Verify message decrypted on other device

## Troubleshooting

### Common Issues

1. **"SDK not initialized"**
   - Ensure MatrixRustSDK package is properly added
   - Check iOS deployment target is 15.0+

2. **"Login failed"**
   - Verify homeserver URL is correct
   - Check Matrix access token is valid
   - Ensure backend Synapse is running

3. **"Room not found"**
   - Check conversation mapping exists
   - Verify user has joined the room
   - Sync may not have completed yet

### Debug Logging

Enable verbose logging:

```swift
#if DEBUG
print("[MatrixService] ...")
#endif
```

## References

- [Matrix Rust SDK](https://github.com/matrix-org/matrix-rust-sdk)
- [Swift Components Package](https://github.com/matrix-org/matrix-rust-components-swift)
- [Element X iOS](https://github.com/element-hq/element-x-ios) - Reference implementation
- [Matrix Spec](https://spec.matrix.org/)
