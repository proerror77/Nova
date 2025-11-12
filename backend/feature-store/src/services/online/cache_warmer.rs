use crate::error::Result;
use super::OnlineFeatureStore;
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::watch;
use tokio::time::{sleep, interval};
use tracing::{error, info, warn};
use uuid::Uuid;

/// Background cache warming job for preloading hot features
///
/// **Purpose**:
/// Pre-populate Redis cache with frequently accessed features to ensure
/// low latency for feed rendering and ranking operations.
///
/// **Strategy**:
/// - Runs every 5 minutes by default
/// - Queries PostgreSQL for active users (last 24h activity)
/// - Computes features from near-line store
/// - Batch loads into Redis with 7-day TTL
///
/// **Usage**:
/// ```rust
/// let warmer = CacheWarmer::new(
///     online_store,
///     feature_computer,
///     Duration::from_secs(300)
/// );
///
/// let (shutdown_tx, handle) = warmer.spawn();
///
/// // Later: shutdown
/// shutdown_tx.send(()).await?;
/// handle.await?;
/// ```
pub struct CacheWarmer {
    online_store: Arc<OnlineFeatureStore>,
    feature_computer: Arc<dyn FeatureComputer>,
    interval: Duration,
}

/// Trait for computing features from source data
///
/// Implementations should query PostgreSQL/ClickHouse and compute
/// features for a batch of users.
#[async_trait::async_trait]
pub trait FeatureComputer: Send + Sync {
    /// Get list of active user IDs (last 24h activity)
    async fn get_active_users(&self) -> Result<Vec<Uuid>>;

    /// Compute features for a batch of users
    ///
    /// Returns HashMap of user_id -> (feature_name -> value)
    async fn compute_features(
        &self,
        user_ids: &[Uuid],
    ) -> Result<HashMap<Uuid, HashMap<String, f64>>>;
}

impl CacheWarmer {
    /// Create a new CacheWarmer instance
    ///
    /// # Arguments
    /// * `online_store` - Online feature store to warm
    /// * `feature_computer` - Implementation for computing features
    /// * `interval` - Time between warming cycles (default: 5 minutes)
    pub fn new(
        online_store: Arc<OnlineFeatureStore>,
        feature_computer: Arc<dyn FeatureComputer>,
        interval: Duration,
    ) -> Self {
        Self {
            online_store,
            feature_computer,
            interval,
        }
    }

    /// Spawn background warming task
    ///
    /// # Returns
    /// - `watch::Sender<()>` - Send signal to shutdown
    /// - `tokio::task::JoinHandle` - Task handle for awaiting completion
    pub fn spawn(
        self,
    ) -> (
        watch::Sender<()>,
        tokio::task::JoinHandle<Result<()>>,
    ) {
        let (shutdown_tx, mut shutdown_rx) = watch::channel(());

        let handle = tokio::spawn(async move {
            info!(
                interval_secs = self.interval.as_secs(),
                "CacheWarmer started"
            );

            let mut timer = interval(self.interval);

            loop {
                tokio::select! {
                    _ = shutdown_rx.changed() => {
                        info!("CacheWarmer received shutdown signal");
                        break;
                    }
                    _ = timer.tick() => {
                        if let Err(e) = self.run_warming_cycle().await {
                            error!(error = %e, "Cache warming cycle failed");
                        }
                    }
                }
            }

            info!("CacheWarmer stopped");
            Ok(())
        });

        (shutdown_tx, handle)
    }

    /// Run a single warming cycle
    async fn run_warming_cycle(&self) -> Result<()> {
        let start = std::time::Instant::now();

        // Step 1: Get active users
        let active_users = match self.feature_computer.get_active_users().await {
            Ok(users) => {
                info!(user_count = users.len(), "Retrieved active users");
                users
            }
            Err(e) => {
                error!(error = %e, "Failed to get active users");
                return Err(e);
            }
        };

        if active_users.is_empty() {
            info!("No active users to warm");
            return Ok(());
        }

        // Step 2: Process in batches to avoid overwhelming systems
        const BATCH_SIZE: usize = 100;
        let mut total_warmed = 0;
        let mut total_errors = 0;

        for batch in active_users.chunks(BATCH_SIZE) {
            match self.warm_batch(batch).await {
                Ok(count) => {
                    total_warmed += count;
                }
                Err(e) => {
                    warn!(
                        batch_size = batch.len(),
                        error = %e,
                        "Failed to warm batch"
                    );
                    total_errors += batch.len();
                }
            }

            // Small delay between batches to avoid spiking Redis
            sleep(Duration::from_millis(100)).await;
        }

        let elapsed = start.elapsed();
        info!(
            total_users = active_users.len(),
            warmed = total_warmed,
            errors = total_errors,
            elapsed_ms = elapsed.as_millis(),
            "Cache warming cycle completed"
        );

        Ok(())
    }

    /// Warm cache for a batch of users
    async fn warm_batch(&self, user_ids: &[Uuid]) -> Result<usize> {
        // Compute features for batch
        let features = self.feature_computer.compute_features(user_ids).await?;

        let mut warmed_count = 0;

        // Warm each user's features
        for (user_id, user_features) in features {
            match self.online_store.warm_features(user_id, user_features).await {
                Ok(_) => {
                    warmed_count += 1;
                }
                Err(e) => {
                    warn!(
                        user_id = %user_id,
                        error = %e,
                        "Failed to warm features for user"
                    );
                }
            }
        }

        Ok(warmed_count)
    }
}

/// Simple in-memory feature computer for testing
#[cfg(test)]
pub struct MockFeatureComputer {
    active_users: Vec<Uuid>,
}

#[cfg(test)]
impl MockFeatureComputer {
    pub fn new(active_users: Vec<Uuid>) -> Self {
        Self { active_users }
    }
}

#[cfg(test)]
#[async_trait::async_trait]
impl FeatureComputer for MockFeatureComputer {
    async fn get_active_users(&self) -> Result<Vec<Uuid>> {
        Ok(self.active_users.clone())
    }

    async fn compute_features(
        &self,
        user_ids: &[Uuid],
    ) -> Result<HashMap<Uuid, HashMap<String, f64>>> {
        let mut result = HashMap::new();

        for user_id in user_ids {
            let mut features = HashMap::new();
            features.insert("engagement_score".to_string(), 0.75);
            features.insert("avg_session_time".to_string(), 120.5);
            result.insert(*user_id, features);
        }

        Ok(result)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_mock_feature_computer() {
        let user_id = Uuid::new_v4();
        let computer = MockFeatureComputer::new(vec![user_id]);

        assert_eq!(computer.active_users.len(), 1);
        assert_eq!(computer.active_users[0], user_id);
    }
}
