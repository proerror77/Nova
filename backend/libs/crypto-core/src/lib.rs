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

// E2E encryption using crypto::box_ (Curve25519XSalsa20Poly1305)
pub fn encrypt(plaintext: &[u8], recipient_public_key: &[u8], sender_secret_key: &[u8], nonce: &[u8]) -> Result<Vec<u8>, CryptoError> {
    sodiumoxide::init().map_err(|_| CryptoError::Encryption)?;
    use sodiumoxide::crypto::box_;
    let pk = box_::PublicKey::from_slice(recipient_public_key).ok_or(CryptoError::Encryption)?;
    let sk = box_::SecretKey::from_slice(sender_secret_key).ok_or(CryptoError::Encryption)?;
    let nonce = box_::Nonce::from_slice(nonce).ok_or(CryptoError::Encryption)?;
    Ok(box_::seal(plaintext, &nonce, &pk, &sk))
}

pub fn decrypt(ciphertext: &[u8], sender_public_key: &[u8], recipient_secret_key: &[u8], nonce: &[u8]) -> Result<Vec<u8>, CryptoError> {
    sodiumoxide::init().map_err(|_| CryptoError::Decryption)?;
    use sodiumoxide::crypto::box_;
    let pk = box_::PublicKey::from_slice(sender_public_key).ok_or(CryptoError::Decryption)?;
    let sk = box_::SecretKey::from_slice(recipient_secret_key).ok_or(CryptoError::Decryption)?;
    let nonce = box_::Nonce::from_slice(nonce).ok_or(CryptoError::Decryption)?;
    box_::open(ciphertext, &nonce, &pk, &sk).map_err(|_| CryptoError::Decryption)
}

// Symmetric secretbox for encryption-at-rest (server-side key)
pub fn encrypt_at_rest(plaintext: &[u8], key32: &[u8], nonce: &[u8]) -> Result<Vec<u8>, CryptoError> {
    sodiumoxide::init().map_err(|_| CryptoError::Encryption)?;
    use sodiumoxide::crypto::secretbox;
    let key = secretbox::Key::from_slice(key32).ok_or(CryptoError::Encryption)?;
    let nonce = secretbox::Nonce::from_slice(nonce).ok_or(CryptoError::Encryption)?;
    Ok(secretbox::seal(plaintext, &nonce, &key))
}

pub fn decrypt_at_rest(ciphertext: &[u8], key32: &[u8], nonce: &[u8]) -> Result<Vec<u8>, CryptoError> {
    sodiumoxide::init().map_err(|_| CryptoError::Decryption)?;
    use sodiumoxide::crypto::secretbox;
    let key = secretbox::Key::from_slice(key32).ok_or(CryptoError::Decryption)?;
    let nonce = secretbox::Nonce::from_slice(nonce).ok_or(CryptoError::Decryption)?;
    secretbox::open(ciphertext, &nonce, &key).map_err(|_| CryptoError::Decryption)
}
