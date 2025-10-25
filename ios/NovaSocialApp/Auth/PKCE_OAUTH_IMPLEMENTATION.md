# iOS OAuth 2.0 with PKCE Implementation Guide

## Overview

This guide explains how to implement OAuth 2.0 with PKCE (Proof Key for Code Exchange) on iOS for secure authentication with Google, Apple, and Facebook.

## Architecture

The OAuth flow consists of three main components:

1. **OAuthStateManager** - Generates and manages state, nonce, and PKCE parameters
2. **AuthViewModel** - Orchestrates the OAuth flow and authentication
3. **Safari View Controller** - Handles the OAuth redirect in the browser

## PKCE Flow

### Step 1: Generate PKCE Parameters

```swift
let (codeVerifier, codeChallenge, method) = OAuthStateManager.shared.generatePKCE()
// Returns:
// - codeVerifier: 128-character random string
// - codeChallenge: SHA256(codeVerifier) encoded in BASE64URL format
// - method: "S256" (SHA256)
```

### Step 2: Generate State Token

```swift
let state = OAuthStateManager.shared.generateState()
// Returns: 32-character random token for CSRF protection
```

### Step 3: Build Authorization URL

Example for Google:

```swift
var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
components.queryItems = [
    URLQueryItem(name: "client_id", value: GOOGLE_CLIENT_ID),
    URLQueryItem(name: "redirect_uri", value: "nova://oauth/google/callback"),
    URLQueryItem(name: "response_type", value: "code"),
    URLQueryItem(name: "scope", value: "openid profile email"),
    URLQueryItem(name: "state", value: state),

    // PKCE parameters
    URLQueryItem(name: "code_challenge", value: codeChallenge),
    URLQueryItem(name: "code_challenge_method", value: method),

    // Additional security
    URLQueryItem(name: "nonce", value: OAuthStateManager.shared.generateNonce()),
    URLQueryItem(name: "prompt", value: "consent"),
]

let authURL = components.url!
```

### Step 4: Launch Authorization (Safari)

```swift
import SafariServices

let safariVC = SFSafariViewController(url: authURL)
present(safariVC, animated: true)
```

### Step 5: Handle Callback

When the user completes authentication, the provider redirects to your app's custom scheme:

```swift
// In SceneDelegate or AppDelegate
func scene(_ scene: UIScene,
           continue userActivity: NSUserActivity) {
    guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
          let url = userActivity.webpageURL else { return }

    handleOAuthCallback(url)
}

private func handleOAuthCallback(_ url: URL) {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
          let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
          let state = components.queryItems?.first(where: { $0.name == "state" })?.value else {
        // Handle error
        return
    }

    // Verify state token (CSRF protection)
    guard state == OAuthStateManager.shared.currentState() else {
        print("State mismatch: CSRF attack detected")
        return
    }

    // Retrieve stored code verifier for token exchange
    let codeVerifier = OAuthStateManager.shared.currentCodeVerifier()!

    // Exchange code for tokens (see Step 6)
    exchangeCodeForTokens(code: code, codeVerifier: codeVerifier)
}
```

### Step 6: Token Exchange

Exchange the authorization code for tokens using the stored code verifier:

```swift
private func exchangeCodeForTokens(code: String, codeVerifier: String) async {
    var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
    request.httpMethod = "POST"

    let body = [
        "grant_type": "authorization_code",
        "code": code,
        "client_id": GOOGLE_CLIENT_ID,
        "client_secret": GOOGLE_CLIENT_SECRET,
        "redirect_uri": "nova://oauth/google/callback",

        // PKCE code verifier
        "code_verifier": codeVerifier,
    ]

    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    do {
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(TokenResponse.self, from: data)

        // Save tokens securely
        try KeychainManager.save(
            token: response.accessToken,
            refreshToken: response.refreshToken,
            forKey: "google_tokens"
        )

        // Clear OAuth state (single-use tokens)
        OAuthStateManager.shared.clearState()
        OAuthStateManager.shared.clearPKCE()
        OAuthStateManager.shared.clearNonce()

        // Update app state
        DispatchQueue.main.async {
            self.appState.isAuthenticated = true
        }
    } catch {
        print("Token exchange failed: \(error)")
    }
}
```

## Provider-Specific Configuration

### Google

```swift
let googleAuthURL = buildOAuthURL(
    baseURL: "https://accounts.google.com/o/oauth2/v2/auth",
    clientId: GOOGLE_CLIENT_ID,
    redirectUri: "nova://oauth/google/callback",
    scope: "openid profile email"
)
```

### Apple

```swift
let appleAuthURL = buildOAuthURL(
    baseURL: "https://appleid.apple.com/auth/authorize",
    clientId: APPLE_CLIENT_ID,
    redirectUri: "nova://oauth/apple/callback",
    scope: "name email"
)
```

### Facebook

```swift
let facebookAuthURL = buildOAuthURL(
    baseURL: "https://www.facebook.com/v13.0/dialog/oauth",
    clientId: FACEBOOK_CLIENT_ID,
    redirectUri: "nova://oauth/facebook/callback",
    scope: "public_profile email"
)
```

## Security Considerations

### 1. PKCE Parameters Storage

- **Code Verifier**: Stored in UserDefaults (for session duration)
- **Code Challenge**: Sent in authorization request (read-only)
- **Code Challenge Method**: Always "S256" (SHA256)

### 2. State Token Validation

```swift
// MUST verify state before exchanging code
if state != OAuthStateManager.shared.currentState() {
    // Reject request - potential CSRF attack
    return
}
```

### 3. Token Storage

Use iOS Keychain for secure token storage:

```swift
import Security

class KeychainManager {
    static func save(token: String, refreshToken: String?, forKey key: String) throws {
        // Implement Keychain storage with encryption
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: token.data(using: .utf8)!,
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
}
```

### 4. Nonce Validation (for ID Tokens)

For OpenID Connect providers (Apple, Google):

```swift
// Validate nonce in ID token claims
func validateNonce(in idToken: String) -> Bool {
    let parts = idToken.split(separator: ".")
    guard parts.count == 3 else { return false }

    let decodedClaims = try? JSONDecoder().decode(
        IDTokenClaims.self,
        from: base64URLDecode(String(parts[1]))
    )

    return decodedClaims?.nonce == OAuthStateManager.shared.currentNonce()
}
```

## Implementation Checklist

- [ ] Add PKCE support to OAuthStateManager (DONE)
- [ ] Update AuthViewModel with OAuth flow methods
- [ ] Create OAuthCallbackHandler for deep links
- [ ] Implement Safari View Controller integration
- [ ] Add token exchange endpoint calls
- [ ] Implement secure token storage in Keychain
- [ ] Add error handling and validation
- [ ] Test with all three providers (Google, Apple, Facebook)
- [ ] Implement token refresh for long-lived sessions
- [ ] Add unit tests for PKCE generation

## Testing PKCE Implementation

```swift
// Test PKCE generation
func testPKCEGeneration() {
    let (verifier, challenge, method) = OAuthStateManager.shared.generatePKCE()

    XCTAssertEqual(verifier.count, 128)
    XCTAssertEqual(method, "S256")
    XCTAssertTrue(verifier.allSatisfy { char in
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".contains(char)
    })

    // Verify challenge is valid BASE64URL
    XCTAssertFalse(challenge.contains("+"))
    XCTAssertFalse(challenge.contains("/"))
    XCTAssertFalse(challenge.contains("="))
}
```

## Environment Variables

Add these to your `AppConfig.swift`:

```swift
let GOOGLE_CLIENT_ID = "YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com"
let GOOGLE_CLIENT_SECRET = "YOUR_GOOGLE_CLIENT_SECRET"
let GOOGLE_REDIRECT_URI = "nova://oauth/google/callback"

let APPLE_CLIENT_ID = "YOUR_APPLE_CLIENT_ID"
let APPLE_TEAM_ID = "YOUR_APPLE_TEAM_ID"
let APPLE_REDIRECT_URI = "nova://oauth/apple/callback"

let FACEBOOK_CLIENT_ID = "YOUR_FACEBOOK_APP_ID"
let FACEBOOK_REDIRECT_URI = "nova://oauth/facebook/callback"
```

## References

- [RFC 7636: PKCE](https://tools.ietf.org/html/rfc7636)
- [OAuth 2.0 Authorization Code Flow](https://tools.ietf.org/html/rfc6749#section-1.3.1)
- [Apple Sign In Implementation Guide](https://developer.apple.com/documentation/sign_in_with_apple)
- [Google OAuth 2.0 on iOS](https://developers.google.com/identity/protocols/oauth2/native-app)
