use actix_web::{web, HttpResponse, Responder};
use chrono::{Duration, Utc};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;

use crate::middleware::UserId;
use crate::services::stories::{PrivacyLevel, StoriesService};

#[derive(Debug, Deserialize)]
pub struct CreateStoryRequest {
    pub content_url: String,
    #[serde(default = "default_content_type")]
    pub content_type: String, // image | video
    #[serde(default)]
    pub caption: Option<String>,
    #[serde(default = "default_privacy")]
    pub privacy_level: String, // public | followers | close_friends
}

fn default_privacy() -> String {
    "public".into()
}
fn default_content_type() -> String {
    "image".into()
}

#[derive(Debug, Serialize)]
pub struct StoryResponse {
    pub id: String,
    pub user_id: String,
    pub content_url: String,
    pub thumbnail_url: Option<String>,
    pub caption: Option<String>,
    pub content_type: String,
    pub privacy_level: String,
    pub expires_at: String,
    pub created_at: String,
}

#[derive(Debug, Deserialize)]
pub struct FeedQuery {
    #[serde(default = "default_limit")]
    pub limit: i64,
}
fn default_limit() -> i64 {
    20
}

// POST /api/v1/stories
pub async fn create_story(
    auth: UserId,
    pool: web::Data<PgPool>,
    json: web::Json<CreateStoryRequest>,
) -> impl Responder {
    if json.content_url.trim().is_empty() {
        return HttpResponse::BadRequest()
            .json(serde_json::json!({"error":"content_url required"}));
    }
    let privacy = match PrivacyLevel::try_from(json.privacy_level.as_str()) {
        Ok(p) => p,
        Err(_) => {
            return HttpResponse::BadRequest()
                .json(serde_json::json!({"error":"invalid privacy_level"}))
        }
    };

    // 24h 过期
    let expires_at = Utc::now() + Duration::hours(24);
    let svc = StoriesService::new(pool.get_ref().clone());
    match svc
        .create_story(
            auth.0,
            &json.content_url,
            json.caption.as_deref(),
            &json.content_type,
            privacy,
            expires_at,
        )
        .await
    {
        Ok(story) => HttpResponse::Created().json(StoryResponse {
            id: story.id.to_string(),
            user_id: story.user_id.to_string(),
            content_url: story.content_url,
            thumbnail_url: story.thumbnail_url,
            caption: story.caption,
            content_type: story.content_type,
            privacy_level: story.privacy_level,
            expires_at: story.expires_at.to_rfc3339(),
            created_at: story.created_at.to_rfc3339(),
        }),
        Err(e) => {
            HttpResponse::InternalServerError().json(serde_json::json!({"error":e.to_string()}))
        }
    }
}

// GET /api/v1/stories
pub async fn list_stories(
    auth: UserId,
    pool: web::Data<PgPool>,
    query: web::Query<FeedQuery>,
) -> impl Responder {
    let svc = StoriesService::new(pool.get_ref().clone());
    match svc.list_feed(auth.0, query.limit).await {
        Ok(list) => {
            let data: Vec<StoryResponse> = list
                .into_iter()
                .map(|s| StoryResponse {
                    id: s.id.to_string(),
                    user_id: s.user_id.to_string(),
                    content_url: s.content_url,
                    thumbnail_url: s.thumbnail_url,
                    caption: s.caption,
                    content_type: s.content_type,
                    privacy_level: s.privacy_level,
                    expires_at: s.expires_at.to_rfc3339(),
                    created_at: s.created_at.to_rfc3339(),
                })
                .collect();
            HttpResponse::Ok().json(serde_json::json!({"stories": data }))
        }
        Err(e) => {
            HttpResponse::InternalServerError().json(serde_json::json!({"error": e.to_string()}))
        }
    }
}

// GET /api/v1/stories/{id}
pub async fn get_story(
    auth: UserId,
    pool: web::Data<PgPool>,
    path: web::Path<String>,
) -> impl Responder {
    let story_id = match uuid::Uuid::parse_str(&path) {
        Ok(id) => id,
        Err(_) => return HttpResponse::BadRequest().finish(),
    };
    let svc = StoriesService::new(pool.get_ref().clone());
    match svc.get_story_for_viewer(story_id, auth.0).await {
        Ok(Some(s)) => {
            // 记录一次浏览（去重）
            let _ = svc.track_view(s.id, auth.0).await;
            HttpResponse::Ok().json(StoryResponse {
                id: s.id.to_string(),
                user_id: s.user_id.to_string(),
                content_url: s.content_url,
                thumbnail_url: s.thumbnail_url,
                caption: s.caption,
                content_type: s.content_type,
                privacy_level: s.privacy_level,
                expires_at: s.expires_at.to_rfc3339(),
                created_at: s.created_at.to_rfc3339(),
            })
        }
        Ok(None) => HttpResponse::NotFound().finish(),
        Err(e) => {
            HttpResponse::InternalServerError().json(serde_json::json!({"error": e.to_string()}))
        }
    }
}

#[derive(Debug, Deserialize)]
pub struct UpdatePrivacyRequest {
    pub privacy_level: String,
}

// PATCH /api/v1/stories/{id}/privacy
pub async fn update_story_privacy(
    auth: UserId,
    pool: web::Data<PgPool>,
    path: web::Path<String>,
    body: web::Json<UpdatePrivacyRequest>,
) -> impl Responder {
    let story_id = match uuid::Uuid::parse_str(&path) {
        Ok(id) => id,
        Err(_) => return HttpResponse::BadRequest().finish(),
    };
    let svc = StoriesService::new(pool.get_ref().clone());
    let privacy = match PrivacyLevel::try_from(body.privacy_level.as_str()) {
        Ok(p) => p,
        Err(_) => return HttpResponse::BadRequest().finish(),
    };
    match svc.update_privacy(auth.0, story_id, privacy).await {
        Ok(true) => HttpResponse::Ok().json(serde_json::json!({"updated": true})),
        Ok(false) => HttpResponse::NotFound().finish(),
        Err(e) => {
            HttpResponse::InternalServerError().json(serde_json::json!({"error": e.to_string()}))
        }
    }
}

// DELETE /api/v1/stories/{id}
pub async fn delete_story(
    auth: UserId,
    pool: web::Data<PgPool>,
    path: web::Path<String>,
) -> impl Responder {
    let story_id = match uuid::Uuid::parse_str(&path) {
        Ok(id) => id,
        Err(_) => return HttpResponse::BadRequest().finish(),
    };
    let svc = StoriesService::new(pool.get_ref().clone());
    match svc.delete_story(auth.0, story_id).await {
        Ok(true) => HttpResponse::Ok().json(serde_json::json!({"deleted": true})),
        Ok(false) => HttpResponse::NotFound().finish(),
        Err(e) => {
            HttpResponse::InternalServerError().json(serde_json::json!({"error": e.to_string()}))
        }
    }
}

// GET /api/v1/stories/user/{user_id}
pub async fn list_user_stories(
    auth: UserId,
    pool: web::Data<PgPool>,
    path: web::Path<String>,
    query: web::Query<FeedQuery>,
) -> impl Responder {
    let owner_id = match uuid::Uuid::parse_str(&path) {
        Ok(id) => id,
        Err(_) => return HttpResponse::BadRequest().finish(),
    };
    let svc = StoriesService::new(pool.get_ref().clone());
    match svc.list_user_stories(owner_id, auth.0, query.limit).await {
        Ok(list) => HttpResponse::Ok().json(serde_json::json!({"stories": list})),
        Err(e) => {
            HttpResponse::InternalServerError().json(serde_json::json!({"error": e.to_string()}))
        }
    }
}

// POST /api/v1/stories/close-friends/{friend_id}
pub async fn add_close_friend(
    auth: UserId,
    pool: web::Data<PgPool>,
    path: web::Path<String>,
) -> impl Responder {
    let friend_id = match uuid::Uuid::parse_str(&path) {
        Ok(id) => id,
        Err(_) => return HttpResponse::BadRequest().finish(),
    };
    let svc = StoriesService::new(pool.get_ref().clone());
    match svc.add_close_friend(auth.0, friend_id).await {
        Ok(()) => HttpResponse::Ok().json(serde_json::json!({"added": true})),
        Err(e) => {
            HttpResponse::InternalServerError().json(serde_json::json!({"error": e.to_string()}))
        }
    }
}

// DELETE /api/v1/stories/close-friends/{friend_id}
pub async fn remove_close_friend(
    auth: UserId,
    pool: web::Data<PgPool>,
    path: web::Path<String>,
) -> impl Responder {
    let friend_id = match uuid::Uuid::parse_str(&path) {
        Ok(id) => id,
        Err(_) => return HttpResponse::BadRequest().finish(),
    };
    let svc = StoriesService::new(pool.get_ref().clone());
    match svc.remove_close_friend(auth.0, friend_id).await {
        Ok(()) => HttpResponse::Ok().json(serde_json::json!({"removed": true})),
        Err(e) => {
            HttpResponse::InternalServerError().json(serde_json::json!({"error": e.to_string()}))
        }
    }
}

// GET /api/v1/stories/close-friends
pub async fn list_close_friends(auth: UserId, pool: web::Data<PgPool>) -> impl Responder {
    let svc = StoriesService::new(pool.get_ref().clone());
    match svc.list_close_friends(auth.0).await {
        Ok(list) => HttpResponse::Ok().json(serde_json::json!({"friends": list})),
        Err(e) => {
            HttpResponse::InternalServerError().json(serde_json::json!({"error": e.to_string()}))
        }
    }
}
