// ============================================
// Profile Updater (用户画像更新器)
// ============================================
//
// Background job that orchestrates user profile building:
// 1. Fetches engagement data from database
// 2. Builds interest tags using InterestBuilder
// 3. Builds behavior patterns using BehaviorBuilder
// 4. Updates user profile in Redis cache
//
// Note: This module uses trait-based abstraction for database operations
// to allow flexible integration with existing PostgreSQL infrastructure.

use super::behavior_builder::{
    BehaviorBuilder, BehaviorBuilderConfig, BehaviorPattern, ContentViewEvent, SessionEvent,
};
use super::interest_builder::{
    EngagementAction, EngagementSignal, InterestBuilder, InterestBuilderConfig, InterestTag,
};
use super::{ProfileBuilderError, Result};
use async_trait::async_trait;
use chrono::{DateTime, Utc};
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::{error, info, warn};
use uuid::Uuid;

/// Complete user profile with interests and behavior patterns
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserProfile {
    pub user_id: Uuid,
    /// Interest tags with weights
    pub interests: Vec<InterestTag>,
    /// Behavior patterns
    pub behavior: BehaviorPattern,
    /// Profile creation time
    pub created_at: DateTime<Utc>,
    /// Last update time
    pub updated_at: DateTime<Utc>,
}

/// Database operations trait for profile data
/// Implement this trait to integrate with your existing PostgreSQL infrastructure
#[async_trait]
pub trait ProfileDatabase: Send + Sync {
    /// Fetch engagement signals for a user
    async fn fetch_engagement_signals(
        &self,
        user_id: Uuid,
        lookback_days: i64,
    ) -> Result<Vec<EngagementSignalData>>;

    /// Fetch session events for a user
    async fn fetch_session_events(
        &self,
        user_id: Uuid,
        lookback_days: i64,
    ) -> Result<Vec<SessionEventData>>;

    /// Fetch content view events for a user
    async fn fetch_content_views(
        &self,
        user_id: Uuid,
        lookback_days: i64,
    ) -> Result<Vec<ContentViewData>>;

    /// Save interest tags to database
    async fn save_interest_tags(&self, user_id: Uuid, tags: &[InterestTag]) -> Result<()>;

    /// Save behavior pattern to database
    async fn save_behavior_pattern(&self, user_id: Uuid, pattern: &BehaviorPattern) -> Result<()>;
}

/// Raw engagement signal data from database
#[derive(Debug, Clone)]
pub struct EngagementSignalData {
    pub user_id: Uuid,
    pub content_id: Uuid,
    pub action: String,
    pub content_tags: Vec<String>,
    pub created_at: DateTime<Utc>,
}

/// Raw session event data from database
#[derive(Debug, Clone)]
pub struct SessionEventData {
    pub user_id: Uuid,
    pub session_id: String,
    pub started_at: DateTime<Utc>,
    pub ended_at: Option<DateTime<Utc>>,
    pub view_count: u32,
    pub engagement_count: u32,
}

/// Raw content view data from database
#[derive(Debug, Clone)]
pub struct ContentViewData {
    pub user_id: Uuid,
    pub content_id: Uuid,
    pub content_duration_ms: u32,
    pub watch_duration_ms: u32,
    pub completion_rate: f32,
    pub viewed_at: DateTime<Utc>,
    pub hour: u8,
    pub day_of_week: u8,
}

/// Profile updater configuration
#[derive(Debug, Clone)]
pub struct ProfileUpdaterConfig {
    /// Interest builder config
    pub interest_config: InterestBuilderConfig,
    /// Behavior builder config
    pub behavior_config: BehaviorBuilderConfig,
    /// Batch size for bulk updates
    pub batch_size: usize,
    /// Whether to update Redis cache after DB update
    pub update_cache: bool,
    /// Redis cache TTL in seconds
    pub cache_ttl_secs: u64,
}

impl Default for ProfileUpdaterConfig {
    fn default() -> Self {
        Self {
            interest_config: InterestBuilderConfig::default(),
            behavior_config: BehaviorBuilderConfig::default(),
            batch_size: 100,
            update_cache: true,
            cache_ttl_secs: 86400, // 24 hours
        }
    }
}

/// Profile updater service
pub struct ProfileUpdater<D: ProfileDatabase> {
    /// Database implementation
    db: Arc<D>,
    /// Redis client for caching
    redis: redis::Client,
    /// Interest builder
    interest_builder: InterestBuilder,
    /// Behavior builder
    behavior_builder: BehaviorBuilder,
    /// Configuration
    config: ProfileUpdaterConfig,
}

impl<D: ProfileDatabase> ProfileUpdater<D> {
    pub fn new(db: Arc<D>, redis: redis::Client, config: ProfileUpdaterConfig) -> Self {
        Self {
            db,
            redis,
            interest_builder: InterestBuilder::new(config.interest_config.clone()),
            behavior_builder: BehaviorBuilder::new(config.behavior_config.clone()),
            config,
        }
    }

    /// Update profile for a single user (real-time update)
    pub async fn update_user_profile(&self, user_id: Uuid) -> Result<UserProfile> {
        info!(user_id = %user_id, "Updating user profile");

        // Fetch engagement signals
        let signal_data = self
            .db
            .fetch_engagement_signals(user_id, self.config.interest_config.lookback_days)
            .await?;

        // Convert to engagement signals
        let signals: Vec<EngagementSignal> = signal_data
            .into_iter()
            .map(|data| EngagementSignal {
                user_id: data.user_id,
                content_id: data.content_id,
                content_tags: data.content_tags,
                action: Self::parse_action(&data.action),
                timestamp: data.created_at,
            })
            .collect();

        // Build interests
        let interests = self.interest_builder.build_interests(signals)?;

        // Fetch session and view data
        let session_data = self
            .db
            .fetch_session_events(user_id, self.config.behavior_config.lookback_days)
            .await?;

        let view_data = self
            .db
            .fetch_content_views(user_id, self.config.behavior_config.lookback_days)
            .await?;

        // Convert to session events
        let sessions: Vec<SessionEvent> = session_data
            .into_iter()
            .map(|data| SessionEvent {
                user_id: data.user_id,
                session_id: data.session_id,
                started_at: data.started_at,
                ended_at: data.ended_at,
                view_count: data.view_count,
                engagement_count: data.engagement_count,
            })
            .collect();

        // Convert to content view events
        let views: Vec<ContentViewEvent> = view_data
            .into_iter()
            .map(|data| ContentViewEvent {
                user_id: data.user_id,
                content_id: data.content_id,
                content_duration_ms: data.content_duration_ms,
                watch_duration_ms: data.watch_duration_ms,
                completion_rate: data.completion_rate,
                viewed_at: data.viewed_at,
                hour: data.hour,
                day_of_week: data.day_of_week,
            })
            .collect();

        // Build behavior pattern
        let behavior = self
            .behavior_builder
            .build_pattern(user_id, sessions, views)?;

        // Create profile
        let now = Utc::now();
        let profile = UserProfile {
            user_id,
            interests: interests.clone(),
            behavior: behavior.clone(),
            created_at: now,
            updated_at: now,
        };

        // Save to database
        self.db
            .save_interest_tags(user_id, &profile.interests)
            .await?;
        self.db
            .save_behavior_pattern(user_id, &profile.behavior)
            .await?;

        // Update Redis cache
        if self.config.update_cache {
            self.update_cache(&profile).await?;
        }

        info!(
            user_id = %user_id,
            interest_count = profile.interests.len(),
            "User profile updated successfully"
        );

        Ok(profile)
    }

    /// Batch update profiles for multiple users
    pub async fn batch_update_profiles(&self, user_ids: Vec<Uuid>) -> Result<usize> {
        info!(user_count = user_ids.len(), "Starting batch profile update");

        let mut success_count = 0;
        let mut error_count = 0;

        for batch in user_ids.chunks(self.config.batch_size) {
            for user_id in batch {
                match self.update_user_profile(*user_id).await {
                    Ok(_) => success_count += 1,
                    Err(e) => {
                        error_count += 1;
                        warn!(
                            user_id = %user_id,
                            error = %e,
                            "Failed to update user profile"
                        );
                    }
                }
            }
        }

        info!(
            success_count = success_count,
            error_count = error_count,
            "Batch profile update completed"
        );

        Ok(success_count)
    }

    /// Parse action string to enum
    fn parse_action(action: &str) -> EngagementAction {
        match action.to_lowercase().as_str() {
            "like" => EngagementAction::Like,
            "comment" => EngagementAction::Comment,
            "share" => EngagementAction::Share,
            "save" | "bookmark" => EngagementAction::Save,
            "complete_watch" => EngagementAction::CompleteWatch,
            "partial_watch" => EngagementAction::PartialWatch,
            "skip" => EngagementAction::Skip,
            "not_interested" => EngagementAction::NotInterested,
            _ => EngagementAction::PartialWatch, // Default
        }
    }

    /// Update Redis cache with profile data
    async fn update_cache(&self, profile: &UserProfile) -> Result<()> {
        let mut conn = self
            .redis
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| ProfileBuilderError::RedisError(e.to_string()))?;

        // Cache interest tags for fast access during ranking
        let interests_key = format!("user:{}:interests", profile.user_id);
        let interests_json = serde_json::to_string(&profile.interests)
            .map_err(|e| ProfileBuilderError::InvalidData(e.to_string()))?;

        let _: () = conn
            .set_ex(&interests_key, &interests_json, self.config.cache_ttl_secs)
            .await
            .map_err(|e| ProfileBuilderError::RedisError(e.to_string()))?;

        // Cache behavior pattern
        let behavior_key = format!("user:{}:behavior", profile.user_id);
        let behavior_json = serde_json::to_string(&profile.behavior)
            .map_err(|e| ProfileBuilderError::InvalidData(e.to_string()))?;

        let _: () = conn
            .set_ex(&behavior_key, &behavior_json, self.config.cache_ttl_secs)
            .await
            .map_err(|e| ProfileBuilderError::RedisError(e.to_string()))?;

        Ok(())
    }

    /// Load profile from cache
    pub async fn load_profile_from_cache(&self, user_id: Uuid) -> Result<Option<UserProfile>> {
        let mut conn = self
            .redis
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| ProfileBuilderError::RedisError(e.to_string()))?;

        // Load interests
        let interests_key = format!("user:{}:interests", user_id);
        let interests_json: Option<String> = conn
            .get(&interests_key)
            .await
            .map_err(|e| ProfileBuilderError::RedisError(e.to_string()))?;

        // Load behavior
        let behavior_key = format!("user:{}:behavior", user_id);
        let behavior_json: Option<String> = conn
            .get(&behavior_key)
            .await
            .map_err(|e| ProfileBuilderError::RedisError(e.to_string()))?;

        match (interests_json, behavior_json) {
            (Some(interests_str), Some(behavior_str)) => {
                let interests: Vec<InterestTag> = serde_json::from_str(&interests_str)
                    .map_err(|e| ProfileBuilderError::InvalidData(e.to_string()))?;

                let behavior: BehaviorPattern = serde_json::from_str(&behavior_str)
                    .map_err(|e| ProfileBuilderError::InvalidData(e.to_string()))?;

                Ok(Some(UserProfile {
                    user_id,
                    interests,
                    behavior,
                    created_at: Utc::now(),
                    updated_at: Utc::now(),
                }))
            }
            _ => Ok(None),
        }
    }
}

/// Stub implementation of ProfileDatabase for testing or when no DB is available
pub struct StubProfileDatabase;

#[async_trait]
impl ProfileDatabase for StubProfileDatabase {
    async fn fetch_engagement_signals(
        &self,
        _user_id: Uuid,
        _lookback_days: i64,
    ) -> Result<Vec<EngagementSignalData>> {
        Ok(Vec::new())
    }

    async fn fetch_session_events(
        &self,
        _user_id: Uuid,
        _lookback_days: i64,
    ) -> Result<Vec<SessionEventData>> {
        Ok(Vec::new())
    }

    async fn fetch_content_views(
        &self,
        _user_id: Uuid,
        _lookback_days: i64,
    ) -> Result<Vec<ContentViewData>> {
        Ok(Vec::new())
    }

    async fn save_interest_tags(&self, _user_id: Uuid, _tags: &[InterestTag]) -> Result<()> {
        Ok(())
    }

    async fn save_behavior_pattern(
        &self,
        _user_id: Uuid,
        _pattern: &BehaviorPattern,
    ) -> Result<()> {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_action() {
        assert!(matches!(
            ProfileUpdater::<StubProfileDatabase>::parse_action("like"),
            EngagementAction::Like
        ));
        assert!(matches!(
            ProfileUpdater::<StubProfileDatabase>::parse_action("COMMENT"),
            EngagementAction::Comment
        ));
        assert!(matches!(
            ProfileUpdater::<StubProfileDatabase>::parse_action("Share"),
            EngagementAction::Share
        ));
    }
}
