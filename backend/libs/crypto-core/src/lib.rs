use rand::{rngs::OsRng, RngCore};
use std::os::raw::{c_uchar, c_ulong};
use std::ptr;
use std::slice;

#[derive(Debug, thiserror::Error)]
pub enum CryptoError {
    #[error("encryption error")]
    Encryption,
    #[error("decryption error")]
    Decryption,
    #[error("key generation error")]
    KeyGeneration,
}

pub fn generate_nonce() -> [u8; 24] {
    let mut nonce = [0u8; 24];
    OsRng.fill_bytes(&mut nonce);
    nonce
}

// X25519 ECDH key exchange for E2EE
pub fn generate_x25519_keypair() -> Result<([u8; 32], [u8; 32]), CryptoError> {
    sodiumoxide::init().map_err(|_| CryptoError::KeyGeneration)?;
    use sodiumoxide::crypto::box_::curve25519xsalsa20poly1305::gen_keypair;

    let (public_key, secret_key) = gen_keypair();

    Ok((public_key.0, secret_key.0))
}

pub fn x25519_derive_shared_secret(
    our_secret_key: &[u8; 32],
    their_public_key: &[u8; 32],
) -> Result<[u8; 32], CryptoError> {
    sodiumoxide::init().map_err(|_| CryptoError::Encryption)?;
    use sodiumoxide::crypto::box_::curve25519xsalsa20poly1305::{precompute, PublicKey, SecretKey};

    let pk = PublicKey(*their_public_key);
    let sk = SecretKey(*our_secret_key);

    let shared_secret = precompute(&pk, &sk);

    // Extract the shared secret bytes (32 bytes)
    Ok(shared_secret.0)
}

// E2E encryption using crypto::box_ (Curve25519XSalsa20Poly1305)
pub fn encrypt(
    plaintext: &[u8],
    recipient_public_key: &[u8],
    sender_secret_key: &[u8],
    nonce: &[u8],
) -> Result<Vec<u8>, CryptoError> {
    sodiumoxide::init().map_err(|_| CryptoError::Encryption)?;
    use sodiumoxide::crypto::box_;
    let pk = box_::PublicKey::from_slice(recipient_public_key).ok_or(CryptoError::Encryption)?;
    let sk = box_::SecretKey::from_slice(sender_secret_key).ok_or(CryptoError::Encryption)?;
    let nonce = box_::Nonce::from_slice(nonce).ok_or(CryptoError::Encryption)?;
    Ok(box_::seal(plaintext, &nonce, &pk, &sk))
}

pub fn decrypt(
    ciphertext: &[u8],
    sender_public_key: &[u8],
    recipient_secret_key: &[u8],
    nonce: &[u8],
) -> Result<Vec<u8>, CryptoError> {
    sodiumoxide::init().map_err(|_| CryptoError::Decryption)?;
    use sodiumoxide::crypto::box_;
    let pk = box_::PublicKey::from_slice(sender_public_key).ok_or(CryptoError::Decryption)?;
    let sk = box_::SecretKey::from_slice(recipient_secret_key).ok_or(CryptoError::Decryption)?;
    let nonce = box_::Nonce::from_slice(nonce).ok_or(CryptoError::Decryption)?;
    box_::open(ciphertext, &nonce, &pk, &sk).map_err(|_| CryptoError::Decryption)
}

// Symmetric secretbox for encryption-at-rest (server-side key)
pub fn encrypt_at_rest(
    plaintext: &[u8],
    key32: &[u8],
    nonce: &[u8],
) -> Result<Vec<u8>, CryptoError> {
    sodiumoxide::init().map_err(|_| CryptoError::Encryption)?;
    use sodiumoxide::crypto::secretbox;
    let key = secretbox::Key::from_slice(key32).ok_or(CryptoError::Encryption)?;
    let nonce = secretbox::Nonce::from_slice(nonce).ok_or(CryptoError::Encryption)?;
    Ok(secretbox::seal(plaintext, &nonce, &key))
}

pub fn decrypt_at_rest(
    ciphertext: &[u8],
    key32: &[u8],
    nonce: &[u8],
) -> Result<Vec<u8>, CryptoError> {
    sodiumoxide::init().map_err(|_| CryptoError::Decryption)?;
    use sodiumoxide::crypto::secretbox;
    let key = secretbox::Key::from_slice(key32).ok_or(CryptoError::Decryption)?;
    let nonce = secretbox::Nonce::from_slice(nonce).ok_or(CryptoError::Decryption)?;
    secretbox::open(ciphertext, &nonce, &key).map_err(|_| CryptoError::Decryption)
}

// Expose JWT utilities (RS256-only) for services
pub mod jwt;

// =============================
// C FFI (for iOS xcframework)
// =============================

#[no_mangle]
pub extern "C" fn cryptocore_generate_nonce(out_buf: *mut c_uchar, out_len: c_ulong) -> c_ulong {
    let len = out_len as usize;
    if out_buf.is_null() || len < 24 {
        return 0;
    }
    let nonce = generate_nonce();
    unsafe {
        ptr::copy_nonoverlapping(nonce.as_ptr(), out_buf, 24);
    }
    24
}

#[no_mangle]
pub extern "C" fn cryptocore_encrypt(
    plaintext_ptr: *const c_uchar,
    plaintext_len: c_ulong,
    recipient_pk_ptr: *const c_uchar,
    recipient_pk_len: c_ulong,
    sender_sk_ptr: *const c_uchar,
    sender_sk_len: c_ulong,
    nonce_ptr: *const c_uchar,
    nonce_len: c_ulong,
    out_len_ptr: *mut c_ulong,
) -> *mut c_uchar {
    let pt = unsafe { slice::from_raw_parts(plaintext_ptr, plaintext_len as usize) };
    let rpk = unsafe { slice::from_raw_parts(recipient_pk_ptr, recipient_pk_len as usize) };
    let ssk = unsafe { slice::from_raw_parts(sender_sk_ptr, sender_sk_len as usize) };
    let nonce = unsafe { slice::from_raw_parts(nonce_ptr, nonce_len as usize) };
    match encrypt(pt, rpk, ssk, nonce) {
        Ok(ct) => {
            let mut v = ct;
            let len = v.len() as c_ulong;
            unsafe {
                if !out_len_ptr.is_null() {
                    *out_len_ptr = len;
                }
            }
            let ptr = v.as_mut_ptr();
            std::mem::forget(v);
            ptr
        }
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn cryptocore_decrypt(
    ciphertext_ptr: *const c_uchar,
    ciphertext_len: c_ulong,
    sender_pk_ptr: *const c_uchar,
    sender_pk_len: c_ulong,
    recipient_sk_ptr: *const c_uchar,
    recipient_sk_len: c_ulong,
    nonce_ptr: *const c_uchar,
    nonce_len: c_ulong,
    out_len_ptr: *mut c_ulong,
) -> *mut c_uchar {
    let ct = unsafe { slice::from_raw_parts(ciphertext_ptr, ciphertext_len as usize) };
    let spk = unsafe { slice::from_raw_parts(sender_pk_ptr, sender_pk_len as usize) };
    let rsk = unsafe { slice::from_raw_parts(recipient_sk_ptr, recipient_sk_len as usize) };
    let nonce = unsafe { slice::from_raw_parts(nonce_ptr, nonce_len as usize) };
    match decrypt(ct, spk, rsk, nonce) {
        Ok(pt) => {
            let mut v = pt;
            let len = v.len() as c_ulong;
            unsafe {
                if !out_len_ptr.is_null() {
                    *out_len_ptr = len;
                }
            }
            let ptr = v.as_mut_ptr();
            std::mem::forget(v);
            ptr
        }
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn cryptocore_free(buf_ptr: *mut c_uchar, buf_len: c_ulong) {
    if buf_ptr.is_null() {
        return;
    }
    unsafe {
        let _ = Vec::from_raw_parts(buf_ptr, buf_len as usize, buf_len as usize);
    }
}
