use actix_web::{web, HttpMessage, HttpRequest, HttpResponse};
use base64::{engine::general_purpose, Engine as _};
use serde::Deserialize;
use std::sync::Arc;
use tracing::{debug, warn};

use crate::error::{AppError, Result};
use crate::middleware::UserId;
use crate::models::FeedResponse;
use crate::services::feed_ranking::FeedRankingService;

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
    pub(crate) fn decode_cursor(&self) -> Result<usize> {
        match &self.cursor {
            Some(cursor) => {
                let decoded = general_purpose::STANDARD
                    .decode(cursor)
                    .map_err(|_| AppError::BadRequest("Invalid cursor format".to_string()))?;

                let offset_str = String::from_utf8(decoded)
                    .map_err(|_| AppError::BadRequest("Invalid cursor encoding".to_string()))?;

                offset_str
                    .parse::<usize>()
                    .map_err(|_| AppError::BadRequest("Invalid cursor value".to_string()))
            }
            None => Ok(0),
        }
    }

    pub(crate) fn encode_cursor(offset: usize) -> String {
        general_purpose::STANDARD.encode(offset.to_string())
    }
}

pub struct FeedHandlerState {
    pub feed_ranking: Arc<FeedRankingService>,
}

pub async fn get_feed(
    query: web::Query<FeedQueryParams>,
    http_req: HttpRequest,
    state: web::Data<FeedHandlerState>,
) -> Result<HttpResponse> {
    let user_id = http_req
        .extensions()
        .get::<UserId>()
        .map(|u| u.0)
        .ok_or_else(|| AppError::Unauthorized("Missing user context".into()))?;
    let offset = query.decode_cursor()?;
    let limit = query.limit.clamp(1, 100) as usize;

    debug!(
        "Feed request: user={} algo={} limit={} offset={}",
        user_id, query.algo, limit, offset
    );

    if query.algo != "ch" && query.algo != "time" {
        return Err(AppError::BadRequest(
            "Invalid algo parameter. Must be 'ch' or 'time'".to_string(),
        ));
    }

    let (post_ids, has_more, total_count) =
        match state.feed_ranking.get_feed(user_id, limit, offset).await {
            Ok(result) => result,
            Err(e) => {
                warn!("Feed primary path failed for user {}: {}", user_id, e);
                state
                    .feed_ranking
                    .fallback_feed(user_id, limit, offset)
                    .await?
            }
        };

    let cursor = if has_more && !post_ids.is_empty() {
        Some(FeedQueryParams::encode_cursor(offset + post_ids.len()))
    } else {
        None
    };

    Ok(HttpResponse::Ok().json(FeedResponse {
        posts: post_ids,
        cursor,
        has_more,
        total_count,
    }))
}
