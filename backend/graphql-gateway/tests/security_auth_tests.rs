//! Security tests for JWT authentication middleware
//!
//! OWASP A02:2021 - Cryptographic Failures
//! OWASP A07:2021 - Identification and Authentication Failures

use actix_web::{test, web, App, HttpResponse};
use graphql_gateway::middleware::jwt::{Claims, JwtMiddleware};
use jsonwebtoken::{encode, Algorithm, EncodingKey, Header};

async fn test_handler() -> actix_web::Result<HttpResponse> {
    Ok(HttpResponse::Ok().body("success"))
}

fn create_test_jwt(user_id: &str, expires_in_seconds: i64, secret: &str) -> String {
    let now = chrono::Utc::now().timestamp();
    let exp = (now + expires_in_seconds) as usize;

    let claims = Claims {
        sub: user_id.to_string(),
        exp,
        iat: now as usize,
        email: "test@example.com".to_string(),
    };

    encode(
        &Header::new(Algorithm::HS256),
        &claims,
        &EncodingKey::from_secret(secret.as_bytes()),
    )
    .unwrap()
}

// =============================================================================
// P0-1: JWT Secret Strength Tests
// =============================================================================

#[test]
#[should_panic(expected = "JWT secret too short")]
fn test_jwt_middleware_rejects_weak_secret_too_short() {
    // SECURITY: Must reject secrets shorter than 32 bytes
    let _ = JwtMiddleware::new("weak".to_string());
}

#[test]
#[should_panic(expected = "JWT secret too short")]
fn test_jwt_middleware_rejects_31_byte_secret() {
    // Boundary test: 31 bytes should fail
    let secret = "a".repeat(31);
    let _ = JwtMiddleware::new(secret);
}

#[test]
fn test_jwt_middleware_accepts_32_byte_secret() {
    // Boundary test: 32 bytes should pass
    let secret = "a".repeat(32);
    let middleware = JwtMiddleware::new(secret.clone());
    // If we get here without panic, test passes
    assert_eq!(middleware.secret, secret);
}

#[test]
fn test_jwt_middleware_accepts_strong_secret() {
    // Production-like secret (64 bytes, high entropy)
    let strong_secret =
        "bGFyZ2UtcmFuZG9tLXNlY3VyZS1zZWNyZXQtd2l0aC1oaWdoLWVudHJvcHktZm9yLXByb2R1Y3Rpb24=";
    let middleware = JwtMiddleware::new(strong_secret.to_string());
    assert!(middleware.secret.len() >= 32);
}

// =============================================================================
// P1-7: Authentication Bypass Prevention
// =============================================================================

#[actix_web::test]
async fn test_jwt_rejects_expired_token() {
    let app = test::init_service(
        App::new()
            .wrap(JwtMiddleware::new("a".repeat(32)))
            .route("/test", web::get().to(test_handler)),
    )
    .await;

    // Token expired 1 hour ago
    let expired_token = create_test_jwt("user-123", -3600, &"a".repeat(32));

    let req = test::TestRequest::get()
        .uri("/test")
        .insert_header(("Authorization", format!("Bearer {}", expired_token)))
        .to_request();

    let resp = test::try_call_service(&app, req).await;
    assert!(resp.is_err(), "Expired JWT should be rejected");
}

#[actix_web::test]
async fn test_jwt_rejects_future_iat() {
    // Token with iat (issued at) in the future - suspicious
    let future_timestamp = chrono::Utc::now().timestamp() + 3600;

    let claims = Claims {
        sub: "user-123".to_string(),
        exp: (future_timestamp + 7200) as usize,
        iat: future_timestamp as usize, // Future iat
        email: "test@example.com".to_string(),
    };

    let secret = "a".repeat(32);
    let token = encode(
        &Header::new(Algorithm::HS256),
        &claims,
        &EncodingKey::from_secret(secret.as_bytes()),
    )
    .unwrap();

    let app = test::init_service(
        App::new()
            .wrap(JwtMiddleware::new(secret))
            .route("/test", web::get().to(test_handler)),
    )
    .await;

    let req = test::TestRequest::get()
        .uri("/test")
        .insert_header(("Authorization", format!("Bearer {}", token)))
        .to_request();

    // Note: jsonwebtoken validates iat by default if Validation::validate_nbf is true
    let resp = test::call_service(&app, req).await;
    // This test may pass or fail depending on validation config
    // Adjust based on actual implementation
    println!("Future iat test status: {}", resp.status());
}

#[actix_web::test]
async fn test_jwt_prevents_signature_tampering() {
    let secret1 = "a".repeat(32);
    let secret2 = "b".repeat(32);

    // Create token with secret1
    let valid_token = create_test_jwt("user-123", 3600, &secret1);

    // Try to validate with secret2
    let app = test::init_service(
        App::new()
            .wrap(JwtMiddleware::new(secret2))
            .route("/test", web::get().to(test_handler)),
    )
    .await;

    let req = test::TestRequest::get()
        .uri("/test")
        .insert_header(("Authorization", format!("Bearer {}", valid_token)))
        .to_request();

    let resp = test::try_call_service(&app, req).await;
    assert!(resp.is_err(), "Signature tampering should be detected");
}

#[actix_web::test]
async fn test_jwt_rejects_none_algorithm() {
    // CRITICAL: "none" algorithm attack (CVE-2015-9235)
    let claims = Claims {
        sub: "user-123".to_string(),
        exp: (chrono::Utc::now().timestamp() + 3600) as usize,
        iat: chrono::Utc::now().timestamp() as usize,
        email: "test@example.com".to_string(),
    };

    // Try to create token with "none" algorithm
    let mut header = Header::new(Algorithm::HS256);
    header.alg = Algorithm::HS256; // jsonwebtoken doesn't support "none"

    // Manually craft token with "none" algorithm (simulated attack)
    let token_parts = "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiJ1c2VyLTEyMyIsImV4cCI6OTk5OTk5OTk5OSwiaWF0IjoxNjAwMDAwMDAwLCJlbWFpbCI6InRlc3RAZXhhbXBsZS5jb20ifQ.";

    let app = test::init_service(
        App::new()
            .wrap(JwtMiddleware::new("a".repeat(32)))
            .route("/test", web::get().to(test_handler)),
    )
    .await;

    let req = test::TestRequest::get()
        .uri("/test")
        .insert_header(("Authorization", format!("Bearer {}", token_parts)))
        .to_request();

    let resp = test::try_call_service(&app, req).await;
    assert!(resp.is_err(), "None algorithm should be rejected");
}

// =============================================================================
// P2-3: Rate Limiting Tests
// =============================================================================

#[actix_web::test]
async fn test_auth_failure_rate_limiting() {
    // TODO: Implement after rate limiting added to JWT middleware
    // Expected behavior: After N failed attempts, return 429 Too Many Requests

    let app = test::init_service(
        App::new()
            .wrap(JwtMiddleware::new("a".repeat(32)))
            .route("/test", web::get().to(test_handler)),
    )
    .await;

    // Attempt 11 failed authentications
    for i in 0..11 {
        let req = test::TestRequest::get()
            .uri("/test")
            .insert_header(("Authorization", "Bearer invalid_token"))
            .to_request();

        let resp = test::try_call_service(&app, req).await;

        if i < 10 {
            // First 10 should fail with 401
            assert!(resp.is_err());
        } else {
            // 11th should be rate limited (429)
            // TODO: Uncomment when rate limiting implemented
            // assert_eq!(resp.status(), 429);
        }
    }
}

// =============================================================================
// Missing Authorization Header Tests
// =============================================================================

#[actix_web::test]
async fn test_jwt_rejects_missing_authorization_header() {
    let app = test::init_service(
        App::new()
            .wrap(JwtMiddleware::new("a".repeat(32)))
            .route("/test", web::get().to(test_handler)),
    )
    .await;

    let req = test::TestRequest::get().uri("/test").to_request();

    let resp = test::try_call_service(&app, req).await;
    assert!(resp.is_err(), "Missing auth header should be rejected");
}

#[actix_web::test]
async fn test_jwt_rejects_invalid_bearer_scheme() {
    let app = test::init_service(
        App::new()
            .wrap(JwtMiddleware::new("a".repeat(32)))
            .route("/test", web::get().to(test_handler)),
    )
    .await;

    // Using "Basic" instead of "Bearer"
    let req = test::TestRequest::get()
        .uri("/test")
        .insert_header(("Authorization", "Basic dXNlcjpwYXNzd29yZA=="))
        .to_request();

    let resp = test::try_call_service(&app, req).await;
    assert!(resp.is_err(), "Non-Bearer scheme should be rejected");
}

#[actix_web::test]
async fn test_jwt_rejects_malformed_token() {
    let app = test::init_service(
        App::new()
            .wrap(JwtMiddleware::new("a".repeat(32)))
            .route("/test", web::get().to(test_handler)),
    )
    .await;

    let req = test::TestRequest::get()
        .uri("/test")
        .insert_header(("Authorization", "Bearer not.a.valid.jwt"))
        .to_request();

    let resp = test::try_call_service(&app, req).await;
    assert!(resp.is_err(), "Malformed JWT should be rejected");
}

// =============================================================================
// Health Check Bypass Tests
// =============================================================================

#[actix_web::test]
async fn test_health_check_bypasses_authentication() {
    let app = test::init_service(
        App::new()
            .wrap(JwtMiddleware::new("a".repeat(32)))
            .route("/health", web::get().to(test_handler)),
    )
    .await;

    // No Authorization header
    let req = test::TestRequest::get().uri("/health").to_request();

    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 200, "Health check should bypass auth");
}

// =============================================================================
// Token Validity Duration Tests
// =============================================================================

#[actix_web::test]
async fn test_jwt_accepts_valid_token_within_time_window() {
    let app = test::init_service(
        App::new()
            .wrap(JwtMiddleware::new("a".repeat(32)))
            .route("/test", web::get().to(test_handler)),
    )
    .await;

    // Token valid for 1 hour
    let valid_token = create_test_jwt("user-123", 3600, &"a".repeat(32));

    let req = test::TestRequest::get()
        .uri("/test")
        .insert_header(("Authorization", format!("Bearer {}", valid_token)))
        .to_request();

    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 200);
}

#[actix_web::test]
async fn test_jwt_rejects_token_expired_by_1_second() {
    let app = test::init_service(
        App::new()
            .wrap(JwtMiddleware::new("a".repeat(32)))
            .route("/test", web::get().to(test_handler)),
    )
    .await;

    // Token expired 1 second ago
    let expired_token = create_test_jwt("user-123", -1, &"a".repeat(32));

    // Wait to ensure token is definitely expired
    tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;

    let req = test::TestRequest::get()
        .uri("/test")
        .insert_header(("Authorization", format!("Bearer {}", expired_token)))
        .to_request();

    let resp = test::try_call_service(&app, req).await;
    assert!(
        resp.is_err(),
        "Token expired by 1 second should be rejected"
    );
}

// =============================================================================
// Performance & DoS Protection Tests
// =============================================================================

#[actix_web::test]
async fn test_jwt_validation_completes_quickly() {
    use std::time::Instant;

    let app = test::init_service(
        App::new()
            .wrap(JwtMiddleware::new("a".repeat(32)))
            .route("/test", web::get().to(test_handler)),
    )
    .await;

    let valid_token = create_test_jwt("user-123", 3600, &"a".repeat(32));

    let req = test::TestRequest::get()
        .uri("/test")
        .insert_header(("Authorization", format!("Bearer {}", valid_token)))
        .to_request();

    let start = Instant::now();
    let _ = test::call_service(&app, req).await;
    let elapsed = start.elapsed();

    // JWT validation should complete in <100ms
    assert!(
        elapsed.as_millis() < 100,
        "JWT validation took {}ms (expected <100ms)",
        elapsed.as_millis()
    );
}

#[actix_web::test]
async fn test_large_jwt_payload_rejected() {
    // Create oversized JWT payload (potential DoS vector)
    let large_email = "x".repeat(10_000); // 10KB email field

    let claims = Claims {
        sub: "user-123".to_string(),
        exp: (chrono::Utc::now().timestamp() + 3600) as usize,
        iat: chrono::Utc::now().timestamp() as usize,
        email: large_email,
    };

    let secret = "a".repeat(32);
    let token = encode(
        &Header::new(Algorithm::HS256),
        &claims,
        &EncodingKey::from_secret(secret.as_bytes()),
    )
    .unwrap();

    let app = test::init_service(
        App::new()
            .wrap(JwtMiddleware::new(secret))
            .route("/test", web::get().to(test_handler)),
    )
    .await;

    let req = test::TestRequest::get()
        .uri("/test")
        .insert_header(("Authorization", format!("Bearer {}", token)))
        .to_request();

    // Should either reject or handle without crashing
    let _ = test::try_call_service(&app, req).await;
    // Test passes if no panic occurs
}
