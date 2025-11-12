//! Integration Tests for JWT Propagation
//!
//! These tests verify the complete flow:
//! Client -> JWT injection -> Server -> JWT validation -> Handler access

use grpc_jwt_propagation::{JwtClientInterceptor, JwtClaimsExt, JwtServerInterceptor};
use tonic::service::Interceptor;
use tonic::{Request, Response, Status};
use uuid::Uuid;

// Test RSA keys (same as crypto-core tests)
const TEST_PRIVATE_KEY: &str = include_str!("test_private_key.pem");
const TEST_PUBLIC_KEY: &str = include_str!("test_public_key.pem");

/// Initialize JWT keys once for all tests
fn init_test_keys() {
    static INIT: std::sync::Once = std::sync::Once::new();
    INIT.call_once(|| {
        crypto_core::jwt::initialize_jwt_keys(TEST_PRIVATE_KEY, TEST_PUBLIC_KEY)
            .expect("Failed to initialize test keys");
    });
}

/// Simulate a gRPC request flowing through client and server interceptors
fn simulate_grpc_flow(
    jwt_token: &str,
) -> Result<Request<()>, Status> {
    // CLIENT SIDE: Create request with JWT interceptor
    let mut client_interceptor = JwtClientInterceptor::new(jwt_token);
    let request = Request::new(());
    let request = client_interceptor.call(request)?;

    // Simulate network transmission (in reality, metadata is serialized)
    // For testing, we can directly pass the request

    // SERVER SIDE: Validate JWT and extract claims
    let mut server_interceptor = JwtServerInterceptor;
    let request = server_interceptor.call(request)?;

    Ok(request)
}

#[test]
fn test_end_to_end_jwt_flow() {
    init_test_keys();

    // Generate a valid token
    let user_id = Uuid::new_v4();
    let token = crypto_core::jwt::generate_access_token(
        user_id,
        "test@example.com",
        "testuser",
    )
    .expect("Failed to generate token");

    // Simulate request flow
    let request = simulate_grpc_flow(&token).expect("Flow should succeed");

    // Verify claims are accessible in handler
    let claims = request.jwt_claims().expect("Claims should be present");
    assert_eq!(claims.user_id, user_id);
    assert_eq!(claims.email, "test@example.com");
    assert_eq!(claims.username, "testuser");
    assert_eq!(claims.token_type, "access");
}

#[test]
fn test_end_to_end_invalid_token() {
    init_test_keys();

    let invalid_token = "invalid.jwt.token";
    let result = simulate_grpc_flow(invalid_token);

    assert!(result.is_err());
    let status = result.unwrap_err();
    assert_eq!(status.code(), tonic::Code::Unauthenticated);
}

#[test]
fn test_end_to_end_tampered_token() {
    init_test_keys();

    // Generate valid token then tamper with it
    let user_id = Uuid::new_v4();
    let token = crypto_core::jwt::generate_access_token(
        user_id,
        "test@example.com",
        "testuser",
    )
    .expect("Failed to generate token");

    let tampered = token.replace("a", "b");
    let result = simulate_grpc_flow(&tampered);

    assert!(result.is_err());
    let status = result.unwrap_err();
    assert_eq!(status.code(), tonic::Code::Unauthenticated);
}

#[test]
fn test_ownership_check_success() {
    init_test_keys();

    let user_id = Uuid::new_v4();
    let token = crypto_core::jwt::generate_access_token(
        user_id,
        "test@example.com",
        "testuser",
    )
    .expect("Failed to generate token");

    let request = simulate_grpc_flow(&token).expect("Flow should succeed");

    // Check ownership (same user ID)
    let result = request.require_ownership(&user_id);
    assert!(result.is_ok());
}

#[test]
fn test_ownership_check_failure() {
    init_test_keys();

    let user_id = Uuid::new_v4();
    let token = crypto_core::jwt::generate_access_token(
        user_id,
        "test@example.com",
        "testuser",
    )
    .expect("Failed to generate token");

    let request = simulate_grpc_flow(&token).expect("Flow should succeed");

    // Check ownership with different user ID
    let other_user_id = Uuid::new_v4();
    let result = request.require_ownership(&other_user_id);

    assert!(result.is_err());
    let status = result.unwrap_err();
    assert_eq!(status.code(), tonic::Code::PermissionDenied);
}

#[test]
fn test_access_token_validation() {
    init_test_keys();

    let user_id = Uuid::new_v4();
    let token = crypto_core::jwt::generate_access_token(
        user_id,
        "test@example.com",
        "testuser",
    )
    .expect("Failed to generate token");

    let request = simulate_grpc_flow(&token).expect("Flow should succeed");

    // Should succeed for access token
    let result = request.require_access_token();
    assert!(result.is_ok());
}

#[test]
fn test_refresh_token_rejected_for_api_access() {
    init_test_keys();

    let user_id = Uuid::new_v4();
    let refresh_token = crypto_core::jwt::generate_refresh_token(
        user_id,
        "test@example.com",
        "testuser",
    )
    .expect("Failed to generate refresh token");

    let request = simulate_grpc_flow(&refresh_token).expect("Flow should succeed");

    // Should fail when requiring access token
    let result = request.require_access_token();
    assert!(result.is_err());
    let status = result.unwrap_err();
    assert_eq!(status.code(), tonic::Code::PermissionDenied);
}

/// Mock service handler demonstrating real-world usage
async fn mock_delete_post_handler(
    request: Request<()>,
    post_owner_id: Uuid,
) -> Result<Response<()>, Status> {
    // Extract claims
    let claims = request.jwt_claims()?;

    // Authorization: only owner can delete
    if !claims.is_owner(&post_owner_id) {
        return Err(Status::permission_denied(
            "You can only delete your own posts"
        ));
    }

    // Proceed with deletion
    Ok(Response::new(()))
}

#[tokio::test]
async fn test_authorization_pattern_owner_deletes_own_post() {
    init_test_keys();

    let user_id = Uuid::new_v4();
    let token = crypto_core::jwt::generate_access_token(
        user_id,
        "test@example.com",
        "testuser",
    )
    .expect("Failed to generate token");

    let request = simulate_grpc_flow(&token).expect("Flow should succeed");

    // User deletes their own post
    let result = mock_delete_post_handler(request, user_id).await;
    assert!(result.is_ok());
}

#[tokio::test]
async fn test_authorization_pattern_user_cannot_delete_others_post() {
    init_test_keys();

    let user_id = Uuid::new_v4();
    let token = crypto_core::jwt::generate_access_token(
        user_id,
        "test@example.com",
        "testuser",
    )
    .expect("Failed to generate token");

    let request = simulate_grpc_flow(&token).expect("Flow should succeed");

    // User tries to delete someone else's post
    let other_user_id = Uuid::new_v4();
    let result = mock_delete_post_handler(request, other_user_id).await;

    assert!(result.is_err());
    let status = result.unwrap_err();
    assert_eq!(status.code(), tonic::Code::PermissionDenied);
    assert!(status.message().contains("You can only delete your own posts"));
}

/// Test that multiple requests can use the same interceptor (cloneable)
#[test]
fn test_client_interceptor_reusable() {
    init_test_keys();

    let user_id = Uuid::new_v4();
    let token = crypto_core::jwt::generate_access_token(
        user_id,
        "test@example.com",
        "testuser",
    )
    .expect("Failed to generate token");

    let interceptor = JwtClientInterceptor::new(token);

    // Clone and use multiple times
    let mut interceptor1 = interceptor.clone();
    let mut interceptor2 = interceptor.clone();

    let request1 = Request::new(());
    let request2 = Request::new(());

    let result1 = interceptor1.call(request1);
    let result2 = interceptor2.call(request2);

    assert!(result1.is_ok());
    assert!(result2.is_ok());
}
