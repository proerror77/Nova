use rand::{rngs::OsRng, RngCore};

#[derive(Debug, thiserror::Error)]
pub enum CryptoError {
    #[error("encryption error")] Encryption,
    #[error("decryption error")] Decryption,
}

pub fn generate_nonce() -> [u8; 24] {
    let mut nonce = [0u8; 24];
    OsRng.fill_bytes(&mut nonce);
    nonce
}

pub fn encrypt(plaintext: &[u8], _recipient_public_key: &[u8], _sender_secret_key: &[u8], _nonce: &[u8]) -> Result<Vec<u8>, CryptoError> {
    // Stub: echo encryption; replace with libsodium/NaCl box in implementation
    Ok(plaintext.to_vec())
}

pub fn decrypt(ciphertext: &[u8], _sender_public_key: &[u8], _recipient_secret_key: &[u8], _nonce: &[u8]) -> Result<Vec<u8>, CryptoError> {
    // Stub: echo decryption
    Ok(ciphertext.to_vec())
}

