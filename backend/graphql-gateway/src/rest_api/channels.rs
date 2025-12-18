/// Channels API endpoints
///
/// GET /api/v2/channels - Get all channels
/// GET /api/v2/channels/{id} - Get channel details
/// GET /api/v2/users/{id}/channels - Get user subscribed channels
/// POST /api/v2/channels/subscribe - Subscribe to channel
/// DELETE /api/v2/channels/unsubscribe - Unsubscribe from channel
/// POST /api/v2/channels/suggest - AI-powered channel suggestions for post content
use actix_web::{web, HttpMessage, HttpRequest, HttpResponse, Result};
use serde::{Deserialize, Serialize};
use tracing::{debug, error, info};

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
                    description: if c.description.is_empty() {
                        None
                    } else {
                        Some(c.description)
                    },
                    category: c.category,
                    subscriber_count: c.subscriber_count,
                    is_subscribed: false,
                    slug: c.slug,
                    icon_url: if c.icon_url.is_empty() {
                        None
                    } else {
                        Some(c.icon_url)
                    },
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
                description: if c.description.is_empty() {
                    None
                } else {
                    Some(c.description)
                },
                category: c.category,
                subscriber_count: c.subscriber_count,
                is_subscribed: false,
                slug: c.slug,
                icon_url: if c.icon_url.is_empty() {
                    None
                } else {
                    Some(c.icon_url)
                },
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

// ============================================
// Channel Suggestion API (AI-powered)
// ============================================

#[derive(Debug, Deserialize)]
pub struct SuggestChannelsRequest {
    /// Post content text
    pub content: String,
    /// Optional hashtags from Alice image analysis
    #[serde(default)]
    pub hashtags: Vec<String>,
    /// Optional themes from Alice image analysis
    #[serde(default)]
    pub themes: Vec<String>,
}

#[derive(Debug, Serialize)]
pub struct ChannelSuggestion {
    pub id: String,
    pub name: String,
    pub slug: String,
    /// Confidence score (0.0 - 1.0)
    pub confidence: f32,
    /// Keywords that matched
    pub matched_keywords: Vec<String>,
}

#[derive(Debug, Serialize)]
pub struct SuggestChannelsResponse {
    pub suggestions: Vec<ChannelSuggestion>,
}

/// POST /api/v2/channels/suggest
/// AI-powered channel suggestions for post content
///
/// Request body:
/// {
///   "content": "My post text...",
///   "hashtags": ["#fitness", "#gym"],  // optional, from Alice
///   "themes": ["workout", "health"]     // optional, from Alice
/// }
///
/// Response:
/// {
///   "suggestions": [
///     { "id": "uuid", "name": "Fitness", "slug": "fitness", "confidence": 0.85, "matched_keywords": ["fitness", "gym"] }
///   ]
/// }
pub async fn suggest_channels(
    req: web::Json<SuggestChannelsRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!(
        content_len = req.content.len(),
        hashtags_count = req.hashtags.len(),
        themes_count = req.themes.len(),
        "POST /api/v2/channels/suggest"
    );

    // Fetch all enabled channels with topic_keywords
    let mut content_client = clients.content_client();
    let channels_req = ListChannelsRequest {
        limit: 100,
        offset: 0,
        category: String::new(),
        enabled_only: true,
    };

    let channels = match content_client.list_channels(channels_req).await {
        Ok(resp) => resp.into_inner().channels,
        Err(e) => {
            error!("Failed to fetch channels for suggestion: {}", e);
            return Ok(HttpResponse::ServiceUnavailable().json(serde_json::json!({
                "error": "Failed to fetch channels"
            })));
        }
    };

    if channels.is_empty() {
        return Ok(HttpResponse::Ok().json(SuggestChannelsResponse {
            suggestions: vec![],
        }));
    }

    // Build combined text for matching
    let mut all_text = req.content.to_lowercase();

    // Add hashtags (remove # prefix)
    for tag in &req.hashtags {
        all_text.push(' ');
        all_text.push_str(&tag.trim_start_matches('#').to_lowercase());
    }

    // Add themes
    for theme in &req.themes {
        all_text.push(' ');
        all_text.push_str(&theme.to_lowercase());
    }

    debug!(
        combined_text_len = all_text.len(),
        "Combined text for classification"
    );

    // Tokenize content into words
    let content_words: Vec<&str> = all_text
        .split(|c: char| !c.is_alphanumeric())
        .filter(|s| !s.is_empty() && s.len() > 2)
        .collect();

    // Score each channel
    let mut suggestions: Vec<ChannelSuggestion> = Vec::new();
    let min_confidence = 0.25;
    let max_suggestions = 3;

    for channel in &channels {
        // Parse topic_keywords from JSON string
        let topic_keywords: Vec<String> = if channel.topic_keywords.is_empty() {
            vec![]
        } else {
            serde_json::from_str(&channel.topic_keywords).unwrap_or_default()
        };

        if topic_keywords.is_empty() {
            continue;
        }

        let (score, matched) = score_channel(&content_words, &all_text, &topic_keywords);

        if score >= min_confidence && !matched.is_empty() {
            suggestions.push(ChannelSuggestion {
                id: channel.id.clone(),
                name: channel.name.clone(),
                slug: channel.slug.clone(),
                confidence: score,
                matched_keywords: matched,
            });
        }
    }

    // Sort by confidence descending
    suggestions.sort_by(|a, b| {
        b.confidence
            .partial_cmp(&a.confidence)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    // Limit to max suggestions
    suggestions.truncate(max_suggestions);

    info!(
        suggestions_count = suggestions.len(),
        "Channel suggestions generated"
    );

    Ok(HttpResponse::Ok().json(SuggestChannelsResponse { suggestions }))
}

/// Score a channel based on keyword matches
fn score_channel(
    content_words: &[&str],
    full_text: &str,
    topic_keywords: &[String],
) -> (f32, Vec<String>) {
    let mut matched_keywords = Vec::new();
    let mut total_weight = 0.0f32;

    for keyword in topic_keywords {
        let keyword_lower = keyword.to_lowercase();

        // Check for exact word match (higher weight)
        let exact_match = content_words.iter().any(|&w| w == keyword_lower);

        // Check for substring match (lower weight)
        let substring_match = !exact_match && full_text.contains(&keyword_lower);

        if exact_match {
            matched_keywords.push(keyword.clone());
            total_weight += 1.0;
        } else if substring_match {
            matched_keywords.push(keyword.clone());
            total_weight += 0.5;
        }
    }

    // Normalize score with diminishing returns
    let keyword_count = topic_keywords.len() as f32;
    let base_score = if keyword_count > 0.0 {
        (total_weight / keyword_count).min(1.0)
    } else {
        0.0
    };

    // Boost score based on number of matches
    let match_boost = (matched_keywords.len() as f32 * 0.1).min(0.3);
    let final_score = (base_score + match_boost).min(1.0);

    (final_score, matched_keywords)
}
