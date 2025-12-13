// ============================================
// User Profile Builder (用戶畫像構建器)
// ============================================
//
// Background service that builds user profiles from:
// 1. Engagement history (likes, comments, shares)
// 2. Watch events (completion rate, watch time)
// 3. Session behavior (active hours, scroll patterns)
//
// Outputs:
// - Interest tags with decay weights
// - Behavior patterns (active hours, session length)
// - Content preferences (video length, content types)
//
// This is the "用戶畫像" (user portrait) system

pub mod interest_builder;
pub mod behavior_builder;
pub mod profile_updater;

pub use interest_builder::{InterestBuilder, InterestTag, InterestBuilderConfig};
pub use behavior_builder::{BehaviorBuilder, BehaviorPattern, BehaviorBuilderConfig};
pub use profile_updater::{
    ProfileUpdater, ProfileDatabase, UserProfile, ProfileUpdaterConfig,
    EngagementSignalData, SessionEventData, ContentViewData, StubProfileDatabase,
};

use thiserror::Error;

#[derive(Debug, Error)]
pub enum ProfileBuilderError {
    #[error("Database error: {0}")]
    DatabaseError(String),

    #[error("ClickHouse error: {0}")]
    ClickHouseError(String),

    #[error("Redis error: {0}")]
    RedisError(String),

    #[error("Invalid data: {0}")]
    InvalidData(String),
}

pub type Result<T> = std::result::Result<T, ProfileBuilderError>;
