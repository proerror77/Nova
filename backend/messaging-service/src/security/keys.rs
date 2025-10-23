use base64::{engine::general_purpose, Engine as _};

pub fn secretbox_key_from_env() -> Result<[u8;32], crate::error::AppError> {
    let b64 = std::env::var("SECRETBOX_KEY_B64")
        .map_err(|_| crate::error::AppError::Config("SECRETBOX_KEY_B64 missing".into()))?;
    let bytes = general_purpose::STANDARD
        .decode(b64)
        .map_err(|_| crate::error::AppError::Config("invalid base64 SECRETBOX_KEY_B64".into()))?;
    if bytes.len() != 32 {
        return Err(crate::error::AppError::Config("SECRETBOX_KEY_B64 must be 32 bytes key".into()));
    }
    let mut key = [0u8; 32];
    key.copy_from_slice(&bytes);
    Ok(key)
}

