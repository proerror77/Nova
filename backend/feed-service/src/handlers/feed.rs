use actix_web::{get, post, web, HttpMessage, HttpRequest, HttpResponse};
use base64::{engine::general_purpose, Engine as _};
use serde::Deserialize;
use std::sync::Arc;
use tracing::{debug, warn};
use uuid::Uuid;

use crate::error::{AppError, Result};
use crate::grpc::clients::ContentServiceClient;
use grpc_clients::nova::content_service::v1::{GetFeedRequest, InvalidateFeedEventRequest};
use crate::middleware::jwt_auth::UserId;
use crate::models::FeedResponse;

#[derive(Debug, Deserialize)]
pub struct FeedQueryParams {
    #[serde(default = "default_algo")]
    pub algo: String,
    #[serde(default = "default_limit")]
    pub limit: u32,
    pub cursor: Option<String>,
}

fn default_algo() -> String {
    "ch".to_string()
}

fn default_limit() -> u32 {
    20
}

impl FeedQueryParams {
    fn decode_cursor(&self) -> Result<usize> {
        match &self.cursor {
            Some(cursor) if !cursor.is_empty() => {
                let decoded = general_purpose::STANDARD
                    .decode(cursor)
                    .map_err(|_| AppError::BadRequest("Invalid cursor format".to_string()))?;
                let offset_str = String::from_utf8(decoded)
                    .map_err(|_| AppError::BadRequest("Invalid cursor encoding".to_string()))?;
                offset_str
                    .parse::<usize>()
                    .map_err(|_| AppError::BadRequest("Invalid cursor value".to_string()))
            }
            _ => Ok(0),
        }
    }

    fn encode_cursor(offset: usize) -> String {
        general_purpose::STANDARD.encode(offset.to_string())
    }
}

pub struct FeedHandlerState {
    pub content_client: Arc<ContentServiceClient>,
}

#[get("")]
pub async fn get_feed(
    query: web::Query<FeedQueryParams>,
    http_req: HttpRequest,
    state: web::Data<FeedHandlerState>,
) -> Result<HttpResponse> {
    let user_id = http_req
        .extensions()
        .get::<UserId>()
        .map(|u| u.0)
        .ok_or_else(|| AppError::Authentication("Missing user context".into()))?;

    if query.algo != "ch" && query.algo != "time" {
        return Err(AppError::BadRequest(
            "Invalid algo parameter. Must be 'ch' or 'time'".to_string(),
        ));
    }

    let limit = query.limit.min(100).max(1);
    let offset = query.decode_cursor()?;

    debug!(
        "Proxy feed request to content-service: user={} algo={} limit={} offset={}",
        user_id, query.algo, limit, offset
    );

    let request = GetFeedRequest {
        user_id: user_id.to_string(),
        algo: query.algo.clone(),
        limit,
        cursor: query.cursor.clone().unwrap_or_default(),
    };

    let response = match state.content_client.get_feed(request).await {
        Ok(resp) => resp,
        Err(status) => {
            warn!(
                "Content-service feed request failed (user={}): status={}",
                user_id, status
            );
            return Err(AppError::Internal(format!(
                "Feed service unavailable: {}",
                status
            )));
        }
    };

    let posts: Vec<Uuid> = {
        let mut posts = Vec::with_capacity(response.post_ids.len());
        for id in response.post_ids {
            if let Ok(uuid) = Uuid::parse_str(&id) {
                posts.push(uuid);
            }
        }
        posts
    };

    let cursor = if response.cursor.is_empty() {
        None
    } else {
        Some(response.cursor)
    };

    Ok(HttpResponse::Ok().json(FeedResponse {
        posts,
        cursor,
        has_more: response.has_more,
        total_count: response.total_count as usize,
    }))
}

#[post("/invalidate")]
pub async fn invalidate_feed_cache(
    http_req: HttpRequest,
    state: web::Data<FeedHandlerState>,
) -> Result<HttpResponse> {
    let user_id = http_req
        .extensions()
        .get::<UserId>()
        .map(|u| u.0)
        .ok_or_else(|| AppError::Authentication("Missing user context".into()))?;

    let request = InvalidateFeedEventRequest {
        event_type: "manual_invalidate".to_string(),
        user_id: user_id.to_string(),
        target_user_id: String::new(),
    };

    state
        .content_client
        .invalidate_feed_event(request)
        .await
        .map_err(|status| AppError::Internal(status.to_string()))?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "success": true,
        "message": "Feed cache invalidated"
    })))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cursor_roundtrip() {
        let offset = 42;
        let encoded = FeedQueryParams::encode_cursor(offset);
        let params = FeedQueryParams {
            algo: default_algo(),
            limit: default_limit(),
            cursor: Some(encoded),
        };
        assert_eq!(params.decode_cursor().unwrap(), offset);
    }

    #[test]
    fn test_cursor_none_defaults_zero() {
        let params = FeedQueryParams {
            algo: default_algo(),
            limit: default_limit(),
            cursor: None,
        };
        assert_eq!(params.decode_cursor().unwrap(), 0);
    }
}
