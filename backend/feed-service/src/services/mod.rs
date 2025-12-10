//! Service layer for feed-service
//!
//! Phase D Refactoring:
//! ✅ ML ranking logic moved to ranking-service
//! ✅ Feed-service now focuses on feed assembly and caching
//! ⚠️  Legacy recommendation_v2 module kept for backward compatibility (to be removed in Phase E)
//!
//! Active modules:
//! - trending: Trending content computation
//! - fallback_ranking: Simple ranking when ranking-service is unavailable
//! - (recommendation_v2, kafka_consumer, vector_search: deprecated, use ranking-service)

pub mod fallback_ranking;
pub mod trending;

// Legacy modules (deprecated - use ranking-service instead)
#[allow(dead_code)]
pub mod kafka_consumer;
#[allow(dead_code)]
pub mod recommendation_v2;
#[allow(dead_code)]
pub mod vector_search;

pub use fallback_ranking::fallback_rank_posts;
pub use trending::TrendingService;
