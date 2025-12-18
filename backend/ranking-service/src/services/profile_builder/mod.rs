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
// - AI-generated user personas and insights
//
// This is the "用戶畫像" (user portrait) system
//
// Architecture:
// ┌─────────────────────────────────────────────────────────────┐
// │                    Profile Builder                          │
// ├─────────────────────────────────────────────────────────────┤
// │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │
// │  │ InterestBuilder │  │ BehaviorBuilder │  │ LlmAnalyzer │ │
// │  │ (興趣標籤構建)  │  │ (行為模式構建)  │  │ (AI分析器)  │ │
// │  └────────┬────────┘  └────────┬────────┘  └──────┬──────┘ │
// │           │                    │                   │        │
// │  ┌────────▼────────────────────▼───────────────────▼─────┐  │
// │  │               ProfileUpdater (整合器)                  │  │
// │  └────────────────────────────┬──────────────────────────┘  │
// │                               │                              │
// │  ┌────────────────────────────▼──────────────────────────┐  │
// │  │            ClickHouseProfileDatabase                   │  │
// │  │            (ClickHouse + Redis 存儲)                   │  │
// │  └───────────────────────────────────────────────────────┘  │
// └─────────────────────────────────────────────────────────────┘

pub mod behavior_builder;
pub mod clickhouse_db;
pub mod interest_builder;
pub mod llm_analyzer;
pub mod profile_updater;

// Core builders
pub use behavior_builder::{
    BehaviorBuilder, BehaviorBuilderConfig, BehaviorPattern, VideoLengthPreference,
};
pub use interest_builder::{EngagementAction, InterestBuilder, InterestBuilderConfig, InterestTag};

// Profile management
pub use profile_updater::{
    ContentViewData, EngagementSignalData, ProfileDatabase, ProfileUpdater, ProfileUpdaterConfig,
    SessionEventData, StubProfileDatabase, UserProfile,
};

// ClickHouse implementation
pub use clickhouse_db::{ClickHouseProfileDatabase, UserEngagementSummary};

// LLM/AI components
pub use llm_analyzer::{
    ConsumptionPatterns, ContentRecommendation, LlmProfileAnalyzer, LlmProvider,
    PredictedPreferences, UserPersona, UserSegment,
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

    #[error("LLM error: {0}")]
    LlmError(String),

    #[error("Invalid data: {0}")]
    InvalidData(String),
}

pub type Result<T> = std::result::Result<T, ProfileBuilderError>;
