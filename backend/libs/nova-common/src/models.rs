//! Shared data models for inter-service communication
//!
//! These models enable consistent communication across Nova microservices
//! using both HTTP and gRPC protocols

use serde::{Deserialize, Serialize};
use uuid::Uuid;
use chrono::{DateTime, Utc};

// ============================================================================
// STREAMING SERVICE MODELS
// ============================================================================

/// Event types for streaming domain
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum EventType {
    StreamStarted,
    StreamEnded,
    ViewerJoined,
    ViewerLeft,
    CommentPosted,
    StreamAnalytics,
}

/// Domain event from any service
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct StreamEvent {
    pub event_type: EventType,
    pub stream_id: Uuid,
    pub creator_id: Uuid,
    pub timestamp: DateTime<Utc>,
    #[serde(flatten)]
    pub data: serde_json::Value,
}

impl StreamEvent {
    pub fn new(event_type: EventType, stream_id: Uuid, creator_id: Uuid) -> Self {
        Self {
            event_type,
            stream_id,
            creator_id,
            timestamp: Utc::now(),
            data: serde_json::json!({}),
        }
    }

    pub fn with_data(mut self, data: serde_json::Value) -> Self {
        self.data = data;
        self
    }
}

// ============================================================================
// RPC COMMAND MODELS
// ============================================================================

/// Request/Response wrapper for inter-service commands
/// Uses request ID for tracing and deduplication
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CommandRequest<T> {
    pub request_id: String,
    pub source_service: String,
    pub target_service: String,
    pub command: T,
    pub timestamp: DateTime<Utc>,
}

impl<T> CommandRequest<T> {
    pub fn new(
        source_service: &str,
        target_service: &str,
        command: T,
    ) -> Self {
        Self {
            request_id: Uuid::new_v4().to_string(),
            source_service: source_service.to_string(),
            target_service: target_service.to_string(),
            command,
            timestamp: Utc::now(),
        }
    }
}

/// Standard response format for inter-service commands
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CommandResponse<T> {
    pub request_id: String,
    pub success: bool,
    pub data: Option<T>,
    pub error: Option<String>,
    pub timestamp: DateTime<Utc>,
}

impl<T> CommandResponse<T> {
    pub fn ok(request_id: String, data: T) -> Self {
        Self {
            request_id,
            success: true,
            data: Some(data),
            error: None,
            timestamp: Utc::now(),
        }
    }

    pub fn error(request_id: String, error: String) -> Self {
        Self {
            request_id,
            success: false,
            data: None,
            error: Some(error),
            timestamp: Utc::now(),
        }
    }
}

// ============================================================================
// STREAMING SERVICE SPECIFIC DTOs
// ============================================================================

/// Minimal stream summary for inter-service queries
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct StreamInfo {
    pub stream_id: Uuid,
    pub creator_id: Uuid,
    pub title: String,
    pub status: StreamStatus,
    pub viewer_count: i64,
    pub started_at: Option<DateTime<Utc>>,
}

/// Stream status
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum StreamStatus {
    Pending,
    Live,
    Ended,
    Archived,
}

/// Streaming service command abstraction
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "command_type")]
pub enum StreamCommand {
    GetStreamInfo { stream_id: Uuid },
    ListLiveStreams { limit: i32 },
    GetViewerCount { stream_id: Uuid },
    PostEvent(StreamEvent),
}

// ============================================================================
// PAGINATION AND FILTERING
// ============================================================================

/// Standard pagination request
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PaginationRequest {
    pub page: i32,
    pub limit: i32,
}

impl PaginationRequest {
    pub fn validate(&self) -> crate::error::Result<()> {
        if self.page < 1 {
            return Err(crate::error::ServiceError::Validation(
                "page must be >= 1".to_string(),
            ));
        }
        if self.limit < 1 || self.limit > 100 {
            return Err(crate::error::ServiceError::Validation(
                "limit must be 1-100".to_string(),
            ));
        }
        Ok(())
    }
}

/// Standard paginated response
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PagedResponse<T> {
    pub items: Vec<T>,
    pub total: i64,
    pub page: i32,
    pub limit: i32,
    pub has_more: bool,
}

impl<T> PagedResponse<T> {
    pub fn new(items: Vec<T>, total: i64, page: i32, limit: i32) -> Self {
        let has_more = (page as i64) * (limit as i64) < total;
        Self {
            items,
            total,
            page,
            limit,
            has_more,
        }
    }
}

// ============================================================================
// HEALTH CHECK
// ============================================================================

/// Service health status
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct HealthStatus {
    pub service_name: String,
    pub status: String, // "healthy" or "degraded"
    pub version: String,
    pub timestamp: DateTime<Utc>,
    pub dependencies: std::collections::HashMap<String, String>,
}
