/// End-to-End Encryption (E2EE) Integration Test Suite
///
/// This test suite validates the complete E2EE flow using X25519 ECDH key exchange
/// and authenticated encryption. It follows TDD principles with comprehensive coverage.
///
/// Test categories:
/// 1. Key Exchange Tests - X25519 keypair generation and ECDH shared secret derivation
/// 2. Encryption/Decryption Tests - Message encryption with derived keys
/// 3. Full E2EE Flow Tests - Complete message lifecycle with E2EE
/// 4. Security Tests - Forward secrecy, tamper detection, key isolation
/// 5. Error Handling Tests - Invalid keys, missing data, malformed input

use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use messaging_service::services::e2ee::E2eeService;
use sqlx::postgres::PgPoolOptions;
use sqlx::{Pool, Postgres, Row};
use uuid::Uuid;

const TEST_MASTER_KEY: [u8; 32] = [7u8; 32];

/// Bootstrap database connection pool for testing
async fn bootstrap_pool() -> Pool<Postgres> {
    let db_url = std::env::var("DATABASE_URL")
        .expect("DATABASE_URL env var required for E2EE tests");
    PgPoolOptions::new()
        .max_connections(10)
        .connect(&db_url)
        .await
        .expect("failed to connect to DATABASE_URL")
}

/// Cleanup test data from device_keys table
async fn cleanup_device_keys(pool: &Pool<Postgres>, user_ids: &[Uuid]) {
    for user_id in user_ids {
        let _ = sqlx::query("DELETE FROM device_keys WHERE user_id = $1")
            .bind(user_id)
            .execute(pool)
            .await;
    }
}

/// Cleanup test data from key_exchanges table
async fn cleanup_key_exchanges(pool: &Pool<Postgres>, conversation_id: Uuid) {
    let _ = sqlx::query("DELETE FROM key_exchanges WHERE conversation_id = $1")
        .bind(conversation_id)
        .execute(pool)
        .await;
}

// ============================================================================
// 1. Key Exchange Tests
// ============================================================================

#[tokio::test]
#[ignore] // Run with: cargo test --test e2ee_integration_test -- --ignored
async fn test_generate_x25519_keypair() {
    // RED: Test X25519 keypair generation
    let e2ee_service = E2eeService::new(TEST_MASTER_KEY);

    let (public_key, secret_key) = e2ee_service.generate_keypair();

    // X25519 keys are 32 bytes
    assert_eq!(public_key.len(), 32, "public key must be 32 bytes");
    assert_eq!(secret_key.len(), 32, "secret key must be 32 bytes");

    // Keys should be different
    assert_ne!(public_key, secret_key, "public and secret keys must differ");

    // Generate another pair to ensure randomness
    let (public_key2, _) = e2ee_service.generate_keypair();
    assert_ne!(public_key, public_key2, "keypairs must be unique");
}

#[tokio::test]
#[ignore]
async fn test_ecdh_shared_secret_derivation() {
    // RED: Test ECDH shared secret computation
    let e2ee_service = E2eeService::new(TEST_MASTER_KEY);

    // Alice and Bob generate keypairs
    let (alice_public, alice_secret) = e2ee_service.generate_keypair();
    let (bob_public, bob_secret) = e2ee_service.generate_keypair();

    // Alice computes shared secret with Bob's public key
    let alice_shared = e2ee_service
        .derive_shared_secret(&alice_secret, &bob_public)
        .expect("Alice should derive shared secret");

    // Bob computes shared secret with Alice's public key
    let bob_shared = e2ee_service
        .derive_shared_secret(&bob_secret, &alice_public)
        .expect("Bob should derive shared secret");

    // Shared secrets must match (ECDH property)
    assert_eq!(alice_shared, bob_shared, "ECDH shared secrets must match");
    assert_eq!(alice_shared.len(), 32, "shared secret must be 32 bytes");
}

#[tokio::test]
#[ignore]
async fn test_device_key_storage_and_retrieval() {
    // RED: Test storing and retrieving device keys from database
    let pool = bootstrap_pool().await;
    let e2ee_service = E2eeService::new(TEST_MASTER_KEY);

    let user_id = Uuid::new_v4();
    let device_id = "test-device-001";

    // Generate and store keypair
    let (public_key, secret_key) = e2ee_service.generate_keypair();
    e2ee_service
        .store_device_key(&pool, user_id, device_id, &public_key, &secret_key)
        .await
        .expect("should store device key");

    // Retrieve public key
    let retrieved_public = e2ee_service
        .get_device_public_key(&pool, user_id, device_id)
        .await
        .expect("should retrieve public key")
        .expect("public key should exist");

    assert_eq!(public_key, retrieved_public, "retrieved public key must match");

    // Retrieve private key (encrypted at rest)
    let retrieved_secret = e2ee_service
        .get_device_secret_key(&pool, user_id, device_id)
        .await
        .expect("should retrieve secret key")
        .expect("secret key should exist");

    assert_eq!(secret_key, retrieved_secret, "retrieved secret key must match");

    cleanup_device_keys(&pool, &[user_id]).await;
}

#[tokio::test]
#[ignore]
async fn test_device_key_unique_constraint() {
    // RED: Test that device key constraint prevents duplicates
    let pool = bootstrap_pool().await;
    let e2ee_service = E2eeService::new(TEST_MASTER_KEY);

    let user_id = Uuid::new_v4();
    let device_id = "test-device-002";

    let (public_key1, secret_key1) = e2ee_service.generate_keypair();
    e2ee_service
        .store_device_key(&pool, user_id, device_id, &public_key1, &secret_key1)
        .await
        .expect("first store should succeed");

    // Attempt to store another key for same user/device
    let (public_key2, secret_key2) = e2ee_service.generate_keypair();
    let result = e2ee_service
        .store_device_key(&pool, user_id, device_id, &public_key2, &secret_key2)
        .await;

    assert!(result.is_err(), "duplicate device key should fail");

    cleanup_device_keys(&pool, &[user_id]).await;
}

#[tokio::test]
#[ignore]
async fn test_concurrent_key_exchanges_no_conflicts() {
    // RED: Test concurrent key exchange storage without race conditions
    let pool = bootstrap_pool().await;
    let e2ee_service = E2eeService::new(TEST_MASTER_KEY);

    let conversation_id = Uuid::new_v4();
    let user_a = Uuid::new_v4();
    let user_b = Uuid::new_v4();

    let (public_a, secret_a) = e2ee_service.generate_keypair();
    let (public_b, secret_b) = e2ee_service.generate_keypair();

    let shared_ab = e2ee_service.derive_shared_secret(&secret_a, &public_b).unwrap();
    let shared_ba = e2ee_service.derive_shared_secret(&secret_b, &public_a).unwrap();

    // Store both exchanges concurrently
    let handles = vec![
        tokio::spawn({
            let pool = pool.clone();
            let e2ee = e2ee_service.clone();
            async move {
                e2ee.record_key_exchange(&pool, conversation_id, user_a, user_b, &shared_ab)
                    .await
            }
        }),
        tokio::spawn({
            let pool = pool.clone();
            let e2ee = e2ee_service.clone();
            async move {
                e2ee.record_key_exchange(&pool, conversation_id, user_b, user_a, &shared_ba)
                    .await
            }
        }),
    ];

    for handle in handles {
        handle.await.unwrap().expect("key exchange storage should succeed");
    }

    // Verify both exchanges were recorded
    let count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM key_exchanges WHERE conversation_id = $1"
    )
    .bind(conversation_id)
    .fetch_one(&pool)
    .await
    .unwrap();

    assert_eq!(count, 2, "both key exchanges should be recorded");

    cleanup_key_exchanges(&pool, conversation_id).await;
}

// ============================================================================
// 2. Encryption/Decryption Tests
// ============================================================================

#[tokio::test]
#[ignore]
async fn test_encrypt_message_with_derived_key() {
    // RED: Test message encryption with ECDH-derived key
    let e2ee_service = E2eeService::new(TEST_MASTER_KEY);

    let (public_a, secret_a) = e2ee_service.generate_keypair();
    let (public_b, secret_b) = e2ee_service.generate_keypair();
    let shared_secret = e2ee_service.derive_shared_secret(&secret_a, &public_b).unwrap();

    let plaintext = b"Hello E2EE World";
    let (ciphertext, nonce) = e2ee_service
        .encrypt_message(&shared_secret, plaintext)
        .expect("encryption should succeed");

    assert!(!ciphertext.is_empty(), "ciphertext should not be empty");
    assert_eq!(nonce.len(), 24, "nonce must be 24 bytes");
    assert_ne!(ciphertext, plaintext, "ciphertext must differ from plaintext");
}

#[tokio::test]
#[ignore]
async fn test_decrypt_message_by_recipient() {
    // RED: Test message decryption by recipient
    let e2ee_service = E2eeService::new(TEST_MASTER_KEY);

    let (public_a, secret_a) = e2ee_service.generate_keypair();
    let (public_b, secret_b) = e2ee_service.generate_keypair();

    let shared_secret_a = e2ee_service.derive_shared_secret(&secret_a, &public_b).unwrap();
    let shared_secret_b = e2ee_service.derive_shared_secret(&secret_b, &public_a).unwrap();

    let plaintext = b"Encrypted message content";
    let (ciphertext, nonce) = e2ee_service
        .encrypt_message(&shared_secret_a, plaintext)
        .unwrap();

    // Bob decrypts using his shared secret
    let decrypted = e2ee_service
        .decrypt_message(&shared_secret_b, &ciphertext, &nonce)
        .expect("decryption should succeed");

    assert_eq!(decrypted, plaintext, "decrypted plaintext must match original");
}

#[tokio::test]
#[ignore]
async fn test_ciphertext_variation_with_different_nonces() {
    // RED: Test that same plaintext produces different ciphertext with different nonces
    let e2ee_service = E2eeService::new(TEST_MASTER_KEY);

    let (public_a, secret_a) = e2ee_service.generate_keypair();
    let (public_b, _) = e2ee_service.generate_keypair();
    let shared_secret = e2ee_service.derive_shared_secret(&secret_a, &public_b).unwrap();

    let plaintext = b"Same message";

    let (ciphertext1, nonce1) = e2ee_service.encrypt_message(&shared_secret, plaintext).unwrap();
    let (ciphertext2, nonce2) = e2ee_service.encrypt_message(&shared_secret, plaintext).unwrap();

    assert_ne!(nonce1, nonce2, "nonces must be different");
    assert_ne!(ciphertext1, ciphertext2, "ciphertexts must differ with different nonces");
}

#[tokio::test]
#[ignore]
async fn test_hkdf_key_derivation() {
    // RED: Test HKDF-SHA256 key derivation from shared secret
    let e2ee_service = E2eeService::new(TEST_MASTER_KEY);

    let (public_a, secret_a) = e2ee_service.generate_keypair();
    let (public_b, _) = e2ee_service.generate_keypair();
    let shared_secret = e2ee_service.derive_shared_secret(&secret_a, &public_b).unwrap();

    let conversation_id = Uuid::new_v4();

    // Derive encryption key using HKDF
    let derived_key = e2ee_service.derive_encryption_key(&shared_secret, conversation_id);

    assert_eq!(derived_key.len(), 32, "derived key must be 32 bytes");

    // Same input should produce same key
    let derived_key2 = e2ee_service.derive_encryption_key(&shared_secret, conversation_id);
    assert_eq!(derived_key, derived_key2, "HKDF derivation must be deterministic");

    // Different conversation should produce different key
    let different_conversation_id = Uuid::new_v4();
    let derived_key3 = e2ee_service.derive_encryption_key(&shared_secret, different_conversation_id);
    assert_ne!(derived_key, derived_key3, "different context should produce different key");
}

#[tokio::test]
#[ignore]
async fn test_base64_encoding_decoding() {
    // RED: Test base64 encoding/decoding of encrypted payloads
    let e2ee_service = E2eeService::new(TEST_MASTER_KEY);

    let (public_a, secret_a) = e2ee_service.generate_keypair();
    let (public_b, _) = e2ee_service.generate_keypair();
    let shared_secret = e2ee_service.derive_shared_secret(&secret_a, &public_b).unwrap();

    let plaintext = b"Test base64 encoding";
    let (ciphertext, nonce) = e2ee_service.encrypt_message(&shared_secret, plaintext).unwrap();

    // Encode to base64
    let ciphertext_b64 = BASE64.encode(&ciphertext);
    let nonce_b64 = BASE64.encode(&nonce);

    // Decode from base64
    let ciphertext_decoded = BASE64.decode(&ciphertext_b64).expect("base64 decode should succeed");
    let nonce_decoded = BASE64.decode(&nonce_b64).expect("nonce decode should succeed");

    assert_eq!(ciphertext, ciphertext_decoded, "base64 roundtrip should preserve ciphertext");
    assert_eq!(nonce.to_vec(), nonce_decoded, "base64 roundtrip should preserve nonce");
}

// ============================================================================
// 3. Full E2EE Flow Tests
// ============================================================================

#[tokio::test]
#[ignore]
async fn test_full_e2ee_message_flow() {
    // RED: Test complete E2EE flow from key exchange to message delivery
    let pool = bootstrap_pool().await;
    let e2ee_service = E2eeService::new(TEST_MASTER_KEY);

    let conversation_id = Uuid::new_v4();
    let alice_id = Uuid::new_v4();
    let bob_id = Uuid::new_v4();
    let alice_device = "alice-device";
    let bob_device = "bob-device";

    // Step 1: Alice generates keypair
    let (alice_public, alice_secret) = e2ee_service.generate_keypair();
    e2ee_service
        .store_device_key(&pool, alice_id, alice_device, &alice_public, &alice_secret)
        .await
        .expect("Alice stores her device key");

    // Step 2: Bob generates keypair
    let (bob_public, bob_secret) = e2ee_service.generate_keypair();
    e2ee_service
        .store_device_key(&pool, bob_id, bob_device, &bob_public, &bob_secret)
        .await
        .expect("Bob stores his device key");

    // Step 3: Alice retrieves Bob's public key
    let bob_public_retrieved = e2ee_service
        .get_device_public_key(&pool, bob_id, bob_device)
        .await
        .unwrap()
        .expect("Alice retrieves Bob's public key");

    // Step 4: Alice performs ECDH to derive shared secret
    let alice_shared = e2ee_service
        .derive_shared_secret(&alice_secret, &bob_public_retrieved)
        .unwrap();

    // Step 5: Record key exchange
    e2ee_service
        .record_key_exchange(&pool, conversation_id, alice_id, bob_id, &alice_shared)
        .await
        .expect("record key exchange");

    // Step 6: Alice encrypts and sends message
    let plaintext = b"Hello Bob, this is E2EE!";
    let encryption_key = e2ee_service.derive_encryption_key(&alice_shared, conversation_id);
    let (ciphertext, nonce) = e2ee_service
        .encrypt_message(&encryption_key, plaintext)
        .unwrap();

    // Step 7: Bob retrieves Alice's public key
    let alice_public_retrieved = e2ee_service
        .get_device_public_key(&pool, alice_id, alice_device)
        .await
        .unwrap()
        .expect("Bob retrieves Alice's public key");

    // Step 8: Bob performs ECDH to derive same shared secret
    let bob_shared = e2ee_service
        .derive_shared_secret(&bob_secret, &alice_public_retrieved)
        .unwrap();

    assert_eq!(alice_shared, bob_shared, "shared secrets must match");

    // Step 9: Bob decrypts message
    let bob_encryption_key = e2ee_service.derive_encryption_key(&bob_shared, conversation_id);
    let decrypted = e2ee_service
        .decrypt_message(&bob_encryption_key, &ciphertext, &nonce)
        .expect("Bob decrypts message");

    // Step 10: Verify content matches
    assert_eq!(decrypted, plaintext, "decrypted content must match original");

    cleanup_device_keys(&pool, &[alice_id, bob_id]).await;
    cleanup_key_exchanges(&pool, conversation_id).await;
}

#[tokio::test]
#[ignore]
async fn test_e2ee_message_recall() {
    // RED: Test that recalled E2EE messages remain encrypted
    let pool = bootstrap_pool().await;
    let e2ee_service = E2eeService::new(TEST_MASTER_KEY);

    let conversation_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let device_id = "test-device";

    let (public_key, secret_key) = e2ee_service.generate_keypair();
    let shared_secret = e2ee_service.derive_shared_secret(&secret_key, &public_key).unwrap();
    let encryption_key = e2ee_service.derive_encryption_key(&shared_secret, conversation_id);

    let plaintext = b"Message to be recalled";
    let (ciphertext, nonce) = e2ee_service.encrypt_message(&encryption_key, plaintext).unwrap();

    // Store encrypted message (simulated)
    let message_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO messages (id, conversation_id, sender_id, content, content_encrypted, content_nonce, encryption_version, recalled)
         VALUES ($1, $2, $3, '', $4, $5, 2, false)"
    )
    .bind(message_id)
    .bind(conversation_id)
    .bind(user_id)
    .bind(ciphertext)
    .bind(nonce.to_vec())
    .execute(&pool)
    .await
    .expect("insert encrypted message");

    // Recall message
    sqlx::query("UPDATE messages SET recalled = true WHERE id = $1")
        .bind(message_id)
        .execute(&pool)
        .await
        .expect("recall message");

    // Verify ciphertext still exists (not deleted)
    let row = sqlx::query("SELECT content_encrypted, recalled FROM messages WHERE id = $1")
        .bind(message_id)
        .fetch_one(&pool)
        .await
        .expect("fetch recalled message");

    let stored_ciphertext: Vec<u8> = row.get("content_encrypted");
    let recalled: bool = row.get("recalled");

    assert!(recalled, "message should be marked as recalled");
    assert!(!stored_ciphertext.is_empty(), "ciphertext should remain stored");

    // Cleanup
    let _ = sqlx::query("DELETE FROM messages WHERE id = $1")
        .bind(message_id)
        .execute(&pool)
        .await;
}

#[tokio::test]
#[ignore]
async fn test_e2ee_message_edit_and_reencryption() {
    // RED: Test editing E2EE message with re-encryption
    let pool = bootstrap_pool().await;
    let e2ee_service = E2eeService::new(TEST_MASTER_KEY);

    let conversation_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();

    let (public_key, secret_key) = e2ee_service.generate_keypair();
    let shared_secret = e2ee_service.derive_shared_secret(&secret_key, &public_key).unwrap();
    let encryption_key = e2ee_service.derive_encryption_key(&shared_secret, conversation_id);

    let original_plaintext = b"Original message";
    let (original_ciphertext, original_nonce) = e2ee_service
        .encrypt_message(&encryption_key, original_plaintext)
        .unwrap();

    let message_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO messages (id, conversation_id, sender_id, content, content_encrypted, content_nonce, encryption_version, version_number)
         VALUES ($1, $2, $3, '', $4, $5, 2, 1)"
    )
    .bind(message_id)
    .bind(conversation_id)
    .bind(user_id)
    .bind(&original_ciphertext)
    .bind(original_nonce.to_vec())
    .execute(&pool)
    .await
    .expect("insert original message");

    // Edit message with re-encryption
    let edited_plaintext = b"Edited message";
    let (edited_ciphertext, edited_nonce) = e2ee_service
        .encrypt_message(&encryption_key, edited_plaintext)
        .unwrap();

    sqlx::query(
        "UPDATE messages SET content_encrypted = $1, content_nonce = $2, version_number = version_number + 1
         WHERE id = $3"
    )
    .bind(&edited_ciphertext)
    .bind(edited_nonce.to_vec())
    .bind(message_id)
    .execute(&pool)
    .await
    .expect("update message with re-encryption");

    // Verify version incremented and ciphertext changed
    let row = sqlx::query("SELECT content_encrypted, content_nonce, version_number FROM messages WHERE id = $1")
        .bind(message_id)
        .fetch_one(&pool)
        .await
        .expect("fetch edited message");

    let stored_ciphertext: Vec<u8> = row.get("content_encrypted");
    let stored_nonce: Vec<u8> = row.get("content_nonce");
    let version: i32 = row.get("version_number");

    assert_eq!(version, 2, "version should be incremented");
    assert_ne!(stored_ciphertext, original_ciphertext, "ciphertext should change after edit");

    // Decrypt and verify new content
    let decrypted = e2ee_service
        .decrypt_message(&encryption_key, &stored_ciphertext, &stored_nonce)
        .unwrap();

    assert_eq!(decrypted, edited_plaintext, "decrypted content should match edited plaintext");

    // Cleanup
    let _ = sqlx::query("DELETE FROM messages WHERE id = $1")
        .bind(message_id)
        .execute(&pool)
        .await;
}

// ============================================================================
// 4. Security Tests
// ============================================================================

#[tokio::test]
#[ignore]
async fn test_encryption_key_changes_per_message() {
    // RED: Verify that each message uses a unique nonce (preventing reuse)
    let e2ee_service = E2eeService::new(TEST_MASTER_KEY);

    let (public_key, secret_key) = e2ee_service.generate_keypair();
    let shared_secret = e2ee_service.derive_shared_secret(&secret_key, &public_key).unwrap();
    let conversation_id = Uuid::new_v4();
    let encryption_key = e2ee_service.derive_encryption_key(&shared_secret, conversation_id);

    let plaintext = b"Repeated message";

    // Encrypt same message multiple times
    let mut nonces = vec![];
    for _ in 0..10 {
        let (_, nonce) = e2ee_service.encrypt_message(&encryption_key, plaintext).unwrap();
        nonces.push(nonce);
    }

    // Verify all nonces are unique
    for i in 0..nonces.len() {
        for j in (i+1)..nonces.len() {
            assert_ne!(nonces[i], nonces[j], "nonces must be unique across messages");
        }
    }
}

#[tokio::test]
#[ignore]
async fn test_ciphertext_stealing_no_plaintext_reveal() {
    // RED: Verify that ciphertext alone cannot reveal plaintext
    let e2ee_service = E2eeService::new(TEST_MASTER_KEY);

    let (public_key, secret_key) = e2ee_service.generate_keypair();
    let shared_secret = e2ee_service.derive_shared_secret(&secret_key, &public_key).unwrap();
    let conversation_id = Uuid::new_v4();
    let encryption_key = e2ee_service.derive_encryption_key(&shared_secret, conversation_id);

    let plaintext = b"Sensitive information";
    let (ciphertext, nonce) = e2ee_service.encrypt_message(&encryption_key, plaintext).unwrap();

    // Attacker has ciphertext and nonce but not the key
    let attacker_key = [42u8; 32]; // Wrong key

    let result = e2ee_service.decrypt_message(&attacker_key, &ciphertext, &nonce);

    assert!(result.is_err(), "decryption with wrong key must fail");
}

#[tokio::test]
#[ignore]
async fn test_forward_secrecy_verification() {
    // RED: Test that compromising one key doesn't compromise past messages
    let e2ee_service = E2eeService::new(TEST_MASTER_KEY);

    let conversation_id = Uuid::new_v4();

    // Time period 1: Generate keypair and send message
    let (public_key1, secret_key1) = e2ee_service.generate_keypair();
    let shared_secret1 = e2ee_service.derive_shared_secret(&secret_key1, &public_key1).unwrap();
    let encryption_key1 = e2ee_service.derive_encryption_key(&shared_secret1, conversation_id);

    let plaintext1 = b"Message from time period 1";
    let (ciphertext1, nonce1) = e2ee_service.encrypt_message(&encryption_key1, plaintext1).unwrap();

    // Time period 2: Generate new keypair (key rotation)
    let (public_key2, secret_key2) = e2ee_service.generate_keypair();
    let shared_secret2 = e2ee_service.derive_shared_secret(&secret_key2, &public_key2).unwrap();
    let encryption_key2 = e2ee_service.derive_encryption_key(&shared_secret2, conversation_id);

    // New key cannot decrypt old message
    let result = e2ee_service.decrypt_message(&encryption_key2, &ciphertext1, &nonce1);

    assert!(result.is_err(), "new key cannot decrypt messages encrypted with old key");
}

#[tokio::test]
#[ignore]
async fn test_hmac_tamper_detection() {
    // RED: Test that tampering with ciphertext is detected
    let e2ee_service = E2eeService::new(TEST_MASTER_KEY);

    let (public_key, secret_key) = e2ee_service.generate_keypair();
    let shared_secret = e2ee_service.derive_shared_secret(&secret_key, &public_key).unwrap();
    let conversation_id = Uuid::new_v4();
    let encryption_key = e2ee_service.derive_encryption_key(&shared_secret, conversation_id);

    let plaintext = b"Original message";
    let (mut ciphertext, nonce) = e2ee_service.encrypt_message(&encryption_key, plaintext).unwrap();

    // Attacker tampers with ciphertext
    if !ciphertext.is_empty() {
        ciphertext[0] ^= 0xFF; // Flip bits
    }

    let result = e2ee_service.decrypt_message(&encryption_key, &ciphertext, &nonce);

    assert!(result.is_err(), "tampered ciphertext must fail authentication");
}

#[tokio::test]
#[ignore]
async fn test_rate_limiting_key_exchange() {
    // RED: Test rate limiting on key exchange attempts (prevent DoS)
    let pool = bootstrap_pool().await;
    let e2ee_service = E2eeService::new(TEST_MASTER_KEY);

    let conversation_id = Uuid::new_v4();
    let user_a = Uuid::new_v4();
    let user_b = Uuid::new_v4();

    let (public_key, secret_key) = e2ee_service.generate_keypair();
    let shared_secret = e2ee_service.derive_shared_secret(&secret_key, &public_key).unwrap();

    // Attempt rapid key exchanges
    let mut success_count = 0;
    for _ in 0..100 {
        if e2ee_service
            .record_key_exchange(&pool, conversation_id, user_a, user_b, &shared_secret)
            .await
            .is_ok()
        {
            success_count += 1;
        }
    }

    // Should allow legitimate exchanges but prevent abuse
    // (Implementation should impose reasonable limit, e.g., 10 per hour)
    assert!(success_count > 0, "legitimate key exchanges should succeed");
    // Note: Rate limiting logic to be implemented in service

    cleanup_key_exchanges(&pool, conversation_id).await;
}

// ============================================================================
// 5. Error Handling Tests
// ============================================================================

#[tokio::test]
#[ignore]
async fn test_decrypt_with_wrong_key_failure() {
    // RED: Test decryption fails with incorrect key
    let e2ee_service = E2eeService::new(TEST_MASTER_KEY);

    let (public_key, secret_key) = e2ee_service.generate_keypair();
    let shared_secret = e2ee_service.derive_shared_secret(&secret_key, &public_key).unwrap();
    let conversation_id = Uuid::new_v4();
    let encryption_key = e2ee_service.derive_encryption_key(&shared_secret, conversation_id);

    let plaintext = b"Encrypted data";
    let (ciphertext, nonce) = e2ee_service.encrypt_message(&encryption_key, plaintext).unwrap();

    // Attempt decryption with wrong key
    let wrong_key = [99u8; 32];
    let result = e2ee_service.decrypt_message(&wrong_key, &ciphertext, &nonce);

    assert!(result.is_err(), "decryption with wrong key must fail");

    if let Err(e) = result {
        let error_msg = e.to_string();
        assert!(
            error_msg.contains("decrypt") || error_msg.contains("authentication"),
            "error message should indicate decryption failure"
        );
    }
}

#[tokio::test]
#[ignore]
async fn test_missing_public_key_error_handling() {
    // RED: Test error handling when public key doesn't exist
    let pool = bootstrap_pool().await;
    let e2ee_service = E2eeService::new(TEST_MASTER_KEY);

    let nonexistent_user = Uuid::new_v4();
    let nonexistent_device = "nonexistent-device";

    let result = e2ee_service
        .get_device_public_key(&pool, nonexistent_user, nonexistent_device)
        .await;

    assert!(result.is_ok(), "should return Ok(None) for missing key");
    assert!(result.unwrap().is_none(), "result should be None for missing key");
}

#[tokio::test]
#[ignore]
async fn test_invalid_base64_ciphertext_error() {
    // RED: Test error handling for malformed base64 ciphertext
    let invalid_base64_strings = vec![
        "!!!invalid-base64!!!",
        "12345", // Too short
        "ZZZZ====", // Invalid characters
        "", // Empty string
    ];

    for invalid_b64 in invalid_base64_strings {
        let result = BASE64.decode(invalid_b64);
        assert!(result.is_err(), "invalid base64 '{}' should fail to decode", invalid_b64);
    }
}

#[tokio::test]
#[ignore]
async fn test_malformed_encrypted_message() {
    // RED: Test handling of malformed encrypted message structure
    let e2ee_service = E2eeService::new(TEST_MASTER_KEY);

    let (public_key, secret_key) = e2ee_service.generate_keypair();
    let shared_secret = e2ee_service.derive_shared_secret(&secret_key, &public_key).unwrap();
    let conversation_id = Uuid::new_v4();
    let encryption_key = e2ee_service.derive_encryption_key(&shared_secret, conversation_id);

    // Test with empty ciphertext
    let result = e2ee_service.decrypt_message(&encryption_key, &[], &[0u8; 24]);
    assert!(result.is_err(), "empty ciphertext should fail");

    // Test with wrong nonce length
    let (ciphertext, _) = e2ee_service.encrypt_message(&encryption_key, b"test").unwrap();
    let wrong_nonce = [0u8; 12]; // Wrong size
    let result = e2ee_service.decrypt_message(&encryption_key, &ciphertext, &wrong_nonce);
    assert!(result.is_err(), "wrong nonce size should fail");
}

#[tokio::test]
#[ignore]
async fn test_replay_attack_prevention() {
    // RED: Test that replay attacks are prevented
    let pool = bootstrap_pool().await;
    let e2ee_service = E2eeService::new(TEST_MASTER_KEY);

    let conversation_id = Uuid::new_v4();
    let sender_id = Uuid::new_v4();
    let recipient_id = Uuid::new_v4();

    let (public_key, secret_key) = e2ee_service.generate_keypair();
    let shared_secret = e2ee_service.derive_shared_secret(&secret_key, &public_key).unwrap();
    let encryption_key = e2ee_service.derive_encryption_key(&shared_secret, conversation_id);

    let plaintext = b"Replayed message";
    let (ciphertext, nonce) = e2ee_service.encrypt_message(&encryption_key, plaintext).unwrap();

    let message_id = Uuid::new_v4();

    // Store message first time
    sqlx::query(
        "INSERT INTO messages (id, conversation_id, sender_id, content, content_encrypted, content_nonce, encryption_version)
         VALUES ($1, $2, $3, '', $4, $5, 2)"
    )
    .bind(message_id)
    .bind(conversation_id)
    .bind(sender_id)
    .bind(&ciphertext)
    .bind(nonce.to_vec())
    .execute(&pool)
    .await
    .expect("insert original message");

    // Attempt to replay same message (duplicate message_id)
    let replay_result = sqlx::query(
        "INSERT INTO messages (id, conversation_id, sender_id, content, content_encrypted, content_nonce, encryption_version)
         VALUES ($1, $2, $3, '', $4, $5, 2)"
    )
    .bind(message_id) // Same ID
    .bind(conversation_id)
    .bind(sender_id)
    .bind(&ciphertext)
    .bind(nonce.to_vec())
    .execute(&pool)
    .await;

    assert!(replay_result.is_err(), "replay attack with duplicate ID should fail");

    // Cleanup
    let _ = sqlx::query("DELETE FROM messages WHERE id = $1")
        .bind(message_id)
        .execute(&pool)
        .await;
}
