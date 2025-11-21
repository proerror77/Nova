use actix_web::{get, web, HttpMessage, HttpRequest, HttpResponse};
use base64::{engine::general_purpose, Engine as _};
use serde::Deserialize;
use std::sync::Arc;
use tracing::{debug, info, warn};
use uuid::Uuid;

use crate::error::{AppError, Result};
use grpc_clients::RankingServiceClient;
use crate::middleware::jwt_auth::UserId;
use crate::models::FeedResponse;
use grpc_clients::nova::ranking_service::v1::RankFeedRequest;

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
    pub ranking_client: Arc<RankingServiceClient<tonic::transport::Channel>>,
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
        "Getting feed for user: user={} algo={} limit={} offset={}",
        user_id, query.algo, limit, offset
    );

    // Delegate recall + ranking to ranking-service
    let mut ranking_client = (*state.ranking_client).clone();
    let ranking_req = RankFeedRequest {
        user_id: user_id.to_string(),
        limit: limit as i32,
        recall_config: None,
    };

    let resp = match ranking_client.rank_feed(ranking_req).await {
        Ok(r) => r.into_inner(),
        Err(err) => {
            warn!(
                "Ranking-service unavailable for user {}: {}. Returning empty feed.",
                user_id, err
            );
            return Ok(HttpResponse::Ok().json(FeedResponse {
                posts: vec![],
                cursor: None,
                has_more: false,
                total_count: 0,
            }));
        }
    };

    let mut posts: Vec<Uuid> = Vec::new();
    for ranked in resp.posts.iter().skip(offset).take(limit as usize) {
        if let Ok(id) = Uuid::parse_str(&ranked.post_id) {
            posts.push(id);
        }
    }

    let total_count = resp.posts.len();
    let has_more = (offset as usize + posts.len()) < total_count;
    let cursor = if has_more {
        Some(FeedQueryParams::encode_cursor(offset + posts.len()))
    } else {
        None
    };

    info!(
        "Feed generated via ranking-service for user: {} (posts: {}, total_candidates: {})",
        user_id,
        posts.len(),
        total_count
    );

    Ok(HttpResponse::Ok().json(FeedResponse {
        posts,
        cursor,
        has_more,
        total_count,
    }))
}

/// Cache invalidation is handled through Redis/Kafka events in production.
/// Manual invalidation endpoint would trigger cache refresh for user's feed.
/// TODO: Implement Redis cache invalidation layer (Phase 1 Stage 1.4 Week 13-14)

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
