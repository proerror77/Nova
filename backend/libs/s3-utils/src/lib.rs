/// Shared S3 utilities for all Nova microservices
///
/// Provides unified AWS S3 client, configuration, and operations
/// to prevent duplication across services.

use aws_sdk_s3::Client;
use std::sync::Arc;

pub mod config;
pub mod operations;

pub use config::S3Config;
pub use operations::S3Operations;

/// Shared S3 client wrapper
#[derive(Clone)]
pub struct S3Client {
    client: Arc<Client>,
    config: S3Config,
}

impl S3Client {
    /// Create new S3 client with configuration from environment
    pub async fn new() -> Result<Self, Box<dyn std::error::Error>> {
        let config = S3Config::from_env()?;
        let aws_config = aws_config::load_from_env().await;
        let client = Client::new(&aws_config);

        Ok(Self {
            client: Arc::new(client),
            config,
        })
    }

    /// Create new S3 client with custom configuration
    pub async fn with_config(config: S3Config) -> Result<Self, Box<dyn std::error::Error>> {
        let aws_config = aws_config::load_from_env().await;
        let client = Client::new(&aws_config);

        Ok(Self {
            client: Arc::new(client),
            config,
        })
    }

    /// Get reference to underlying AWS S3 client
    pub fn client(&self) -> &Client {
        &self.client
    }

    /// Get S3 configuration
    pub fn config(&self) -> &S3Config {
        &self.config
    }

    /// Health check for S3 connectivity
    pub async fn health_check(&self) -> Result<(), Box<dyn std::error::Error>> {
        self.client
            .head_bucket()
            .bucket(&self.config.bucket)
            .send()
            .await?;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_s3_config_from_env() {
        // This requires AWS environment variables to be set
        // In test environment, this may fail gracefully
        let _config = S3Config::from_env();
    }
}
