use crate::error::AppError;
use crypto_core::jwt as core_jwt;

#[derive(Debug, Clone)]
pub struct Claims {
    pub sub: String, // subject - typically the user_id
    pub exp: i64,    // expiration time (unix timestamp)
}

/// Validate JWT signature and extract claims (RS256 only via crypto-core)
pub async fn verify_jwt(token: &str) -> Result<Claims, AppError> {
    // Use shared crypto-core to enforce RS256 without insecure fallbacks
    match core_jwt::validate_token(token) {
        Ok(token_data) => Ok(Claims {
            sub: token_data.claims.sub,
            exp: token_data.claims.exp,
        }),
        Err(_) => Err(AppError::Unauthorized),
    }
}
