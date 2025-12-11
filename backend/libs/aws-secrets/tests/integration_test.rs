//! Integration tests for AWS Secrets Manager with rotation support
//!
//! These tests verify:
//! 1. Secret fetching and caching behavior
//! 2. Cache invalidation and refresh on rotation
//! 3. Error handling for missing/invalid secrets
//! 4. JWT config parsing and validation
//!
//! Prerequisites:
//! - AWS credentials configured (IAM user or IRSA in K8s)
//! - Test secret created in AWS Secrets Manager
//! - Set environment variable: AWS_SECRETS_TEST_SECRET_NAME
//!
//! Run tests:
//! ```bash
//! export AWS_SECRETS_TEST_SECRET_NAME="test/nova/jwt-config"
//! cargo test --package aws-secrets --test integration_test -- --nocapture
//! ```

use aws_secrets::{JwtSecretConfig, SecretError, SecretManager};
use std::env;
use std::time::Duration;
use tokio::time::sleep;

/// Helper function to get test secret name from environment
fn get_test_secret_name() -> String {
    env::var("AWS_SECRETS_TEST_SECRET_NAME").unwrap_or_else(|_| "test/nova/jwt-config".to_string())
}

/// Test: Create SecretManager and verify initialization
#[tokio::test]
async fn test_secret_manager_initialization() {
    let result = SecretManager::new().await;
    assert!(
        result.is_ok(),
        "SecretManager initialization failed: {:?}",
        result.err()
    );

    let manager = result.unwrap();
    let (entries, size) = manager.cache_stats().await;
    assert_eq!(entries, 0, "Cache should be empty on initialization");
}

/// Test: Fetch secret and verify caching
#[tokio::test]
async fn test_secret_fetch_and_cache() {
    let manager = SecretManager::new()
        .await
        .expect("Failed to create manager");
    let secret_name = get_test_secret_name();

    // Skip test if secret doesn't exist (allows running tests without AWS setup)
    if let Err(SecretError::NotFound(_)) = manager.get_secret(&secret_name).await {
        eprintln!(
            "Skipping test: Secret '{}' not found in AWS Secrets Manager",
            secret_name
        );
        eprintln!("To run this test, create the secret or set AWS_SECRETS_TEST_SECRET_NAME");
        return;
    }

    // First fetch: should hit AWS and cache
    let secret1 = manager
        .get_secret(&secret_name)
        .await
        .expect("Failed to fetch secret");
    assert!(!secret1.is_empty(), "Secret should not be empty");

    let (entries, _) = manager.cache_stats().await;
    assert_eq!(entries, 1, "Cache should contain 1 entry after first fetch");

    // Second fetch: should hit cache
    let secret2 = manager
        .get_secret(&secret_name)
        .await
        .expect("Failed to fetch secret from cache");
    assert_eq!(secret1, secret2, "Cached secret should match original");

    let (entries, _) = manager.cache_stats().await;
    assert_eq!(entries, 1, "Cache should still contain 1 entry");
}

/// Test: JWT config parsing and validation
#[tokio::test]
async fn test_jwt_config_parsing() {
    let manager = SecretManager::new()
        .await
        .expect("Failed to create manager");
    let secret_name = get_test_secret_name();

    // Skip test if secret doesn't exist
    let jwt_config_result = manager.get_jwt_config(&secret_name).await;
    if let Err(SecretError::NotFound(_)) = jwt_config_result {
        eprintln!(
            "Skipping test: Secret '{}' not found in AWS Secrets Manager",
            secret_name
        );
        return;
    }

    let jwt_config = jwt_config_result.expect("Failed to parse JWT config");

    // Validate required fields
    assert!(
        !jwt_config.signing_key.is_empty(),
        "Signing key is required"
    );
    assert!(!jwt_config.algorithm.is_empty(), "Algorithm is required");
    assert!(!jwt_config.issuer.is_empty(), "Issuer is required");
    assert!(!jwt_config.audience.is_empty(), "Audience is required");
    assert!(
        jwt_config.expiry_seconds > 0,
        "Expiry seconds must be positive"
    );

    // Validate algorithm
    assert!(
        matches!(
            jwt_config.algorithm.as_str(),
            "HS256" | "HS384" | "HS512" | "RS256" | "RS384" | "RS512" | "ES256" | "ES384"
        ),
        "Invalid JWT algorithm: {}",
        jwt_config.algorithm
    );

    // Validate asymmetric key requirement
    if jwt_config.algorithm.starts_with("RS") || jwt_config.algorithm.starts_with("ES") {
        assert!(
            jwt_config.validation_key.is_some(),
            "Asymmetric algorithms require validation_key"
        );
    }

    println!("JWT Config validated: {:?}", jwt_config);
}

/// Test: Cache invalidation
#[tokio::test]
async fn test_cache_invalidation() {
    let manager = SecretManager::new()
        .await
        .expect("Failed to create manager");
    let secret_name = get_test_secret_name();

    // Skip test if secret doesn't exist
    if let Err(SecretError::NotFound(_)) = manager.get_secret(&secret_name).await {
        eprintln!(
            "Skipping test: Secret '{}' not found in AWS Secrets Manager",
            secret_name
        );
        return;
    }

    // Fetch secret to populate cache
    let _ = manager
        .get_secret(&secret_name)
        .await
        .expect("Failed to fetch secret");

    let (entries_before, _) = manager.cache_stats().await;
    assert_eq!(entries_before, 1, "Cache should contain 1 entry");

    // Invalidate cache
    manager.invalidate_cache(&secret_name).await;

    let (entries_after, _) = manager.cache_stats().await;
    assert_eq!(entries_after, 0, "Cache should be empty after invalidation");

    // Fetch again: should hit AWS and re-cache
    let _ = manager
        .get_secret(&secret_name)
        .await
        .expect("Failed to fetch secret after invalidation");

    let (entries_final, _) = manager.cache_stats().await;
    assert_eq!(
        entries_final, 1,
        "Cache should contain 1 entry after re-fetch"
    );
}

/// Test: Cache expiration (TTL)
#[tokio::test]
async fn test_cache_ttl_expiration() {
    // Create manager with 2-second TTL for testing
    let manager = SecretManager::with_cache_ttl(Duration::from_secs(2))
        .await
        .expect("Failed to create manager");
    let secret_name = get_test_secret_name();

    // Skip test if secret doesn't exist
    if let Err(SecretError::NotFound(_)) = manager.get_secret(&secret_name).await {
        eprintln!(
            "Skipping test: Secret '{}' not found in AWS Secrets Manager",
            secret_name
        );
        return;
    }

    // Fetch secret to populate cache
    let _ = manager
        .get_secret(&secret_name)
        .await
        .expect("Failed to fetch secret");

    let (entries_before, _) = manager.cache_stats().await;
    assert_eq!(entries_before, 1, "Cache should contain 1 entry");

    // Wait for TTL to expire (2 seconds + margin)
    sleep(Duration::from_secs(3)).await;

    let (entries_after, _) = manager.cache_stats().await;
    assert_eq!(
        entries_after, 0,
        "Cache should be empty after TTL expiration"
    );

    // Fetch again: should hit AWS and re-cache
    let _ = manager
        .get_secret(&secret_name)
        .await
        .expect("Failed to fetch secret after TTL expiration");

    let (entries_final, _) = manager.cache_stats().await;
    assert_eq!(
        entries_final, 1,
        "Cache should contain 1 entry after re-fetch"
    );
}

/// Test: Simulate secret rotation
#[tokio::test]
async fn test_secret_rotation_simulation() {
    let manager = SecretManager::with_cache_ttl(Duration::from_secs(2))
        .await
        .expect("Failed to create manager");
    let secret_name = get_test_secret_name();

    // Skip test if secret doesn't exist
    if let Err(SecretError::NotFound(_)) = manager.get_secret(&secret_name).await {
        eprintln!(
            "Skipping test: Secret '{}' not found in AWS Secrets Manager",
            secret_name
        );
        return;
    }

    // Phase 1: Fetch initial secret version
    let secret_v1 = manager
        .get_secret(&secret_name)
        .await
        .expect("Failed to fetch secret v1");
    println!("Secret V1 fetched (length: {})", secret_v1.len());

    // Phase 2: Simulate rotation by invalidating cache
    // In production, AWS Secrets Manager rotation Lambda would update the secret
    // and services would detect the new version after cache TTL expires
    println!("Simulating secret rotation (invalidating cache)...");
    manager.invalidate_cache(&secret_name).await;

    // Phase 3: Fetch secret again (would get new version if it was rotated)
    let secret_v2 = manager
        .get_secret(&secret_name)
        .await
        .expect("Failed to fetch secret v2");
    println!("Secret V2 fetched (length: {})", secret_v2.len());

    // In this test, secret didn't actually rotate, so values should match
    // In production with real rotation, secret_v2 would differ from secret_v1
    assert_eq!(
        secret_v1, secret_v2,
        "Secret values match (no actual rotation in test)"
    );

    println!("Secret rotation simulation complete");
    println!("In production, after AWS rotation:");
    println!("1. Rotation Lambda updates secret in AWS");
    println!("2. Cache expires after TTL (5 minutes default)");
    println!("3. Next fetch gets new secret version");
    println!("4. Old JWT tokens remain valid until expiry");
}

/// Test: Error handling for non-existent secret
#[tokio::test]
#[ignore = "Requires AWS credentials"]
async fn test_secret_not_found_error() {
    let manager = SecretManager::new()
        .await
        .expect("Failed to create manager");
    let non_existent_secret = "test/nova/nonexistent-secret-12345";

    let result = manager.get_secret(non_existent_secret).await;
    assert!(
        result.is_err(),
        "Should return error for non-existent secret"
    );

    match result.unwrap_err() {
        SecretError::NotFound(name) => {
            assert_eq!(name, non_existent_secret);
        }
        other => panic!("Expected NotFound error, got: {:?}", other),
    }
}

/// Test: Error handling for invalid JWT config format
#[test]
fn test_invalid_jwt_config_parsing() {
    // Missing required signing key fields
    let invalid_json = r#"{
        "issuer": "nova",
        "audience": ["api"],
        "expiry_seconds": 3600
    }"#;

    let result = JwtSecretConfig::from_json(invalid_json);
    assert!(result.is_err(), "Should fail to parse invalid JWT config");

    match result.unwrap_err() {
        SecretError::InvalidFormat(msg) => {
            assert!(
                msg.contains("JWT config missing expected fields"),
                "Unexpected error message: {msg}"
            );
        }
        other => panic!("Expected InvalidFormat error, got: {:?}", other),
    }
}

/// Test: Concurrent access to cache
#[tokio::test]
async fn test_concurrent_cache_access() {
    let manager = SecretManager::new()
        .await
        .expect("Failed to create manager");
    let secret_name = get_test_secret_name();

    // Skip test if secret doesn't exist
    if let Err(SecretError::NotFound(_)) = manager.get_secret(&secret_name).await {
        eprintln!(
            "Skipping test: Secret '{}' not found in AWS Secrets Manager",
            secret_name
        );
        return;
    }

    // Spawn 10 concurrent tasks fetching the same secret
    let mut handles = vec![];
    for i in 0..10 {
        let manager_clone = manager.clone();
        let secret_name_clone = secret_name.clone();
        let handle = tokio::spawn(async move {
            let result = manager_clone.get_secret(&secret_name_clone).await;
            println!("Task {}: {:?}", i, result.as_ref().map(|s| s.len()));
            result
        });
        handles.push(handle);
    }

    // Wait for all tasks to complete
    let results: Vec<_> = futures_util::future::join_all(handles)
        .await
        .into_iter()
        .collect();

    // Verify all tasks succeeded
    for (i, result) in results.iter().enumerate() {
        assert!(
            result.is_ok(),
            "Task {} failed: {:?}",
            i,
            result.as_ref().err()
        );
        let secret_result = result.as_ref().unwrap();
        assert!(
            secret_result.is_ok(),
            "Task {} got error: {:?}",
            i,
            secret_result.as_ref().err()
        );
    }

    // Verify cache hit (should only fetch once from AWS)
    let (entries, _) = manager.cache_stats().await;
    assert_eq!(
        entries, 1,
        "Cache should contain 1 entry despite 10 concurrent requests"
    );

    println!("All 10 concurrent tasks completed successfully");
}

/// Test: Multiple secret names in cache
#[tokio::test]
async fn test_multiple_secrets_in_cache() {
    let manager = SecretManager::new()
        .await
        .expect("Failed to create manager");
    let secret_name = get_test_secret_name();

    // Skip test if secret doesn't exist
    if let Err(SecretError::NotFound(_)) = manager.get_secret(&secret_name).await {
        eprintln!(
            "Skipping test: Secret '{}' not found in AWS Secrets Manager",
            secret_name
        );
        return;
    }

    // Fetch first secret
    let _ = manager
        .get_secret(&secret_name)
        .await
        .expect("Failed to fetch secret");

    let (entries, _) = manager.cache_stats().await;
    assert_eq!(entries, 1, "Cache should contain 1 entry");

    // Try to fetch a different non-existent secret
    let _ = manager.get_secret("test/nova/another-secret").await;

    // Cache should still contain only 1 entry (NotFound errors aren't cached)
    let (entries, _) = manager.cache_stats().await;
    assert_eq!(
        entries, 1,
        "Cache should still contain 1 entry (errors not cached)"
    );
}

/// Test: Custom cache TTL configuration
#[tokio::test]
async fn test_custom_cache_ttl() {
    // Create manager with 10-second TTL
    let manager = SecretManager::with_cache_ttl(Duration::from_secs(10))
        .await
        .expect("Failed to create manager with custom TTL");

    // Verify manager was created successfully
    let (entries, _) = manager.cache_stats().await;
    assert_eq!(
        entries, 0,
        "Cache should be empty on initialization with custom TTL"
    );
}

/// Test: SecretManagerBuilder pattern
#[tokio::test]
async fn test_secret_manager_builder() {
    use aws_secrets::SecretManagerBuilder;

    let manager = SecretManagerBuilder::new()
        .cache_ttl(Duration::from_secs(60))
        .max_cache_entries(50)
        .build()
        .await
        .expect("Failed to build SecretManager");

    let (entries, _) = manager.cache_stats().await;
    assert_eq!(
        entries, 0,
        "Builder-created manager should have empty cache"
    );
}
