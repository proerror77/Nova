/// Story handlers - HTTP endpoints for story operations
use crate::error::Result;
use crate::services::{PrivacyLevel, StoriesService};
use actix_web::{web, HttpResponse};
use chrono::{DateTime, Utc};
use sqlx::PgPool;
use serde::Deserialize;
use uuid::Uuid;

#[derive(Deserialize)]
pub struct PaginationParams {
    pub limit: i64,
}

#[derive(Deserialize)]
pub struct CreateStoryRequest {
    pub content_url: String,
    pub caption: Option<String>,
    pub content_type: String,
    pub privacy_level: String,
    pub expires_at: DateTime<Utc>,
}

#[derive(Deserialize)]
pub struct UpdatePrivacyRequest {
    pub privacy_level: String,
}

/// Create a new story
pub async fn create_story(
    pool: web::Data<PgPool>,
    user_id: Uuid,
    req: web::Json<CreateStoryRequest>,
) -> Result<HttpResponse> {
    let service = StoriesService::new((**pool).clone());
    let privacy = PrivacyLevel::try_from(req.privacy_level.as_str())?;

    let story = service
        .create_story(
            user_id,
            &req.content_url,
            req.caption.as_deref(),
            &req.content_type,
            privacy,
            req.expires_at,
        )
        .await?;

    Ok(HttpResponse::Created().json(story))
}

/// Get a story
pub async fn get_story(
    pool: web::Data<PgPool>,
    story_id: web::Path<Uuid>,
    user_id: Uuid,
) -> Result<HttpResponse> {
    let service = StoriesService::new((**pool).clone());
    match service.get_story_for_viewer(*story_id, user_id).await? {
        Some(story) => Ok(HttpResponse::Ok().json(story)),
        None => Ok(HttpResponse::NotFound().finish()),
    }
}

/// Get stories feed for user
pub async fn get_stories_feed(
    pool: web::Data<PgPool>,
    user_id: Uuid,
    query: web::Query<PaginationParams>,
) -> Result<HttpResponse> {
    let service = StoriesService::new((**pool).clone());
    let stories = service.list_feed(user_id, query.limit).await?;

    Ok(HttpResponse::Ok().json(stories))
}

/// Get user's stories
pub async fn get_user_stories(
    pool: web::Data<PgPool>,
    owner_id: web::Path<Uuid>,
    user_id: Uuid,
    query: web::Query<PaginationParams>,
) -> Result<HttpResponse> {
    let service = StoriesService::new((**pool).clone());
    let stories = service
        .list_user_stories(*owner_id, user_id, query.limit)
        .await?;

    Ok(HttpResponse::Ok().json(stories))
}

/// Track story view
pub async fn track_story_view(
    pool: web::Data<PgPool>,
    story_id: web::Path<Uuid>,
    user_id: Uuid,
) -> Result<HttpResponse> {
    let service = StoriesService::new((**pool).clone());
    service.track_view(*story_id, user_id).await?;

    Ok(HttpResponse::Ok().finish())
}

/// Update story privacy
pub async fn update_story_privacy(
    pool: web::Data<PgPool>,
    story_id: web::Path<Uuid>,
    user_id: Uuid,
    req: web::Json<UpdatePrivacyRequest>,
) -> Result<HttpResponse> {
    let service = StoriesService::new((**pool).clone());
    let privacy = PrivacyLevel::try_from(req.privacy_level.as_str())?;

    let updated = service
        .update_privacy(user_id, *story_id, privacy)
        .await?;

    if updated {
        Ok(HttpResponse::Ok().finish())
    } else {
        Ok(HttpResponse::NotFound().finish())
    }
}

/// Delete a story
pub async fn delete_story(
    pool: web::Data<PgPool>,
    story_id: web::Path<Uuid>,
    user_id: Uuid,
) -> Result<HttpResponse> {
    let service = StoriesService::new((**pool).clone());
    let deleted = service.delete_story(user_id, *story_id).await?;

    if deleted {
        Ok(HttpResponse::NoContent().finish())
    } else {
        Ok(HttpResponse::NotFound().finish())
    }
}

/// Add a close friend
pub async fn add_close_friend(
    pool: web::Data<PgPool>,
    user_id: Uuid,
    req: web::Json<AddCloseFreindRequest>,
) -> Result<HttpResponse> {
    let service = StoriesService::new((**pool).clone());
    service.add_close_friend(user_id, req.friend_id).await?;

    Ok(HttpResponse::Ok().finish())
}

/// Remove a close friend
pub async fn remove_close_friend(
    pool: web::Data<PgPool>,
    user_id: Uuid,
    friend_id: web::Path<Uuid>,
) -> Result<HttpResponse> {
    let service = StoriesService::new((**pool).clone());
    service.remove_close_friend(user_id, *friend_id).await?;

    Ok(HttpResponse::Ok().finish())
}

#[derive(Deserialize)]
pub struct AddCloseFreindRequest {
    pub friend_id: Uuid,
}
