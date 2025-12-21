//! User Profile Settings API endpoints
//!
//! GET /api/v2/users/{id} - Get user profile
//! GET /api/v2/users/username/{username} - Get user profile by username
//! PUT /api/v2/users/{id} - Update user profile
//! POST /api/v2/users/avatar - Upload user avatar

#![allow(dead_code)]

use actix_web::{web, HttpMessage, HttpRequest, HttpResponse, Result};
use serde::{Deserialize, Serialize};
use tracing::{error, info};

use crate::clients::proto::auth::{
    auth_service_client::AuthServiceClient, Gender, GetUserByUsernameRequest,
    GetUserProfilesByIdsRequest, UpdateUserProfileRequest,
};
use crate::clients::proto::media::{
    media_service_client::MediaServiceClient, InitiateUploadRequest, MediaType,
};
use crate::clients::ServiceClients;
use crate::middleware::jwt::AuthenticatedUser;
use tonic::Status;

/// Convert Gender enum (i32) to display string
fn gender_to_string(gender: i32) -> Option<String> {
    match Gender::try_from(gender) {
        Ok(Gender::Male) => Some("male".to_string()),
        Ok(Gender::Female) => Some("female".to_string()),
        Ok(Gender::Other) => Some("other".to_string()),
        Ok(Gender::PreferNotToSay) => Some("prefer_not_to_say".to_string()),
        Ok(Gender::Unspecified) | Err(_) => None,
    }
}

/// Convert string to Gender enum (i32)
fn string_to_gender(s: Option<&String>) -> i32 {
    match s.map(|s| s.to_lowercase()).as_deref() {
        Some("male") => Gender::Male as i32,
        Some("female") => Gender::Female as i32,
        Some("other") => Gender::Other as i32,
        Some("prefer_not_to_say") => Gender::PreferNotToSay as i32,
        _ => Gender::Unspecified as i32,
    }
}

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
    pub avatar_url: Option<String>,
    pub cover_url: Option<String>,
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

#[derive(Debug, Deserialize)]
pub struct BatchProfilesRequest {
    pub user_ids: Vec<String>,
}

#[derive(Debug, Serialize)]
pub struct BatchProfilesResponse {
    pub profiles: Vec<BatchProfile>,
}

#[derive(Debug, Serialize)]
pub struct BatchProfile {
    pub user_id: String,
    pub username: String,
    pub display_name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub avatar_url: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct UserProfileResponse {
    pub id: String,
    pub username: String,
    pub email: String,
    pub display_name: Option<String>,
    pub first_name: Option<String>,
    pub last_name: Option<String>,
    pub avatar_url: Option<String>,
    pub cover_url: Option<String>,
    pub bio: Option<String>,
    pub location: Option<String>,
    pub date_of_birth: Option<String>,
    pub gender: Option<String>,
    pub website: Option<String>,
    pub is_verified: bool,
    pub is_private: bool,
    pub follower_count: i32,
    pub following_count: i32,
    pub post_count: i32,
    pub created_at: i64,
    pub updated_at: i64,
}

/// POST /api/v2/auth/users/profiles/batch
/// Batch fetch basic profiles (username/display_name/avatar_url)
pub async fn batch_get_profiles(
    http_req: HttpRequest,
    req: web::Json<BatchProfilesRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let authed = http_req.extensions().get::<AuthenticatedUser>().copied();
    if authed.is_none() {
        return Ok(HttpResponse::Unauthorized().finish());
    }

    if req.user_ids.is_empty() {
        return Ok(HttpResponse::Ok().json(BatchProfilesResponse { profiles: vec![] }));
    }

    let mut auth_client: AuthServiceClient<_> = clients.auth_client();
    let batch_req = tonic::Request::new(GetUserProfilesByIdsRequest {
        user_ids: req.user_ids.clone(),
    });

    let resp = match auth_client.get_user_profiles_by_ids(batch_req).await {
        Ok(resp) => resp.into_inner(),
        Err(e) => {
            error!("get_user_profiles_by_ids failed: {}", e);
            return Ok(HttpResponse::ServiceUnavailable().finish());
        }
    };

    if let Some(err) = resp.error {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": err.message
        })));
    }

    let profiles = resp
        .profiles
        .into_iter()
        .map(|p| {
            let display_name = p.display_name.clone().unwrap_or_else(|| p.username.clone());
            BatchProfile {
                user_id: p.user_id,
                username: p.username,
                display_name,
                avatar_url: p.avatar_url,
            }
        })
        .collect();

    Ok(HttpResponse::Ok().json(BatchProfilesResponse { profiles }))
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

    // Use get_user_profiles_by_ids to get full profile with extended fields
    let mut auth_client: AuthServiceClient<_> = clients.auth_client();
    let req = tonic::Request::new(GetUserProfilesByIdsRequest {
        user_ids: vec![user_id.to_string()],
    });
    let resp = match auth_client.get_user_profiles_by_ids(req).await {
        Ok(resp) => resp.into_inner(),
        Err(e) => {
            error!("get_user_profiles_by_ids failed: {}", e);
            return Ok(HttpResponse::ServiceUnavailable().finish());
        }
    };

    if let Some(err) = resp.error {
        return Ok(HttpResponse::NotFound().json(serde_json::json!({
            "error": err.message
        })));
    }

    // Get the first (and only) profile from the batch response
    if let Some(p) = resp.profiles.into_iter().next() {
        // Build display_name from first_name and last_name if not set
        let display_name =
            p.display_name
                .or_else(|| match (p.first_name.as_ref(), p.last_name.as_ref()) {
                    (Some(f), Some(l)) if !f.is_empty() && !l.is_empty() => {
                        Some(format!("{} {}", f, l))
                    }
                    (Some(f), _) if !f.is_empty() => Some(f.clone()),
                    (_, Some(l)) if !l.is_empty() => Some(l.clone()),
                    _ => None,
                });

        let profile = UserProfileResponse {
            id: p.user_id,
            username: p.username,
            email: p.email.unwrap_or_default(),
            display_name,
            first_name: p.first_name,
            last_name: p.last_name,
            avatar_url: p.avatar_url,
            cover_url: p.cover_photo_url,
            bio: p.bio,
            location: p.location,
            date_of_birth: p.date_of_birth,
            gender: gender_to_string(p.gender),
            website: None,
            is_verified: false,
            is_private: p.is_private,
            follower_count: 0,
            following_count: 0,
            post_count: 0,
            created_at: p.created_at,
            updated_at: p.updated_at,
        };
        // Wrap in "user" object to match iOS client expected format
        return Ok(HttpResponse::Ok().json(serde_json::json!({
            "user": profile
        })));
    }

    Ok(HttpResponse::NotFound().finish())
}

/// GET /api/v2/users/username/{username}
/// Get user profile by username
pub async fn get_profile_by_username(
    http_req: HttpRequest,
    username: web::Path<String>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let authed = http_req.extensions().get::<AuthenticatedUser>().copied();
    if authed.is_none() {
        return Ok(HttpResponse::Unauthorized().finish());
    }

    info!(username = %username, "GET /api/v2/users/username/{username}");

    let mut auth_client: AuthServiceClient<_> = clients.auth_client();

    // First, get user by username to obtain the user_id
    let req = tonic::Request::new(GetUserByUsernameRequest {
        username: username.to_string(),
    });
    let user_resp = match auth_client.get_user_by_username(req).await {
        Ok(resp) => resp.into_inner(),
        Err(e) => {
            error!("get_user_by_username failed: {}", e);
            if e.code() == tonic::Code::NotFound {
                return Ok(HttpResponse::NotFound().json(serde_json::json!({
                    "error": "User not found"
                })));
            }
            return Ok(HttpResponse::ServiceUnavailable().finish());
        }
    };

    if let Some(err) = user_resp.error {
        return Ok(HttpResponse::NotFound().json(serde_json::json!({
            "error": err.message
        })));
    }

    let user_id = match user_resp.user {
        Some(u) => u.id,
        None => return Ok(HttpResponse::NotFound().finish()),
    };

    // Now get full profile using user_id
    let profile_req = tonic::Request::new(GetUserProfilesByIdsRequest {
        user_ids: vec![user_id.clone()],
    });
    let profile_resp = match auth_client.get_user_profiles_by_ids(profile_req).await {
        Ok(resp) => resp.into_inner(),
        Err(e) => {
            error!("get_user_profiles_by_ids failed: {}", e);
            return Ok(HttpResponse::ServiceUnavailable().finish());
        }
    };

    if let Some(err) = profile_resp.error {
        return Ok(HttpResponse::NotFound().json(serde_json::json!({
            "error": err.message
        })));
    }

    if let Some(p) = profile_resp.profiles.into_iter().next() {
        // Build display_name from first_name and last_name if not set
        let display_name =
            p.display_name
                .or_else(|| match (p.first_name.as_ref(), p.last_name.as_ref()) {
                    (Some(f), Some(l)) if !f.is_empty() && !l.is_empty() => {
                        Some(format!("{} {}", f, l))
                    }
                    (Some(f), _) if !f.is_empty() => Some(f.clone()),
                    (_, Some(l)) if !l.is_empty() => Some(l.clone()),
                    _ => None,
                });

        let profile = UserProfileResponse {
            id: p.user_id,
            username: p.username,
            email: p.email.unwrap_or_default(),
            display_name,
            first_name: p.first_name,
            last_name: p.last_name,
            avatar_url: p.avatar_url,
            cover_url: p.cover_photo_url,
            bio: p.bio,
            location: p.location,
            date_of_birth: p.date_of_birth,
            gender: gender_to_string(p.gender),
            website: None,
            is_verified: false,
            is_private: p.is_private,
            follower_count: 0,
            following_count: 0,
            post_count: 0,
            created_at: p.created_at,
            updated_at: p.updated_at,
        };
        // Wrap in "user" object to match iOS client expected format
        return Ok(HttpResponse::Ok().json(serde_json::json!({
            "user": profile
        })));
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
        avatar_url = ?req.avatar_url,
        "PUT /api/v2/users/{user_id}"
    );

    let mut auth_client: AuthServiceClient<_> = clients.auth_client();

    // Build display_name from first_name + last_name if provided
    let display_name = match (&req.first_name, &req.last_name) {
        (Some(f), Some(l)) => Some(format!("{} {}", f, l)),
        (Some(f), None) => Some(f.clone()),
        (None, Some(l)) => Some(l.clone()),
        (None, None) => None,
    };

    let update_req = UpdateUserProfileRequest {
        user_id: user_id.to_string(),
        display_name,
        bio: req.bio.clone(),
        avatar_url: req.avatar_url.clone(),
        cover_photo_url: req.cover_url.clone(),
        location: req.location.clone(),
        is_private: None,
        // Extended profile fields
        first_name: req.first_name.clone(),
        last_name: req.last_name.clone(),
        date_of_birth: req.date_of_birth.clone(),
        gender: string_to_gender(req.gender.as_ref()),
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
                // Build display_name from first_name and last_name if not set
                let display_name = p.display_name.or_else(|| {
                    match (p.first_name.as_ref(), p.last_name.as_ref()) {
                        (Some(f), Some(l)) if !f.is_empty() && !l.is_empty() => {
                            Some(format!("{} {}", f, l))
                        }
                        (Some(f), _) if !f.is_empty() => Some(f.clone()),
                        (_, Some(l)) if !l.is_empty() => Some(l.clone()),
                        _ => None,
                    }
                });

                let profile = UserProfileResponse {
                    id: p.user_id,
                    username: p.username,
                    email: p.email.unwrap_or_default(),
                    display_name,
                    first_name: p.first_name,
                    last_name: p.last_name,
                    avatar_url: p.avatar_url,
                    cover_url: p.cover_photo_url,
                    bio: p.bio,
                    location: p.location,
                    date_of_birth: p.date_of_birth,
                    gender: gender_to_string(p.gender),
                    website: None,
                    is_verified: false,
                    is_private: p.is_private,
                    follower_count: 0,
                    following_count: 0,
                    post_count: 0,
                    created_at: p.created_at,
                    updated_at: p.updated_at,
                };
                // Wrap in "user" object to match iOS client expected format
                Ok(HttpResponse::Ok().json(serde_json::json!({
                    "user": profile
                })))
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
    let Some(authed) = http_req.extensions().get::<AuthenticatedUser>().copied() else {
        return Ok(HttpResponse::Unauthorized().finish());
    };

    let user_id = authed.0;

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
            is_private: None,
            first_name: None,
            last_name: None,
            date_of_birth: None,
            gender: Gender::Unspecified as i32,
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
