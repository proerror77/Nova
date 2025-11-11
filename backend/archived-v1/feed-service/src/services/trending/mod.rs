/// Trending/Discovery Service
///
/// Real-time trending content discovery with time-decay algorithm
pub mod algorithm;
pub mod compute;
pub mod service;

pub use algorithm::TrendingAlgorithm;
pub use compute::TrendingComputeService;
pub use service::TrendingService;
