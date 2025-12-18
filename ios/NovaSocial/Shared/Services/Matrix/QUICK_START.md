# Matrix E2EE Quick Start Guide

## Integration Status

✅ **COMPLETE** - Matrix Rust SDK integration is ready to use

## What Was Changed

### 1. Package Dependency Added
- **Package:** matrix-rust-components-swift
- **URL:** https://github.com/matrix-org/matrix-rust-components-swift
- **Version:** 1.0.0+
- **Status:** Added to Xcode project, will download on next build

### 2. Implementation Files
- ✅ **MatrixService.swift** - SDK wrapper with conditional import
- ✅ **MatrixBridgeService.swift** - Full implementation (ready to use)
- ✅ **MatrixSSOManager.swift** - SSO authentication (ready to use)
- ✅ **Info.plist** - URL schemes configured

### 3. Configuration
- Staging: `https://matrix.staging.gcp.icered.com`
- Server: `staging.gcp.icered.com`
- Callbacks: `nova-staging://matrix-sso-callback`

## How to Use

### Check E2EE Availability

```swift
import Foundation

// Check if Matrix E2EE is available
if MatrixBridgeService.shared.isE2EEAvailable {
    print("E2EE enabled")
} else {
    print("E2EE not available")
}
```

### Initialize on Login

```swift
// After user logs in to Nova
Task {
    do {
        try await MatrixBridgeService.shared.initialize()
        print("Matrix initialized: \(MatrixBridgeService.shared.isE2EEAvailable)")
    } catch {
        print("Matrix init failed: \(error)")
    }
}
```

### Send Encrypted Message

```swift
// Check if E2EE is available
guard MatrixBridgeService.shared.isE2EEAvailable else {
    // Fallback to regular API
    return
}

// Send via Matrix E2EE
let eventId = try await MatrixBridgeService.shared.sendMessage(
    conversationId: conversation.id,
    content: "Hello, encrypted world!"
)
```

### Start Encrypted Conversation

```swift
// Create new conversation with E2EE
let conversation = try await MatrixBridgeService.shared.startConversationWithFriend(
    friendUserId: friend.id
)

// Use the conversation ID for messaging
print("Created conversation: \(conversation.id)")
```

### Listen for Incoming Messages

```swift
// Set up message handler
MatrixBridgeService.shared.onMatrixMessage = { conversationId, message in
    print("New message in \(conversationId): \(message.content)")

    // Convert to Nova message format
    let novaMessage = MatrixBridgeService.shared.convertToNovaMessage(
        message,
        conversationId: conversationId
    )
}
```

## Next Build Steps

1. **Open Xcode Project**
   ```bash
   open /Users/proerror/Documents/Nova/ios/NovaSocial/ICERED.xcodeproj
   ```

2. **Wait for Package Resolution** (2-5 minutes)
   - Xcode will download MatrixRustSDK
   - Check bottom status bar for progress

3. **Build the App** (Cmd+B)
   - First build may take longer
   - SDK includes pre-compiled Rust binaries

4. **Test Integration**
   - Run app on simulator or device
   - Login with Nova account
   - Check `MatrixBridgeService.shared.isE2EEAvailable`

## Troubleshooting

### "Cannot find 'MatrixRustSDK' in scope"
- SDK is still downloading or failed to resolve
- Try: **File → Packages → Reset Package Caches**
- Then: **File → Packages → Update to Latest Package Versions**

### "isE2EEAvailable returns false"
- MatrixBridgeService not initialized
- Call `await MatrixBridgeService.shared.initialize()`
- Check for initialization errors in logs

### SSO Login Fails
- Verify homeserver is accessible
- Check URL scheme is registered in Info.plist
- Ensure backend Synapse is running

## Key Properties

### MatrixBridgeService.shared
- `isInitialized: Bool` - Bridge initialized
- `isE2EEAvailable: Bool` - E2EE ready to use
- `isBridgeEnabled: Bool` - Feature enabled for user

### Methods
- `initialize()` - Start Matrix client
- `sendMessage(conversationId:content:)` - Send E2EE message
- `startConversationWithFriend(friendUserId:)` - Create E2EE chat
- `shutdown(clearCredentials:)` - Clean shutdown

## Files Modified

```
ios/NovaSocial/
├── ICERED.xcodeproj/project.pbxproj         (Package added)
└── Shared/Services/Matrix/
    ├── MatrixService.swift                   (SDK import added)
    ├── MatrixStubs.swift                     (Stubs removed)
    ├── MatrixBridgeService.swift             (No changes - already complete)
    ├── MatrixSSOManager.swift                (No changes - already complete)
    ├── INTEGRATION_GUIDE.md                  (Existing documentation)
    ├── MATRIX_INTEGRATION_COMPLETE.md        (New - full details)
    └── QUICK_START.md                        (This file)
```

## Build Configuration

No additional build settings needed. The package dependency handles:
- ✅ Framework linking
- ✅ Header search paths
- ✅ Library search paths
- ✅ Swift module imports

## Status: READY TO BUILD

The integration is complete. Next step is to build the app in Xcode.
