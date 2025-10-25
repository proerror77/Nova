use crate::error::AppError;
use jsonwebtoken::{decode, DecodingKey, Validation, Algorithm};
use serde::Deserialize;
use std::env;
use uuid::Uuid;

#[derive(Debug, Deserialize)]
pub struct Claims {
    pub sub: String,  // subject - typically the user_id
    pub exp: usize,   // expiration time
}

/// Validate JWT signature and extract claims
pub async fn verify_jwt(token: &str) -> Result<Claims, AppError> {
    // Prefer RSA public key (RS256) verification if provided; fallback to HS256 secret if not
    if let Ok(pub_pem) = env::var("JWT_PUBLIC_KEY_PEM") {
        let key = DecodingKey::from_rsa_pem(pub_pem.as_bytes())
            .map_err(|_| AppError::Unauthorized)?;
        let validation = Validation::new(Algorithm::RS256);
        decode::<Claims>(token, &key, &validation)
            .map(|data| data.claims)
            .map_err(|_| AppError::Unauthorized)
    } else {
        let secret = env::var("JWT_SECRET").unwrap_or_else(|_| "dev_secret_change_in_production_32chars".into());
        let key = DecodingKey::from_secret(secret.as_bytes());
        decode::<Claims>(token, &key, &Validation::default())
            .map(|data| data.claims)
            .map_err(|_| AppError::Unauthorized)
    }
}

/// Middleware to extract JWT and add user_id to extensions
pub async fn auth_middleware(
    mut req: axum::extract::Request,
    next: axum::middleware::Next,
) -> Result<axum::response::Response, AppError> {
    // Extract Authorization header
    let auth_header = req
        .headers()
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|h| h.to_str().ok())
        .ok_or(AppError::Unauthorized)?;

    // Parse Bearer token
    let token = auth_header
        .strip_prefix("Bearer ")
        .ok_or(AppError::Unauthorized)?;

    // Verify JWT and extract claims
    let claims = verify_jwt(token).await?;

    // Parse user_id from claims.sub (should be a UUID)
    let user_id = Uuid::parse_str(&claims.sub)
        .map_err(|_| AppError::BadRequest("Invalid user_id in token".into()))?;

    // Add user_id to request extensions
    req.extensions_mut().insert(user_id);

    Ok(next.run(req).await)
}
