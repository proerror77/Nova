use actix_web::{delete, get, post, web, HttpResponse};
use serde::Serialize;
use sqlx::{PgPool, Row};
use uuid::Uuid;

use crate::db::user_repo;
use crate::middleware::jwt_auth::UserId;
use crate::services::graph::GraphService;
use crate::services::kafka_producer::EventProducer;
use std::sync::Arc;
use crate::metrics::helpers::record_social_follow_event;
use crate::cache::{FeedCache, invalidate_search_cache, invalidate_user_cache};

#[derive(Serialize)]
struct FollowResponse { status: String }

/// POST /api/v1/users/{id}/follow
pub async fn follow_user(
    path: web::Path<String>,
    pool: web::Data<PgPool>,
    graph: web::Data<GraphService>,
    event_producer: web::Data<Arc<EventProducer>>,
    redis_manager: Option<web::Data<redis::aio::ConnectionManager>>,
    user: UserId,
) -> HttpResponse {
    let target_id = match Uuid::parse_str(&path.into_inner()) {
        Ok(id) => id,
        Err(_) => return HttpResponse::BadRequest().json(serde_json::json!({"error": "invalid user id"})),
    };

    if target_id == user.0 {
        return HttpResponse::BadRequest().json(serde_json::json!({"error": "cannot follow self"}));
    }

    // Ensure target user exists
    let exists: bool = match sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)",
    )
    .bind(target_id)
    .fetch_one(pool.get_ref())
    .await
    {
        Ok(v) => v,
        Err(e) => {
            return HttpResponse::InternalServerError().json(serde_json::json!({
                "error": "db_error",
                "details": e.to_string()
            }));
        }
    };
    if !exists {
        return HttpResponse::NotFound().json(serde_json::json!({"error":"user_not_found"}));
    }

    let query = r#"
        INSERT INTO follows (follower_id, following_id)
        VALUES ($1, $2)
        ON CONFLICT (follower_id, following_id) DO NOTHING
    "#;

    match sqlx::query(query)
        .bind(user.0)
        .bind(target_id)
        .execute(pool.get_ref())
        .await
    {
        Ok(_) => {
            record_social_follow_event("new_follow", "request");
            // Fire-and-forget Neo4j follow if enabled
            if graph.is_enabled() {
                let g = graph.get_ref().clone();
                tokio::spawn(async move {
                    let _ = g.follow(user.0, target_id).await;
                });
            }
            // Publish event for analytics/feed invalidation
            {
                let producer = event_producer.get_ref().clone();
                let key = format!("follow-{}-{}", user.0, target_id);
                let payload = serde_json::json!({
                    "event_id": Uuid::new_v4().to_string(),
                    "event_type": "new_follow",
                    "user_id": 0, // optional (use properties below for UUIDs)
                    "timestamp": chrono::Utc::now().timestamp_millis(),
                    "properties": {
                        "follower_id": user.0.to_string(),
                        "followee_id": target_id.to_string()
                    }
                })
                .to_string();
                tokio::spawn(async move {
                    let _ = producer.send_json(&key, &payload).await;
                });
            }
            // Synchronous cache invalidation (fallback)
            if let Some(redis_manager) = redis_manager {
                let mut cache = FeedCache::new(redis_manager.get_ref().clone(), 120);
                let _ = cache
                    .invalidate_by_event("new_follow", user.0, Some(target_id))
                    .await;

                // Invalidate user caches since profile visibility may have changed
                let _ = invalidate_user_cache(redis_manager.get_ref(), user.0).await;
                let _ = invalidate_user_cache(redis_manager.get_ref(), target_id).await;

                // Invalidate search caches - follow relationship affects search visibility
                let _ = invalidate_search_cache(redis_manager.get_ref(), "").await;
            }

            HttpResponse::Ok().json(FollowResponse { status: "ok".into() })
        }
        Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({
            "error": "db_error",
            "details": e.to_string()
        })),
    }
}

/// DELETE /api/v1/users/{id}/follow
pub async fn unfollow_user(
    path: web::Path<String>,
    pool: web::Data<PgPool>,
    graph: web::Data<GraphService>,
    event_producer: web::Data<Arc<EventProducer>>,
    redis_manager: Option<web::Data<redis::aio::ConnectionManager>>,
    user: UserId,
) -> HttpResponse {
    let target_id = match Uuid::parse_str(&path.into_inner()) {
        Ok(id) => id,
        Err(_) => return HttpResponse::BadRequest().json(serde_json::json!({"error": "invalid user id"})),
    };

    let query = r#"
        DELETE FROM follows WHERE follower_id = $1 AND following_id = $2
    "#;

    match sqlx::query(query)
        .bind(user.0)
        .bind(target_id)
        .execute(pool.get_ref())
        .await
    {
        Ok(_) => {
            record_social_follow_event("unfollow", "request");
            if graph.is_enabled() {
                let g = graph.get_ref().clone();
                tokio::spawn(async move {
                    let _ = g.unfollow(user.0, target_id).await;
                });
            }
            // Publish unfollow event
            {
                let producer = event_producer.get_ref().clone();
                let key = format!("unfollow-{}-{}", user.0, target_id);
                let payload = serde_json::json!({
                    "event_id": Uuid::new_v4().to_string(),
                    "event_type": "unfollow",
                    "user_id": 0,
                    "timestamp": chrono::Utc::now().timestamp_millis(),
                    "properties": {
                        "follower_id": user.0.to_string(),
                        "followee_id": target_id.to_string()
                    }
                })
                .to_string();
                tokio::spawn(async move {
                    let _ = producer.send_json(&key, &payload).await;
                });
            }
            // Synchronous cache invalidation (fallback)
            if let Some(redis_manager) = redis_manager {
                let mut cache = FeedCache::new(redis_manager.get_ref().clone(), 120);
                let _ = cache
                    .invalidate_by_event("new_follow", user.0, Some(target_id))
                    .await;

                // Invalidate user caches since profile visibility may have changed
                let _ = invalidate_user_cache(redis_manager.get_ref(), user.0).await;
                let _ = invalidate_user_cache(redis_manager.get_ref(), target_id).await;

                // Invalidate search caches - follow relationship affects search visibility
                let _ = invalidate_search_cache(redis_manager.get_ref(), "").await;
            }

            HttpResponse::Ok().json(FollowResponse { status: "ok".into() })
        }
        Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({
            "error": "db_error",
            "details": e.to_string()
        })),
    }
}

#[derive(Serialize)]
struct RelationshipUser {
    user_id: Uuid,
    username: String,
    avatar_url: Option<String>,
}

/// GET /api/v1/users/{id}/followers
/// OPTIMIZED: Single query with JOIN to get user data
pub async fn get_followers(
    path: web::Path<String>,
    q: web::Query<std::collections::HashMap<String, String>>,
    pool: web::Data<PgPool>,
) -> HttpResponse {
    let id = match Uuid::parse_str(&path.into_inner()) {
        Ok(id) => id,
        Err(_) => return HttpResponse::BadRequest().finish(),
    };
    let limit = q.get("limit").and_then(|s| s.parse::<i64>().ok()).unwrap_or(50).clamp(1, 200);
    let offset = q.get("offset").and_then(|s| s.parse::<i64>().ok()).unwrap_or(0).max(0);

    // OPTIMIZED: JOIN with users table to get username and avatar in single query
    let sql = r#"
        SELECT f.follower_id, u.username, u.avatar_url
        FROM follows f
        JOIN users u ON f.follower_id = u.id
        WHERE f.following_id = $1 AND u.deleted_at IS NULL
        ORDER BY f.created_at DESC
        LIMIT $2 OFFSET $3
    "#;
    match sqlx::query_as::<_, (Uuid, String, Option<String>)>(sql)
        .bind(id)
        .bind(limit)
        .bind(offset)
        .fetch_all(pool.get_ref())
        .await
    {
        Ok(rows) => {
            let users: Vec<RelationshipUser> = rows
                .into_iter()
                .map(|(user_id, username, avatar_url)| RelationshipUser { user_id, username, avatar_url })
                .collect();
            let count = users.len();
            HttpResponse::Ok().json(serde_json::json!({"users": users, "count": count}))
        }
        Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({"error": e.to_string()})),
    }
}

/// GET /api/v1/users/{id}/following
/// OPTIMIZED: Single query with JOIN to get user data
pub async fn get_following(
    path: web::Path<String>,
    q: web::Query<std::collections::HashMap<String, String>>,
    pool: web::Data<PgPool>,
) -> HttpResponse {
    let id = match Uuid::parse_str(&path.into_inner()) {
        Ok(id) => id,
        Err(_) => return HttpResponse::BadRequest().finish(),
    };
    let limit = q.get("limit").and_then(|s| s.parse::<i64>().ok()).unwrap_or(50).clamp(1, 200);
    let offset = q.get("offset").and_then(|s| s.parse::<i64>().ok()).unwrap_or(0).max(0);

    // OPTIMIZED: JOIN with users table to get username and avatar in single query
    let sql = r#"
        SELECT f.following_id, u.username, u.avatar_url
        FROM follows f
        JOIN users u ON f.following_id = u.id
        WHERE f.follower_id = $1 AND u.deleted_at IS NULL
        ORDER BY f.created_at DESC
        LIMIT $2 OFFSET $3
    "#;
    match sqlx::query_as::<_, (Uuid, String, Option<String>)>(sql)
        .bind(id)
        .bind(limit)
        .bind(offset)
        .fetch_all(pool.get_ref())
        .await
    {
        Ok(rows) => {
            let users: Vec<RelationshipUser> = rows
                .into_iter()
                .map(|(user_id, username, avatar_url)| RelationshipUser { user_id, username, avatar_url })
                .collect();
            let count = users.len();
            HttpResponse::Ok().json(serde_json::json!({"users": users, "count": count}))
        }
        Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({"error": e.to_string()})),
    }
}

/// POST /api/v1/users/{id}/block
pub async fn block_user(
    path: web::Path<String>,
    pool: web::Data<PgPool>,
    user: UserId,
    redis_manager: Option<web::Data<redis::aio::ConnectionManager>>,
) -> HttpResponse {
    let target_id = match Uuid::parse_str(&path.into_inner()) {
        Ok(id) => id,
        Err(_) => return HttpResponse::BadRequest().json(serde_json::json!({"error": "invalid user id"})),
    };

    if target_id == user.0 {
        return HttpResponse::BadRequest().json(serde_json::json!({"error": "cannot block yourself"}));
    }

    match user_repo::block_user(pool.get_ref(), user.0, target_id).await {
        Ok(_) => {
            // Invalidate caches after blocking user
            if let Some(redis_manager) = redis_manager {
                // User caches affected by block
                let _ = invalidate_user_cache(redis_manager.get_ref(), user.0).await;
                let _ = invalidate_user_cache(redis_manager.get_ref(), target_id).await;
                // Search caches affected by block status change
                let _ = invalidate_search_cache(redis_manager.get_ref(), "").await;
            }
            HttpResponse::Ok().json(FollowResponse { status: "ok".into() })
        }
        Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({
            "error": "db_error",
            "details": e.to_string()
        })),
    }
}

/// DELETE /api/v1/users/{id}/block
pub async fn unblock_user(
    path: web::Path<String>,
    pool: web::Data<PgPool>,
    user: UserId,
    redis_manager: Option<web::Data<redis::aio::ConnectionManager>>,
) -> HttpResponse {
    let target_id = match Uuid::parse_str(&path.into_inner()) {
        Ok(id) => id,
        Err(_) => return HttpResponse::BadRequest().json(serde_json::json!({"error": "invalid user id"})),
    };

    match user_repo::unblock_user(pool.get_ref(), user.0, target_id).await {
        Ok(_) => {
            // Invalidate caches after unblocking user
            if let Some(redis_manager) = redis_manager {
                // User caches affected by unblock
                let _ = invalidate_user_cache(redis_manager.get_ref(), user.0).await;
                let _ = invalidate_user_cache(redis_manager.get_ref(), target_id).await;
                // Search caches affected by block status change
                let _ = invalidate_search_cache(redis_manager.get_ref(), "").await;
            }
            HttpResponse::Ok().json(FollowResponse { status: "ok".into() })
        }
        Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({
            "error": "db_error",
            "details": e.to_string()
        })),
    }
}
