/// Story handlers - HTTP endpoints for story operations
use crate::error::{AppError, Result};
use crate::services::{PrivacyLevel, StoriesService};
use actix_web::{dev::Payload, web, FromRequest, HttpRequest, HttpResponse};
use chrono::{DateTime, Utc};
use futures::future::{ready, Ready};
use serde::Deserialize;
use sqlx::PgPool;
use uuid::Uuid;

#[derive(Deserialize)]
pub struct PaginationParams {
    #[serde(default = "default_limit")]
    pub limit: i64,
}

fn default_limit() -> i64 {
    20
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

/// Extract authenticated user ID from `x-user-id` header.
#[derive(Debug, Clone, Copy)]
pub struct AuthenticatedUser(pub Uuid);

impl FromRequest for AuthenticatedUser {
    type Error = actix_web::Error;
    type Future = Ready<std::result::Result<Self, Self::Error>>;

    fn from_request(req: &HttpRequest, _: &mut Payload) -> Self::Future {
        let result = req
            .headers()
            .get("x-user-id")
            .ok_or_else(|| AppError::Unauthorized("missing x-user-id header".into()))
            .and_then(|value| {
                value
                    .to_str()
                    .map_err(|_| AppError::BadRequest("invalid x-user-id header syntax".into()))
            })
            .and_then(|value| {
                Uuid::parse_str(value).map_err(|_| {
                    AppError::BadRequest("x-user-id header must be a valid UUID".into())
                })
            })
            .map(AuthenticatedUser)
            .map_err(|e| actix_web::Error::from(e));

        ready(result)
    }
}

/// Create a new story
pub async fn create_story(
    pool: web::Data<PgPool>,
    auth: AuthenticatedUser,
    req: web::Json<CreateStoryRequest>,
) -> Result<HttpResponse> {
    let service = StoriesService::new((**pool).clone());
    let privacy = PrivacyLevel::try_from(req.privacy_level.as_str())?;

    let story = service
        .create_story(
            auth.0,
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
    auth: AuthenticatedUser,
) -> Result<HttpResponse> {
    let service = StoriesService::new((**pool).clone());
    match service.get_story_for_viewer(*story_id, auth.0).await? {
        Some(story) => Ok(HttpResponse::Ok().json(story)),
        None => Ok(HttpResponse::NotFound().finish()),
    }
}

/// Get stories feed for user
pub async fn get_stories_feed(
    pool: web::Data<PgPool>,
    auth: AuthenticatedUser,
    query: web::Query<PaginationParams>,
) -> Result<HttpResponse> {
    let service = StoriesService::new((**pool).clone());
    let stories = service.list_feed(auth.0, query.limit).await?;

    Ok(HttpResponse::Ok().json(stories))
}

/// Get user's stories
pub async fn get_user_stories(
    pool: web::Data<PgPool>,
    owner_id: web::Path<Uuid>,
    auth: AuthenticatedUser,
    query: web::Query<PaginationParams>,
) -> Result<HttpResponse> {
    let service = StoriesService::new((**pool).clone());
    let stories = service
        .list_user_stories(*owner_id, auth.0, query.limit)
        .await?;

    Ok(HttpResponse::Ok().json(stories))
}

/// Track story view
pub async fn track_story_view(
    pool: web::Data<PgPool>,
    story_id: web::Path<Uuid>,
    auth: AuthenticatedUser,
) -> Result<HttpResponse> {
    let service = StoriesService::new((**pool).clone());
    service.track_view(*story_id, auth.0).await?;

    Ok(HttpResponse::Ok().finish())
}

/// Update story privacy
pub async fn update_story_privacy(
    pool: web::Data<PgPool>,
    story_id: web::Path<Uuid>,
    auth: AuthenticatedUser,
    req: web::Json<UpdatePrivacyRequest>,
) -> Result<HttpResponse> {
    let service = StoriesService::new((**pool).clone());
    let privacy = PrivacyLevel::try_from(req.privacy_level.as_str())?;

    let updated = service.update_privacy(auth.0, *story_id, privacy).await?;

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
    auth: AuthenticatedUser,
) -> Result<HttpResponse> {
    let service = StoriesService::new((**pool).clone());
    let deleted = service.delete_story(auth.0, *story_id).await?;

    if deleted {
        Ok(HttpResponse::NoContent().finish())
    } else {
        Ok(HttpResponse::NotFound().finish())
    }
}

/// Add a close friend
pub async fn add_close_friend(
    pool: web::Data<PgPool>,
    auth: AuthenticatedUser,
    req: web::Json<AddCloseFreindRequest>,
) -> Result<HttpResponse> {
    let service = StoriesService::new((**pool).clone());
    service.add_close_friend(auth.0, req.friend_id).await?;

    Ok(HttpResponse::Ok().finish())
}

/// Remove a close friend
pub async fn remove_close_friend(
    pool: web::Data<PgPool>,
    auth: AuthenticatedUser,
    friend_id: web::Path<Uuid>,
) -> Result<HttpResponse> {
    let service = StoriesService::new((**pool).clone());
    service.remove_close_friend(auth.0, *friend_id).await?;

    Ok(HttpResponse::Ok().finish())
}

#[derive(Deserialize)]
pub struct AddCloseFreindRequest {
    pub friend_id: Uuid,
}
