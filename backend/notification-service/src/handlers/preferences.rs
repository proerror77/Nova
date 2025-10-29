/// Notification preferences handlers
use actix_web::{web, HttpResponse, Result as ActixResult};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use crate::services::NotificationService;
use std::sync::Arc;
use super::ApiResponse;

/// Update notification preferences request
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct UpdatePreferencesPayload {
    pub enabled: Option<bool>,
    pub like_enabled: Option<bool>,
    pub comment_enabled: Option<bool>,
    pub follow_enabled: Option<bool>,
    pub mention_enabled: Option<bool>,
    pub message_enabled: Option<bool>,
    pub stream_enabled: Option<bool>,
    pub quiet_hours_start: Option<String>,
    pub quiet_hours_end: Option<String>,
    pub prefer_fcm: Option<bool>,
    pub prefer_apns: Option<bool>,
    pub prefer_email: Option<bool>,
}

/// Get user's notification preferences
///
/// GET /api/v1/preferences/{user_id}
pub async fn get_preferences(
    service: web::Data<Arc<NotificationService>>,
    path: web::Path<Uuid>,
) -> ActixResult<HttpResponse> {
    let user_id = path.into_inner();

    match service.get_preferences(user_id).await {
        Ok(preferences) => {
            Ok(HttpResponse::Ok().json(ApiResponse::ok(preferences)))
        }
        Err(e) => {
            Ok(HttpResponse::InternalServerError().json(ApiResponse::<String>::err(e)))
        }
    }
}

/// Update notification preferences
///
/// PUT /api/v1/preferences/{user_id}
pub async fn update_preferences(
    service: web::Data<Arc<NotificationService>>,
    path: web::Path<Uuid>,
    req: web::Json<UpdatePreferencesPayload>,
) -> ActixResult<HttpResponse> {
    let user_id = path.into_inner();

    // Get current preferences
    match service.get_preferences(user_id).await {
        Ok(mut prefs) => {
            // Update fields if provided
            if let Some(enabled) = req.enabled {
                prefs.enabled = enabled;
            }
            if let Some(like_enabled) = req.like_enabled {
                prefs.like_enabled = like_enabled;
            }
            if let Some(comment_enabled) = req.comment_enabled {
                prefs.comment_enabled = comment_enabled;
            }
            if let Some(follow_enabled) = req.follow_enabled {
                prefs.follow_enabled = follow_enabled;
            }
            if let Some(mention_enabled) = req.mention_enabled {
                prefs.mention_enabled = mention_enabled;
            }
            if let Some(message_enabled) = req.message_enabled {
                prefs.message_enabled = message_enabled;
            }
            if let Some(stream_enabled) = req.stream_enabled {
                prefs.stream_enabled = stream_enabled;
            }
            if req.quiet_hours_start.is_some() {
                prefs.quiet_hours_start = req.quiet_hours_start.clone();
            }
            if req.quiet_hours_end.is_some() {
                prefs.quiet_hours_end = req.quiet_hours_end.clone();
            }
            if let Some(prefer_fcm) = req.prefer_fcm {
                prefs.prefer_fcm = prefer_fcm;
            }
            if let Some(prefer_apns) = req.prefer_apns {
                prefs.prefer_apns = prefer_apns;
            }
            if let Some(prefer_email) = req.prefer_email {
                prefs.prefer_email = prefer_email;
            }

            // In a full implementation, we would update the database here
            // For now, we'll just return the updated preferences
            Ok(HttpResponse::Ok().json(ApiResponse::ok(prefs)))
        }
        Err(e) => {
            Ok(HttpResponse::InternalServerError().json(ApiResponse::<String>::err(e)))
        }
    }
}

/// Register routes
pub fn register_routes(cfg: &mut web::ServiceConfig) {
    cfg.service(
        web::scope("/api/v1/preferences")
            .route("/{user_id}", web::get().to(get_preferences))
            .route("/{user_id}", web::put().to(update_preferences)),
    );
}
