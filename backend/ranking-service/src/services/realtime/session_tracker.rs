// ============================================
// Session Tracker (会话追踪器)
// ============================================
//
// Tracks user behavior within a session for real-time personalization
//
// Events tracked:
// - Content views with watch time
// - Engagement actions (like, comment, share)
// - Scroll behavior (speed, direction)
// - Session start/end, background/foreground
//
// Redis keys:
// - session:{session_id}:meta - Session metadata
// - session:{session_id}:views - Recent content views
// - session:{session_id}:engagements - Engagement events

use super::{RealtimeError, Result};
use chrono::{DateTime, Duration, Utc};
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use tracing::{debug, info};
use uuid::Uuid;

/// Session metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionMetadata {
    pub session_id: String,
    pub user_id: Uuid,
    pub started_at: DateTime<Utc>,
    pub last_activity: DateTime<Utc>,
    pub device_type: String,
    pub app_version: String,
    /// Total content views in session
    pub view_count: u32,
    /// Total engagements in session
    pub engagement_count: u32,
    /// Is session currently active
    pub is_active: bool,
}

/// Content view event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContentViewEvent {
    pub content_id: Uuid,
    pub author_id: Option<Uuid>,
    pub viewed_at: DateTime<Utc>,
    pub watch_duration_ms: u32,
    pub content_duration_ms: u32,
    pub completion_rate: f32,
    pub content_tags: Vec<String>,
    /// Scroll behavior when viewing
    pub scroll_away_at_ms: Option<u32>,
}

impl ContentViewEvent {
    pub fn is_engaged(&self) -> bool {
        // Consider engaged if watched > 50% or > 30 seconds
        self.completion_rate >= 0.5 || self.watch_duration_ms >= 30000
    }
}

/// Engagement event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EngagementEvent {
    pub content_id: Uuid,
    pub action: EngagementAction,
    pub timestamp: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum EngagementAction {
    Like,
    Comment,
    Share,
    Save,
    NotInterested,
    Report,
}

impl EngagementAction {
    /// Weight for interest inference
    pub fn interest_weight(&self) -> f64 {
        match self {
            EngagementAction::Like => 1.0,
            EngagementAction::Comment => 2.0,
            EngagementAction::Share => 3.0,
            EngagementAction::Save => 2.5,
            EngagementAction::NotInterested => -2.0, // Negative signal
            EngagementAction::Report => -5.0,        // Strong negative
        }
    }
}

/// Real-time session tracker
pub struct SessionTracker {
    redis: redis::Client,
    /// Session TTL in seconds (default: 2 hours)
    session_ttl: u64,
    /// Maximum recent views to track per session
    max_recent_views: usize,
    /// Key prefix
    key_prefix: String,
}

impl SessionTracker {
    pub fn new(redis: redis::Client) -> Self {
        Self {
            redis,
            session_ttl: 7200, // 2 hours
            max_recent_views: 100,
            key_prefix: "session".to_string(),
        }
    }

    /// Create with custom TTL
    pub fn with_ttl(mut self, ttl_seconds: u64) -> Self {
        self.session_ttl = ttl_seconds;
        self
    }

    fn meta_key(&self, session_id: &str) -> String {
        format!("{}:{}:meta", self.key_prefix, session_id)
    }

    fn views_key(&self, session_id: &str) -> String {
        format!("{}:{}:views", self.key_prefix, session_id)
    }

    fn engagements_key(&self, session_id: &str) -> String {
        format!("{}:{}:engagements", self.key_prefix, session_id)
    }

    /// Start a new session
    pub async fn start_session(
        &self,
        session_id: &str,
        user_id: Uuid,
        device_type: &str,
        app_version: &str,
    ) -> Result<SessionMetadata> {
        let mut conn = self
            .redis
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| RealtimeError::RedisError(e.to_string()))?;

        let now = Utc::now();
        let meta = SessionMetadata {
            session_id: session_id.to_string(),
            user_id,
            started_at: now,
            last_activity: now,
            device_type: device_type.to_string(),
            app_version: app_version.to_string(),
            view_count: 0,
            engagement_count: 0,
            is_active: true,
        };

        let meta_json =
            serde_json::to_string(&meta).map_err(|e| RealtimeError::InvalidData(e.to_string()))?;

        let _: () = conn
            .set_ex(self.meta_key(session_id), meta_json, self.session_ttl)
            .await
            .map_err(|e| RealtimeError::RedisError(e.to_string()))?;

        info!(
            session_id = session_id,
            user_id = %user_id,
            "Session started"
        );

        Ok(meta)
    }

    /// Record content view event
    pub async fn record_view(&self, session_id: &str, event: ContentViewEvent) -> Result<()> {
        let mut conn = self
            .redis
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| RealtimeError::RedisError(e.to_string()))?;

        // Add to views list
        let event_json =
            serde_json::to_string(&event).map_err(|e| RealtimeError::InvalidData(e.to_string()))?;

        let _: () = conn
            .lpush(self.views_key(session_id), &event_json)
            .await
            .map_err(|e| RealtimeError::RedisError(e.to_string()))?;

        // Trim to max size
        let _: () = conn
            .ltrim(
                self.views_key(session_id),
                0,
                self.max_recent_views as isize,
            )
            .await
            .map_err(|e| RealtimeError::RedisError(e.to_string()))?;

        // Set TTL
        let _: () = conn
            .expire(self.views_key(session_id), self.session_ttl as i64)
            .await
            .map_err(|e| RealtimeError::RedisError(e.to_string()))?;

        // Update session metadata
        self.update_session_activity(session_id, true, false)
            .await?;

        debug!(
            session_id = session_id,
            content_id = %event.content_id,
            completion_rate = event.completion_rate,
            "View recorded"
        );

        Ok(())
    }

    /// Record engagement event
    pub async fn record_engagement(&self, session_id: &str, event: EngagementEvent) -> Result<()> {
        let mut conn = self
            .redis
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| RealtimeError::RedisError(e.to_string()))?;

        // Add to engagements list
        let event_json =
            serde_json::to_string(&event).map_err(|e| RealtimeError::InvalidData(e.to_string()))?;

        let _: () = conn
            .lpush(self.engagements_key(session_id), &event_json)
            .await
            .map_err(|e| RealtimeError::RedisError(e.to_string()))?;

        // Set TTL
        let _: () = conn
            .expire(self.engagements_key(session_id), self.session_ttl as i64)
            .await
            .map_err(|e| RealtimeError::RedisError(e.to_string()))?;

        // Update session metadata
        self.update_session_activity(session_id, false, true)
            .await?;

        debug!(
            session_id = session_id,
            content_id = %event.content_id,
            action = ?event.action,
            "Engagement recorded"
        );

        Ok(())
    }

    /// Update session activity timestamps and counters
    async fn update_session_activity(
        &self,
        session_id: &str,
        increment_views: bool,
        increment_engagements: bool,
    ) -> Result<()> {
        let mut conn = self
            .redis
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| RealtimeError::RedisError(e.to_string()))?;

        let meta_json: Option<String> = conn
            .get(self.meta_key(session_id))
            .await
            .map_err(|e| RealtimeError::RedisError(e.to_string()))?;

        if let Some(json) = meta_json {
            let mut meta: SessionMetadata = serde_json::from_str(&json)
                .map_err(|e| RealtimeError::InvalidData(e.to_string()))?;

            meta.last_activity = Utc::now();
            if increment_views {
                meta.view_count += 1;
            }
            if increment_engagements {
                meta.engagement_count += 1;
            }

            let updated_json = serde_json::to_string(&meta)
                .map_err(|e| RealtimeError::InvalidData(e.to_string()))?;

            let _: () = conn
                .set_ex(self.meta_key(session_id), updated_json, self.session_ttl)
                .await
                .map_err(|e| RealtimeError::RedisError(e.to_string()))?;
        }

        Ok(())
    }

    /// Get recent content views for session
    pub async fn get_recent_views(
        &self,
        session_id: &str,
        limit: usize,
    ) -> Result<Vec<ContentViewEvent>> {
        let mut conn = self
            .redis
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| RealtimeError::RedisError(e.to_string()))?;

        let events_json: Vec<String> = conn
            .lrange(self.views_key(session_id), 0, limit as isize)
            .await
            .map_err(|e| RealtimeError::RedisError(e.to_string()))?;

        let mut events = Vec::new();
        for json in events_json {
            if let Ok(event) = serde_json::from_str::<ContentViewEvent>(&json) {
                events.push(event);
            }
        }

        Ok(events)
    }

    /// Get session metadata
    pub async fn get_session(&self, session_id: &str) -> Result<Option<SessionMetadata>> {
        let mut conn = self
            .redis
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| RealtimeError::RedisError(e.to_string()))?;

        let meta_json: Option<String> = conn
            .get(self.meta_key(session_id))
            .await
            .map_err(|e| RealtimeError::RedisError(e.to_string()))?;

        match meta_json {
            Some(json) => {
                let meta = serde_json::from_str(&json)
                    .map_err(|e| RealtimeError::InvalidData(e.to_string()))?;
                Ok(Some(meta))
            }
            None => Ok(None),
        }
    }

    /// End session
    pub async fn end_session(&self, session_id: &str) -> Result<()> {
        let mut conn = self
            .redis
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| RealtimeError::RedisError(e.to_string()))?;

        let meta_json: Option<String> = conn
            .get(self.meta_key(session_id))
            .await
            .map_err(|e| RealtimeError::RedisError(e.to_string()))?;

        if let Some(json) = meta_json {
            let mut meta: SessionMetadata = serde_json::from_str(&json)
                .map_err(|e| RealtimeError::InvalidData(e.to_string()))?;

            meta.is_active = false;
            meta.last_activity = Utc::now();

            let updated_json = serde_json::to_string(&meta)
                .map_err(|e| RealtimeError::InvalidData(e.to_string()))?;

            // Keep session data for a shorter period after ending
            let _: () = conn
                .set_ex(self.meta_key(session_id), updated_json, 300) // 5 minutes
                .await
                .map_err(|e| RealtimeError::RedisError(e.to_string()))?;

            info!(
                session_id = session_id,
                view_count = meta.view_count,
                engagement_count = meta.engagement_count,
                "Session ended"
            );
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_engagement_weight() {
        assert_eq!(EngagementAction::Like.interest_weight(), 1.0);
        assert_eq!(EngagementAction::Comment.interest_weight(), 2.0);
        assert_eq!(EngagementAction::Share.interest_weight(), 3.0);
        assert!(EngagementAction::NotInterested.interest_weight() < 0.0);
    }

    #[test]
    fn test_content_view_engaged() {
        let mut event = ContentViewEvent {
            content_id: Uuid::new_v4(),
            author_id: None,
            viewed_at: Utc::now(),
            watch_duration_ms: 10000,
            content_duration_ms: 60000,
            completion_rate: 0.16,
            content_tags: vec![],
            scroll_away_at_ms: None,
        };

        // Low completion, short watch
        assert!(!event.is_engaged());

        // High completion
        event.completion_rate = 0.5;
        assert!(event.is_engaged());

        // Long watch time
        event.completion_rate = 0.1;
        event.watch_duration_ms = 35000;
        assert!(event.is_engaged());
    }
}
