use crate::error::AppError;
use crypto_core::jwt as core_jwt;
use uuid::Uuid;

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

/// Middleware to extract JWT and add user_id to extensions
pub async fn auth_middleware(
    mut req: axum::extract::Request,
    next: axum::middleware::Next,
) -> Result<axum::response::Response, AppError> {
    // Allow unauthenticated access to introspection endpoints
    let path = req.uri().path();
    if matches!(
        path,
        "/health" | "/metrics" | "/openapi.json" | "/swagger-ui" | "/docs"
    ) {
        return Ok(next.run(req).await);
    }
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
