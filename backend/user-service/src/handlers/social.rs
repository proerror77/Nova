/// Social graph management handlers (follows, blocks, mutes)
use actix_web::{post, delete, get, web, HttpMessage, HttpResponse, HttpRequest};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use uuid::Uuid;

use crate::db::SocialRepository;
use crate::error::{AppError, Result};
use crate::middleware::jwt_auth::UserId;

/// Follow request payload
#[derive(Debug, Deserialize)]
pub struct FollowRequest {
    /// User ID to follow
    pub user_id: Uuid,
}

/// Generic social action response
#[derive(Debug, Serialize)]
pub struct SocialActionResponse {
    pub success: bool,
    pub message: String,
}

/// User stats response
#[derive(Debug, Serialize)]
pub struct UserStatsResponse {
    pub followers_count: i64,
    pub following_count: i64,
}

/// Users list response
#[derive(Debug, Serialize)]
pub struct UsersListResponse {
    pub users: Vec<Uuid>,
    pub total: i64,
    pub limit: i64,
    pub offset: i64,
}

/// POST /api/v1/users/{user_id}/follow
/// Follow a user
#[post("/users/{user_id}/follow")]
pub async fn follow_user(
    user_id_param: web::Path<Uuid>,
    http_req: HttpRequest,
    pool: web::Data<PgPool>,
) -> Result<HttpResponse> {
    let current_user_id = http_req
        .extensions()
        .get::<UserId>()
        .map(|u| u.0)
        .ok_or_else(|| AppError::Authentication("Missing user context".into()))?;

    let target_user_id = user_id_param.into_inner();

    tracing::info!(
        "User {} following user {}",
        current_user_id,
        target_user_id
    );

    SocialRepository::follow(&pool, current_user_id, target_user_id).await?;

    Ok(HttpResponse::Ok().json(SocialActionResponse {
        success: true,
        message: format!("Successfully followed user {}", target_user_id),
    }))
}

/// POST /api/v1/users/{user_id}/unfollow
/// Unfollow a user
#[post("/users/{user_id}/unfollow")]
pub async fn unfollow_user(
    user_id_param: web::Path<Uuid>,
    http_req: HttpRequest,
    pool: web::Data<PgPool>,
) -> Result<HttpResponse> {
    let current_user_id = http_req
        .extensions()
        .get::<UserId>()
        .map(|u| u.0)
        .ok_or_else(|| AppError::Authentication("Missing user context".into()))?;

    let target_user_id = user_id_param.into_inner();

    tracing::info!(
        "User {} unfollowing user {}",
        current_user_id,
        target_user_id
    );

    SocialRepository::unfollow(&pool, current_user_id, target_user_id).await?;

    Ok(HttpResponse::Ok().json(SocialActionResponse {
        success: true,
        message: format!("Successfully unfollowed user {}", target_user_id),
    }))
}

/// POST /api/v1/users/{user_id}/block
/// Block a user
#[post("/users/{user_id}/block")]
pub async fn block_user(
    user_id_param: web::Path<Uuid>,
    http_req: HttpRequest,
    pool: web::Data<PgPool>,
) -> Result<HttpResponse> {
    let current_user_id = http_req
        .extensions()
        .get::<UserId>()
        .map(|u| u.0)
        .ok_or_else(|| AppError::Authentication("Missing user context".into()))?;

    let target_user_id = user_id_param.into_inner();

    tracing::info!(
        "User {} blocking user {}",
        current_user_id,
        target_user_id
    );

    SocialRepository::block(&pool, current_user_id, target_user_id).await?;

    Ok(HttpResponse::Ok().json(SocialActionResponse {
        success: true,
        message: format!("Successfully blocked user {}", target_user_id),
    }))
}

/// DELETE /api/v1/users/{user_id}/block
/// Unblock a user
#[delete("/users/{user_id}/block")]
pub async fn unblock_user(
    user_id_param: web::Path<Uuid>,
    http_req: HttpRequest,
    pool: web::Data<PgPool>,
) -> Result<HttpResponse> {
    let current_user_id = http_req
        .extensions()
        .get::<UserId>()
        .map(|u| u.0)
        .ok_or_else(|| AppError::Authentication("Missing user context".into()))?;

    let target_user_id = user_id_param.into_inner();

    tracing::info!(
        "User {} unblocking user {}",
        current_user_id,
        target_user_id
    );

    SocialRepository::unblock(&pool, current_user_id, target_user_id).await?;

    Ok(HttpResponse::Ok().json(SocialActionResponse {
        success: true,
        message: format!("Successfully unblocked user {}", target_user_id),
    }))
}

/// POST /api/v1/users/{user_id}/mute
/// Mute a user
#[post("/users/{user_id}/mute")]
pub async fn mute_user(
    user_id_param: web::Path<Uuid>,
    http_req: HttpRequest,
    pool: web::Data<PgPool>,
) -> Result<HttpResponse> {
    let current_user_id = http_req
        .extensions()
        .get::<UserId>()
        .map(|u| u.0)
        .ok_or_else(|| AppError::Authentication("Missing user context".into()))?;

    let target_user_id = user_id_param.into_inner();

    tracing::info!(
        "User {} muting user {}",
        current_user_id,
        target_user_id
    );

    SocialRepository::mute(&pool, current_user_id, target_user_id).await?;

    Ok(HttpResponse::Ok().json(SocialActionResponse {
        success: true,
        message: format!("Successfully muted user {}", target_user_id),
    }))
}

/// DELETE /api/v1/users/{user_id}/mute
/// Unmute a user
#[delete("/users/{user_id}/mute")]
pub async fn unmute_user(
    user_id_param: web::Path<Uuid>,
    http_req: HttpRequest,
    pool: web::Data<PgPool>,
) -> Result<HttpResponse> {
    let current_user_id = http_req
        .extensions()
        .get::<UserId>()
        .map(|u| u.0)
        .ok_or_else(|| AppError::Authentication("Missing user context".into()))?;

    let target_user_id = user_id_param.into_inner();

    tracing::info!(
        "User {} unmuting user {}",
        current_user_id,
        target_user_id
    );

    SocialRepository::unmute(&pool, current_user_id, target_user_id).await?;

    Ok(HttpResponse::Ok().json(SocialActionResponse {
        success: true,
        message: format!("Successfully unmuted user {}", target_user_id),
    }))
}

/// GET /api/v1/users/{user_id}/followers
/// Get followers list for a user
#[get("/users/{user_id}/followers")]
pub async fn get_followers(
    user_id_param: web::Path<Uuid>,
    query: web::Query<std::collections::HashMap<String, String>>,
    pool: web::Data<PgPool>,
) -> Result<HttpResponse> {
    let target_user_id = user_id_param.into_inner();

    let limit: i64 = query
        .get("limit")
        .and_then(|l| l.parse().ok())
        .unwrap_or(20)
        .min(100);
    let offset: i64 = query
        .get("offset")
        .and_then(|o| o.parse().ok())
        .unwrap_or(0)
        .max(0);

    tracing::debug!(
        "Getting followers for user {} (limit={}, offset={})",
        target_user_id,
        limit,
        offset
    );

    let followers = SocialRepository::get_followers(&pool, target_user_id, limit, offset).await?;
    let total = SocialRepository::get_followers_count(&pool, target_user_id).await?;

    Ok(HttpResponse::Ok().json(UsersListResponse {
        users: followers,
        total,
        limit,
        offset,
    }))
}

/// GET /api/v1/users/{user_id}/following
/// Get following list for a user
#[get("/users/{user_id}/following")]
pub async fn get_following(
    user_id_param: web::Path<Uuid>,
    query: web::Query<std::collections::HashMap<String, String>>,
    pool: web::Data<PgPool>,
) -> Result<HttpResponse> {
    let target_user_id = user_id_param.into_inner();

    let limit: i64 = query
        .get("limit")
        .and_then(|l| l.parse().ok())
        .unwrap_or(20)
        .min(100);
    let offset: i64 = query
        .get("offset")
        .and_then(|o| o.parse().ok())
        .unwrap_or(0)
        .max(0);

    tracing::debug!(
        "Getting following for user {} (limit={}, offset={})",
        target_user_id,
        limit,
        offset
    );

    let following = SocialRepository::get_following(&pool, target_user_id, limit, offset).await?;
    let total = SocialRepository::get_following_count(&pool, target_user_id).await?;

    Ok(HttpResponse::Ok().json(UsersListResponse {
        users: following,
        total,
        limit,
        offset,
    }))
}

/// GET /api/v1/users/{user_id}/stats
/// Get follower/following stats for a user
#[get("/users/{user_id}/stats")]
pub async fn get_user_stats(
    user_id_param: web::Path<Uuid>,
    pool: web::Data<PgPool>,
) -> Result<HttpResponse> {
    let target_user_id = user_id_param.into_inner();

    tracing::debug!("Getting social stats for user {}", target_user_id);

    let followers_count =
        SocialRepository::get_followers_count(&pool, target_user_id).await?;
    let following_count =
        SocialRepository::get_following_count(&pool, target_user_id).await?;

    Ok(HttpResponse::Ok().json(UserStatsResponse {
        followers_count,
        following_count,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_follow_request_serialization() {
        let user_id = Uuid::new_v4();
        let req = FollowRequest { user_id };
        assert_eq!(req.user_id, user_id);
    }

    #[test]
    fn test_social_action_response() {
        let response = SocialActionResponse {
            success: true,
            message: "Test message".to_string(),
        };
        assert!(response.success);
    }
}
