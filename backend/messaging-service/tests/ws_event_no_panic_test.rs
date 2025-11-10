/// Unit tests for WebSocket event handling without todo!() panic
/// These tests verify that AppState can be constructed and used without panicking

use messaging_service::{
    config::Config,
    redis_client::RedisClient,
    services::encryption::EncryptionService,
    state::AppState,
    websocket::ConnectionRegistry,
};
use grpc_clients::AuthClient;
use sqlx::postgres::PgPoolOptions;
use std::sync::Arc;
use uuid::Uuid;

/// Test that AppState can be constructed with all fields initialized
#[tokio::test]
async fn test_app_state_construction_complete() {
    // Load test environment
    dotenvy::dotenv().ok();

    let database_url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgres://postgres:postgres@localhost/messaging_test".to_string());
    let redis_url = std::env::var("REDIS_URL")
        .unwrap_or_else(|_| "redis://127.0.0.1:6379/1".to_string());

    // Create database pool
    let db = PgPoolOptions::new()
        .max_connections(5)
        .connect(&database_url)
        .await
        .expect("Failed to create test database pool");

    // Create Redis client
    let redis = RedisClient::new(&redis_url, None)
        .await
        .expect("Failed to create test Redis client");

    // Create config
    let config = Arc::new(Config::test_defaults());

    // Create encryption service
    let encryption = Arc::new(EncryptionService::new(config.encryption_master_key));

    // Create auth client
    let auth_client = Arc::new(
        AuthClient::new(&config.auth_service_url)
            .await
            .expect("Failed to create auth client"),
    );

    // Create ConnectionRegistry
    let registry = ConnectionRegistry::new();

    // Construct AppState - THIS MUST NOT PANIC
    let state = AppState {
        db,
        registry,
        redis,
        config,
        apns: None,
        encryption,
        key_exchange_service: None,
        auth_client,
    };

    // Verify state can be cloned (required for WebSocket session)
    let cloned_state = state.clone();

    // Verify cloned state has all fields
    assert!(cloned_state.config.database_url.len() > 0);
    assert!(Arc::strong_count(&cloned_state.encryption) >= 1);
    assert!(Arc::strong_count(&cloned_state.auth_client) >= 1);
}

/// Test that encryption service works correctly
#[test]
fn test_encryption_service_no_panic() {
    let master_key = [0u8; 32];
    let encryption = EncryptionService::new(master_key);

    let conversation_id = Uuid::new_v4();
    let plaintext = b"test message";

    // Encrypt - THIS MUST NOT PANIC
    let (ciphertext, nonce) = encryption
        .encrypt(conversation_id, plaintext)
        .expect("Encryption failed");

    // Decrypt - THIS MUST NOT PANIC
    let decrypted = encryption
        .decrypt(conversation_id, &ciphertext, &nonce)
        .expect("Decryption failed");

    assert_eq!(plaintext, &decrypted[..]);
}

/// Test that conversation key derivation works
#[test]
fn test_conversation_key_derivation() {
    let master_key = [0u8; 32];
    let encryption = EncryptionService::new(master_key);

    let conversation_id = Uuid::new_v4();

    // Derive key - THIS MUST NOT PANIC
    let key1 = encryption.conversation_key(conversation_id);
    let key2 = encryption.conversation_key(conversation_id);

    // Same conversation should produce same key
    assert_eq!(key1, key2);

    // Different conversation should produce different key
    let other_conversation_id = Uuid::new_v4();
    let key3 = encryption.conversation_key(other_conversation_id);
    assert_ne!(key1, key3);
}

/// Test that ConnectionRegistry works correctly
#[tokio::test]
async fn test_connection_registry_no_panic() {
    let registry = ConnectionRegistry::new();
    let conversation_id = Uuid::new_v4();

    // Add subscriber - THIS MUST NOT PANIC
    let (subscriber_id, mut rx) = registry.add_subscriber(conversation_id).await;

    // Remove subscriber - THIS MUST NOT PANIC
    registry.remove_subscriber(conversation_id, subscriber_id).await;

    // Verify receiver is closed
    assert!(rx.recv().await.is_none());
}

/// Test AppState cloning preserves all fields
#[tokio::test]
async fn test_app_state_clone_preserves_fields() {
    let config = Arc::new(Config::test_defaults());
    let encryption = Arc::new(EncryptionService::new(config.encryption_master_key));

    let database_url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgres://postgres:postgres@localhost/messaging_test".to_string());
    let redis_url = std::env::var("REDIS_URL")
        .unwrap_or_else(|_| "redis://127.0.0.1:6379/1".to_string());

    let db = PgPoolOptions::new()
        .max_connections(5)
        .connect(&database_url)
        .await
        .expect("Failed to create test database pool");

    let redis = RedisClient::new(&redis_url, None)
        .await
        .expect("Failed to create test Redis client");

    let auth_client = Arc::new(
        AuthClient::new(&config.auth_service_url)
            .await
            .expect("Failed to create auth client"),
    );

    let registry = ConnectionRegistry::new();

    let state = AppState {
        db,
        registry,
        redis,
        config: Arc::clone(&config),
        apns: None,
        encryption: Arc::clone(&encryption),
        key_exchange_service: None,
        auth_client: Arc::clone(&auth_client),
    };

    // Clone multiple times - THIS MUST NOT PANIC
    let clone1 = state.clone();
    let clone2 = state.clone();
    let clone3 = clone1.clone();

    // Verify reference counts increased
    assert!(Arc::strong_count(&config) >= 4); // Original + 3 clones
    assert!(Arc::strong_count(&encryption) >= 4);
    assert!(Arc::strong_count(&auth_client) >= 4);

    // Verify all clones have same config values
    assert_eq!(state.config.database_url, clone1.config.database_url);
    assert_eq!(state.config.database_url, clone2.config.database_url);
    assert_eq!(state.config.database_url, clone3.config.database_url);
}
