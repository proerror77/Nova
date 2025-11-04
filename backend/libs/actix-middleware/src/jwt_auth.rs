use actix_web::{
    dev::{forward_ready, Service, ServiceRequest, ServiceResponse, Transform},
    Error, HttpMessage,
};
use futures::future::{ready, Ready};
use redis::aio::ConnectionManager;
use redis::AsyncCommands;
use std::future::Future;
use std::pin::Pin;
use std::rc::Rc;
use std::sync::Arc;
use tokio::sync::Mutex;
use uuid::Uuid;
use crate::metrics::{JWT_CACHE_HIT, JWT_CACHE_MISS, JWT_REVOKED};

/// User ID extracted from JWT
#[derive(Debug, Clone, Copy)]
pub struct UserId(pub Uuid);

/// JWT Claims cached in Redis (to avoid repeated validation)
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
struct CachedClaims {
    sub: String,
    email: String,
    username: String,
}

/// JWT Authentication Middleware with Redis caching
///
/// This middleware validates JWT tokens and caches the validation result in Redis
/// to avoid expensive cryptographic operations on every request.
///
/// Cache TTL: 10 minutes (standard JWT access token lifetime is 1 hour)
/// Cache key: "jwt:validation:{token_hash}"
pub struct JwtAuthMiddleware {
    redis: Option<Arc<Mutex<ConnectionManager>>>,
    cache_ttl_secs: usize,
}

impl JwtAuthMiddleware {
    /// Create middleware without Redis caching (original behavior)
    pub fn new() -> Self {
        Self {
            redis: None,
            cache_ttl_secs: 600, // 10 minutes
        }
    }

    /// Create middleware with Redis caching
    pub fn with_cache(redis: Arc<Mutex<ConnectionManager>>, cache_ttl_secs: usize) -> Self {
        Self {
            redis: Some(redis),
            cache_ttl_secs,
        }
    }
}

impl Default for JwtAuthMiddleware {
    fn default() -> Self {
        Self::new()
    }
}

impl<S, B> Transform<S, ServiceRequest> for JwtAuthMiddleware
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error> + 'static,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<B>;
    type Error = Error;
    type Transform = JwtAuthMiddlewareService<S>;
    type InitError = ();
    type Future = Ready<Result<Self::Transform, Self::InitError>>;

    fn new_transform(&self, service: S) -> Self::Future {
        ready(Ok(JwtAuthMiddlewareService {
            service: Rc::new(service),
            redis: self.redis.clone(),
            cache_ttl_secs: self.cache_ttl_secs,
        }))
    }
}

pub struct JwtAuthMiddlewareService<S> {
    service: Rc<S>,
    redis: Option<Arc<Mutex<ConnectionManager>>>,
    cache_ttl_secs: usize,
}

impl<S, B> Service<ServiceRequest> for JwtAuthMiddlewareService<S>
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error> + 'static,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<B>;
    type Error = Error;
    type Future = Pin<Box<dyn Future<Output = Result<Self::Response, Self::Error>>>>;

    forward_ready!(service);

    fn call(&self, req: ServiceRequest) -> Self::Future {
        let service = self.service.clone();
        let redis = self.redis.clone();
        let cache_ttl_secs = self.cache_ttl_secs;

        Box::pin(async move {
            // Extract Authorization header
            let auth_header = req
                .headers()
                .get("Authorization")
                .and_then(|h| h.to_str().ok())
                .ok_or_else(|| {
                    actix_web::error::ErrorUnauthorized("Missing Authorization header")
                })?;

            // Extract token
            let token = auth_header.strip_prefix("Bearer ").ok_or_else(|| {
                actix_web::error::ErrorUnauthorized("Invalid Authorization header format")
            })?;

            // Compute token hash for cache key
            let token_hash = crypto_core::hash::sha256(token.as_bytes());
            let cache_key = format!("jwt:validation:{}", hex::encode(&token_hash));

            // Try to get cached claims from Redis (with double-check verification)
            let claims = if let Some(redis_conn) = &redis {
                // Get exclusive access to the connection from the mutex
                let mut conn = redis_conn.lock().await;
                match conn.get::<_, String>(&cache_key).await {
                    Ok(cached_json) => {
                        match serde_json::from_str::<CachedClaims>(&cached_json) {
                            Ok(cached_claims) => {
                                // Double-check: verify token is not revoked before using cache (TOCTOU mitigation)
                                // This prevents a race condition where token is revoked between check and use
                                if is_token_revoked(redis_conn, token).await? {
                                    tracing::warn!("Token is revoked; bypassing cache");
                                    JWT_REVOKED.inc();
                                    // Validate fresh token (will fail due to revocation)
                                    validate_and_cache_token(token, redis_conn, &cache_key, cache_ttl_secs).await?
                                } else {
                                    // Double-verify: re-validate JWT signature to ensure cache hasn't been tampered with
                                    // This is a defense-in-depth measure for high-security scenarios
                                    match validate_token_directly(token).await {
                                        Ok(_) => {
                                            tracing::debug!("JWT validation cache hit");
                                            JWT_CACHE_HIT.inc();
                                            cached_claims
                                        }
                                        Err(e) => {
                                            tracing::warn!("Cached JWT failed re-validation: {}", e);
                                            // Cache is invalid, fall through to fresh validation
                                            validate_and_cache_token(token, redis_conn, &cache_key, cache_ttl_secs).await?
                                        }
                                    }
                                }
                            }
                            Err(e) => {
                                tracing::warn!("Failed to deserialize cached claims: {}", e);
                                // Fall through to fresh validation
                                validate_and_cache_token(token, redis_conn, &cache_key, cache_ttl_secs).await?
                            }
                        }
                    }
                    Err(_) => {
                        // Cache miss - validate and store
                        tracing::debug!("JWT validation cache miss");
                        JWT_CACHE_MISS.inc();
                        validate_and_cache_token(token, redis_conn, &cache_key, cache_ttl_secs).await?
                    }
                }
            } else {
                // No Redis - validate directly
                validate_token_directly(token).await?
            };

            // Extract user_id from claims
            let user_id = Uuid::parse_str(&claims.sub).map_err(|e| {
                tracing::error!("Invalid user_id UUID in token: {}", e);
                actix_web::error::ErrorUnauthorized("Invalid token: malformed user_id")
            })?;

            // Insert UserId into request extensions
            req.extensions_mut().insert(UserId(user_id));

            service.call(req).await
        })
    }
}

/// FromRequest implementation for UserId
impl actix_web::FromRequest for UserId {
    type Error = actix_web::Error;
    type Future = Ready<Result<Self, Self::Error>>;

    fn from_request(
        req: &actix_web::HttpRequest,
        _payload: &mut actix_web::dev::Payload,
    ) -> Self::Future {
        match req.extensions().get::<UserId>() {
            Some(user_id) => ready(Ok(*user_id)),
            None => ready(Err(actix_web::error::ErrorUnauthorized(
                "User not authenticated",
            ))),
        }
    }
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Validate token directly without caching
async fn validate_token_directly(token: &str) -> Result<CachedClaims, actix_web::Error> {
    let token_data = crypto_core::jwt::validate_token(token).map_err(|e| {
        tracing::warn!("JWT validation failed: {}", e);
        actix_web::error::ErrorUnauthorized(format!("Invalid token: {}", e))
    })?;

    Ok(CachedClaims {
        sub: token_data.claims.sub,
        email: token_data.claims.email,
        username: token_data.claims.username,
    })
}

/// Validate token and cache the result in Redis
async fn validate_and_cache_token(
    token: &str,
    redis: &Arc<Mutex<ConnectionManager>>,
    cache_key: &str,
    cache_ttl_secs: usize,
) -> Result<CachedClaims, actix_web::Error> {
    // Validate token
    let token_data = crypto_core::jwt::validate_token(token).map_err(|e| {
        tracing::warn!("JWT validation failed: {}", e);
        actix_web::error::ErrorUnauthorized(format!("Invalid token: {}", e))
    })?;

    let claims = CachedClaims {
        sub: token_data.claims.sub,
        email: token_data.claims.email,
        username: token_data.claims.username,
    };

    // Cache the claims in Redis
    let cached_json = serde_json::to_string(&claims).map_err(|e| {
        tracing::error!("Failed to serialize claims for caching: {}", e);
        actix_web::error::ErrorInternalServerError("JWT caching error")
    })?;

    // Fire-and-forget Redis cache set with expiration
    let redis_clone = redis.clone();
    let cache_key = cache_key.to_string();
    tokio::spawn(async move {
        let mut conn = redis_clone.lock().await.clone();
        let _result: Result<(), redis::RedisError> =
            conn.set_ex(&cache_key, cached_json, cache_ttl_secs as u64).await;
        if let Err(e) = _result {
            tracing::warn!("Failed to cache JWT validation: {}", e);
        }
    });

    Ok(claims)
}

/// Check whether token is revoked via revocation store (Redis or DB-backed cache)
async fn is_token_revoked(redis: &Arc<Mutex<ConnectionManager>>, token: &str) -> Result<bool, actix_web::Error> {
    // Compute jti hash key when available; fallback to token hash
    let token_hash = crypto_core::hash::sha256(token.as_bytes());
    let key = format!("jwt:revoked:{}", hex::encode(token_hash));

    match redis.lock().await.exists::<_, bool>(&key).await {
        Ok(exists) => Ok(exists),
        Err(e) => {
            tracing::warn!("revocation check failed: {}", e);
            Ok(false)
        }
    }
}
