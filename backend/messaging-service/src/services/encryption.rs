use crate::error::AppError;
use crypto_core::{decrypt_at_rest, encrypt_at_rest, generate_nonce};
use hkdf::Hkdf;
use sha2::Sha256;
use uuid::Uuid;

/// Handles server-managed symmetric encryption derived from a master key.
#[derive(Clone)]
pub struct EncryptionService {
    master_key: [u8; 32],
}

impl EncryptionService {
    pub fn new(master_key: [u8; 32]) -> Self {
        Self { master_key }
    }

    pub fn conversation_key(&self, conversation_id: Uuid) -> [u8; 32] {
        self.derive_conversation_key(conversation_id)
    }

    fn derive_conversation_key(&self, conversation_id: Uuid) -> [u8; 32] {
        let hk = Hkdf::<Sha256>::new(None, &self.master_key);
        let mut key = [0u8; 32];
        hk.expand(conversation_id.as_bytes(), &mut key)
            .expect("HKDF expand must succeed for 32 byte output");
        key
    }

    pub fn encrypt(
        &self,
        conversation_id: Uuid,
        plaintext: &[u8],
    ) -> Result<(Vec<u8>, [u8; 24]), AppError> {
        let key = self.derive_conversation_key(conversation_id);
        let nonce = generate_nonce();
        let ciphertext =
            encrypt_at_rest(plaintext, &key, &nonce).map_err(|e| AppError::Encryption(e.to_string()))?;
        Ok((ciphertext, nonce))
    }

    pub fn decrypt(
        &self,
        conversation_id: Uuid,
        ciphertext: &[u8],
        nonce: &[u8],
    ) -> Result<Vec<u8>, AppError> {
        let key = self.derive_conversation_key(conversation_id);
        decrypt_at_rest(ciphertext, &key, nonce).map_err(|e| AppError::Encryption(e.to_string()))
    }
}
