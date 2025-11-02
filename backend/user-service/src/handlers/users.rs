use crate::cache::{get_cached_user, invalidate_user_cache, set_cached_user, CachedUser};
use actix_web::{web, HttpMessage, HttpRequest, HttpResponse, Responder};
use base64::engine::general_purpose;
use base64::Engine;
use redis::aio::ConnectionManager;
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use uuid::Uuid;

use crate::db::user_repo;
use crate::grpc::nova::auth::v1::UserProfile as ProtoUserProfile;
use crate::grpc::{AuthServiceClient, UserProfileUpdate};
use crate::middleware::UserId;
use crate::models::{UpdateUserProfileRequest, UserProfile};

#[derive(Debug, Serialize)]
pub struct PublicUser {
    pub id: Uuid,
    pub username: String,
    pub email: String,
    pub display_name: Option<String>,
    pub bio: Option<String>,
    pub avatar_url: Option<String>,
    pub is_verified: bool,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

/// GET /api/v1/users/{id}
/// With Redis caching for improved performance
pub async fn get_user(
    path: web::Path<String>,
    pool: web::Data<PgPool>,
    req: HttpRequest,
    redis: Option<web::Data<ConnectionManager>>,
) -> impl Responder {
    let id = match Uuid::parse_str(&path.into_inner()) {
        Ok(id) => id,
        Err(e) => {
            return HttpResponse::BadRequest().json(serde_json::json!({
                "error": "Invalid user id",
                "details": e.to_string()
            }))
        }
    };

    // Try to get user from cache first
    if let Some(redis_mgr) = redis.as_ref() {
        if let Ok(Some(cached_user)) = get_cached_user(redis_mgr.get_ref(), id).await {
            // Return cached user
            return HttpResponse::Ok().json(PublicUser {
                id: cached_user.id,
                username: cached_user.username,
                email: String::new(), // Cache doesn't store email
                display_name: cached_user.display_name,
                bio: cached_user.bio,
                avatar_url: cached_user.avatar_url,
                is_verified: cached_user.email_verified,
                created_at: chrono::Utc::now(), // Approximate
            });
        }
    }

    match user_repo::find_by_id(pool.get_ref(), id).await {
        Ok(Some(u)) => {
            // Cache the user after fetching
            if let Some(redis_mgr) = redis.as_ref() {
                let cached: CachedUser = u.clone().into();
                let _ = set_cached_user(redis_mgr.get_ref(), &cached).await;
            }
            // Check if the requester is blocked by or has blocked the target user
            if let Some(requester) = req.extensions().get::<UserId>() {
                let requester_id = requester.0;

                // OPTIMIZED: Single query for bidirectional block check
                let is_blocked = user_repo::are_blocked(pool.get_ref(), requester_id, id)
                    .await
                    .unwrap_or(false);

                if is_blocked {
                    return HttpResponse::Forbidden().json(serde_json::json!({
                        "error": "User not accessible"
                    }));
                }

                // Check if account is private and requester is not the owner
                if u.private_account && requester_id != id {
                    // For private accounts, only show limited info to non-owner non-follower
                    return HttpResponse::Ok().json(PublicUser {
                        id: u.id,
                        username: u.username,
                        email: String::new(), // Don't expose email
                        display_name: u.display_name,
                        bio: u.bio,
                        avatar_url: u.avatar_url,
                        is_verified: u.email_verified,
                        created_at: u.created_at,
                    });
                }
            }

            HttpResponse::Ok().json(PublicUser {
                id: u.id,
                username: u.username,
                email: u.email,
                display_name: u.display_name,
                bio: u.bio,
                avatar_url: u.avatar_url,
                is_verified: u.email_verified,
                created_at: u.created_at,
            })
        }
        Ok(None) => HttpResponse::NotFound().finish(),
        Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({
            "error": "Database error",
            "details": e.to_string()
        })),
    }
}

// ==============================
// Public Key Endpoints (E2E)
// ==============================

#[derive(Debug, Deserialize)]
pub struct UpsertPublicKeyRequest {
    pub public_key: String,
}

/// PUT /api/v1/users/me/public-key
pub async fn upsert_my_public_key(
    auth_client: web::Data<AuthServiceClient>,
    user: UserId,
    body: web::Json<UpsertPublicKeyRequest>,
) -> impl Responder {
    // Validate format: base64-encoded 32 bytes (NaCl public key)
    if let Err(_) = general_purpose::STANDARD.decode(&body.public_key) {
        return HttpResponse::BadRequest().json(serde_json::json!({
            "error": "Invalid public key format - must be valid base64"
        }));
    }
    if let Ok(decoded) = general_purpose::STANDARD.decode(&body.public_key) {
        if decoded.len() != 32 {
            return HttpResponse::BadRequest().json(serde_json::json!({
                "error": "Invalid public key length - must be 32 bytes"
            }));
        }
    }

    match auth_client
        .upsert_public_key(user.0, &body.public_key)
        .await
    {
        Ok(_) => HttpResponse::NoContent().finish(),
        Err(e) => {
            tracing::error!(user_id=%user.0, error=%e, "Failed to upsert public key via auth-service");
            HttpResponse::BadGateway().json(serde_json::json!({
                "error": "Failed to persist public key",
                "details": e.message().to_string()
            }))
        }
    }
}

#[derive(Debug, Serialize)]
pub struct PublicKeyResponse {
    pub public_key: String,
}

/// GET /api/v1/users/{id}/public-key
pub async fn get_user_public_key(
    path: web::Path<String>,
    auth_client: web::Data<AuthServiceClient>,
) -> impl Responder {
    let id = match Uuid::parse_str(&path.into_inner()) {
        Ok(id) => id,
        Err(e) => {
            return HttpResponse::BadRequest().json(serde_json::json!({
                "error": "Invalid user id",
                "details": e.to_string()
            }))
        }
    };

    match auth_client.get_public_key(id).await {
        Ok(Some(pk)) => HttpResponse::Ok().json(PublicKeyResponse { public_key: pk }),
        Ok(None) => HttpResponse::NotFound().finish(),
        Err(e) => {
            tracing::error!(user_id=%id, error=%e, "Failed to fetch public key from auth-service");
            HttpResponse::BadGateway().json(serde_json::json!({
                "error": "Failed to fetch public key",
                "details": e.message().to_string()
            }))
        }
    }
}

/// PATCH /api/v1/users/me
pub async fn update_profile(
    http_req: HttpRequest,
    auth_client: web::Data<AuthServiceClient>,
    req: web::Json<UpdateUserProfileRequest>,
    redis: Option<web::Data<ConnectionManager>>,
) -> impl Responder {
    let user_id = match http_req.extensions().get::<UserId>() {
        Some(user_id_wrapper) => user_id_wrapper.0,
        None => {
            return HttpResponse::Unauthorized().json(serde_json::json!({
                "error": "Unauthorized",
                "details": "User ID not found in request"
            }))
        }
    };

    // Validate field lengths
    if let Some(ref display_name) = req.display_name {
        if display_name.len() > 100 {
            return HttpResponse::BadRequest().json(serde_json::json!({
                "error": "Display name exceeds maximum length of 100 characters"
            }));
        }
    }

    if let Some(ref bio) = req.bio {
        if bio.len() > 500 {
            return HttpResponse::BadRequest().json(serde_json::json!({
                "error": "Bio exceeds maximum length of 500 characters"
            }));
        }
    }

    if let Some(ref location) = req.location {
        if location.len() > 100 {
            return HttpResponse::BadRequest().json(serde_json::json!({
                "error": "Location exceeds maximum length of 100 characters"
            }));
        }
    }

    let payload = UserProfileUpdate {
        display_name: req.display_name.as_deref(),
        bio: req.bio.as_deref(),
        avatar_url: req.avatar_url.as_deref(),
        cover_photo_url: req.cover_photo_url.as_deref(),
        location: req.location.as_deref(),
        private_account: req.private_account,
    };

    match auth_client.update_user_profile(user_id, payload).await {
        Ok(profile) => {
            if let Some(redis_mgr) = redis.as_ref() {
                let _ = invalidate_user_cache(redis_mgr.get_ref(), user_id).await;
            }
            HttpResponse::Ok().json(map_proto_profile(&profile))
        }
        Err(e) => {
            tracing::error!(user_id=%user_id, error=%e, "Auth-service failed to update profile");
            HttpResponse::BadGateway().json(serde_json::json!({
                "error": "Failed to update profile",
                "details": e.message().to_string()
            }))
        }
    }
}

/// GET /api/v1/users/me
pub async fn get_current_user(http_req: HttpRequest, pool: web::Data<PgPool>) -> impl Responder {
    let user_id = match http_req.extensions().get::<UserId>() {
        Some(user_id_wrapper) => user_id_wrapper.0,
        None => {
            return HttpResponse::Unauthorized().json(serde_json::json!({
                "error": "Unauthorized"
            }))
        }
    };

    match user_repo::find_by_id(pool.get_ref(), user_id).await {
        Ok(Some(user)) => HttpResponse::Ok().json(UserProfile {
            id: user.id.to_string(),
            username: user.username,
            email: Some(user.email),
            display_name: user.display_name,
            bio: user.bio,
            avatar_url: user.avatar_url,
            cover_photo_url: user.cover_photo_url,
            location: user.location,
            private_account: user.private_account,
            created_at: user.created_at.to_rfc3339(),
        }),
        Ok(None) => HttpResponse::NotFound().json(serde_json::json!({
            "error": "User not found"
        })),
        Err(e) => {
            tracing::error!("Database error: {}", e);
            HttpResponse::InternalServerError().json(serde_json::json!({
                "error": "Database error",
                "details": e.to_string()
            }))
        }
    }
}

fn map_proto_profile(profile: &ProtoUserProfile) -> UserProfile {
    UserProfile {
        id: profile.user_id.clone(),
        username: profile.username.clone(),
        email: profile.email.clone(),
        display_name: profile.display_name.clone(),
        bio: profile.bio.clone(),
        avatar_url: profile.avatar_url.clone(),
        cover_photo_url: profile.cover_photo_url.clone(),
        location: profile.location.clone(),
        private_account: profile.private_account,
        created_at: to_rfc3339(profile.created_at),
    }
}

fn to_rfc3339(ts: i64) -> String {
    if let Some(naive) = chrono::NaiveDateTime::from_timestamp_opt(ts, 0) {
        chrono::DateTime::<chrono::Utc>::from_utc(naive, chrono::Utc).to_rfc3339()
    } else {
        chrono::Utc::now().to_rfc3339()
    }
}
