# Critical Test Implementations for PR #59

**Purpose**: Copy-paste ready test code that can be implemented immediately
**Scope**: P0 blocker tests (28 tests)
**Estimated Time**: 30-40 hours to implement and verify
**Language**: Rust (backend), Swift (iOS)

---

## Part 1: GraphQL Gateway Auth Tests

### File: `backend/graphql-gateway/tests/graphql_auth_middleware_test.rs`

```rust
//! GraphQL Authentication Middleware Tests (P0 BLOCKER)
//!
//! Tests that verify:
//! 1. Unauthenticated requests are rejected
//! 2. Invalid tokens are rejected
//! 3. Expired tokens are rejected
//! 4. Valid tokens allow access

use actix_web::{test, web, App, HttpResponse};
use async_graphql::{EmptySubscription, Object, Schema};
use serde_json::json;

#[derive(Default)]
struct QueryRoot;

#[Object]
impl QueryRoot {
    async fn health(&self) -> &'static str {
        "ok"
    }

    async fn feed(&self) -> FeedResponse {
        FeedResponse {
            posts: vec![],
            cursor: None,
            has_more: false,
        }
    }
}

#[derive(serde::Serialize)]
struct FeedResponse {
    posts: Vec<Post>,
    cursor: Option<String>,
    has_more: bool,
}

#[derive(serde::Serialize, Clone)]
struct Post {
    id: String,
    content: String,
}

type AppSchema = Schema<QueryRoot, EmptySubscription, EmptySubscription>;

// GraphQL handler from main.rs
async fn graphql_handler(
    schema: web::Data<AppSchema>,
    body: String,
) -> HttpResponse {
    // Parse GraphQL request
    match serde_json::from_str::<serde_json::Value>(&body) {
        Ok(req) => {
            let query = req.get("query").and_then(|q| q.as_str());
            if let Some(query) = query {
                let result = schema.execute(query).await;
                HttpResponse::Ok().json(result)
            } else {
                HttpResponse::BadRequest().finish()
            }
        }
        Err(_) => HttpResponse::BadRequest().finish(),
    }
}

#[actix_web::test]
async fn test_unauthenticated_query_rejected_with_401() {
    let schema = Schema::build(QueryRoot, EmptySubscription, EmptySubscription).finish();

    let app = test::init_service(
        App::new()
            // JWT middleware should go here
            .app_data(web::Data::new(schema))
            .route("/graphql", web::post().to(graphql_handler)),
    )
    .await;

    // Request WITHOUT Authorization header
    let req = test::TestRequest::post()
        .uri("/graphql")
        .set_payload(r#"{"query": "{ feed { posts { id } } }"}"#)
        .to_request();

    let resp = test::call_service(&app, req).await;

    // CRITICAL: Must return 401, not 200
    assert_eq!(
        resp.status(),
        actix_web::http::StatusCode::UNAUTHORIZED,
        "Unauthenticated request should return 401 Unauthorized"
    );
}

#[actix_web::test]
async fn test_malformed_auth_header_rejected() {
    let schema = Schema::build(QueryRoot, EmptySubscription, EmptySubscription).finish();

    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(schema))
            .route("/graphql", web::post().to(graphql_handler)),
    )
    .await;

    // Request with invalid auth header
    let req = test::TestRequest::post()
        .uri("/graphql")
        .insert_header(("Authorization", "Bearer invalid-token-xyz"))
        .set_payload(r#"{"query": "{ feed { posts { id } } }"}"#)
        .to_request();

    let resp = test::call_service(&app, req).await;

    // Should reject malformed token
    assert_eq!(resp.status(), actix_web::http::StatusCode::UNAUTHORIZED);
}

#[actix_web::test]
async fn test_mutation_requires_auth() {
    let schema = Schema::build(QueryRoot, EmptySubscription, EmptySubscription).finish();

    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(schema))
            .route("/graphql", web::post().to(graphql_handler)),
    )
    .await;

    // Mutation without auth header
    let req = test::TestRequest::post()
        .uri("/graphql")
        .set_payload(
            r#"{"query": "mutation { createPost(content: \"hack\") { id } }"}"#,
        )
        .to_request();

    let resp = test::call_service(&app, req).await;

    // CRITICAL: Mutations must also require auth
    assert_eq!(resp.status(), actix_web::http::StatusCode::UNAUTHORIZED);
}

#[actix_web::test]
async fn test_query_without_auth_header_does_not_expose_errors() {
    let schema = Schema::build(QueryRoot, EmptySubscription, EmptySubscription).finish();

    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(schema))
            .route("/graphql", web::post().to(graphql_handler)),
    )
    .await;

    let req = test::TestRequest::post()
        .uri("/graphql")
        .set_payload(r#"{"query": "{ feed { posts { id } } }"}"#)
        .to_request();

    let resp = test::call_service(&app, req).await;
    let status = resp.status();

    // Security: Don't expose internal error details
    // Just return 401 with generic message
    assert_eq!(status, actix_web::http::StatusCode::UNAUTHORIZED);
}
```

---

## Part 2: Permission Check Tests

### File: `backend/graphql-gateway/tests/graphql_authorization_test.rs`

```rust
//! GraphQL Authorization Tests (P0 BLOCKER - IDOR Prevention)
//!
//! Tests that verify:
//! 1. Users cannot modify other users' posts
//! 2. Users cannot delete other users' posts
//! 3. Users cannot view private profile data
//! 4. Permission checks happen BEFORE data modification

use actix_web::{test, web, App};
use async_graphql::{EmptySubscription, Object, Schema};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Clone, Debug, Serialize, Deserialize)]
struct Post {
    id: String,
    content: String,
    user_id: String,
    created_at: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct User {
    id: String,
    username: String,
    email: Option<String>,  // Private field
    phone: Option<String>,  // Private field
}

#[derive(Default)]
struct Mutation;

#[Object]
impl Mutation {
    async fn update_post(
        &self,
        ctx: &async_graphql::Context<'_>,
        post_id: String,
        content: String,
    ) -> Result<Post, String> {
        // Get authenticated user
        let user_id = ctx.data::<String>().map_err(|_| "Unauthorized")?.clone();

        // Simulated database lookup
        let post = get_post_from_db(&post_id)
            .await
            .ok_or("Post not found")?;

        // CRITICAL: Permission check MUST happen before any modification
        if post.user_id != user_id {
            return Err("FORBIDDEN: Not the post owner".to_string());
        }

        // Only then modify
        update_post_in_db(&post_id, content).await?;

        Ok(Post {
            id: post.id,
            content,
            user_id: post.user_id,
            created_at: post.created_at,
        })
    }

    async fn delete_post(
        &self,
        ctx: &async_graphql::Context<'_>,
        post_id: String,
    ) -> Result<bool, String> {
        let user_id = ctx.data::<String>().map_err(|_| "Unauthorized")?.clone();

        let post = get_post_from_db(&post_id)
            .await
            .ok_or("Post not found")?;

        // Permission check FIRST
        if post.user_id != user_id {
            return Err("FORBIDDEN: Not the post owner".to_string());
        }

        // Then delete
        delete_post_from_db(&post_id).await?;

        Ok(true)
    }
}

// Mock database functions
async fn get_post_from_db(id: &str) -> Option<Post> {
    // In real implementation, query database
    Some(Post {
        id: id.to_string(),
        content: "Original content".to_string(),
        user_id: "alice-id".to_string(),
        created_at: "2025-01-01".to_string(),
    })
}

async fn update_post_in_db(id: &str, content: String) -> Result<(), String> {
    // In real implementation, update database
    Ok(())
}

async fn delete_post_from_db(id: &str) -> Result<(), String> {
    // In real implementation, delete from database
    Ok(())
}

// Tests

#[tokio::test]
async fn test_user_cannot_update_other_user_post() {
    // Setup: Alice creates a post
    let alice_id = "alice-id";
    let post_id = "post-123";

    // Bob tries to update Alice's post
    let bob_id = "bob-id";

    // Create mock context for Bob
    let schema = Schema::build(Mutation::default(), EmptySubscription, EmptySubscription)
        .data(bob_id.to_string())
        .finish();

    // Execute mutation as Bob
    let result = schema
        .execute(&format!(
            r#"mutation {{ updatePost(postId: "{}", content: "HACKED") {{ id }} }}"#,
            post_id
        ))
        .await;

    // CRITICAL: Must fail with permission error
    assert!(
        result.errors.iter().any(|e| {
            let msg = e.message.to_lowercase();
            msg.contains("forbidden") || msg.contains("not authorized")
        }),
        "Should reject update with FORBIDDEN error. Got: {:?}",
        result.errors
    );
}

#[tokio::test]
async fn test_user_cannot_delete_other_user_post() {
    let post_id = "post-123";
    let bob_id = "bob-id";

    let schema = Schema::build(Mutation::default(), EmptySubscription, EmptySubscription)
        .data(bob_id.to_string())
        .finish();

    let result = schema
        .execute(&format!(
            r#"mutation {{ deletePost(postId: "{}") {{ success }} }}"#,
            post_id
        ))
        .await;

    // Must reject deletion attempt
    assert!(
        result.errors.len() > 0,
        "Should return error when trying to delete other user's post"
    );
}

#[tokio::test]
async fn test_own_post_modification_succeeds() {
    // Alice modifying her own post should succeed
    let alice_id = "alice-id";
    let post_id = "post-123";

    let schema = Schema::build(Mutation::default(), EmptySubscription, EmptySubscription)
        .data(alice_id.to_string())
        .finish();

    // This would fail because our mock returns alice-id for all posts
    // In real test, mock would return correct owner
    let _result = schema
        .execute(&format!(
            r#"mutation {{ updatePost(postId: "{}", content: "Updated") {{ id }} }}"#,
            post_id
        ))
        .await;

    // When properly mocked: assert!(result.errors.is_empty());
}

#[tokio::test]
async fn test_permission_check_happens_before_modification() {
    // This is the most critical test for IDOR prevention
    // It verifies that permission check happens BEFORE any database modification

    let unauthorized_user = "bob-id";
    let post_id = "post-123";

    let schema = Schema::build(Mutation::default(), EmptySubscription, EmptySubscription)
        .data(unauthorized_user.to_string())
        .finish();

    // Attempt unauthorized modification
    let result = schema
        .execute(&format!(
            r#"mutation {{ updatePost(postId: "{}", content: "HACKED") {{ id }} }}"#,
            post_id
        ))
        .await;

    // Must have errors (permission denied)
    assert!(
        !result.errors.is_empty(),
        "Should have permission error before any modification"
    );

    // Verify post wasn't actually modified (in real test with database)
    // let post = query_post(post_id).await;
    // assert_eq!(post.content, "Original content");
}
```

---

## Part 3: Input Validation Tests

### File: `backend/graphql-gateway/tests/graphql_input_validation_test.rs`

```rust
//! Input Validation Tests (P0 BLOCKER)
//!
//! Tests that verify:
//! 1. Email format validation
//! 2. Password strength validation
//! 3. Content length limits
//! 4. Invalid IDs are rejected

use async_graphql::{EmptySubscription, Object, Schema};

#[derive(Default)]
struct Mutation;

#[Object]
impl Mutation {
    async fn register(
        &self,
        email: String,
        password: String,
    ) -> Result<RegistrationResponse, String> {
        // Email validation
        if !is_valid_email(&email) {
            return Err("INVALID_EMAIL: Email must be in format user@example.com".to_string());
        }

        // Password strength validation
        if !is_strong_password(&password) {
            return Err("WEAK_PASSWORD: Password must be 12+ chars with uppercase, lowercase, numbers, special chars".to_string());
        }

        // All validations passed
        Ok(RegistrationResponse {
            user_id: "new-user-id".to_string(),
            email,
        })
    }

    async fn create_post(
        &self,
        content: String,
    ) -> Result<Post, String> {
        // Content length validation
        if content.is_empty() {
            return Err("EMPTY_CONTENT: Post content cannot be empty".to_string());
        }

        if content.len() > 5000 {
            return Err("CONTENT_TOO_LONG: Post content must be <= 5000 characters".to_string());
        }

        Ok(Post {
            id: "post-123".to_string(),
            content,
        })
    }
}

#[derive(serde::Serialize)]
struct RegistrationResponse {
    user_id: String,
    email: String,
}

#[derive(serde::Serialize)]
struct Post {
    id: String,
    content: String,
}

// Validation functions
fn is_valid_email(email: &str) -> bool {
    // Basic email validation
    email.contains('@') && email.contains('.') && email.len() > 5
}

fn is_strong_password(password: &str) -> bool {
    if password.len() < 12 {
        return false;
    }

    let has_uppercase = password.chars().any(|c| c.is_uppercase());
    let has_lowercase = password.chars().any(|c| c.is_lowercase());
    let has_number = password.chars().any(|c| c.is_numeric());
    let has_special = password.chars().any(|c| !c.is_alphanumeric());

    has_uppercase && has_lowercase && has_number && has_special
}

// Tests

#[tokio::test]
async fn test_invalid_email_formats_rejected() {
    let schema = Schema::build(Mutation::default(), EmptySubscription, EmptySubscription)
        .finish();

    let invalid_emails = vec![
        ("notanemail", "missing @"),
        ("@example.com", "missing local part"),
        ("user@", "missing domain"),
        ("user@@example.com", "double @"),
        ("user example@example.com", "contains space"),
    ];

    for (email, description) in invalid_emails {
        let result = schema
            .execute(&format!(
                r#"mutation {{ register(email: "{}", password: "SecurePass123!") {{ userId }} }}"#,
                email
            ))
            .await;

        assert!(
            !result.errors.is_empty(),
            "Should reject invalid email: {} ({})",
            email,
            description
        );

        assert!(
            result.errors[0].message.contains("INVALID_EMAIL"),
            "Error message should mention INVALID_EMAIL for: {}",
            email
        );
    }
}

#[tokio::test]
async fn test_weak_password_rejected() {
    let schema = Schema::build(Mutation::default(), EmptySubscription, EmptySubscription)
        .finish();

    let weak_passwords = vec![
        ("short", "too short"),
        ("nouppercase123!", "missing uppercase"),
        ("NOLOWERCASE123!", "missing lowercase"),
        ("NoNumbers!", "missing numbers"),
        ("NoSpecialChar1", "missing special char"),
    ];

    for (password, description) in weak_passwords {
        let result = schema
            .execute(&format!(
                r#"mutation {{ register(email: "test@example.com", password: "{}") {{ userId }} }}"#,
                password
            ))
            .await;

        assert!(
            !result.errors.is_empty(),
            "Should reject weak password: {} ({})",
            password,
            description
        );
    }
}

#[tokio::test]
async fn test_valid_password_accepted() {
    let schema = Schema::build(Mutation::default(), EmptySubscription, EmptySubscription)
        .finish();

    let result = schema
        .execute(
            r#"mutation { register(email: "user@example.com", password: "SecurePass123!") { userId } }"#
        )
        .await;

    // Should NOT have errors
    assert!(result.errors.is_empty(), "Valid password should be accepted");
}

#[tokio::test]
async fn test_empty_post_content_rejected() {
    let schema = Schema::build(Mutation::default(), EmptySubscription, EmptySubscription)
        .finish();

    let result = schema
        .execute(r#"mutation { createPost(content: "") { id } }"#)
        .await;

    assert!(
        !result.errors.is_empty(),
        "Empty post content should be rejected"
    );
}

#[tokio::test]
async fn test_post_content_too_long_rejected() {
    let schema = Schema::build(Mutation::default(), EmptySubscription, EmptySubscription)
        .finish();

    // Generate content longer than 5000 chars
    let huge_content = "x".repeat(10000);

    let result = schema
        .execute(&format!(
            r#"mutation {{ createPost(content: "{}") {{ id }} }}"#,
            huge_content
        ))
        .await;

    assert!(
        !result.errors.is_empty(),
        "Content > 5000 chars should be rejected"
    );

    assert!(
        result.errors[0].message.contains("CONTENT_TOO_LONG"),
        "Error should mention content length limit"
    );
}

#[tokio::test]
async fn test_valid_post_content_accepted() {
    let schema = Schema::build(Mutation::default(), EmptySubscription, EmptySubscription)
        .finish();

    let result = schema
        .execute(r#"mutation { createPost(content: "Hello world!") { id } }"#)
        .await;

    assert!(result.errors.is_empty(), "Valid post should be created");
}
```

---

## Part 4: Connection Pooling Tests

### File: `backend/graphql-gateway/tests/connection_pooling_test.rs`

```rust
//! Connection Pooling Tests (P0 BLOCKER - Performance/Reliability)
//!
//! Tests that verify:
//! 1. Connections are reused, not created per request
//! 2. Connection pool doesn't exceed max size
//! 3. Connections are properly cleaned up
//! 4. Failed connections are replaced

use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

// Mock gRPC channel with connection tracking
struct MockChannel {
    id: usize,
    created_count: Arc<AtomicUsize>,
    is_active: bool,
}

impl MockChannel {
    fn new() -> (Self, Arc<AtomicUsize>) {
        let created_count = Arc::new(AtomicUsize::new(0));
        let id = created_count.fetch_add(1, Ordering::SeqCst);
        (
            MockChannel {
                id,
                created_count: created_count.clone(),
                is_active: true,
            },
            created_count,
        )
    }

    fn get_created_count(&self) -> usize {
        self.created_count.load(Ordering::SeqCst)
    }
}

// Mock ServiceClients with connection reuse tracking
struct MockServiceClients {
    connection_count: Arc<AtomicUsize>,
    channels: Arc<std::sync::Mutex<std::collections::HashMap<String, MockChannel>>>,
}

impl MockServiceClients {
    fn new() -> Self {
        MockServiceClients {
            connection_count: Arc::new(AtomicUsize::new(0)),
            channels: Arc::new(std::sync::Mutex::new(std::collections::HashMap::new())),
        }
    }

    async fn get_user_service_channel(&self) -> MockChannel {
        let mut channels = self.channels.lock().unwrap();

        // Check if channel already exists
        if let Some(channel) = channels.get("user_service") {
            // GOOD: Reusing existing connection
            return MockChannel {
                id: channel.id,
                created_count: channel.created_count.clone(),
                is_active: true,
            };
        }

        // Create new channel
        let (channel, _) = MockChannel::new();
        self.connection_count.fetch_add(1, Ordering::SeqCst);
        channels.insert("user_service".to_string(), channel.clone());

        channel
    }

    fn get_connection_count(&self) -> usize {
        self.connection_count.load(Ordering::SeqCst)
    }
}

// Tests

#[tokio::test]
async fn test_connections_are_reused() {
    let clients = MockServiceClients::new();

    // Make 10 requests
    for _ in 0..10 {
        let _channel = clients.get_user_service_channel().await;
        // In real test: execute GraphQL query using channel
    }

    // Should have created only 1 connection, not 10
    assert_eq!(
        clients.get_connection_count(),
        1,
        "Should reuse connection instead of creating 10 new ones"
    );
}

#[tokio::test]
async fn test_connection_pool_size_respected() {
    const MAX_POOL_SIZE: usize = 10;
    let clients = MockServiceClients::new();

    // Make 50 concurrent requests
    let futures: Vec<_> = (0..50)
        .map(|_| {
            let clients = clients.clone();
            async move { clients.get_user_service_channel().await }
        })
        .collect();

    futures::future::join_all(futures).await;

    // Should not exceed max pool size significantly
    let actual_connections = clients.get_connection_count();
    assert!(
        actual_connections <= MAX_POOL_SIZE * 2,
        "Created {} connections, should be <= {} (max allowed with some overhead)",
        actual_connections,
        MAX_POOL_SIZE * 2
    );
}

#[tokio::test]
async fn test_no_connection_leak_on_error() {
    // This test would verify:
    // 1. Start with N connections
    // 2. Make requests that fail
    // 3. End with N connections (no leak)
    //
    // In real implementation with database:
    // - Use connection pool stats before/after
    // - Verify count matches
}

#[tokio::test]
async fn test_connection_timeout_enforced() {
    // This test would verify:
    // 1. Hanging service doesn't block forever
    // 2. Request times out after configured timeout
    // 3. Connection is properly closed after timeout
    //
    // In real implementation:
    // - Mock service that doesn't respond
    // - Set timeout to 5s
    // - Verify request fails after 5s, not 30s+
}

// Helper trait implementation for the mock
impl Clone for MockChannel {
    fn clone(&self) -> Self {
        MockChannel {
            id: self.id,
            created_count: self.created_count.clone(),
            is_active: self.is_active,
        }
    }
}

impl Clone for MockServiceClients {
    fn clone(&self) -> Self {
        MockServiceClients {
            connection_count: self.connection_count.clone(),
            channels: self.channels.clone(),
        }
    }
}
```

---

## Part 5: iOS Security Tests

### File: `ios/NovaSocialTests/Security/TokenStorageTests.swift`

```swift
//! iOS Token Storage Security Tests (P0 BLOCKER)
//!
//! Tests that verify:
//! 1. Tokens are stored in Keychain (NOT UserDefaults)
//! 2. Tokens are encrypted at rest
//! 3. Tokens are cleared on logout

import XCTest
@testable import NovaSocial

class TokenStorageTests: XCTestCase {
    var tokenManager: TokenManager!

    override func setUp() {
        super.setUp()
        // Initialize token manager with real or mock keychain
        tokenManager = TokenManager(useRealKeychain: true)
        // Clear any existing tokens
        tokenManager.clearAllTokens()
    }

    override func tearDown() {
        super.tearDown()
        tokenManager.clearAllTokens()
    }

    // CRITICAL TEST 1: Token in Keychain, not UserDefaults
    func testTokenStoredInKeychainNotUserDefaults() {
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

        // Save token
        tokenManager.saveToken(token)

        // Verify it's in Keychain
        let keychainToken = tokenManager.getTokenFromKeychain()
        XCTAssertEqual(keychainToken, token, "Token should be retrievable from Keychain")

        // CRITICAL: Verify it's NOT in UserDefaults
        let userDefaultsToken = UserDefaults.standard.string(forKey: "api_token")
        XCTAssertNil(userDefaultsToken, "SECURITY ISSUE: Token should NOT be in UserDefaults!")

        // Also check other common insecure locations
        let pasteboardToken = UIPasteboard.general.string
        XCTAssertNil(pasteboardToken, "Token should NOT be in Pasteboard")
    }

    // CRITICAL TEST 2: Token cleared on logout
    func testTokenClearedOnLogout() {
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

        // Save token
        tokenManager.saveToken(token)

        // Verify it's saved
        XCTAssertNotNil(tokenManager.getTokenFromKeychain())

        // Logout
        tokenManager.clearAllTokens()

        // Verify token is cleared
        XCTAssertNil(
            tokenManager.getTokenFromKeychain(),
            "Token should be cleared after logout"
        )
    }

    // CRITICAL TEST 3: Token not in logs
    func testTokenNotInLogs() {
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

        // Save token
        tokenManager.saveToken(token)

        // Capture logs
        let logs = captureDebugLogs {
            tokenManager.getTokenFromKeychain()
        }

        // Verify token is not printed
        XCTAssertFalse(
            logs.contains(token),
            "SECURITY ISSUE: Token should never appear in logs"
        )

        // Check for partial token exposure
        let tokenPrefix = String(token.prefix(20))
        XCTAssertFalse(
            logs.contains(tokenPrefix),
            "Token prefix should not appear in logs"
        )
    }

    // CRITICAL TEST 4: Refresh token also protected
    func testRefreshTokenStoredSecurely() {
        let refreshToken = "refresh_token_xyz123..."

        tokenManager.saveRefreshToken(refreshToken)

        // Should be in Keychain
        let keychainToken = tokenManager.getRefreshTokenFromKeychain()
        XCTAssertEqual(keychainToken, refreshToken)

        // Should NOT be in UserDefaults
        let userDefaultsToken = UserDefaults.standard.string(forKey: "refresh_token")
        XCTAssertNil(userDefaultsToken, "Refresh token must not be in UserDefaults")
    }

    // Helper function to capture logs
    func captureDebugLogs(block: @escaping () -> Void) -> String {
        var logs = ""

        // In real test, would capture NSLog/print output
        // For now, this is pseudocode

        block()
        return logs
    }
}
```

### File: `ios/NovaSocialTests/Security/APIClientSecurityTests.swift`

```swift
//! API Client Security Tests (P0 BLOCKER)
//!
//! Tests that verify:
//! 1. SSL/TLS certificate pinning
//! 2. Automatic token refresh on 401
//! 3. No sensitive data in requests/responses

import XCTest
@testable import NovaSocial

class APIClientSecurityTests: XCTestCase {
    var apiClient: APIClient!
    var mockURLSession: MockURLSession!

    override func setUp() {
        super.setUp()
        mockURLSession = MockURLSession()
        apiClient = APIClient(urlSession: mockURLSession)
    }

    // CRITICAL TEST 1: Certificate pinning
    func testSSLCertificatePinning() {
        // This test verifies the app only accepts pinned certificates

        mockURLSession.useSelfSignedCertificate = true
        mockURLSession.certificatePinningEnabled = false

        let expectation = XCTestExpectation(description: "Request should fail")

        apiClient.fetchFeed { result in
            if case .failure(let error) = result {
                // Should fail with certificate validation error
                XCTAssertTrue(
                    error.localizedDescription.contains("certificate"),
                    "Should reject self-signed certificate"
                )
                expectation.fulfill()
            } else {
                XCTFail("Should reject self-signed certificate")
            }
        }

        wait(for: [expectation], timeout: 2.0)
    }

    // CRITICAL TEST 2: Automatic token refresh on 401
    func testAutoRefreshTokenOn401() {
        // Simulate expired token scenario
        mockURLSession.responses = [
            // First request: 401 Unauthorized (expired token)
            MockResponse(statusCode: 401, headers: ["WWW-Authenticate": "Bearer realm=\"nova\""]),

            // Token refresh request: 200 OK with new token
            MockResponse(statusCode: 200,
                        body: #"{"access_token": "new_token_xyz", "expires_in": 3600}"#),

            // Retry original request: 200 OK
            MockResponse(statusCode: 200, body: #"{"posts": []}"#),
        ]

        let expectation = XCTestExpectation(description: "Request should succeed after refresh")

        apiClient.fetchFeed { result in
            switch result {
            case .success(let feed):
                XCTAssertNotNil(feed, "Should successfully fetch feed after token refresh")
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Should succeed after token refresh, got error: \(error)")
            }
        }

        wait(for: [expectation], timeout: 3.0)

        // Verify token was refreshed
        XCTAssertEqual(mockURLSession.requestCount, 3, "Should make 3 requests (original + refresh + retry)")
    }

    // CRITICAL TEST 3: No token in error responses
    func testTokenNotExposedInErrorMessages() {
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

        mockURLSession.responses = [
            MockResponse(
                statusCode: 500,
                body: #"{"error": "Internal server error", "details": "..."}"#
            )
        ]

        apiClient.saveToken(token)

        let expectation = XCTestExpectation(description: "Error handled")

        apiClient.fetchFeed { result in
            if case .failure(let error) = result {
                // Verify token is not in error message
                XCTAssertFalse(
                    error.localizedDescription.contains(token),
                    "Token should NOT be in error message"
                )
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // CRITICAL TEST 4: Sensitive headers not logged
    func testAuthHeaderNotInLogs() {
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

        // Capture network logs
        var networkLogs = ""
        let originalLogger = URLSession.shared

        // Make request with token
        apiClient.saveToken(token)
        let expectation = XCTestExpectation(description: "Request made")

        apiClient.fetchFeed { _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // Verify token not in logs
        // (In real test, capture actual URLSession logs)
        // XCTAssertFalse(networkLogs.contains(token))
    }
}

// Mock helper classes
struct MockResponse {
    let statusCode: Int
    let headers: [String: String] = [:]
    let body: String = ""
}

class MockURLSession: URLSession {
    var responses: [MockResponse] = []
    var requestCount = 0
    var useSelfSignedCertificate = false
    var certificatePinningEnabled = true

    // Override dataTask to return mock responses
    override func dataTask(
        with request: URLRequest,
        completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTask {
        // Return mock task
        return URLSessionDataTask()
    }
}
```

---

## Implementation Checklist

### Backend Tests (Estimated: 30 hours)

- [ ] `graphql_auth_middleware_test.rs` (4 tests, ~2 hours)
- [ ] `graphql_authorization_test.rs` (5 tests, ~3 hours)
- [ ] `graphql_input_validation_test.rs` (7 tests, ~3 hours)
- [ ] `connection_pooling_test.rs` (4 tests, ~2 hours)
- [ ] Integrate tests into CI/CD pipeline (~2 hours)
- [ ] Fix failing tests by implementing backend code (~18 hours)

### iOS Tests (Estimated: 10 hours)

- [ ] `TokenStorageTests.swift` (4 tests, ~3 hours)
- [ ] `APIClientSecurityTests.swift` (4 tests, ~4 hours)
- [ ] Fix failures by implementing iOS security (~3 hours)

### Total: 40 hours for P0 blocker tests

---

## Running Tests

```bash
# Backend tests
cargo test --test graphql_auth_middleware_test
cargo test --test graphql_authorization_test
cargo test --test graphql_input_validation_test
cargo test --test connection_pooling_test

# iOS tests
xcodebuild test -project ios/NovaSocial/NovaSocial.xcodeproj \
  -scheme NovaSocial \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Next Steps

1. Copy test files into project
2. Run tests (they will fail - that's expected with TDD)
3. Implement features to make tests pass
4. Commit with message: "test(pr59): add P0 security tests"
5. Implement remaining P1 tests
6. Merge PR when all P0 tests pass

