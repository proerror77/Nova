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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn command_request_has_unique_id() {
        #[derive(serde::Serialize)]
        struct TestCmd {
            value: String,
        }

        let req = CommandRequest::new("svc-a", "svc-b", TestCmd {
            value: "test".into(),
        });

        assert_eq!(req.source_service, "svc-a");
        assert_eq!(req.target_service, "svc-b");
        assert!(!req.request_id.is_empty());
    }

    #[test]
    fn command_request_has_timestamp() {
        #[derive(serde::Serialize)]
        struct TestCmd {
            value: String,
        }

        let before = Utc::now();
        let req = CommandRequest::new("a", "b", TestCmd {
            value: "test".into(),
        });
        let after = Utc::now();

        assert!(req.timestamp >= before && req.timestamp <= after);
    }

    #[test]
    fn command_response_success_has_data() {
        let response = CommandResponse::ok("req-1".into(), "success data");

        assert!(response.success);
        assert_eq!(response.data, Some("success data"));
        assert_eq!(response.error, None);
        assert_eq!(response.request_id, "req-1");
    }

    #[test]
    fn command_response_error_has_message() {
        let response: CommandResponse<String> =
            CommandResponse::error("req-2".into(), "error message".into());

        assert!(!response.success);
        assert_eq!(response.data, None);
        assert_eq!(response.error, Some("error message".into()));
        assert_eq!(response.request_id, "req-2");
    }

    #[test]
    fn stream_event_creation_has_timestamp() {
        let stream_id = Uuid::new_v4();
        let creator_id = Uuid::new_v4();

        let before = Utc::now();
        let event = StreamEvent::new(EventType::StreamStarted, stream_id, creator_id);
        let after = Utc::now();

        assert_eq!(event.event_type, EventType::StreamStarted);
        assert_eq!(event.stream_id, stream_id);
        assert_eq!(event.creator_id, creator_id);
        assert!(event.timestamp >= before && event.timestamp <= after);
    }

    #[test]
    fn stream_event_with_data() {
        let stream_id = Uuid::new_v4();
        let creator_id = Uuid::new_v4();

        let event = StreamEvent::new(EventType::StreamEnded, stream_id, creator_id)
            .with_data(serde_json::json!({
                "duration_seconds": 3600,
                "viewer_count": 150
            }));

        assert_eq!(event.data["duration_seconds"], 3600);
        assert_eq!(event.data["viewer_count"], 150);
    }

    #[test]
    fn stream_info_creation() {
        let stream_id = Uuid::new_v4();
        let creator_id = Uuid::new_v4();

        let info = StreamInfo {
            stream_id,
            creator_id,
            title: "My Stream".to_string(),
            status: StreamStatus::Live,
            viewer_count: 100,
            started_at: None,
        };

        assert_eq!(info.title, "My Stream");
        assert_eq!(info.status, StreamStatus::Live);
        assert_eq!(info.viewer_count, 100);
    }

    #[test]
    fn stream_status_equality() {
        assert_eq!(StreamStatus::Live, StreamStatus::Live);
        assert_ne!(StreamStatus::Live, StreamStatus::Ended);
        assert_eq!(StreamStatus::Pending, StreamStatus::Pending);
    }

    #[test]
    fn pagination_request_validates_page() {
        let valid_req = PaginationRequest { page: 1, limit: 20 };
        assert!(valid_req.validate().is_ok());

        let invalid_req = PaginationRequest { page: 0, limit: 20 };
        assert!(invalid_req.validate().is_err());

        let negative_req = PaginationRequest { page: -1, limit: 20 };
        assert!(negative_req.validate().is_err());
    }

    #[test]
    fn pagination_request_validates_limit() {
        let valid_req = PaginationRequest { page: 1, limit: 50 };
        assert!(valid_req.validate().is_ok());

        let too_small = PaginationRequest { page: 1, limit: 0 };
        assert!(too_small.validate().is_err());

        let too_large = PaginationRequest { page: 1, limit: 101 };
        assert!(too_large.validate().is_err());
    }

    #[test]
    fn paged_response_calculates_has_more() {
        // Page 1 of 20 pages - has more
        let response = PagedResponse::new(vec![1, 2, 3], 100, 1, 5);
        assert!(response.has_more);

        // Page 20 (last page) - no more
        let last_page = PagedResponse::new(vec![96, 97, 98, 99, 100], 100, 20, 5);
        assert!(!last_page.has_more);

        // Exactly one page
        let single = PagedResponse::new(vec![1, 2, 3], 3, 1, 5);
        assert!(!single.has_more);
    }

    #[test]
    fn paged_response_structure() {
        let items = vec!["a", "b", "c"];
        let response = PagedResponse::new(items.clone(), 30, 2, 10);

        assert_eq!(response.items, items);
        assert_eq!(response.total, 30);
        assert_eq!(response.page, 2);
        assert_eq!(response.limit, 10);
    }

    #[test]
    fn health_status_creation() {
        let mut deps = std::collections::HashMap::new();
        deps.insert("database".to_string(), "healthy".to_string());
        deps.insert("redis".to_string(), "healthy".to_string());

        let status = HealthStatus {
            service_name: "streaming-service".to_string(),
            status: "healthy".to_string(),
            version: "1.0.0".to_string(),
            timestamp: Utc::now(),
            dependencies: deps,
        };

        assert_eq!(status.service_name, "streaming-service");
        assert_eq!(status.status, "healthy");
        assert_eq!(status.dependencies.len(), 2);
    }

    #[test]
    fn stream_command_serialization() {
        let cmd = StreamCommand::GetStreamInfo {
            stream_id: Uuid::new_v4(),
        };

        let json = serde_json::to_string(&cmd).expect("Should serialize");
        assert!(json.contains("GetStreamInfo"));

        let deserialized: StreamCommand =
            serde_json::from_str(&json).expect("Should deserialize");
        match deserialized {
            StreamCommand::GetStreamInfo { .. } => {} // Success
            _ => panic!("Wrong command type"),
        }
    }

    #[test]
    fn command_request_response_roundtrip() {
        #[derive(serde::Serialize, serde::Deserialize, PartialEq, Debug)]
        struct MyCommand {
            name: String,
            count: i32,
        }

        let cmd = MyCommand {
            name: "test".to_string(),
            count: 42,
        };

        let request = CommandRequest::new("svc-a", "svc-b", cmd.clone());
        let json = serde_json::to_string(&request).expect("Should serialize");
        let deserialized: CommandRequest<MyCommand> =
            serde_json::from_str(&json).expect("Should deserialize");

        assert_eq!(deserialized.command, cmd);
    }
}
