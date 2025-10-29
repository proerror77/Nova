/// Caching layer for media-service
///
/// This module handles:
/// - Video metadata caching
/// - Upload session caching
use crate::error::{AppError, Result};
use crate::models::{Upload, Video};
use redis::aio::ConnectionManager;
use redis::AsyncCommands;
use serde::de::DeserializeOwned;
use serde::Serialize;
use std::sync::Arc;
use tokio::sync::Mutex;
use uuid::Uuid;

const DEFAULT_TTL_SECONDS: u64 = 300;

/// Redis-backed cache helper for media entities
#[derive(Clone)]
pub struct MediaCache {
    conn: Arc<Mutex<ConnectionManager>>,
    ttl_seconds: u64,
}

impl MediaCache {
    /// Initialize cache from Redis client
    pub async fn new(client: redis::Client, ttl_seconds: Option<u64>) -> Result<Self> {
        let manager = ConnectionManager::new(client)
            .await
            .map_err(|e| AppError::CacheError(format!("Failed to connect to Redis: {e}")))?;

        Ok(Self::with_manager(Arc::new(Mutex::new(manager)), ttl_seconds))
    }

    pub fn with_manager(
        manager: Arc<Mutex<ConnectionManager>>,
        ttl_seconds: Option<u64>,
    ) -> Self {
        Self {
            conn: manager,
            ttl_seconds: ttl_seconds.unwrap_or(DEFAULT_TTL_SECONDS),
        }
    }

    /// Cache a video record
    pub async fn cache_video(&self, video: &Video) -> Result<()> {
        self.set_json(&Self::video_key(video.id), video, None).await
    }

    /// Retrieve cached video if available
    pub async fn get_video(&self, video_id: Uuid) -> Result<Option<Video>> {
        self.get_json(&Self::video_key(video_id)).await
    }

    /// Invalidate video cache entry
    pub async fn invalidate_video(&self, video_id: Uuid) -> Result<()> {
        self.delete(&Self::video_key(video_id)).await
    }

    /// Cache an upload session
    pub async fn cache_upload(&self, upload: &Upload) -> Result<()> {
        self.set_json(&Self::upload_key(upload.id), upload, None)
            .await
    }

    /// Retrieve cached upload session
    pub async fn get_upload(&self, upload_id: Uuid) -> Result<Option<Upload>> {
        self.get_json(&Self::upload_key(upload_id)).await
    }

    /// Remove upload from cache
    pub async fn invalidate_upload(&self, upload_id: Uuid) -> Result<()> {
        self.delete(&Self::upload_key(upload_id)).await
    }

    /// Store arbitrary JSON payload in Redis
    pub async fn set_json<T: Serialize>(
        &self,
        key: &str,
        value: &T,
        ttl: Option<u64>,
    ) -> Result<()> {
        let payload = serde_json::to_string(value)
            .map_err(|e| AppError::CacheError(format!("Failed to serialize cache value: {e}")))?;

        let mut conn = self.conn.lock().await;
        let ttl = ttl.unwrap_or(self.ttl_seconds);
        conn.set_ex(key, payload, ttl)
            .await
            .map_err(|e| AppError::CacheError(format!("Failed to write to cache: {e}")))
    }

    /// Retrieve JSON payload from Redis
    pub async fn get_json<T: DeserializeOwned>(&self, key: &str) -> Result<Option<T>> {
        let mut conn = self.conn.lock().await;
        let value: Option<String> = conn
            .get(key)
            .await
            .map_err(|e| AppError::CacheError(format!("Failed to read from cache: {e}")))?;

        match value {
            Some(raw) => {
                let parsed = serde_json::from_str(&raw).map_err(|e| {
                    AppError::CacheError(format!("Failed to deserialize cache value: {e}"))
                })?;
                Ok(Some(parsed))
            }
            None => Ok(None),
        }
    }

    /// Delete cache key
    pub async fn delete(&self, key: &str) -> Result<()> {
        let mut conn = self.conn.lock().await;
        conn.del(key)
            .await
            .map(|_: usize| ())
            .map_err(|e| AppError::CacheError(format!("Failed to delete cache key: {e}")))
    }

    fn video_key(id: Uuid) -> String {
        format!("media:video:{id}")
    }

    fn upload_key(id: Uuid) -> String {
        format!("media:upload:{id}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_key_helpers() {
        let id = Uuid::nil();
        assert_eq!(
            MediaCache::video_key(id),
            "media:video:00000000-0000-0000-0000-000000000000"
        );
        assert_eq!(
            MediaCache::upload_key(id),
            "media:upload:00000000-0000-0000-0000-000000000000"
        );
    }
}
