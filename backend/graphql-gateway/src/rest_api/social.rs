//! Social Graph API endpoints (Friends, Recommendations, Devices, etc.)
//!
//! GET /api/v2/search/users - Search users
//! GET /api/v2/friends/recommendations - Get friend recommendations
//! POST /api/v2/friends/add - Add friend
//! DELETE /api/v2/friends/remove - Remove friend
//! GET /api/v2/friends/list - Get friends list
//! GET /api/v2/devices - Get login devices
//! POST /api/v2/devices/logout - Logout from device
//! GET /api/v2/devices/current - Get current device

#![allow(dead_code)]
/// POST /api/v2/accounts/switch - Switch account
/// POST /api/v2/invitations/generate - Generate invite code
/// POST /api/v2/chat/groups/create - Create group chat
use actix_web::{web, HttpMessage, HttpRequest, HttpResponse, Result};
use serde::{Deserialize, Serialize};
use tracing::{error, info};

use crate::clients::proto::auth::{
    auth_service_client::AuthServiceClient, GenerateInviteRequest, GetCurrentDeviceRequest,
    GetInvitationStatsRequest, ListDevicesRequest, ListInvitationsRequest, LogoutDeviceRequest,
};
use crate::clients::proto::chat::{ConversationType, CreateConversationRequest};
use crate::clients::proto::social::{
    FollowUserRequest as GrpcFollowUserRequest, GetFollowingRequest as GrpcGetFollowingRequest,
    UnfollowUserRequest as GrpcUnfollowUserRequest,
};
use crate::clients::ServiceClients;
use crate::middleware::jwt::AuthenticatedUser;

#[derive(Debug, Serialize)]
pub struct UserCard {
    pub id: String,
    pub username: String,
    pub display_name: String,
    pub avatar_url: Option<String>,
    pub bio: Option<String>,
    pub is_following: bool,
}

#[derive(Debug, Deserialize)]
pub struct SearchRequest {
    pub q: String,
    pub limit: Option<u32>,
}

#[derive(Debug, Deserialize)]
pub struct FriendActionRequest {
    pub user_id: String,
}

#[derive(Debug, Serialize)]
pub struct Device {
    pub id: String,
    pub name: String,
    pub device_type: String, // "mobile", "web", "desktop"
    pub os: String,
    pub last_active: i64,
    pub is_current: bool,
}

#[derive(Debug, Deserialize)]
pub struct GroupChatRequest {
    pub name: String,
    pub member_ids: Vec<String>,
    pub description: Option<String>,
}

/// Simple device view derived from request context
fn current_device_from_request(req: &HttpRequest) -> Device {
    let ua = req
        .headers()
        .get("User-Agent")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("unknown");
    let ip = req
        .connection_info()
        .realip_remote_addr()
        .unwrap_or("0.0.0.0")
        .to_string();
    let device_id = format!(
        "dev_{}",
        md5::compute(format!("{}:{}", ua, ip))
            .0
            .iter()
            .map(|b| format!("{:02x}", b))
            .collect::<String>()
    );

    Device {
        id: device_id,
        name: ua.to_string(),
        device_type: "unknown".to_string(),
        os: "unknown".to_string(),
        last_active: chrono::Utc::now().timestamp(),
        is_current: true,
    }
}

/// GET /api/v2/search/users?q={query}
/// Search users
pub async fn search_users(
    query: web::Query<SearchRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!(q = %query.q, "GET /api/v2/search/users");

    let mut search_client = clients.search_client();
    let req = tonic::Request::new(crate::clients::proto::search::SearchUsersRequest {
        query: query.q.clone(),
        filter: None,
        limit: query.limit.unwrap_or(20) as i32,
        offset: 0,
    });

    match clients
        .call_search(|| async move { search_client.search_users(req).await })
        .await
    {
        Ok(resp) => Ok(HttpResponse::Ok().json(resp)),
        Err(e) => {
            error!("search_users failed: {}", e);
            Ok(HttpResponse::ServiceUnavailable().finish())
        }
    }
}

/// GET /api/v2/friends/recommendations
/// Get friend recommendations
pub async fn get_recommendations(
    query: web::Query<std::collections::HashMap<String, String>>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let limit = query
        .get("limit")
        .and_then(|l| l.parse::<u32>().ok())
        .unwrap_or(10);

    info!(limit = limit, "GET /api/v2/friends/recommendations");

    // Placeholder: until recommendation RPC is available, degrade gracefully
    let mut search_client = clients.search_client();
    let req = tonic::Request::new(crate::clients::proto::search::GetSearchSuggestionsRequest {
        query: "".to_string(),
        limit: limit as i32,
    });

    match clients
        .call_search(|| async move { search_client.get_search_suggestions(req).await })
        .await
    {
        Ok(resp) => Ok(HttpResponse::Ok().json(resp)),
        Err(e) => {
            error!("get_recommendations failed: {}", e);
            Ok(HttpResponse::ServiceUnavailable().finish())
        }
    }
}

/// POST /api/v2/friends/add
/// Add friend (follow user in social-service)
pub async fn add_friend(
    http_req: HttpRequest,
    req: web::Json<FriendActionRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    // Extract authenticated user ID from JWT middleware
    let authenticated_user = http_req
        .extensions()
        .get::<AuthenticatedUser>()
        .copied()
        .ok_or_else(|| actix_web::error::ErrorUnauthorized("Not authenticated"))?;

    let follower_id = authenticated_user.0.to_string();

    info!(
        follower_id = %follower_id,
        followee_id = %req.user_id,
        "POST /api/v2/friends/add"
    );

    // Call social-service FollowUser RPC
    let mut social_client = clients.social_client();
    let grpc_request = tonic::Request::new(GrpcFollowUserRequest {
        follower_id: follower_id.clone(),
        followee_id: req.user_id.clone(),
    });

    match clients
        .call_social(|| async move { social_client.follow_user(grpc_request).await })
        .await
    {
        Ok(_) => {
            info!(
                follower_id = %follower_id,
                followee_id = %req.user_id,
                "Friend added successfully"
            );

            Ok(HttpResponse::Ok().json(serde_json::json!({
                "status": "friend_added",
                "user_id": req.user_id,
            })))
        }
        Err(e) => {
            error!(
                follower_id = %follower_id,
                followee_id = %req.user_id,
                error = %e,
                "Failed to add friend"
            );

            // Map ServiceError to HTTP response
            Ok(HttpResponse::InternalServerError().json(serde_json::json!({
                "error": "failed_to_add_friend",
                "message": e.to_string(),
            })))
        }
    }
}

/// DELETE /api/v2/friends/remove
/// Remove friend (unfollow user in social-service)
pub async fn remove_friend(
    http_req: HttpRequest,
    req: web::Json<FriendActionRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    // Extract authenticated user ID from JWT middleware
    let authenticated_user = http_req
        .extensions()
        .get::<AuthenticatedUser>()
        .copied()
        .ok_or_else(|| actix_web::error::ErrorUnauthorized("Not authenticated"))?;

    let follower_id = authenticated_user.0.to_string();

    info!(
        follower_id = %follower_id,
        followee_id = %req.user_id,
        "DELETE /api/v2/friends/remove"
    );

    // Call social-service UnfollowUser RPC
    let mut social_client = clients.social_client();
    let grpc_request = tonic::Request::new(GrpcUnfollowUserRequest {
        follower_id: follower_id.clone(),
        followee_id: req.user_id.clone(),
    });

    match clients
        .call_social(|| async move { social_client.unfollow_user(grpc_request).await })
        .await
    {
        Ok(_) => {
            info!(
                follower_id = %follower_id,
                followee_id = %req.user_id,
                "Friend removed successfully"
            );

            Ok(HttpResponse::Ok().json(serde_json::json!({
                "status": "friend_removed",
                "user_id": req.user_id,
            })))
        }
        Err(e) => {
            error!(
                follower_id = %follower_id,
                followee_id = %req.user_id,
                error = %e,
                "Failed to remove friend"
            );

            Ok(HttpResponse::InternalServerError().json(serde_json::json!({
                "error": "failed_to_remove_friend",
                "message": e.to_string(),
            })))
        }
    }
}

/// GET /api/v2/friends/list
/// Get friends list (users you are following)
pub async fn get_friends_list(
    http_req: HttpRequest,
    query: web::Query<std::collections::HashMap<String, String>>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    // Extract authenticated user ID from JWT middleware
    let authenticated_user = http_req
        .extensions()
        .get::<AuthenticatedUser>()
        .copied()
        .ok_or_else(|| actix_web::error::ErrorUnauthorized("Not authenticated"))?;

    let user_id = authenticated_user.0.to_string();

    let limit = query
        .get("limit")
        .and_then(|l| l.parse::<i32>().ok())
        .unwrap_or(50);

    let offset = query
        .get("offset")
        .and_then(|o| o.parse::<i32>().ok())
        .unwrap_or(0);

    info!(
        user_id = %user_id,
        limit = limit,
        offset = offset,
        "GET /api/v2/friends/list"
    );

    // Call social-service GetFollowing RPC
    let mut social_client = clients.social_client();
    let grpc_request = tonic::Request::new(GrpcGetFollowingRequest {
        user_id: user_id.clone(),
        limit,
        offset,
    });

    match clients
        .call_social(|| async move { social_client.get_following(grpc_request).await })
        .await
    {
        Ok(response) => {
            info!(user_id = %user_id, total = response.total, "Friends list retrieved successfully");

            Ok(HttpResponse::Ok().json(serde_json::json!({
                "friends": response.user_ids,
                "total": response.total,
            })))
        }
        Err(e) => {
            error!(
                user_id = %user_id,
                error = %e,
                "Failed to get friends list"
            );

            Ok(HttpResponse::InternalServerError().json(serde_json::json!({
                "error": "failed_to_get_friends",
                "message": e.to_string(),
            })))
        }
    }
}

/// GET /api/v2/devices
/// Get login devices
pub async fn get_devices(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let Some(authed) = http_req.extensions().get::<AuthenticatedUser>().copied() else {
        return Ok(HttpResponse::Unauthorized().finish());
    };
    info!("GET /api/v2/devices");

    let mut auth_client: AuthServiceClient<_> = clients.auth_client();
    let req = ListDevicesRequest {
        user_id: authed.0.to_string(),
        limit: 50,
        offset: 0,
    };

    match clients
        .call_auth(|| async move { auth_client.list_devices(req).await })
        .await
    {
        Ok(resp) => Ok(HttpResponse::Ok().json(resp)),
        Err(e) => {
            error!("list_devices failed: {}", e);
            Ok(HttpResponse::ServiceUnavailable().finish())
        }
    }
}

/// POST /api/v2/devices/logout
/// Logout from device
pub async fn logout_device(
    http_req: HttpRequest,
    req: web::Json<serde_json::Value>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let Some(authed) = http_req.extensions().get::<AuthenticatedUser>().copied() else {
        return Ok(HttpResponse::Unauthorized().finish());
    };
    info!("POST /api/v2/devices/logout");

    let device_id = req
        .get("device_id")
        .and_then(|v| v.as_str())
        .unwrap_or_default();
    let all = req.get("all").and_then(|v| v.as_bool()).unwrap_or(false);

    let mut auth_client: AuthServiceClient<_> = clients.auth_client();
    let logout_req = LogoutDeviceRequest {
        user_id: authed.0.to_string(),
        device_id: device_id.to_string(),
        all,
    };

    match clients
        .call_auth(|| async move { auth_client.logout_device(logout_req).await })
        .await
    {
        Ok(resp) => Ok(HttpResponse::Ok().json(resp)),
        Err(e) => {
            error!("logout_device failed: {}", e);
            Ok(HttpResponse::ServiceUnavailable().finish())
        }
    }
}

/// GET /api/v2/devices/current
/// Get current device info
pub async fn get_current_device(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let Some(authed) = http_req.extensions().get::<AuthenticatedUser>().copied() else {
        return Ok(HttpResponse::Unauthorized().finish());
    };
    info!("GET /api/v2/devices/current");

    let mut auth_client: AuthServiceClient<_> = clients.auth_client();
    let req = GetCurrentDeviceRequest {
        user_id: authed.0.to_string(),
        device_id: None,
    };

    match clients
        .call_auth(|| async move { auth_client.get_current_device(req).await })
        .await
    {
        Ok(resp) => Ok(HttpResponse::Ok().json(resp)),
        Err(e) => {
            error!("get_current_device failed: {}", e);
            Ok(HttpResponse::ServiceUnavailable().finish())
        }
    }
}

/// POST /api/v2/invitations/generate
/// Generate invite code
pub async fn generate_invite_code(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let Some(authed) = http_req.extensions().get::<AuthenticatedUser>().copied() else {
        return Ok(HttpResponse::Unauthorized().finish());
    };
    info!("POST /api/v2/invitations/generate");

    let issuer = authed.0;

    let mut auth_client: AuthServiceClient<_> = clients.auth_client();
    let req = GenerateInviteRequest {
        issuer_user_id: issuer.to_string(),
        target_email: None,
        target_phone: None,
        expires_at: None,
    };

    match clients
        .call_auth(|| async move { auth_client.generate_invite(req).await })
        .await
    {
        Ok(resp) => Ok(HttpResponse::Ok().json(resp)),
        Err(e) => {
            error!("generate_invite failed: {}", e);
            Ok(HttpResponse::ServiceUnavailable().finish())
        }
    }
}

/// GET /api/v2/invitations
/// List user's invitations
pub async fn list_invitations(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let Some(authed) = http_req.extensions().get::<AuthenticatedUser>().copied() else {
        return Ok(HttpResponse::Unauthorized().finish());
    };
    info!("GET /api/v2/invitations");

    let user_id = authed.0;

    let mut auth_client: AuthServiceClient<_> = clients.auth_client();
    let req = ListInvitationsRequest {
        user_id: user_id.to_string(),
        limit: Some(50),
        offset: None,
    };

    match clients
        .call_auth(|| async move { auth_client.list_invitations(req).await })
        .await
    {
        Ok(resp) => Ok(HttpResponse::Ok().json(resp)),
        Err(e) => {
            error!("list_invitations failed: {}", e);
            Ok(HttpResponse::ServiceUnavailable().finish())
        }
    }
}

/// GET /api/v2/invitations/stats
/// Get invitation statistics
pub async fn get_invitation_stats(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let Some(authed) = http_req.extensions().get::<AuthenticatedUser>().copied() else {
        return Ok(HttpResponse::Unauthorized().finish());
    };
    info!("GET /api/v2/invitations/stats");

    let user_id = authed.0;

    let mut auth_client: AuthServiceClient<_> = clients.auth_client();
    let req = GetInvitationStatsRequest {
        user_id: user_id.to_string(),
    };

    match clients
        .call_auth(|| async move { auth_client.get_invitation_stats(req).await })
        .await
    {
        Ok(resp) => Ok(HttpResponse::Ok().json(resp)),
        Err(e) => {
            error!("get_invitation_stats failed: {}", e);
            Ok(HttpResponse::ServiceUnavailable().finish())
        }
    }
}

/// POST /api/v2/chat/groups/create
/// Create group chat
///
/// NOTE: realtime_chat.proto currently doesn't have a CreateGroupChat or CreateConversation RPC.
/// The proto only has operations on existing conversations (GetConversation, SendMessage, etc.).
///
/// TODO: Either:
/// 1. Add CreateConversation RPC to realtime_chat.proto with these fields:
///    - name: string
///    - conversation_type: ConversationType (GROUP)
///    - participant_ids: repeated string
/// 2. Or implement group creation via direct database access in realtime-chat-service
///    and expose through a new RPC
///
/// For now, keeping mock implementation until proto is extended.
pub async fn create_group_chat(
    http_req: HttpRequest,
    req: web::Json<GroupChatRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    // Extract authenticated user ID from JWT middleware
    let authenticated_user = http_req
        .extensions()
        .get::<AuthenticatedUser>()
        .copied()
        .ok_or_else(|| actix_web::error::ErrorUnauthorized("Not authenticated"))?;

    let creator_id = authenticated_user.0.to_string();
    let mut members = req.member_ids.clone();
    if !members.iter().any(|m| m == &creator_id) {
        members.push(creator_id.clone());
    }

    info!(
        creator_id = %creator_id,
        group_name = %req.name,
        member_count = %req.member_ids.len(),
        "POST /api/v2/chat/groups/create"
    );

    let mut chat_client = clients.chat_client();
    let grpc_request = CreateConversationRequest {
        name: req.name.clone(),
        conversation_type: ConversationType::Group as i32,
        participant_ids: members,
    };

    match clients
        .call_chat(|| async move { chat_client.create_conversation(grpc_request).await })
        .await
    {
        Ok(resp) => Ok(HttpResponse::Ok().json(resp)),
        Err(e) => {
            error!("create_group_chat failed: {}", e);
            Ok(HttpResponse::ServiceUnavailable().finish())
        }
    }
}
