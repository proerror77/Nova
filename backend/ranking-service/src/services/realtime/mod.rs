// ============================================
// Real-time Session Tracking Module
// ============================================
//
// TikTok-style within-session personalization:
// 1. Track user interests during active session
// 2. Adjust recommendations based on real-time signals
// 3. Capture scroll behavior and engagement patterns
// 4. Session-level preference decay
//
// Redis-backed for low-latency real-time updates

pub mod session_tracker;
pub mod session_interests;

pub use session_tracker::SessionTracker;
pub use session_interests::{SessionInterest, SessionInterestManager};

use thiserror::Error;

#[derive(Debug, Error)]
pub enum RealtimeError {
    #[error("Session not found: {0}")]
    SessionNotFound(String),

    #[error("Redis error: {0}")]
    RedisError(String),

    #[error("Invalid data: {0}")]
    InvalidData(String),
}

pub type Result<T> = std::result::Result<T, RealtimeError>;
