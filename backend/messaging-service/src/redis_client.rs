use redis::aio::ConnectionManager;
use redis::{Client, RedisResult};
use redis_utils::SharedConnectionManager;
use std::sync::Arc;
use tokio::sync::Mutex;

#[derive(Clone)]
pub struct RedisClient {
    manager: SharedConnectionManager,
}

impl RedisClient {
    pub fn new(manager: SharedConnectionManager) -> Self {
        Self { manager }
    }

    pub fn manager(&self) -> SharedConnectionManager {
        self.manager.clone()
    }

    pub async fn from_url(url: &str) -> RedisResult<Self> {
        let client = Client::open(url)?;
        let manager = ConnectionManager::new(client).await?;
        Ok(Self {
            manager: Arc::new(Mutex::new(manager)),
        })
    }

    pub async fn get_multiplexed_async_connection(&self) -> RedisResult<ConnectionManager> {
        let guard = self.manager.lock().await;
        Ok(guard.clone())
    }
}
