/// Business logic layer for content-service
///
/// This module provides high-level operations:
/// - Post service: Post creation, retrieval, updates
/// - Story service: Story lifecycle management
/// - Feed ranking: Feed ranking and recommendations
///
/// Note: Comment/like/share services are in social-service.
/// Extracted from user-service as part of P1.2 service splitting.
pub mod feed_ranking;
pub mod posts;
pub mod stories;

// Re-export commonly used services
pub use feed_ranking::{FeedRankingConfig, FeedRankingService};
pub use posts::PostService;
pub use stories::{PrivacyLevel, StoriesService};
