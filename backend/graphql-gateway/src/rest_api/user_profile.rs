/// User Profile Settings API endpoints
///
/// GET /api/v2/users/{id} - Get user profile
/// PUT /api/v2/users/{id} - Update user profile
/// POST /api/v2/users/avatar - Upload user avatar
use actix_web::{web, HttpResponse, Result};
use serde::{Deserialize, Serialize};
use tracing::{error, info};

use crate::clients::ServiceClients;

#[derive(Debug, Deserialize)]
pub struct UpdateProfileRequest {
    pub first_name: Option<String>,
    pub last_name: Option<String>,
    pub username: Option<String>,
    pub bio: Option<String>,
    pub location: Option<String>,
    pub date_of_birth: Option<String>,
    pub gender: Option<String>,
    pub website: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct AvatarUploadRequest {
    pub url: String, // URL of uploaded avatar image
}

#[derive(Debug, Serialize)]
pub struct UserProfileResponse {
    pub id: String,
    pub username: String,
    pub email: String,
    pub first_name: Option<String>,
    pub last_name: Option<String>,
    pub avatar_url: Option<String>,
    pub bio: Option<String>,
    pub location: Option<String>,
    pub date_of_birth: Option<String>,
    pub gender: Option<String>,
    pub website: Option<String>,
    pub created_at: i64,
    pub updated_at: i64,
}

/// GET /api/v2/users/{id}
/// Get user profile
pub async fn get_profile(
    user_id: web::Path<String>,
    _clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!(user_id = %user_id, "GET /api/v2/users/{id}");

    // TODO: Implement actual user profile fetch from identity-service or user-service
    // For now, return placeholder
    let response = UserProfileResponse {
        id: user_id.to_string(),
        username: "placeholder".to_string(),
        email: "placeholder@example.com".to_string(),
        first_name: None,
        last_name: None,
        avatar_url: None,
        bio: None,
        location: None,
        date_of_birth: None,
        gender: None,
        website: None,
        created_at: chrono::Utc::now().timestamp(),
        updated_at: chrono::Utc::now().timestamp(),
    };

    Ok(HttpResponse::Ok().json(response))
}

/// PUT /api/v2/users/{id}
/// Update user profile
pub async fn update_profile(
    user_id: web::Path<String>,
    req: web::Json<UpdateProfileRequest>,
    _clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!(
        user_id = %user_id,
        first_name = ?req.first_name,
        "PUT /api/v2/users/{id}"
    );

    // TODO: Implement actual profile update via identity-service or user-service
    let response = UserProfileResponse {
        id: user_id.to_string(),
        username: "placeholder".to_string(),
        email: "placeholder@example.com".to_string(),
        first_name: req.first_name.clone(),
        last_name: req.last_name.clone(),
        avatar_url: None,
        bio: req.bio.clone(),
        location: req.location.clone(),
        date_of_birth: req.date_of_birth.clone(),
        gender: req.gender.clone(),
        website: req.website.clone(),
        created_at: chrono::Utc::now().timestamp(),
        updated_at: chrono::Utc::now().timestamp(),
    };

    Ok(HttpResponse::Ok().json(response))
}

/// POST /api/v2/users/avatar
/// Upload user avatar
pub async fn upload_avatar(
    req: web::Json<AvatarUploadRequest>,
    _clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!(avatar_url = %req.url, "POST /api/v2/users/avatar");

    // TODO: Implement actual avatar upload via media-service
    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "avatar_updated",
        "url": req.url,
    })))
}
