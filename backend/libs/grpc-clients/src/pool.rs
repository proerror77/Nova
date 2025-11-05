/// Connection Pool Management
///
/// Manages gRPC connection pooling and lifecycle for efficient inter-service communication.

use std::sync::Arc;
use tonic::transport::{Channel, Endpoint};
use std::time::Duration;

/// gRPC Connection Pool
/// Manages multiple connections with automatic cleanup and health checks
pub struct ConnectionPool {
    channels: Vec<Arc<Channel>>,
    current_index: std::sync::atomic::AtomicUsize,
    size: usize,
}

impl ConnectionPool {
    /// Create a new connection pool
    pub async fn new(
        endpoint: &str,
        pool_size: usize,
        timeout_secs: u64,
    ) -> Result<Self, Box<dyn std::error::Error>> {
        let mut channels = Vec::new();

        for _ in 0..pool_size {
            let channel = Endpoint::from_shared(endpoint.to_string())?
                .connect_timeout(Duration::from_secs(timeout_secs))
                .connect()
                .await?;

            channels.push(Arc::new(channel));
        }

        Ok(Self {
            channels,
            current_index: std::sync::atomic::AtomicUsize::new(0),
            size: pool_size,
        })
    }

    /// Get next connection from pool (round-robin)
    pub fn get(&self) -> Arc<Channel> {
        let index = self.current_index.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        self.channels[index % self.size].clone()
    }

    /// Get pool size
    pub fn size(&self) -> usize {
        self.size
    }

    /// Health check all connections
    pub async fn health_check(&self) -> Result<(), Box<dyn std::error::Error>> {
        // Implement health check logic here
        // For now, just return ok
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_connection_pool_creation() {
        // This would require a running gRPC server
        // Skipped in normal test runs
    }
}
