//! User Profile Settings API endpoints
//!
//! GET /api/v2/users/{id} - Get user profile
//! PUT /api/v2/users/{id} - Update user profile
//! POST /api/v2/users/avatar - Upload user avatar

#![allow(dead_code)]

use actix_web::{web, HttpMessage, HttpRequest, HttpResponse, Result};
use serde::{Deserialize, Serialize};
use tracing::{error, info};

use crate::clients::proto::auth::{
    auth_service_client::AuthServiceClient, GetUserRequest, UpdateUserProfileRequest,
};
use crate::clients::proto::media::{
    media_service_client::MediaServiceClient, InitiateUploadRequest, MediaType,
};
use crate::clients::ServiceClients;
use crate::middleware::jwt::AuthenticatedUser;
use tonic::Status;

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
    /// Already uploaded URL (legacy flow)
    pub url: Option<String>,
    /// Optional presign flow inputs
    pub file_name: Option<String>,
    pub file_size: Option<i64>,
    pub content_type: Option<String>,
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
    http_req: HttpRequest,
    user_id: web::Path<String>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let authed = http_req.extensions().get::<AuthenticatedUser>().copied();
    if authed.is_none() {
        return Ok(HttpResponse::Unauthorized().finish());
    }

    info!(user_id = %user_id, "GET /api/v2/users/{user_id}");

    let mut auth_client: AuthServiceClient<_> = clients.auth_client();
    let req = tonic::Request::new(GetUserRequest {
        user_id: user_id.to_string(),
    });
    let resp = match auth_client.get_user(req).await {
        Ok(resp) => resp.into_inner(),
        Err(e) => {
            error!("get_user failed: {}", e);
            return Ok(HttpResponse::ServiceUnavailable().finish());
        }
    };

    if let Some(err) = resp.error {
        return Ok(HttpResponse::NotFound().json(serde_json::json!({
            "error": err.message
        })));
    }

    if let Some(u) = resp.user {
        let profile = UserProfileResponse {
            id: u.id,
            username: u.username,
            email: u.email,
            first_name: None,
            last_name: None,
            avatar_url: None,
            bio: None,
            location: None,
            date_of_birth: None,
            gender: None,
            website: None,
            created_at: u.created_at,
            updated_at: chrono::Utc::now().timestamp(),
        };
        return Ok(HttpResponse::Ok().json(profile));
    }

    Ok(HttpResponse::NotFound().finish())
}

/// PUT /api/v2/users/{id}
/// Update user profile
pub async fn update_profile(
    http_req: HttpRequest,
    user_id: web::Path<String>,
    req: web::Json<UpdateProfileRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let authed = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    if authed != user_id.as_str() {
        return Ok(HttpResponse::Unauthorized().body("cannot update other user profiles"));
    }

    info!(
        user_id = %user_id,
        first_name = ?req.first_name,
        "PUT /api/v2/users/{user_id}"
    );

    let mut auth_client: AuthServiceClient<_> = clients.auth_client();
    let update_req = UpdateUserProfileRequest {
        user_id: user_id.to_string(),
        display_name: req.first_name.clone().map(|f| {
            req.last_name
                .clone()
                .map(|l| format!("{} {}", f, l))
                .unwrap_or(f)
        }),
        bio: req.bio.clone(),
        avatar_url: None,
        cover_photo_url: None,
        location: req.location.clone(),
        private_account: None,
    };

    let resp = auth_client
        .update_user_profile(tonic::Request::new(update_req))
        .await
        .map(|r| r.into_inner());

    match resp {
        Ok(resp) => {
            if let Some(err) = resp.error {
                return Ok(HttpResponse::BadRequest().json(serde_json::json!({
                    "error": err.message
                })));
            }
            if let Some(p) = resp.profile {
                let profile = UserProfileResponse {
                    id: p.user_id,
                    username: p.username,
                    email: p.email.unwrap_or_default(),
                    first_name: None,
                    last_name: None,
                    avatar_url: p.avatar_url,
                    bio: p.bio,
                    location: p.location,
                    date_of_birth: None,
                    gender: None,
                    website: None,
                    created_at: p.created_at,
                    updated_at: p.updated_at,
                };
                Ok(HttpResponse::Ok().json(profile))
            } else {
                Ok(HttpResponse::InternalServerError().finish())
            }
        }
        Err(Status { .. }) => Ok(HttpResponse::ServiceUnavailable().finish()),
    }
}

/// POST /api/v2/users/avatar
/// Upload user avatar
pub async fn upload_avatar(
    http_req: HttpRequest,
    req: web::Json<AvatarUploadRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    if http_req
        .extensions()
        .get::<AuthenticatedUser>()
        .copied()
        .is_none()
    {
        return Ok(HttpResponse::Unauthorized().finish());
    }

    let user_id = http_req
        .extensions()
        .get::<AuthenticatedUser>()
        .copied()
        .map(|u| u.0)
        .unwrap();

    // Legacy flow: URL already available
    if let Some(url) = &req.url {
        info!(avatar_url = %url, "POST /api/v2/users/avatar (direct url)");

        let mut auth_client: AuthServiceClient<_> = clients.auth_client();
        let update_req = UpdateUserProfileRequest {
            user_id: user_id.to_string(),
            display_name: None,
            bio: None,
            avatar_url: Some(url.clone()),
            cover_photo_url: None,
            location: None,
            private_account: None,
        };

        return match auth_client
            .update_user_profile(tonic::Request::new(update_req))
            .await
        {
            Ok(resp) => {
                let inner = resp.into_inner();
                if let Some(err) = inner.error {
                    Ok(HttpResponse::BadRequest().json(serde_json::json!({
                        "error": err.message
                    })))
                } else {
                    Ok(HttpResponse::Ok().json(serde_json::json!({
                        "status": "avatar_updated",
                        "url": url,
                    })))
                }
            }
            Err(e) => {
                error!("update avatar failed: {}", e);
                Ok(HttpResponse::ServiceUnavailable().finish())
            }
        };
    }

    // Presign flow via media-service
    let file_name = match &req.file_name {
        Some(name) => name.clone(),
        None => {
            return Ok(
                HttpResponse::BadRequest().body("file_name is required when url is not provided")
            )
        }
    };
    let file_size = req.file_size.unwrap_or(0);
    let content_type = req
        .content_type
        .clone()
        .unwrap_or_else(|| "application/octet-stream".to_string());

    info!(
        %file_name,
        file_size,
        %content_type,
        "POST /api/v2/users/avatar (presign via media-service)"
    );

    let mut media_client: MediaServiceClient<_> = clients.media_client();
    let start_req = InitiateUploadRequest {
        user_id: user_id.to_string(),
        filename: file_name,
        media_type: MediaType::Image as i32,
        mime_type: content_type,
        size_bytes: file_size,
    };

    match media_client.initiate_upload(start_req).await {
        Ok(resp) => Ok(HttpResponse::Ok().json(resp.into_inner())),
        Err(e) => {
            error!("media StartUpload failed: {}", e);
            Ok(HttpResponse::ServiceUnavailable().finish())
        }
    }
}
