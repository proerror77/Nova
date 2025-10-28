use actix_web::{post, web, HttpResponse};
use chrono::{SecondsFormat, TimeZone, Utc};
use serde::Deserialize;
use std::sync::Arc;
use tracing::{debug, error, warn};
use uuid::Uuid;

use crate::error::{AppError, Result};
use crate::middleware::CircuitBreaker;
use crate::services::kafka_producer::EventProducer;

#[derive(Debug, Deserialize)]
pub struct EventRecord {
    #[serde(default)]
    pub ts: Option<i64>,
    pub user_id: Uuid,
    pub post_id: Uuid,
    #[serde(default)]
    pub author_id: Option<Uuid>,
    pub action: String,
    #[serde(default)]
    pub dwell_ms: Option<u32>,
    #[serde(default)]
    pub device: Option<String>,
    #[serde(default)]
    pub app_ver: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct EventBatch {
    pub events: Vec<EventRecord>,
}

/// Event handler state with Circuit Breaker protection
pub struct EventHandlerState {
    pub producer: Arc<EventProducer>,
    pub kafka_cb: Arc<CircuitBreaker>, // Kafka circuit breaker for event publishing
}

#[post("")]
pub async fn ingest_events(
    payload: web::Json<EventBatch>,
    state: web::Data<EventHandlerState>,
) -> Result<HttpResponse> {
    if payload.events.is_empty() {
        return Err(AppError::BadRequest("events array cannot be empty".into()));
    }

    for event in &payload.events {
        validate_action(&event.action)?;

        let event_time = event.ts.map_or_else(Utc::now, |millis| {
            let secs = millis / 1000;
            let nanos = ((millis % 1000) * 1_000_000) as u32;
            Utc.timestamp_opt(secs, nanos)
                .single()
                .unwrap_or_else(Utc::now)
        });

        let payload_json = serde_json::json!({
            "event_time": event_time.to_rfc3339_opts(SecondsFormat::Millis, true),
            "user_id": event.user_id,
            "post_id": event.post_id,
            "author_id": event.author_id.unwrap_or(event.user_id),
            "action": event.action,
            "dwell_ms": event.dwell_ms.unwrap_or(0),
            "device": event.device.clone().unwrap_or_else(|| "unknown".into()),
            "app_ver": event.app_ver.clone().unwrap_or_else(|| "unknown".into())
        });

        let payload_str = serde_json::to_string(&payload_json)?;
        let user_id_str = event.user_id.to_string();

        // Publish event with Kafka CB protection
        if let Err(e) = state
            .kafka_cb
            .call(|| {
                let producer = state.producer.clone();
                let key = user_id_str.clone();
                let payload = payload_str.clone();
                async move { producer.send_json(&key, &payload).await }
            })
            .await
        {
            match &e {
                AppError::Internal(msg) if msg.contains("Circuit breaker is OPEN") => {
                    warn!(
                        "Kafka circuit is OPEN for user {}, event publishing blocked, queuing for retry",
                        event.user_id
                    );
                    // TODO: Queue event for async retry when Kafka recovers
                }
                _ => {
                    error!("Failed to publish event for user {}: {}", event.user_id, e);
                }
            }
            return Err(e);
        }

        debug!("Event published for user {}", event.user_id);
    }

    Ok(HttpResponse::Accepted().json(serde_json::json!({
        "success": true,
        "count": payload.events.len()
    })))
}

fn validate_action(action: &str) -> Result<()> {
    match action {
        "view" | "impression" | "like" | "comment" | "share" => Ok(()),
        other => {
            warn!("Unknown action received: {}", other);
            Err(AppError::BadRequest(format!(
                "Unsupported action '{}'. Expected one of view/impression/like/comment/share",
                other
            )))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_validate_action_ok() {
        assert!(validate_action("view").is_ok());
    }

    #[tokio::test]
    async fn test_validate_action_err() {
        assert!(validate_action("unknown").is_err());
    }
}
