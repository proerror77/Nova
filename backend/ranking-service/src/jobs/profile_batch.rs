// ============================================
// Profile Batch Job (用戶畫像批量更新任務)
// ============================================
//
// Background job that periodically updates user profiles.
// Designed to run as a Kubernetes CronJob or standalone process.
//
// Workflow:
// 1. Fetch active users from ClickHouse (users with recent activity)
// 2. For each user, rebuild their interest tags and behavior patterns
// 3. Optionally run LLM analysis for high-value users
// 4. Cache results in Redis
//
// Usage:
//   ranking-service --mode profile-batch --batch-size 100 --llm-enabled

use crate::config::{ClickHouseConfig, Config, LlmConfig};
use crate::services::profile_builder::{
    ClickHouseProfileDatabase, LlmProfileAnalyzer, ProfileDatabase, ProfileUpdater,
    ProfileUpdaterConfig, UserProfile,
};
use chrono::{DateTime, Utc};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::time::sleep;
use tracing::{error, info, warn};
use uuid::Uuid;

/// Profile batch job configuration
#[derive(Debug, Clone)]
pub struct ProfileBatchConfig {
    /// Number of users to process in each batch
    pub batch_size: u32,
    /// Maximum number of users to process in total (0 = unlimited)
    pub max_users: u32,
    /// Delay between batches (to avoid overloading the system)
    pub batch_delay_ms: u64,
    /// Whether to run LLM analysis for users
    pub llm_enabled: bool,
    /// Minimum engagement threshold for LLM analysis
    pub llm_min_engagement: u32,
    /// Whether to run continuously or exit after one pass
    pub run_once: bool,
    /// Interval between full passes (if not run_once)
    pub interval_secs: u64,
}

impl Default for ProfileBatchConfig {
    fn default() -> Self {
        Self {
            batch_size: 100,
            max_users: 0,
            batch_delay_ms: 500,
            llm_enabled: false,
            llm_min_engagement: 50,
            run_once: true,
            interval_secs: 3600 * 4, // 4 hours
        }
    }
}

impl ProfileBatchConfig {
    /// Create config from environment variables
    pub fn from_env() -> Self {
        Self {
            batch_size: std::env::var("PROFILE_BATCH_SIZE")
                .unwrap_or_else(|_| "100".to_string())
                .parse()
                .unwrap_or(100),
            max_users: std::env::var("PROFILE_MAX_USERS")
                .unwrap_or_else(|_| "0".to_string())
                .parse()
                .unwrap_or(0),
            batch_delay_ms: std::env::var("PROFILE_BATCH_DELAY_MS")
                .unwrap_or_else(|_| "500".to_string())
                .parse()
                .unwrap_or(500),
            llm_enabled: std::env::var("PROFILE_LLM_ENABLED")
                .unwrap_or_else(|_| "false".to_string())
                .parse()
                .unwrap_or(false),
            llm_min_engagement: std::env::var("PROFILE_LLM_MIN_ENGAGEMENT")
                .unwrap_or_else(|_| "50".to_string())
                .parse()
                .unwrap_or(50),
            run_once: std::env::var("PROFILE_RUN_ONCE")
                .unwrap_or_else(|_| "true".to_string())
                .parse()
                .unwrap_or(true),
            interval_secs: std::env::var("PROFILE_INTERVAL_SECS")
                .unwrap_or_else(|_| "14400".to_string())
                .parse()
                .unwrap_or(14400),
        }
    }
}

/// Profile batch job statistics
#[derive(Debug, Clone, Default)]
pub struct BatchJobStats {
    pub started_at: Option<DateTime<Utc>>,
    pub completed_at: Option<DateTime<Utc>>,
    pub users_processed: u32,
    pub users_succeeded: u32,
    pub users_failed: u32,
    pub llm_analyses: u32,
    pub llm_failures: u32,
    pub total_duration_ms: u64,
}

/// Profile batch job runner
pub struct ProfileBatchJob {
    config: ProfileBatchConfig,
    ch_db: Arc<ClickHouseProfileDatabase>,
    redis_client: redis::Client,
    llm_analyzer: Option<LlmProfileAnalyzer>,
}

impl ProfileBatchJob {
    /// Create a new profile batch job
    pub fn new(
        config: ProfileBatchConfig,
        ch_config: &ClickHouseConfig,
        redis_url: &str,
        llm_config: Option<&LlmConfig>,
    ) -> Result<Self, Box<dyn std::error::Error>> {
        let ch_db = Arc::new(ClickHouseProfileDatabase::from_config(ch_config));

        let redis_client = redis::Client::open(redis_url)?;

        let llm_analyzer = if config.llm_enabled {
            llm_config.and_then(|cfg| LlmProfileAnalyzer::from_config(cfg))
        } else {
            None
        };

        Ok(Self {
            config,
            ch_db,
            redis_client,
            llm_analyzer,
        })
    }

    /// Create from app config
    pub fn from_config(
        batch_config: ProfileBatchConfig,
        app_config: &Config,
    ) -> Result<Self, Box<dyn std::error::Error>> {
        Self::new(
            batch_config,
            &app_config.clickhouse,
            &app_config.redis.url,
            Some(&app_config.llm),
        )
    }

    /// Run the batch job
    pub async fn run(&self) -> Result<BatchJobStats, Box<dyn std::error::Error>> {
        loop {
            let stats = self.run_single_pass().await?;

            info!(
                processed = stats.users_processed,
                succeeded = stats.users_succeeded,
                failed = stats.users_failed,
                llm_analyses = stats.llm_analyses,
                duration_ms = stats.total_duration_ms,
                "Profile batch job pass completed"
            );

            if self.config.run_once {
                return Ok(stats);
            }

            info!(
                interval_secs = self.config.interval_secs,
                "Sleeping until next pass"
            );
            sleep(Duration::from_secs(self.config.interval_secs)).await;
        }
    }

    /// Run a single pass of the batch job
    async fn run_single_pass(&self) -> Result<BatchJobStats, Box<dyn std::error::Error>> {
        let start_time = Instant::now();
        let mut stats = BatchJobStats {
            started_at: Some(Utc::now()),
            ..Default::default()
        };

        info!(
            batch_size = self.config.batch_size,
            max_users = self.config.max_users,
            llm_enabled = self.config.llm_enabled,
            "Starting profile batch job pass"
        );

        // Fetch users that need profile updates
        let user_limit = if self.config.max_users > 0 {
            self.config.max_users
        } else {
            10000 // Default max
        };

        let users = self
            .ch_db
            .fetch_users_needing_update(user_limit)
            .await
            .map_err(|e| format!("Failed to fetch users: {}", e))?;

        info!(user_count = users.len(), "Fetched users for profile update");

        // Create profile updater
        let updater_config = ProfileUpdaterConfig::default();
        let updater =
            ProfileUpdater::new(self.ch_db.clone(), self.redis_client.clone(), updater_config);

        // Process users in batches
        for (batch_idx, batch) in users.chunks(self.config.batch_size as usize).enumerate() {
            info!(
                batch = batch_idx + 1,
                users = batch.len(),
                "Processing user batch"
            );

            for user_id in batch {
                stats.users_processed += 1;

                match updater.update_user_profile(*user_id).await {
                    Ok(profile) => {
                        stats.users_succeeded += 1;

                        // Run LLM analysis for high-engagement users
                        if self.should_run_llm_analysis(&profile) {
                            if let Err(e) = self.run_llm_analysis(&profile).await {
                                warn!(
                                    user_id = %user_id,
                                    error = %e,
                                    "LLM analysis failed"
                                );
                                stats.llm_failures += 1;
                            } else {
                                stats.llm_analyses += 1;
                            }
                        }
                    }
                    Err(e) => {
                        stats.users_failed += 1;
                        error!(
                            user_id = %user_id,
                            error = %e,
                            "Failed to update user profile"
                        );
                    }
                }
            }

            // Delay between batches
            if self.config.batch_delay_ms > 0 {
                sleep(Duration::from_millis(self.config.batch_delay_ms)).await;
            }
        }

        stats.completed_at = Some(Utc::now());
        stats.total_duration_ms = start_time.elapsed().as_millis() as u64;

        Ok(stats)
    }

    /// Check if LLM analysis should be run for a user
    fn should_run_llm_analysis(&self, profile: &UserProfile) -> bool {
        if !self.config.llm_enabled || self.llm_analyzer.is_none() {
            return false;
        }

        // Run LLM for users with sufficient engagement history
        let total_interactions: u32 = profile
            .interests
            .iter()
            .map(|t| t.interaction_count as u32)
            .sum();

        total_interactions >= self.config.llm_min_engagement
    }

    /// Run LLM analysis for a user profile
    async fn run_llm_analysis(&self, profile: &UserProfile) -> Result<(), String> {
        let analyzer = self
            .llm_analyzer
            .as_ref()
            .ok_or("LLM analyzer not initialized")?;

        let persona = analyzer
            .analyze_profile(profile)
            .await
            .map_err(|e| format!("LLM analysis failed: {}", e))?;

        info!(
            user_id = %profile.user_id,
            segment = persona.segment.as_str(),
            confidence = persona.confidence,
            "Generated AI persona"
        );

        // The persona is automatically cached by the analyzer
        Ok(())
    }
}

/// Entry point for running the profile batch job as a standalone process
pub async fn run_profile_batch_job() -> Result<(), Box<dyn std::error::Error>> {
    info!("Initializing profile batch job");

    let config = Config::from_env()?;
    let batch_config = ProfileBatchConfig::from_env();

    let job = ProfileBatchJob::from_config(batch_config, &config)?;
    let stats = job.run().await?;

    info!(
        processed = stats.users_processed,
        succeeded = stats.users_succeeded,
        failed = stats.users_failed,
        "Profile batch job completed"
    );

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_from_env() {
        // Test default config
        let config = ProfileBatchConfig::default();
        assert_eq!(config.batch_size, 100);
        assert!(config.run_once);
    }
}
