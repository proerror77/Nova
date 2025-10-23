use crate::error::AppError;
use jsonwebtoken::{decode, DecodingKey, Validation};
use serde::Deserialize;
use std::env;

#[derive(Debug, Deserialize)]
struct Claims {
    // Minimal set for validation; extend with sub, roles, etc.
    exp: usize,
}

// Validate JWT signature and expiry; returns Ok(()) if valid, Err otherwise
pub async fn verify_jwt(token: &str) -> Result<(), AppError> {
    let secret = env::var("JWT_SECRET").unwrap_or_else(|_| "dev_secret_change_in_production_32chars".into());
    let key = DecodingKey::from_secret(secret.as_bytes());
    decode::<Claims>(token, &key, &Validation::default())
        .map(|_| ())
        .map_err(|_| AppError::Unauthorized("invalid token".into()))
}
