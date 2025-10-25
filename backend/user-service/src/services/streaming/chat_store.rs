//! Redis-backed chat store for live stream comments
//!
//! Comments are ephemeral and kept in Redis lists with capped history.

use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use redis::{aio::ConnectionManager, AsyncCommands};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Chat comment payload stored in Redis
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StreamComment {
    pub id: Uuid,
    pub stream_id: Uuid,
    pub user_id: Uuid,
    pub username: Option<String>,
    pub message: String,
    pub created_at: DateTime<Utc>,
}

impl StreamComment {
    pub fn new(stream_id: Uuid, user_id: Uuid, username: Option<String>, message: String) -> Self {
        Self {
            id: Uuid::new_v4(),
            stream_id,
            user_id,
            username,
            message,
            created_at: Utc::now(),
        }
    }
}

/// Redis-backed comment history (capped list)
#[derive(Clone)]
pub struct StreamChatStore {
    redis: ConnectionManager,
    max_history: usize,
}

impl StreamChatStore {
    pub fn new(redis: ConnectionManager, max_history: usize) -> Self {
        Self { redis, max_history }
    }

    fn key(stream_id: Uuid) -> String {
        format!("stream:{}:comments", stream_id)
    }

    /// Append comment to history while keeping capped size
    pub async fn append_comment(&mut self, comment: &StreamComment) -> Result<()> {
        let key = Self::key(comment.stream_id);
        let payload = serde_json::to_string(comment)?;
        self.redis
            .lpush::<_, _, ()>(&key, payload)
            .await
            .context("failed to push comment to redis")?;
        let max_index = (self.max_history.saturating_sub(1)) as isize;
        self.redis
            .ltrim::<_, ()>(&key, 0, max_index)
            .await
            .context("failed to trim comment history")?;
        Ok(())
    }

    /// Fetch most recent comments up to limit (newest first)
    pub async fn get_recent_comments(
        &mut self,
        stream_id: Uuid,
        limit: usize,
    ) -> Result<Vec<StreamComment>> {
        let key = Self::key(stream_id);
        let limit = limit.min(self.max_history) as isize;
        let raw: Vec<String> = self
            .redis
            .lrange(&key, 0, limit.saturating_sub(1))
            .await
            .context("failed to fetch comments from redis")?;

        let mut comments = Vec::with_capacity(raw.len());
        for entry in raw {
            if let Ok(comment) = serde_json::from_str::<StreamComment>(&entry) {
                comments.push(comment);
            }
        }

        Ok(comments)
    }

    /// Clear chat history when stream ends
    pub async fn clear_comments(&mut self, stream_id: Uuid) -> Result<()> {
        let key = Self::key(stream_id);
        self.redis
            .del::<_, ()>(&key)
            .await
            .context("failed to clear comments from redis")?;
        Ok(())
    }
}
