/// OAuth Token Refresh Background Job
///
/// Automatically refreshes OAuth tokens before they expire.
///
/// This job:
/// 1. Queries for OAuth connections with tokens expiring within a window
/// 2. Attempts to refresh each token using the provider's refresh endpoint
/// 3. Updates the database with new tokens on success
/// 4. Logs metrics and errors for monitoring
/// 5. Handles failures gracefully without stopping the entire job
///
/// IMPORTANT: This implementation requires encrypted token storage
/// Current schema stores hashed tokens which cannot be refreshed.
/// See OAUTH_TOKEN_STORAGE_FIX.md for migration details.
use crate::db::oauth_repo;
use crate::models::OAuthConnection;
use crate::services::oauth::{OAuthError, OAuthProviderFactory};
use chrono::Utc;
use sqlx::PgPool;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::RwLock;
use tokio::task::JoinHandle;
use tokio::time::interval;
use tracing::{debug, error, info, warn};

/// Configuration for OAuth token refresh job
#[derive(Debug, Clone)]
pub struct OAuthTokenRefreshConfig {
    /// Interval between refresh attempts (seconds)
    pub refresh_interval_secs: u64,
    /// Time window for expiring tokens to refresh (seconds)
    /// Tokens expiring within this window will be refreshed
    pub expiry_window_secs: i64,
    /// Maximum number of tokens to refresh per cycle
    pub max_tokens_per_cycle: usize,
    /// Retry delay for failed refresh attempts (milliseconds)
    pub retry_delay_ms: u64,
    /// Maximum retry attempts for a single token refresh
    pub max_retries: u32,
}

impl Default for OAuthTokenRefreshConfig {
    fn default() -> Self {
        Self {
            refresh_interval_secs: 300, // 5 minutes
            expiry_window_secs: 600,    // 10 minutes before expiry
            max_tokens_per_cycle: 100,
            retry_delay_ms: 1000,
            max_retries: 3,
        }
    }
}

/// Statistics for OAuth token refresh job
#[derive(Debug, Clone, Default)]
pub struct OAuthTokenRefreshStats {
    pub total_refreshes_attempted: u64,
    pub successful_refreshes: u64,
    pub failed_refreshes: u64,
    pub skipped_tokens: u64, // Tokens without refresh_token or encrypt keys
    pub last_refresh_at: Option<i64>, // Unix timestamp
}

/// OAuth Token Refresh Job
pub struct OAuthTokenRefreshJob {
    config: OAuthTokenRefreshConfig,
    pool: Arc<PgPool>,
    stats: Arc<RwLock<OAuthTokenRefreshStats>>,
}

impl OAuthTokenRefreshJob {
    /// Create a new token refresh job
    pub fn new(config: OAuthTokenRefreshConfig, pool: Arc<PgPool>) -> Self {
        Self {
            config,
            pool,
            stats: Arc::new(RwLock::new(OAuthTokenRefreshStats::default())),
        }
    }

    /// Start the background job
    /// Returns a JoinHandle that can be awaited or aborted
    pub fn start(self) -> JoinHandle<()> {
        tokio::spawn(async move {
            let mut interval = interval(Duration::from_secs(self.config.refresh_interval_secs));

            info!(
                "Starting OAuth token refresh job (interval: {}s, window: {}s)",
                self.config.refresh_interval_secs, self.config.expiry_window_secs
            );

            loop {
                interval.tick().await;

                if let Err(e) = self.refresh_cycle().await {
                    error!("OAuth token refresh cycle failed: {}", e);
                }
            }
        })
    }

    /// Execute one refresh cycle
    async fn refresh_cycle(&self) -> Result<(), String> {
        debug!("Starting OAuth token refresh cycle");

        // 1. Query for connections with expiring tokens
        let connections =
            oauth_repo::find_expiring_tokens(self.pool.as_ref(), self.config.expiry_window_secs)
                .await
                .map_err(|e| format!("Failed to query expiring tokens: {}", e))?;

        if connections.is_empty() {
            debug!("No expiring OAuth tokens found");
            return Ok(());
        }

        info!(
            "Found {} OAuth connections with expiring tokens",
            connections.len()
        );

        // 2. Limit tokens to process per cycle
        let tokens_to_process =
            &connections[0..std::cmp::min(connections.len(), self.config.max_tokens_per_cycle)];

        // 3. Attempt to refresh each token
        for connection in tokens_to_process {
            let mut stats = self.stats.write().await;
            stats.total_refreshes_attempted += 1;
            drop(stats); // Release lock before async call

            if let Err(e) = self.refresh_single_token(connection).await {
                error!(
                    "Failed to refresh token for user={}, provider={}: {}",
                    connection.user_id, connection.provider, e
                );
                // Stats already updated in refresh_single_token
            }
        }

        // 4. Update stats
        {
            let mut stats = self.stats.write().await;
            stats.last_refresh_at = Some(Utc::now().timestamp());
        }

        debug!("OAuth token refresh cycle complete");
        Ok(())
    }

    /// Refresh a single OAuth token
    async fn refresh_single_token(&self, connection: &OAuthConnection) -> Result<(), String> {
        // Check if encrypted tokens are available
        // For backward compatibility, we skip tokens without encrypted storage
        let encrypted_available = match sqlx::query_scalar::<_, bool>(
            "SELECT COALESCE(tokens_encrypted, false) FROM oauth_connections WHERE id = $1",
        )
        .bind(connection.id)
        .fetch_one(self.pool.as_ref())
        .await
        {
            Ok(val) => val,
            Err(e) => {
                error!("Failed to check token encryption status: {}", e);
                return Err(format!("Database error: {}", e));
            }
        };

        if !encrypted_available {
            debug!(
                "Skipping refresh for user={}, provider={} - tokens not encrypted",
                connection.user_id, connection.provider
            );
            let mut stats = self.stats.write().await;
            stats.skipped_tokens += 1;
            return Ok(());
        }

        // Get decrypted refresh token
        let refresh_token =
            crate::db::oauth_repo::get_decrypted_refresh_token(self.pool.as_ref(), connection.id)
                .await
                .map_err(|e| {
                    warn!(
                        "Failed to decrypt refresh token for user={}, provider={}: {}",
                        connection.user_id, connection.provider, e
                    );
                    e
                })?;

        // Attempt refresh with retries
        let mut attempt = 0;
        loop {
            attempt += 1;
            match self.refresh_with_provider(connection, &refresh_token).await {
                Ok(response) => {
                    // Update tokens in database
                    let new_expires_at = std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .map(|d| d.as_secs() as i64 + response.expires_in)
                        .ok();

                    if let Err(e) = crate::db::oauth_repo::update_tokens(
                        self.pool.as_ref(),
                        connection.id,
                        &response.access_token,
                        response.refresh_token.as_deref(),
                        new_expires_at,
                    )
                    .await
                    {
                        error!(
                            "Failed to update tokens for user={}, provider={}: {}",
                            connection.user_id, connection.provider, e
                        );
                        let mut stats = self.stats.write().await;
                        stats.failed_refreshes += 1;
                        return Err(format!("Failed to update tokens: {}", e));
                    }

                    info!(
                        "Successfully refreshed OAuth token for user={}, provider={}",
                        connection.user_id, connection.provider
                    );
                    let mut stats = self.stats.write().await;
                    stats.successful_refreshes += 1;
                    return Ok(());
                }
                Err(e) if attempt < self.config.max_retries => {
                    warn!(
                        "Token refresh attempt {}/{} failed for user={}, provider={}: {}. Retrying...",
                        attempt, self.config.max_retries, connection.user_id, connection.provider, e
                    );
                    // Exponential backoff
                    let delay_ms = self.config.retry_delay_ms * 2_u64.pow(attempt - 1);
                    tokio::time::sleep(std::time::Duration::from_millis(delay_ms)).await;
                }
                Err(e) => {
                    error!(
                        "Token refresh failed after {} attempts for user={}, provider={}: {}",
                        attempt, connection.user_id, connection.provider, e
                    );
                    let mut stats = self.stats.write().await;
                    stats.failed_refreshes += 1;
                    return Err(e.to_string());
                }
            }
        }
    }

    /// Attempt to refresh using provider-specific endpoint
    /// This is the actual refresh logic (currently unused due to schema issue)
    #[allow(dead_code)]
    async fn refresh_with_provider(
        &self,
        connection: &OAuthConnection,
        refresh_token: &str,
    ) -> Result<RefreshTokenResponse, OAuthError> {
        // Create provider instance
        OAuthProviderFactory::create(&connection.provider)?;

        // Call provider-specific refresh method
        match connection.provider.as_str() {
            "google" => self.refresh_google_token(refresh_token).await,
            "apple" => self.refresh_apple_token(refresh_token).await,
            "facebook" => self.refresh_facebook_token(refresh_token).await,
            _ => Err(OAuthError::ConfigError(format!(
                "Unknown provider: {}",
                connection.provider
            ))),
        }
    }

    /// Refresh Google OAuth token
    #[allow(dead_code)]
    async fn refresh_google_token(
        &self,
        refresh_token: &str,
    ) -> Result<RefreshTokenResponse, OAuthError> {
        let client = reqwest::Client::new();
        let client_id = std::env::var("GOOGLE_CLIENT_ID")
            .map_err(|_| OAuthError::ConfigError("GOOGLE_CLIENT_ID not set".to_string()))?;
        let client_secret = std::env::var("GOOGLE_CLIENT_SECRET")
            .map_err(|_| OAuthError::ConfigError("GOOGLE_CLIENT_SECRET not set".to_string()))?;

        let response = client
            .post("https://oauth2.googleapis.com/token")
            .form(&[
                ("client_id", client_id.as_str()),
                ("client_secret", client_secret.as_str()),
                ("refresh_token", refresh_token),
                ("grant_type", "refresh_token"),
            ])
            .send()
            .await
            .map_err(|e| OAuthError::NetworkError(format!("Failed to refresh token: {}", e)))?;

        let token_response: GoogleTokenRefreshResponse = response
            .json()
            .await
            .map_err(|e| OAuthError::TokenExchange(format!("Failed to parse response: {}", e)))?;

        Ok(RefreshTokenResponse {
            access_token: token_response.access_token,
            refresh_token: token_response.refresh_token,
            expires_in: token_response.expires_in,
        })
    }

    /// Refresh Apple OAuth token
    #[allow(dead_code)]
    async fn refresh_apple_token(
        &self,
        refresh_token: &str,
    ) -> Result<RefreshTokenResponse, OAuthError> {
        // Apple's token refresh uses the same endpoint as initial auth
        // but with grant_type=refresh_token
        let client = reqwest::Client::new();
        let client_id = std::env::var("APPLE_CLIENT_ID")
            .map_err(|_| OAuthError::ConfigError("APPLE_CLIENT_ID not set".to_string()))?;

        let response = client
            .post("https://appleid.apple.com/auth/token")
            .form(&[
                ("client_id", client_id.as_str()),
                ("refresh_token", refresh_token),
                ("grant_type", "refresh_token"),
            ])
            .send()
            .await
            .map_err(|e| OAuthError::NetworkError(format!("Failed to refresh token: {}", e)))?;

        let token_response: AppleTokenRefreshResponse = response
            .json()
            .await
            .map_err(|e| OAuthError::TokenExchange(format!("Failed to parse response: {}", e)))?;

        Ok(RefreshTokenResponse {
            access_token: token_response.access_token,
            refresh_token: token_response.refresh_token,
            expires_in: token_response.expires_in,
        })
    }

    /// Refresh Facebook OAuth token
    #[allow(dead_code)]
    async fn refresh_facebook_token(
        &self,
        refresh_token: &str,
    ) -> Result<RefreshTokenResponse, OAuthError> {
        let client = reqwest::Client::new();
        let app_id = std::env::var("FACEBOOK_CLIENT_ID")
            .map_err(|_| OAuthError::ConfigError("FACEBOOK_CLIENT_ID not set".to_string()))?;
        let app_secret = std::env::var("FACEBOOK_CLIENT_SECRET")
            .map_err(|_| OAuthError::ConfigError("FACEBOOK_CLIENT_SECRET not set".to_string()))?;

        let response = client
            .get("https://graph.instagram.com/refresh_access_token")
            .query(&[
                ("grant_type", "ig_refresh_token"),
                ("access_token", refresh_token),
            ])
            .send()
            .await
            .map_err(|e| OAuthError::NetworkError(format!("Failed to refresh token: {}", e)))?;

        let token_response: FacebookTokenRefreshResponse = response
            .json()
            .await
            .map_err(|e| OAuthError::TokenExchange(format!("Failed to parse response: {}", e)))?;

        Ok(RefreshTokenResponse {
            access_token: token_response.access_token,
            refresh_token: Some(refresh_token.to_string()), // Facebook doesn't return new refresh token
            expires_in: token_response.expires_in,
        })
    }

    /// Get current statistics
    pub async fn get_stats(&self) -> OAuthTokenRefreshStats {
        self.stats.read().await.clone()
    }
}

/// Standard refresh token response wrapper
#[derive(Debug)]
struct RefreshTokenResponse {
    pub access_token: String,
    pub refresh_token: Option<String>,
    pub expires_in: i64,
}

/// Google token refresh response
#[derive(Debug, serde::Deserialize)]
struct GoogleTokenRefreshResponse {
    pub access_token: String,
    #[serde(default)]
    pub refresh_token: Option<String>,
    pub expires_in: i64,
    pub token_type: String,
}

/// Apple token refresh response
#[derive(Debug, serde::Deserialize)]
struct AppleTokenRefreshResponse {
    pub access_token: String,
    #[serde(default)]
    pub refresh_token: Option<String>,
    pub expires_in: i64,
    pub token_type: String,
}

/// Facebook token refresh response
#[derive(Debug, serde::Deserialize)]
struct FacebookTokenRefreshResponse {
    pub access_token: String,
    pub expires_in: i64,
}

#[cfg(test)]
#[cfg(all(test, feature = "legacy_internal_tests"))]
mod tests {
    use super::*;

    #[test]
    fn test_token_refresh_config_defaults() {
        let config = OAuthTokenRefreshConfig::default();
        assert_eq!(config.refresh_interval_secs, 300);
        assert_eq!(config.expiry_window_secs, 600);
        assert_eq!(config.max_tokens_per_cycle, 100);
    }

    #[test]
    fn test_token_refresh_stats_default() {
        let stats = OAuthTokenRefreshStats::default();
        assert_eq!(stats.total_refreshes_attempted, 0);
        assert_eq!(stats.successful_refreshes, 0);
        assert_eq!(stats.failed_refreshes, 0);
        assert_eq!(stats.skipped_tokens, 0);
        assert_eq!(stats.last_refresh_at, None);
    }

    #[test]
    fn test_token_refresh_job_creation() {
        // Just verify the job can be created without panicking
        use sqlx::postgres::PgPoolOptions;

        let pg_pool = PgPoolOptions::new()
            .max_connections(1)
            .connect_lazy("postgres://postgres:postgres@localhost:5432/postgres")
            .unwrap();
        let pool = std::sync::Arc::new(pg_pool);

        let config = OAuthTokenRefreshConfig::default();
        let _job = OAuthTokenRefreshJob::new(config, pool);

        assert!(true); // Compilation and creation succeeded
    }
}
