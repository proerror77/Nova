# iOS Authentication Status

**Date**: 2025-11-19
**Status**: ⚠️ Blocked - Backend Configuration Issue

---

## 🔍 Problem Summary

Feed API 一直返回 401 "Missing user context"，即使提供了有效的 JWT token。

### Root Cause

後端 feed-service 已定義 JWT 認證中間件 (`src/middleware/jwt_auth.rs`)，但**未應用到 HTTP 路由上**。

**代碼證據**:

```rust
// backend/feed-service/src/main.rs (line 307-309)
.service(
    web::scope("/api/v2/feed")
        .service(get_feed)  // ❌ Missing: .wrap(JwtAuthMiddleware)
)
```

```rust
// backend/feed-service/src/handlers/feed.rs (line 64-68)
let user_id = http_req
    .extensions()
    .get::<UserId>()  // ❌ UserId never inserted because middleware not applied
    .ok_or_else(|| AppError::Authentication("Missing user context".into()))?;
```

---

## 🧪 Testing Results

### Test JWT Token Generated

使用後端測試密鑰生成了有效的 JWT token:

```bash
# Generate test token
python3 backend/scripts/generate_test_token.py

# Token details:
User ID: 00000000-0000-0000-0000-000000000001
Email: test@nova.com
Username: test_user
Expires: 1 hour from generation
```

### API Test Results

```bash
# Without token
GET /api/v2/feed?user_id=test123&limit=20
→ 401 Unauthorized {"error":"Missing user context"}

# With valid JWT token
GET /api/v2/feed?user_id=test&limit=20
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
→ 401 Unauthorized {"error":"Missing user context"}
```

**結論**: Token 本身是有效的，但中間件未執行，因此 `UserId` 從未被插入到 request extensions 中。

---

## ✅ iOS Implementation (Completed)

### 1. Mock Authentication Support

**File**: `ios/NovaSocial/Shared/Services/Networking/APIClient.swift`

```swift
/// Enable mock authentication for development/testing
/// WARNING: This is a temporary solution for testing only
/// TODO: Replace with real authentication flow once backend is fixed
func enableMockAuth() {
    #if DEBUG
    self.authToken = "mock-dev-token-for-testing"
    print("⚠️ Mock authentication enabled - for testing only!")
    #endif
}
```

### 2. App Initialization

**File**: `ios/NovaSocial/App.swift`

```swift
init() {
    // Enable mock authentication for testing
    // TODO: Remove this once real authentication is implemented
    APIClient.shared.enableMockAuth()
}
```

### 3. Token Generation Script

**File**: `backend/scripts/generate_test_token.py`

```python
# Generates valid JWT tokens using backend test RSA keys
# Usage: python3 generate_test_token.py
```

---

## 🔧 Backend Fix Required

### Option 1: Apply JWT Middleware to Routes

**File**: `backend/feed-service/src/main.rs`

```rust
// Add this import
use crate::middleware::jwt_auth::JwtAuthMiddleware;

// Update HTTP server configuration
.service(
    web::scope("/api/v2/feed")
        .wrap(JwtAuthMiddleware)  // ✅ Add middleware
        .service(get_feed)
)
```

### Option 2: Apply Middleware Globally

```rust
App::new()
    .wrap(JwtAuthMiddleware)  // ✅ Apply to all routes
    .app_data(db_pool.clone())
    // ... rest of configuration
```

### Option 3: Initialize JWT Keys

Ensure JWT keys are initialized on startup:

```rust
// In main() function before starting HTTP server
let private_key = std::env::var("JWT_PRIVATE_KEY_PEM")
    .expect("JWT_PRIVATE_KEY_PEM must be set");
let public_key = std::env::var("JWT_PUBLIC_KEY_PEM")
    .expect("JWT_PUBLIC_KEY_PEM must be set");

crate::security::jwt::initialize_keys(&private_key, &public_key)
    .expect("Failed to initialize JWT keys");
```

**Note**: Check if keys are stored in Kubernetes secrets or environment variables.

---

## 📋 Next Steps

### Backend Team

- [ ] **Priority 1**: Apply JWT middleware to feed-service routes
  - File: `backend/feed-service/src/main.rs`
  - Add `.wrap(JwtAuthMiddleware)` to `/api/v2/feed` scope

- [ ] **Priority 2**: Verify JWT keys configuration
  - Check environment variables: `JWT_PRIVATE_KEY_PEM`, `JWT_PUBLIC_KEY_PEM`
  - Ensure keys match between identity-service and feed-service

- [ ] **Priority 3**: Test authentication flow
  ```bash
  # Get token from identity-service
  curl -X POST http://api.nova.local/api/v2/auth/login \
    -H "Content-Type: application/json" \
    -d '{"email":"test@nova.com","password":"password"}'

  # Use token to access feed
  curl -X GET "http://api.nova.local/api/v2/feed?user_id=xxx&limit=20" \
    -H "Authorization: Bearer <token>"
  ```

### iOS Team (After Backend Fix)

- [ ] **Test with real authentication**
  - Implement login flow to get real JWT token
  - Remove mock authentication from App.swift
  - Test feed loading with authenticated requests

- [ ] **Implement full auth flow**
  ```swift
  // 1. Login
  func login(email: String, password: String) async throws -> User {
      let response: LoginResponse = try await client.request(
          endpoint: "/api/v2/auth/login",
          method: "POST",
          body: ["email": email, "password": password]
      )
      APIClient.shared.setAuthToken(response.accessToken)
      return response.user
  }

  // 2. Refresh token
  func refreshToken() async throws {
      let response: TokenResponse = try await client.request(
          endpoint: "/api/v2/auth/refresh",
          method: "POST",
          body: ["refreshToken": storedRefreshToken]
      )
      APIClient.shared.setAuthToken(response.accessToken)
  }
  ```

- [ ] **Handle token expiration**
  - Catch 401 errors
  - Auto-refresh access token
  - Redirect to login if refresh fails

---

## 🧪 Testing After Fix

### Step 1: Verify Middleware Applied

```bash
# Should return 401 with different error message (invalid token, not missing context)
curl -X GET "http://api.nova.local/api/v2/feed?user_id=test&limit=20" \
  -H "Authorization: Bearer invalid-token"

# Expected: {"error":"Invalid or expired token","code":401}
# Not: {"error":"Missing user context","code":401}
```

### Step 2: Test with Valid Token

```bash
# Generate token
python3 backend/scripts/generate_test_token.py

# Test API
curl -X GET "http://api.nova.local/api/v2/feed?user_id=00000000-0000-0000-0000-000000000001&limit=20" \
  -H "Authorization: Bearer <generated-token>"

# Expected: {"posts":[],"cursor":"...","has_more":false,"total_count":0}
# (Empty because test user has no following, but 200 OK response)
```

### Step 3: iOS App Testing

```swift
// In Xcode, run the app
// HomeView should load and call getUserFeed()
// Should succeed and display empty state or actual posts
```

---

## 📊 Authentication Architecture

```
┌─────────────┐
│  iOS App    │
└──────┬──────┘
       │ 1. Login Request
       │ POST /api/v2/auth/login
       │ {email, password}
       ▼
┌─────────────────┐
│ identity-service│──→ Generate JWT Token (RS256)
└────────┬────────┘    {sub: user_id, email, username, exp: ...}
         │
         │ 2. Return Token
         │ {access_token, refresh_token}
         ▼
┌─────────────┐
│  iOS App    │──→ Store token in APIClient
└──────┬──────┘
       │ 3. API Request
       │ GET /api/v2/feed?user_id=xxx
       │ Authorization: Bearer <token>
       ▼
┌─────────────────┐
│  Ingress        │──→ Route to feed-service
└────────┬────────┘
         ▼
┌─────────────────┐
│  feed-service   │
│                 │
│  JwtAuthMiddleware ──→ 4. Validate Token
│      ├── Extract Bearer token
│      ├── Verify RS256 signature
│      ├── Check expiration
│      └── Insert UserId into request extensions
│                 │
│  get_feed()    ──→ 5. Get UserId from extensions
│                 │   Generate feed
│                 │
└────────┬────────┘
         │ 6. Return Feed
         │ {posts: [...], cursor, has_more}
         ▼
┌─────────────┐
│  iOS App    │──→ Display in HomeView
└─────────────┘
```

---

## 🚨 Current Blocker

**Status**: ⛔ **BLOCKED**

**Blocker**: Backend feed-service JWT middleware not applied to routes

**Impact**:
- Cannot test feed loading in iOS app
- All authenticated endpoints return 401
- Authentication flow cannot be validated end-to-end

**Owner**: Backend team

**ETA**: Waiting for backend fix

---

## 📝 Files Modified (iOS)

1. ✅ `ios/NovaSocial/Shared/Services/Networking/APIClient.swift`
   - Added `enableMockAuth()` method for testing

2. ✅ `ios/NovaSocial/App.swift`
   - Call `enableMockAuth()` on app init

3. ✅ `backend/scripts/generate_test_token.py`
   - Token generation script for testing

4. ✅ `backend/scripts/generate_test_token.rs`
   - Rust version (requires cargo)

5. ✅ `ios/AUTHENTICATION_STATUS.md`
   - This documentation file

---

## 🔗 Related Documentation

- `IOS_FEED_API_CHANGES.md` - Feed API migration details
- `AWS_CONNECTION_FINAL_TEST_REPORT.md` - Backend connectivity tests
- `V2_API_MIGRATION_SUMMARY.md` - Complete v2 migration summary

---

**Last Updated**: 2025-11-19
**Maintained By**: Nova iOS Team
**Status**: ⚠️ Awaiting Backend Fix
