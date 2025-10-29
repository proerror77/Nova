/// Trending Compute Service
///
/// Background service for computing trending scores
use sqlx::PgPool;
use tracing::{debug, error, info};

use super::algorithm::TrendingAlgorithm;
use crate::db::trending_repo::{TimeWindow, TrendingRepo};
use crate::error::Result;

/// Trending compute service for background jobs
pub struct TrendingComputeService {
    repo: TrendingRepo,
    algorithm: TrendingAlgorithm,
}

impl TrendingComputeService {
    pub fn new(pool: PgPool) -> Self {
        Self {
            repo: TrendingRepo::new(pool),
            algorithm: TrendingAlgorithm::default(),
        }
    }

    pub fn with_algorithm(pool: PgPool, algorithm: TrendingAlgorithm) -> Self {
        Self {
            repo: TrendingRepo::new(pool),
            algorithm,
        }
    }

    /// Compute trending scores for all time windows
    pub async fn compute_all_windows(&self) -> Result<()> {
        info!("Computing trending scores for all time windows");

        let windows = vec![
            TimeWindow::OneHour,
            TimeWindow::TwentyFourHours,
            TimeWindow::SevenDays,
        ];

        for window in windows {
            if let Err(e) = self.compute_trending_scores(window, None).await {
                error!("Failed to compute trending for window {}: {}", window, e);
            }
        }

        Ok(())
    }

    /// Compute trending scores for a specific time window
    pub async fn compute_trending_scores(
        &self,
        time_window: TimeWindow,
        category: Option<&str>,
    ) -> Result<i32> {
        let start = std::time::Instant::now();

        debug!(
            "Computing trending scores: window={}, category={:?}",
            time_window, category
        );

        // Refresh trending scores using database function
        let updated = self
            .repo
            .refresh_trending_scores(
                time_window,
                category,
                100, // Top 100 items
            )
            .await?;

        let duration = start.elapsed();

        info!(
            "Computed {} trending items for window={}, category={:?} in {:?}",
            updated, time_window, category, duration
        );

        Ok(updated)
    }

    /// Compute trending for specific category
    pub async fn compute_category_trending(
        &self,
        category: &str,
        time_window: TimeWindow,
    ) -> Result<i32> {
        self.compute_trending_scores(time_window, Some(category))
            .await
    }

    /// Compute trending for all categories
    pub async fn compute_all_categories(&self) -> Result<()> {
        let categories = vec![
            "entertainment",
            "news",
            "sports",
            "gaming",
            "music",
            "education",
            "technology",
        ];

        for category in categories {
            for window in &[
                TimeWindow::OneHour,
                TimeWindow::TwentyFourHours,
                TimeWindow::SevenDays,
            ] {
                if let Err(e) = self.compute_category_trending(category, *window).await {
                    error!(
                        "Failed to compute trending for category={}, window={}: {}",
                        category, window, e
                    );
                }
            }
        }

        Ok(())
    }

    /// Run full trending computation cycle
    ///
    /// This should be called periodically (e.g., every hour)
    pub async fn run_computation_cycle(&self) -> Result<()> {
        info!("Starting trending computation cycle");
        let start = std::time::Instant::now();

        // Compute global trending
        self.compute_all_windows().await?;

        // Compute category trending
        self.compute_all_categories().await?;

        let duration = start.elapsed();
        info!("Trending computation cycle completed in {:?}", duration);

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_compute_service_creation() {
        // This test would require a database connection
        // For now, just test that the types compile correctly
    }

    #[test]
    fn test_algorithm_validation() {
        let algo = TrendingAlgorithm::default();
        assert!(algo.validate().is_ok());
    }
}
