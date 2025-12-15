/// Channels API endpoints
///
/// GET /api/v2/channels - Get all channels
/// GET /api/v2/channels/{id} - Get channel details
/// GET /api/v2/users/{id}/channels - Get user subscribed channels
/// POST /api/v2/channels/subscribe - Subscribe to channel
/// DELETE /api/v2/channels/unsubscribe - Unsubscribe from channel
use actix_web::{web, HttpMessage, HttpRequest, HttpResponse, Result};
use serde::{Deserialize, Serialize};
use tracing::{error, info};

use crate::clients::proto::auth::{ListUserChannelsRequest, UpdateUserChannelsRequest};
use crate::clients::proto::content::{GetChannelRequest, ListChannelsRequest};
use crate::clients::ServiceClients;
use crate::middleware::jwt::AuthenticatedUser;

#[derive(Debug, Serialize)]
pub struct Channel {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub category: String,
    pub subscriber_count: u32,
    pub is_subscribed: bool,
    pub slug: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub icon_url: Option<String>,
    pub display_order: i32,
    pub is_enabled: bool,
}

#[derive(Debug, Serialize)]
pub struct ChannelsListResponse {
    pub channels: Vec<Channel>,
    pub total: u32,
}

#[derive(Debug, Deserialize)]
pub struct ChannelSubscriptionRequest {
    pub channel_id: String,
}

/// GET /api/v2/channels
/// Get all channels with pagination
/// Query parameters:
///   - limit: Number of channels to return (default: 50)
///   - offset: Pagination offset (default: 0)
///   - category: Filter by category (optional)
///   - enabled_only: Only return enabled channels (default: true)
pub async fn get_all_channels(
    query: web::Query<std::collections::HashMap<String, String>>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let limit = query
        .get("limit")
        .and_then(|l| l.parse::<u32>().ok())
        .unwrap_or(50);

    let offset = query
        .get("offset")
        .and_then(|o| o.parse::<u32>().ok())
        .unwrap_or(0);

    let category = query.get("category").cloned().unwrap_or_default();

    // Default to enabled_only=true for client requests
    let enabled_only = query
        .get("enabled_only")
        .map(|v| v == "true" || v == "1")
        .unwrap_or(true);

    info!(
        limit = limit,
        offset = offset,
        category = %category,
        enabled_only = enabled_only,
        "GET /api/v2/channels"
    );

    let mut content_client = clients.content_client();
    let req = ListChannelsRequest {
        limit: limit as i32,
        offset: offset as i32,
        category,
        enabled_only,
    };

    match content_client.list_channels(req).await {
        Ok(resp) => {
            let inner = resp.into_inner();
            let mut channels: Vec<Channel> = inner
                .channels
                .into_iter()
                .map(|c| Channel {
                    id: c.id,
                    name: c.name,
                    description: if c.description.is_empty() { None } else { Some(c.description) },
                    category: c.category,
                    subscriber_count: c.subscriber_count,
                    is_subscribed: false,
                    slug: c.slug,
                    icon_url: if c.icon_url.is_empty() { None } else { Some(c.icon_url) },
                    display_order: c.display_order,
                    is_enabled: c.is_enabled,
                })
                .collect();

            // Sort by display_order (ascending) for consistent ordering
            channels.sort_by_key(|c| c.display_order);

            Ok(HttpResponse::Ok().json(ChannelsListResponse {
                total: inner.total as u32,
                channels,
            }))
        }
        Err(e) => {
            error!("list_channels failed: {}", e);
            Ok(HttpResponse::ServiceUnavailable().finish())
        }
    }
}

/// GET /api/v2/channels/{id}
/// Get channel details
pub async fn get_channel_details(
    channel_id: web::Path<String>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!(channel_id = %channel_id, "GET /api/v2/channels/{channel_id}");

    let mut content_client = clients.content_client();
    let req = GetChannelRequest {
        id: channel_id.to_string(),
    };

    match content_client.get_channel(req).await {
        Ok(resp) => {
            let inner = resp.into_inner();
            if !inner.found || inner.channel.is_none() {
                return Ok(HttpResponse::NotFound().json(serde_json::json!({
                    "error": "channel_not_found"
                })));
            }
            let c = inner.channel.expect("channel was just checked");
            Ok(HttpResponse::Ok().json(Channel {
                id: c.id,
                name: c.name,
                description: if c.description.is_empty() { None } else { Some(c.description) },
                category: c.category,
                subscriber_count: c.subscriber_count,
                is_subscribed: false,
                slug: c.slug,
                icon_url: if c.icon_url.is_empty() { None } else { Some(c.icon_url) },
                display_order: c.display_order,
                is_enabled: c.is_enabled,
            }))
        }
        Err(e) => {
            error!("get_channel failed: {}", e);
            Ok(HttpResponse::ServiceUnavailable().finish())
        }
    }
}

/// GET /api/v2/users/{id}/channels
/// Get user's subscribed channels
pub async fn get_user_channels(
    http_req: HttpRequest,
    user_id: web::Path<String>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let authed = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    if authed != user_id.as_str() {
        return Ok(HttpResponse::Unauthorized().body("cannot view channels for other users"));
    }

    info!(user_id = %user_id, "GET /api/v2/users/{user_id}/channels");

    let mut auth_client = clients.auth_client();
    let req = ListUserChannelsRequest {
        user_id: user_id.to_string(),
    };

    match clients
        .call_auth(|| async move { auth_client.list_user_channels(req).await })
        .await
    {
        Ok(resp) => Ok(HttpResponse::Ok().json(serde_json::json!({
            "channels": resp.channel_ids,
            "total": resp.channel_ids.len(),
        }))),
        Err(e) => {
            error!("list_user_channels failed: {}", e);
            Ok(HttpResponse::ServiceUnavailable().finish())
        }
    }
}

/// POST /api/v2/channels/subscribe
/// Subscribe to channel
pub async fn subscribe_channel(
    http_req: HttpRequest,
    req: web::Json<ChannelSubscriptionRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let authed = if let Some(user) = http_req.extensions().get::<AuthenticatedUser>().copied() {
        user
    } else {
        return Ok(HttpResponse::Unauthorized().finish());
    };
    info!(channel_id = %req.channel_id, "POST /api/v2/channels/subscribe");

    let mut auth_client = clients.auth_client();
    let update_req = UpdateUserChannelsRequest {
        user_id: authed.0.to_string(),
        subscribe_ids: vec![req.channel_id.clone()],
        unsubscribe_ids: Vec::new(),
    };

    match clients
        .call_auth(|| async move { auth_client.update_user_channels(update_req).await })
        .await
    {
        Ok(resp) => Ok(HttpResponse::Ok().json(serde_json::json!({
            "status": "subscribed",
            "channel_id": req.channel_id,
            "subscriptions": resp.channel_ids,
        }))),
        Err(e) => {
            error!("subscribe_channel failed: {}", e);
            Ok(HttpResponse::ServiceUnavailable().finish())
        }
    }
}

/// DELETE /api/v2/channels/unsubscribe
/// Unsubscribe from channel
pub async fn unsubscribe_channel(
    http_req: HttpRequest,
    req: web::Json<ChannelSubscriptionRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let authed = if let Some(user) = http_req.extensions().get::<AuthenticatedUser>().copied() {
        user
    } else {
        return Ok(HttpResponse::Unauthorized().finish());
    };
    info!(channel_id = %req.channel_id, "DELETE /api/v2/channels/unsubscribe");

    let mut auth_client = clients.auth_client();
    let update_req = UpdateUserChannelsRequest {
        user_id: authed.0.to_string(),
        subscribe_ids: Vec::new(),
        unsubscribe_ids: vec![req.channel_id.clone()],
    };

    match clients
        .call_auth(|| async move { auth_client.update_user_channels(update_req).await })
        .await
    {
        Ok(resp) => Ok(HttpResponse::Ok().json(serde_json::json!({
            "status": "unsubscribed",
            "channel_id": req.channel_id,
            "subscriptions": resp.channel_ids,
        }))),
        Err(e) => {
            error!("unsubscribe_channel failed: {}", e);
            Ok(HttpResponse::ServiceUnavailable().finish())
        }
    }
}
