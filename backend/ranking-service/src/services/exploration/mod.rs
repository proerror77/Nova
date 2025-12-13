// ============================================
// Exploration Module (探索模块)
// ============================================
//
// Implements explore-exploit balance for new content discovery
// using Upper Confidence Bound (UCB) algorithm.
//
// TikTok-style new content handling:
// 1. New content enters exploration pool
// 2. UCB algorithm balances showing new content vs proven content
// 3. Content graduates to main pool after sufficient impressions
// 4. Cold-start handling for new creators
//
// Key Metrics:
// - Exploitation: avg_engagement_rate (CTR, completion rate)
// - Exploration: uncertainty bonus based on impression count

pub mod ucb;
pub mod new_content_pool;

pub use ucb::UCBExplorer;
pub use new_content_pool::{NewContentPool, NewContentEntry};

use thiserror::Error;

#[derive(Debug, Error)]
pub enum ExplorationError {
    #[error("Pool operation failed: {0}")]
    PoolError(String),

    #[error("Redis error: {0}")]
    RedisError(String),

    #[error("Invalid content: {0}")]
    InvalidContent(String),
}

pub type Result<T> = std::result::Result<T, ExplorationError>;
