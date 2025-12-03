# Deep Linking Guide - NovaSocial iOS

**Version**: 1.0.0
**Last Updated**: October 19, 2025

---

## Table of Contents

1. [Overview](#overview)
2. [Supported Deep Links](#supported-deep-links)
3. [URL Scheme vs Universal Links](#url-scheme-vs-universal-links)
4. [Implementation](#implementation)
5. [Testing](#testing)
6. [Analytics](#analytics)
7. [Troubleshooting](#troubleshooting)
8. [Best Practices](#best-practices)

---

## Overview

NovaSocial supports two types of deep linking:

1. **Custom URL Scheme**: `novasocial://` - Works everywhere, always opens app
2. **Universal Links**: `https://nova.social/` - Seamless web-to-app transition

### Why Both?

| Feature | Custom Scheme | Universal Links |
|---------|---------------|-----------------|
| Works in Safari | ✅ | ✅ |
| Works in Messages | ✅ | ✅ |
| Works in Mail | ✅ | ✅ |
| Works in third-party apps | ✅ | ⚠️ Varies |
| SEO-friendly | ❌ | ✅ |
| Fallback to web | ❌ | ✅ |
| Requires server setup | ❌ | ✅ |

---

## Supported Deep Links

### 1. User Routes

#### View User Profile

**Universal Link**:
```
https://nova.social/user/123
https://nova.social/u/123
https://nova.social/@johndoe
```

**Custom Scheme**:
```
novasocial://user/123
```

**Parameters**:
- `userId` (required): User ID or username

**Example Usage**:
```swift
let url = DeepLinkBuilder.userProfile(userId: "123")
// https://nova.social/user/123
```

---

#### Current User Profile

**Universal Link**:
```
https://nova.social/profile
```

**Custom Scheme**:
```
novasocial://user
```

**Behavior**: Opens the authenticated user's profile

---

#### Followers List

**Universal Link**:
```
https://nova.social/user/123/followers
```

**Custom Scheme**:
```
novasocial://user/123/followers
```

---

#### Following List

**Universal Link**:
```
https://nova.social/user/123/following
```

**Custom Scheme**:
```
novasocial://user/123/following
```

---

### 2. Content Routes

#### View Post

**Universal Link**:
```
https://nova.social/post/456
https://nova.social/p/456
```

**Custom Scheme**:
```
novasocial://post/456
```

**Parameters**:
- `postId` (required): Post ID

**Example Usage**:
```swift
let url = DeepLinkBuilder.post(postId: "456")
// https://nova.social/post/456
```

---

#### Feed

**Universal Link**:
```
https://nova.social/
https://nova.social/feed
```

**Custom Scheme**:
```
novasocial://feed
```

---

#### Explore

**Universal Link**:
```
https://nova.social/explore
```

**Custom Scheme**:
```
novasocial://explore
```

---

#### Notifications

**Universal Link**:
```
https://nova.social/notifications
```

**Custom Scheme**:
```
novasocial://notifications
```

**Authentication**: Required

---

### 3. Search Routes

#### Search with Query

**Universal Link**:
```
https://nova.social/search?q=swift
```

**Custom Scheme**:
```
novasocial://search?q=swift
```

**Parameters**:
- `q` (optional): Search query

---

#### Hashtag Search

**Universal Link**:
```
https://nova.social/hashtag/ios
https://nova.social/tag/ios
```

**Custom Scheme**:
```
novasocial://search?q=%23ios
```

**Example Usage**:
```swift
let url = DeepLinkBuilder.hashtag(tag: "ios")
// https://nova.social/hashtag/ios
```

---

### 4. Authentication Routes

#### Email Verification

**Universal Link**:
```
https://nova.social/verify?token=abc123xyz
```

**Custom Scheme**:
```
novasocial://auth/verify?token=abc123xyz
```

**Parameters**:
- `token` (required): Verification token from email

**Usage**: Sent in verification emails

---

#### Password Reset

**Universal Link**:
```
https://nova.social/reset-password?token=xyz789abc
```

**Custom Scheme**:
```
novasocial://auth/reset-password?token=xyz789abc
```

**Parameters**:
- `token` (required): Reset token from email

**Usage**: Sent in password reset emails

---

#### OAuth Callback

**Custom Scheme Only**:
```
novasocial://auth/oauth/google?code=authcode123
```

**Parameters**:
- `provider`: OAuth provider (google, apple, facebook)
- `code`: Authorization code

---

### 5. Settings Routes

#### Settings Home

**Universal Link**:
```
https://nova.social/settings
```

**Custom Scheme**:
```
novasocial://settings
```

---

#### Privacy Settings

**Universal Link**:
```
https://nova.social/settings/privacy
```

**Custom Scheme**:
```
novasocial://settings/privacy
```

---

#### Account Settings

**Universal Link**:
```
https://nova.social/settings/account
```

**Custom Scheme**:
```
novasocial://settings/account
```

---

#### Notification Settings

**Universal Link**:
```
https://nova.social/settings/notifications
```

**Custom Scheme**:
```
novasocial://settings/notifications
```

---

### 6. Media Routes

#### Camera

**Custom Scheme Only**:
```
novasocial://camera
```

**Authentication**: Required

---

#### Media Library

**Custom Scheme Only**:
```
novasocial://media
```

**Authentication**: Required

---

## URL Scheme vs Universal Links

### When to Use Custom URL Scheme

✅ **Use Cases**:
- Internal app navigation
- OAuth callbacks
- Custom share buttons
- Deep links from other apps
- Testing in simulator

❌ **Avoid**:
- Social media sharing (use Universal Links)
- Email campaigns (use Universal Links)
- SEO-critical pages (use Universal Links)

---

### When to Use Universal Links

✅ **Use Cases**:
- Social media sharing
- Email campaigns
- Website links
- SMS marketing
- QR codes
- SEO-critical content

❌ **Avoid**:
- OAuth callbacks (may not work in all browsers)
- Internal-only navigation

---

## Implementation

### Architecture

```
┌─────────────────────────────────────────────────┐
│                  App Entry                       │
│              (NovaSocialApp.swift)               │
│                                                   │
│  .onOpenURL { url in }                           │
│  .onContinueUserActivity(.browsing) { ... }      │
└──────────────────┬──────────────────────────────┘
                   │
                   v
┌─────────────────────────────────────────────────┐
│             DeepLinkRouter                       │
│                                                   │
│  • Parse URL → DeepLinkRoute enum                │
│  • Validate parameters                           │
│  • Generate URLs                                 │
└──────────────────┬──────────────────────────────┘
                   │
                   v
┌─────────────────────────────────────────────────┐
│           DeepLinkHandler                        │
│                                                   │
│  • Navigate to route                             │
│  • Check authentication                          │
│  • Update navigation state                       │
└──────────────────┬──────────────────────────────┘
                   │
                   v
┌─────────────────────────────────────────────────┐
│       DeepLinkNavigationState                    │
│                                                   │
│  • selectedTab                                   │
│  • presentedSheet                                │
│  • navigationPath                                │
└─────────────────────────────────────────────────┘
```

---

### Code Integration

#### 1. App Setup

```swift
@main
struct NovaSocialApp: App {
    @StateObject private var deepLinkRouter = DeepLinkRouter()
    @StateObject private var navigationState = DeepLinkNavigationState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(deepLinkRouter)
                .environmentObject(navigationState)
                // Custom URL Scheme
                .onOpenURL { url in
                    deepLinkRouter.handle(url: url)
                }
                // Universal Links
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    deepLinkRouter.handle(url: url)
                }
        }
    }
}
```

---

#### 2. Parse URLs

```swift
let router = DeepLinkRouter()

// Parse custom scheme
let customURL = URL(string: "novasocial://post/123")!
let route1 = router.parse(url: customURL)
// Result: .post(postId: "123")

// Parse universal link
let universalURL = URL(string: "https://nova.social/user/456")!
let route2 = router.parse(url: universalURL)
// Result: .userProfile(userId: "456")
```

---

#### 3. Generate URLs

```swift
// Generate universal link
let userURL = router.generateURL(for: .userProfile(userId: "123"))
// https://nova.social/user/123

// Generate custom scheme URL
let postURL = router.generateURL(
    for: .post(postId: "456"),
    preferUniversalLink: false
)
// novasocial://post/456
```

---

#### 4. Share Content

```swift
let route = DeepLinkRoute.post(postId: "123")
let activityItems = route.activityItems(router: deepLinkRouter)

let activityVC = UIActivityViewController(
    activityItems: activityItems,
    applicationActivities: nil
)
present(activityVC, animated: true)
```

---

## Testing

### 1. Simulator Testing (Custom Scheme Only)

```bash
# Open user profile
xcrun simctl openurl booted "novasocial://user/123"

# Open post
xcrun simctl openurl booted "novasocial://post/456"

# Search
xcrun simctl openurl booted "novasocial://search?q=swift"

# Notifications
xcrun simctl openurl booted "novasocial://notifications"

# Settings
xcrun simctl openurl booted "novasocial://settings/privacy"

# Email verification
xcrun simctl openurl booted "novasocial://auth/verify?token=abc123"
```

---

### 2. Device Testing (Universal Links)

#### Method 1: Notes App

1. Open Notes app
2. Create new note
3. Type test URLs:
   ```
   https://nova.social/user/123
   https://nova.social/post/456
   https://nova.social/search?q=swift
   ```
4. Tap links → Should open in NovaSocial app

---

#### Method 2: Messages

1. Send yourself a message with test link
2. Tap link
3. Verify app opens

---

#### Method 3: Safari

1. Navigate to `https://nova.social/user/123`
2. Should see banner: "Open in NovaSocial"
3. Tap banner

**Note**: Safari requires long-press → "Open in NovaSocial"

---

### 3. Automated Tests

#### Unit Tests

```swift
import XCTest
@testable import NovaSocial

class DeepLinkRouterTests: XCTestCase {

    var router: DeepLinkRouter!

    override func setUp() {
        router = DeepLinkRouter()
    }

    func testParseUserProfileURL() {
        let url = URL(string: "novasocial://user/123")!
        let route = router.parse(url: url)

        XCTAssertEqual(route, .userProfile(userId: "123"))
    }

    func testParsePostURL() {
        let url = URL(string: "https://nova.social/post/456")!
        let route = router.parse(url: url)

        XCTAssertEqual(route, .post(postId: "456"))
    }

    func testGenerateURL() {
        let route = DeepLinkRoute.userProfile(userId: "123")
        let url = router.generateURL(for: route)

        XCTAssertEqual(url?.absoluteString, "https://nova.social/user/123")
    }

    func testInvalidURL() {
        let url = URL(string: "https://example.com/unknown")!
        let route = router.parse(url: url)

        if case .unknown = route {
            XCTAssert(true)
        } else {
            XCTFail("Should be unknown route")
        }
    }
}
```

---

#### UI Tests

```swift
import XCTest

class DeepLinkUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUp() {
        app = XCUIApplication()
        app.launch()
    }

    func testDeepLinkToUserProfile() {
        // Simulate deep link
        let url = "novasocial://user/123"
        app.open(URL(string: url)!)

        // Verify navigation
        XCTAssertTrue(app.navigationBars["@johndoe"].exists)
    }

    func testDeepLinkToPost() {
        let url = "novasocial://post/456"
        app.open(URL(string: url)!)

        XCTAssertTrue(app.staticTexts["Post 456"].exists)
    }
}

extension XCUIApplication {
    func open(_ url: URL) {
        // Launch with URL
        launchArguments += ["-deep-link-url", url.absoluteString]
        launch()
    }
}
```

---

### 4. Test Checklist

#### Custom URL Scheme

- [ ] User profile: `novasocial://user/123`
- [ ] Post detail: `novasocial://post/456`
- [ ] Search: `novasocial://search?q=test`
- [ ] Notifications: `novasocial://notifications`
- [ ] Feed: `novasocial://feed`
- [ ] Settings: `novasocial://settings`
- [ ] Camera: `novasocial://camera`
- [ ] Email verification: `novasocial://auth/verify?token=abc`

#### Universal Links

- [ ] User profile: `https://nova.social/user/123`
- [ ] Short user link: `https://nova.social/u/123`
- [ ] Username link: `https://nova.social/@johndoe`
- [ ] Post detail: `https://nova.social/post/456`
- [ ] Short post link: `https://nova.social/p/456`
- [ ] Search: `https://nova.social/search?q=test`
- [ ] Hashtag: `https://nova.social/hashtag/ios`
- [ ] Notifications: `https://nova.social/notifications`
- [ ] Settings: `https://nova.social/settings/privacy`

#### Edge Cases

- [ ] Invalid user ID
- [ ] Non-existent post
- [ ] Unauthenticated access to protected route
- [ ] Malformed URLs
- [ ] Missing required parameters
- [ ] Special characters in query
- [ ] Very long URLs (> 2000 chars)

---

## Analytics

### Tracked Events

```swift
// Deep link opened
analytics.track("deep_link_opened", properties: [
    "url": url.absoluteString,
    "scheme": url.scheme,
    "host": url.host,
    "path": url.path,
    "source": source, // "universal_link" or "custom_scheme"
    "route": route.name
])

// Deep link conversion
analytics.track("deep_link_converted", properties: [
    "route": route.name,
    "action": action, // "view_profile", "like_post", etc.
    "time_to_action": timeInterval
])

// Deep link error
analytics.track("deep_link_error", properties: [
    "url": url.absoluteString,
    "error": error.localizedDescription
])
```

---

### Key Metrics

1. **Deep Link Open Rate**
   - Total deep links opened
   - By source (Messages, Mail, Safari, etc.)
   - By type (Universal vs Custom)

2. **Conversion Rate**
   - % of deep links that led to action
   - Average time from open to action
   - Drop-off points

3. **Error Rate**
   - Invalid URLs
   - Missing parameters
   - Authentication failures

4. **Popular Routes**
   - Most opened routes
   - Least used routes
   - Routes by user segment

---

## Troubleshooting

### Universal Links Not Working

**Symptom**: Links open in Safari instead of app

**Solutions**:

1. **Verify Server Configuration**
   ```bash
   curl https://nova.social/apple-app-site-association
   # Should return JSON with 200 status
   ```

2. **Check Team ID**
   - Ensure Team ID in `apple-app-site-association` matches Xcode

3. **Clear Cache**
   - Reinstall app
   - Restart device
   - Wait 24 hours for Apple CDN

4. **Test in Private Browsing**
   - Safari may have learned preference
   - Long-press link → "Open in NovaSocial"

---

### Custom Scheme Not Working

**Symptom**: "Cannot open page" error

**Solutions**:

1. **Verify Info.plist**
   ```xml
   <key>CFBundleURLTypes</key>
   <array>
       <dict>
           <key>CFBundleURLSchemes</key>
           <array>
               <string>novasocial</string>
           </array>
       </dict>
   </array>
   ```

2. **Check App.swift Integration**
   ```swift
   .onOpenURL { url in
       deepLinkRouter.handle(url: url)
   }
   ```

3. **Test with Correct Scheme**
   - Must be lowercase: `novasocial://` not `NovaSocial://`

---

### Navigation Not Working

**Symptom**: App opens but doesn't navigate

**Solutions**:

1. **Check Route Parsing**
   ```swift
   let route = router.parse(url: url)
   print("Parsed route: \(route)")
   ```

2. **Verify Authentication**
   - Protected routes require login
   - Check `isAuthenticated` state

3. **Debug Navigation State**
   ```swift
   print("Selected tab: \(navigationState.selectedTab)")
   print("Presented sheet: \(navigationState.presentedSheet)")
   ```

---

### Parameter Extraction Failing

**Symptom**: Parameters are nil or incorrect

**Solutions**:

1. **URL Encoding**
   ```swift
   // Correct
   let query = "swift ui".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
   let url = URL(string: "novasocial://search?q=\(query ?? "")")

   // Incorrect
   let url = URL(string: "novasocial://search?q=swift ui") // Spaces not encoded
   ```

2. **Query Item Parsing**
   ```swift
   let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
   let query = components?.queryItems?.first(where: { $0.name == "q" })?.value
   ```

---

## Best Practices

### 1. URL Design

✅ **Do**:
- Use human-readable paths: `/user/johndoe`
- Keep URLs short and clean
- Use consistent naming
- Encode special characters

❌ **Don't**:
- Expose sensitive data in URLs
- Use excessively long paths
- Include temporary tokens in shareable links

---

### 2. Error Handling

```swift
func navigate(to route: DeepLinkRoute) {
    switch route {
    case .userProfile(let userId):
        // Validate user ID
        guard isValidUserId(userId) else {
            showError("Invalid user ID")
            return
        }

        // Check authentication if needed
        guard !requiresAuth || isAuthenticated else {
            showLoginPrompt()
            return
        }

        // Navigate
        navigationState.presentedSheet = .userProfile(userId: userId)

    case .invalid(let error):
        showError(error)
    }
}
```

---

### 3. Accessibility

```swift
// Announce navigation
private func announceRouteChange(route: DeepLinkRoute) {
    let announcement = routeAnnouncement(for: route)
    AccessibilityHelper.announceScreenChange()
    AccessibilityHelper.announce(announcement)
}

// Example announcement
"Opening profile for user johndoe"
"Navigating to notifications"
```

---

### 4. Security

```swift
// Validate all parameters
guard userId.rangeOfCharacter(from: .alphanumerics.inverted) == nil else {
    return .invalid(error: "Invalid user ID format")
}

// Rate limit deep link handling
private func canHandleDeepLink() -> Bool {
    guard let lastTime = lastDeepLinkTime else {
        lastDeepLinkTime = Date()
        return true
    }

    let elapsed = Date().timeIntervalSince(lastTime)
    guard elapsed >= minimumInterval else {
        return false
    }

    lastDeepLinkTime = Date()
    return true
}
```

---

### 5. Testing

- ✅ Test all routes on real device
- ✅ Test with and without authentication
- ✅ Test invalid parameters
- ✅ Test long URLs
- ✅ Test special characters
- ✅ Test from different sources (Safari, Messages, Mail)
- ✅ Test universal links after 24-hour cache period

---

## Resources

- [Deep Linking Implementation](/Users/proerror/Documents/nova/ios/NovaSocial/DeepLinking/)
- [Universal Links Setup](/Users/proerror/Documents/nova/ios/NovaSocial/Config/UniversalLinksSetup.md)
- [Accessibility Guide](/Users/proerror/Documents/nova/ios/NovaSocial/Accessibility/AccessibilityChecklist.md)
- [Apple Documentation](https://developer.apple.com/documentation/xcode/supporting-universal-links-in-your-app)
