# Universal Links Setup Guide

## Overview

Universal Links allow NovaSocial to open deep links from web URLs seamlessly, providing a native app experience when links are tapped in Safari, Messages, Mail, and other apps.

---

## 1. Server Configuration

### Upload `apple-app-site-association` File

1. **Location**: Upload to your web server at:
   ```
   https://nova.social/.well-known/apple-app-site-association
   https://nova.social/apple-app-site-association
   ```

2. **Content-Type**: Must be served with:
   ```
   Content-Type: application/json
   ```

3. **HTTPS Required**: Universal Links only work over HTTPS (not HTTP)

4. **No File Extension**: The file must NOT have a `.json` extension

### Apache Configuration

```apache
<Files "apple-app-site-association">
    ForceType application/json
</Files>
```

### Nginx Configuration

```nginx
location /apple-app-site-association {
    default_type application/json;
}

location /.well-known/apple-app-site-association {
    default_type application/json;
}
```

### Verification

Test your configuration:
```bash
curl -I https://nova.social/apple-app-site-association
```

Expected response:
```
HTTP/2 200
content-type: application/json
```

---

## 2. Xcode Project Configuration

### Step 1: Enable Associated Domains

1. Open `NovaSocial.xcodeproj` in Xcode
2. Select the **NovaSocial** target
3. Go to **Signing & Capabilities** tab
4. Click **+ Capability**
5. Add **Associated Domains**

### Step 2: Add Domains

In the Associated Domains section, add:
```
applinks:nova.social
applinks:www.nova.social
```

For development/staging environments:
```
applinks:staging.nova.social
applinks:dev.nova.social
```

### Step 3: Update Team ID

In `apple-app-site-association`, replace `TEAM_ID` with your actual Team ID:

```json
"appIDs": [
  "ABC123XYZ.com.nova.social",
  "ABC123XYZ.com.nova.social.debug"
]
```

Find your Team ID:
1. Go to [Apple Developer](https://developer.apple.com/account)
2. Navigate to **Membership**
3. Copy **Team ID**

### Step 4: Update Bundle Identifiers

Ensure your bundle identifiers match:
- **Production**: `com.nova.social`
- **Debug**: `com.nova.social.debug`

---

## 3. Entitlements Configuration

Xcode should auto-generate `NovaSocial.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.associated-domains</key>
    <array>
        <string>applinks:nova.social</string>
        <string>applinks:www.nova.social</string>
    </array>
</dict>
</plist>
```

---

## 4. URL Scheme Configuration

### Info.plist Configuration

Add custom URL scheme for fallback:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLName</key>
        <string>com.nova.social</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>novasocial</string>
        </array>
    </dict>
</array>
```

This allows URLs like:
```
novasocial://user/123
novasocial://post/456
novasocial://search?q=swift
```

---

## 5. Testing Universal Links

### Test on Device (Recommended)

Universal Links must be tested on a real device (not simulator):

1. **Send Test Links**:
   - Send yourself an email with test links
   - Send test links in Messages
   - Create a Notes document with links

2. **Test Links**:
   ```
   https://nova.social/user/123
   https://nova.social/post/456
   https://nova.social/search?q=test
   https://nova.social/hashtag/ios
   https://nova.social/notifications
   ```

3. **Expected Behavior**:
   - Long press → Should show "Open in NovaSocial"
   - Tap → Should open directly in app (if installed)

### Test Custom URL Scheme

Works in both simulator and device:

```bash
xcrun simctl openurl booted "novasocial://user/123"
xcrun simctl openurl booted "novasocial://post/456"
xcrun simctl openurl booted "novasocial://search?q=test"
```

### Debugging Tools

#### 1. Apple CDN Validation

Check if Apple has cached your file:
```bash
curl https://app-site-association.cdn-apple.com/a/v1/nova.social
```

**Note**: It may take up to 24 hours for Apple's CDN to update.

#### 2. Clear Universal Links Cache (on device)

```bash
# Connect device via USB
# Reset universal links cache
defaults delete com.apple.MobileSafari WKWebsiteDataStore
```

Then restart the device.

#### 3. Console Debugging

In Xcode Console, filter for:
```
swcd
```

This shows universal link matching activity.

---

## 6. Implementation in App

### App.swift Integration

The deep link handler is integrated in `App.swift`:

```swift
import SwiftUI

@main
struct NovaSocialApp: App {
    @StateObject private var deepLinkRouter = DeepLinkRouter()
    @StateObject private var navigationState = DeepLinkNavigationState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(deepLinkRouter)
                .environmentObject(navigationState)
                .onOpenURL { url in
                    // Handle custom URL scheme
                    deepLinkRouter.handle(url: url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                    // Handle Universal Links
                    guard let url = userActivity.webpageURL else { return }
                    deepLinkRouter.handle(url: url)
                }
        }
    }
}
```

### Route Handling

Routes are defined in `DeepLinkRouter.swift`:

```swift
enum DeepLinkRoute {
    case userProfile(userId: String)
    case post(postId: String)
    case search(query: String?)
    case notifications
    // ... more routes
}
```

---

## 7. Security Considerations

### Validate Deep Link Parameters

Always validate parameters from deep links:

```swift
private func navigateToUserProfile(userId: String) {
    // Validate userId format
    guard userId.rangeOfCharacter(from: .alphanumerics.inverted) == nil else {
        handleInvalidLink(error: "Invalid user ID")
        return
    }

    // Proceed with navigation
    navigationState.presentedSheet = .userProfile(userId: userId)
}
```

### Authentication Checks

Protect authenticated routes:

```swift
private func navigateToNotifications() {
    guard isAuthenticated else {
        showAuthenticationRequired()
        return
    }

    navigationState.selectedTab = .notifications
}
```

### Rate Limiting

Implement rate limiting for sensitive operations triggered by deep links:

```swift
private var lastDeepLinkTimestamp: Date?
private let minimumDeepLinkInterval: TimeInterval = 1.0

func handle(url: URL) {
    // Rate limit
    if let lastTimestamp = lastDeepLinkTimestamp,
       Date().timeIntervalSince(lastTimestamp) < minimumDeepLinkInterval {
        return
    }

    lastDeepLinkTimestamp = Date()

    // Process deep link
    router.handle(url: url)
}
```

---

## 8. Common Issues and Solutions

### Issue 1: Universal Links Not Working

**Symptoms**: Links open in Safari instead of app

**Solutions**:
1. Verify `apple-app-site-association` is accessible:
   ```bash
   curl https://nova.social/apple-app-site-association
   ```

2. Check Team ID matches in both file and Xcode

3. Ensure HTTPS is used (not HTTP)

4. Wait 24 hours for Apple CDN to update

5. Reinstall app on device

6. Reset device

### Issue 2: Links Open Safari First

**Cause**: iOS has learned user preference to open in Safari

**Solution**:
1. Long press a link
2. Select "Open in NovaSocial"
3. iOS will remember preference

### Issue 3: Some Links Work, Others Don't

**Cause**: Pattern matching issue in `apple-app-site-association`

**Solution**:
1. Verify patterns match your URL structure
2. Test each pattern individually
3. Check for typos in components

### Issue 4: Links Work in Messages but Not Safari

**Cause**: Safari has different caching behavior

**Solution**:
1. Clear Safari history and website data
2. Restart device
3. Test in Private Browsing mode

---

## 9. Production Checklist

Before launching:

- [ ] `apple-app-site-association` uploaded to production server
- [ ] File served with correct `Content-Type: application/json`
- [ ] HTTPS working correctly
- [ ] Team ID updated in association file
- [ ] Bundle identifiers match
- [ ] Associated Domains configured in Xcode
- [ ] Tested all deep link routes on real device
- [ ] Universal Links tested in:
  - [ ] Safari
  - [ ] Messages
  - [ ] Mail
  - [ ] Notes
  - [ ] Third-party apps
- [ ] Custom URL scheme tested
- [ ] Error handling implemented
- [ ] Analytics tracking configured
- [ ] Accessibility announcements working
- [ ] Documentation updated

---

## 10. Analytics and Monitoring

Track deep link usage:

```swift
private func trackDeepLink(url: URL) {
    analyticsService?.track(event: "deep_link_opened", properties: [
        "url": url.absoluteString,
        "scheme": url.scheme ?? "unknown",
        "host": url.host ?? "unknown",
        "path": url.path,
        "source": "universal_link"
    ])
}
```

Monitor metrics:
- Deep link open rate
- Most used routes
- Conversion from deep link to action
- Error rates by route

---

## Resources

- [Apple Universal Links Documentation](https://developer.apple.com/ios/universal-links/)
- [Supporting Universal Links](https://developer.apple.com/documentation/xcode/supporting-universal-links-in-your-app)
- [Associated Domains Entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_developer_associated-domains)
- [Universal Links Validator](https://branch.io/resources/aasa-validator/)
