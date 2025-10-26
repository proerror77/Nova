/// OAuth Token Encryption Service
///
/// Provides AES-256-GCM encryption/decryption for OAuth tokens.
///
/// This module handles secure token storage by encrypting OAuth access and refresh tokens
/// before storing them in the database. Encryption keys should be managed securely via:
/// - AWS KMS (recommended for production)
/// - HashiCorp Vault
/// - Environment variables (development only)
///
/// ## Encryption Format
///
/// Each encrypted token is stored as BYTEA with the following format:
/// - IV (12 bytes): Initialization vector for GCM
/// - Ciphertext (variable): Encrypted token
/// - Tag (16 bytes): Authentication tag
///
/// The IV is randomly generated for each encryption to ensure security even when
/// encrypting the same token multiple times.
use aes_gcm::{
    aead::{Aead, KeyInit, Payload},
    Aes256Gcm, Nonce,
};
use base64::engine::{general_purpose::STANDARD, Engine};
use rand::Rng;
use thiserror::Error;

/// Token encryption errors
#[derive(Debug, Error)]
pub enum TokenEncryptionError {
    #[error("Encryption failed: {0}")]
    EncryptionFailed(String),

    #[error("Decryption failed: {0}")]
    DecryptionFailed(String),

    #[error("Invalid key length: {0}")]
    InvalidKeyLength(String),

    #[error("Invalid encryption key: {0}")]
    InvalidKey(String),

    #[error("Missing encryption key")]
    MissingKey,
}

/// Token encryption service
pub struct TokenEncryptionService {
    /// AES-256-GCM cipher
    cipher: Aes256Gcm,
}

impl TokenEncryptionService {
    /// Create a new token encryption service from a base64-encoded 256-bit key
    ///
    /// # Arguments
    /// * `key_base64` - Base64-encoded 256-bit (32-byte) encryption key
    ///
    /// # Returns
    /// A new TokenEncryptionService instance
    pub fn new(key_base64: &str) -> Result<Self, TokenEncryptionError> {
        // Decode base64 key
        let key_bytes = STANDARD.decode(key_base64).map_err(|e| {
            TokenEncryptionError::InvalidKey(format!("Failed to decode base64: {}", e))
        })?;

        // Verify key length (must be 32 bytes for AES-256)
        if key_bytes.len() != 32 {
            return Err(TokenEncryptionError::InvalidKeyLength(format!(
                "Key must be 32 bytes (256 bits), got {} bytes",
                key_bytes.len()
            )));
        }

        // Create cipher from key
        let key = aes_gcm::Key::<Aes256Gcm>::from_slice(&key_bytes);
        let cipher = Aes256Gcm::new(key);

        Ok(Self { cipher })
    }

    /// Create a new encryption service from environment variable
    ///
    /// Looks for `OAUTH_TOKEN_ENCRYPTION_KEY` environment variable containing
    /// a base64-encoded 256-bit key.
    pub fn from_env() -> Result<Self, TokenEncryptionError> {
        let key_base64 = std::env::var("OAUTH_TOKEN_ENCRYPTION_KEY")
            .map_err(|_| TokenEncryptionError::MissingKey)?;
        Self::new(&key_base64)
    }

    /// Encrypt an OAuth token
    ///
    /// # Arguments
    /// * `token` - The token string to encrypt
    ///
    /// # Returns
    /// Encrypted bytes in format: [IV (12 bytes)][Ciphertext][Tag (16 bytes)]
    pub fn encrypt(&self, token: &str) -> Result<Vec<u8>, TokenEncryptionError> {
        // Generate random 12-byte nonce (IV)
        let mut rng = rand::thread_rng();
        let nonce_bytes: [u8; 12] = rng.gen();
        let nonce = Nonce::from_slice(&nonce_bytes);

        // Encrypt token
        let ciphertext = self
            .cipher
            .encrypt(nonce, Payload::from(token.as_bytes()))
            .map_err(|e| {
                TokenEncryptionError::EncryptionFailed(format!("AES-GCM failed: {}", e))
            })?;

        // Combine: IV + Ciphertext
        let mut result = Vec::with_capacity(12 + ciphertext.len());
        result.extend_from_slice(&nonce_bytes);
        result.extend_from_slice(&ciphertext);

        Ok(result)
    }

    /// Decrypt an OAuth token
    ///
    /// # Arguments
    /// * `encrypted` - Encrypted bytes in format: [IV (12 bytes)][Ciphertext][Tag (16 bytes)]
    ///
    /// # Returns
    /// Decrypted token string
    pub fn decrypt(&self, encrypted: &[u8]) -> Result<String, TokenEncryptionError> {
        // Verify minimum length (12 bytes IV + 16 bytes tag)
        if encrypted.len() < 28 {
            return Err(TokenEncryptionError::DecryptionFailed(
                "Encrypted data too short".to_string(),
            ));
        }

        // Extract IV (first 12 bytes)
        let nonce = Nonce::from_slice(&encrypted[..12]);

        // Extract ciphertext (remaining bytes)
        let ciphertext = &encrypted[12..];

        // Decrypt
        let plaintext = self
            .cipher
            .decrypt(nonce, Payload::from(ciphertext))
            .map_err(|e| {
                TokenEncryptionError::DecryptionFailed(format!("AES-GCM failed: {}", e))
            })?;

        // Convert to string
        String::from_utf8(plaintext)
            .map_err(|e| TokenEncryptionError::DecryptionFailed(format!("Invalid UTF-8: {}", e)))
    }
}

/// Generate a random 256-bit encryption key encoded in base64
///
/// Useful for generating new encryption keys. The output can be stored in
/// environment variables or key management systems.
pub fn generate_encryption_key() -> String {
    let mut rng = rand::thread_rng();
    let key_bytes: [u8; 32] = rng.gen();
    STANDARD.encode(&key_bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_encryption_key() {
        let key = generate_encryption_key();
        assert!(!key.is_empty());
        // Base64 encoded 32 bytes should be ~43 characters
        assert!(key.len() > 40);
    }

    #[test]
    fn test_encrypt_decrypt_roundtrip() {
        let key = generate_encryption_key();
        let service = TokenEncryptionService::new(&key).unwrap();

        let token = "test_oauth_token_12345";
        let encrypted = service.encrypt(token).unwrap();
        let decrypted = service.decrypt(&encrypted).unwrap();

        assert_eq!(token, decrypted);
    }

    #[test]
    fn test_encrypt_produces_different_ciphertexts() {
        let key = generate_encryption_key();
        let service = TokenEncryptionService::new(&key).unwrap();

        let token = "same_token";
        let encrypted1 = service.encrypt(token).unwrap();
        let encrypted2 = service.encrypt(token).unwrap();

        // Same token encrypted twice should produce different ciphertexts
        // (due to random nonce)
        assert_ne!(encrypted1, encrypted2);

        // But both should decrypt to the same token
        assert_eq!(service.decrypt(&encrypted1).unwrap(), token);
        assert_eq!(service.decrypt(&encrypted2).unwrap(), token);
    }

    #[test]
    fn test_decrypt_various_tokens() {
        let key = generate_encryption_key();
        let service = TokenEncryptionService::new(&key).unwrap();

        let tokens = vec![
            "short",
            "medium_length_token",
            "very_long_token_with_many_characters_and_special_chars_!@#$%",
            "token_with_unicode_αβγδ",
        ];

        for token in tokens {
            let encrypted = service.encrypt(token).unwrap();
            let decrypted = service.decrypt(&encrypted).unwrap();
            assert_eq!(token, decrypted, "Failed for token: {}", token);
        }
    }

    #[test]
    fn test_invalid_key_length() {
        let short_key = STANDARD.encode("too_short");
        let result = TokenEncryptionService::new(&short_key);
        assert!(result.is_err());
    }

    #[test]
    fn test_invalid_base64() {
        let invalid_base64 = "not@valid@base64!!!";
        let result = TokenEncryptionService::new(invalid_base64);
        assert!(result.is_err());
    }

    #[test]
    fn test_decrypt_corrupted_data() {
        let key = generate_encryption_key();
        let service = TokenEncryptionService::new(&key).unwrap();

        // Create corrupted encrypted data
        let mut corrupted = service.encrypt("test").unwrap();
        // Flip some bits in the ciphertext
        if corrupted.len() > 12 {
            corrupted[13] ^= 0xFF;
        }

        let result = service.decrypt(&corrupted);
        assert!(result.is_err());
    }

    #[test]
    fn test_multiple_services_same_key() {
        let key = generate_encryption_key();
        let service1 = TokenEncryptionService::new(&key).unwrap();
        let service2 = TokenEncryptionService::new(&key).unwrap();

        let token = "test_token";
        let encrypted = service1.encrypt(token).unwrap();

        // Different service instance with same key should decrypt correctly
        let decrypted = service2.decrypt(&encrypted).unwrap();
        assert_eq!(token, decrypted);
    }

    #[test]
    fn test_different_keys_incompatible() {
        let key1 = generate_encryption_key();
        let key2 = generate_encryption_key();

        let service1 = TokenEncryptionService::new(&key1).unwrap();
        let service2 = TokenEncryptionService::new(&key2).unwrap();

        let token = "test_token";
        let encrypted = service1.encrypt(token).unwrap();

        // Decryption with different key should fail
        let result = service2.decrypt(&encrypted);
        assert!(result.is_err());
    }
}
