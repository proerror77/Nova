//! Stream service (business logic layer)
//!
//! Orchestrates repository + Redis + Kafka to implement stream lifecycle

use super::chat_store::{StreamChatStore, StreamComment};
use super::models::*;
use super::redis_counter::ViewerCounter;
use super::repository::StreamRepository;
use crate::services::kafka_producer::EventProducer;
use anyhow::{anyhow, Result};
use serde_json::json;
use std::sync::Arc;
use uuid::Uuid;

/// Stream service (business logic)
pub struct StreamService {
    repo: StreamRepository,
    viewer_counter: ViewerCounter,
    chat_store: StreamChatStore,
    kafka_producer: Arc<EventProducer>,
    rtmp_base_url: String,
    hls_cdn_url: String,
}

impl StreamService {
    pub fn new(
        repo: StreamRepository,
        viewer_counter: ViewerCounter,
        chat_store: StreamChatStore,
        kafka_producer: Arc<EventProducer>,
        rtmp_base_url: String,
        hls_cdn_url: String,
    ) -> Self {
        Self {
            repo,
            viewer_counter,
            chat_store,
            kafka_producer,
            rtmp_base_url,
            hls_cdn_url,
        }
    }

    /// Create new stream
    pub async fn create_stream(
        &mut self,
        creator_id: Uuid,
        request: CreateStreamRequest,
    ) -> Result<CreateStreamResponse> {
        // Check if creator already has an active stream
        if self.repo.has_active_stream(creator_id).await? {
            return Err(anyhow!("Creator already has an active stream"));
        }

        // Generate stream key (UUID for security)
        let stream_key = Uuid::new_v4().to_string();
        let rtmp_url = self.rtmp_base_url.clone();
        let stream_url = format!("{}/{}", rtmp_url, stream_key);

        // Create stream in database
        let stream = self
            .repo
            .create_stream(
                creator_id,
                request.title,
                request.description,
                request.category,
                stream_key.clone(),
                rtmp_url.clone(),
            )
            .await?;

        Ok(CreateStreamResponse {
            stream_id: stream.id,
            stream_key,
            rtmp_url,
            stream_url,
            hls_url: None, // Only available when live
            status: stream.status,
            created_at: stream.created_at.and_utc(),
        })
    }

    /// Start stream (called by RTMP webhook)
    pub async fn start_stream(&mut self, stream_key: &str) -> Result<()> {
        let stream = self
            .repo
            .get_stream_by_key(stream_key)
            .await?
            .ok_or_else(|| anyhow!("Stream not found"))?;

        // Generate HLS URL
        let hls_url = format!("{}/hls/{}/index.m3u8", self.hls_cdn_url, stream.id);

        // Update database
        self.repo.start_stream(stream.id, hls_url).await?;

        // Add to Redis active set
        self.viewer_counter.add_active_stream(stream.id).await?;

        // Publish Kafka event: stream.started
        let event = json!({
            "event_type": "stream.started",
            "stream_id": stream.id,
            "creator_id": stream.creator_id,
            "title": stream.title,
            "timestamp": chrono::Utc::now().to_rfc3339()
        });

        if let Err(e) = self
            .kafka_producer
            .send_json(&stream.id.to_string(), &event.to_string())
            .await
        {
            tracing::warn!("Failed to publish stream.started event: {}", e);
            // Non-blocking: continue even if Kafka fails
        }

        Ok(())
    }

    /// End stream (called by RTMP webhook)
    pub async fn end_stream(&mut self, stream_key: &str) -> Result<()> {
        let stream = self
            .repo
            .get_stream_by_key(stream_key)
            .await?
            .ok_or_else(|| anyhow!("Stream not found"))?;

        // Fetch final viewer count and calculate duration
        let final_viewer_count = self
            .viewer_counter
            .get_viewer_count(stream.id)
            .await
            .unwrap_or(0);

        let duration_seconds = if let Some(started_at) = stream.started_at {
            let now = chrono::Utc::now().naive_utc();
            (now - started_at).num_seconds() as i64
        } else {
            0
        };

        // Update database
        self.repo.end_stream(stream.id).await?;

        // Cleanup Redis
        self.viewer_counter.cleanup_stream(stream.id).await?;
        self.chat_store.clear_comments(stream.id).await?;

        // Publish Kafka event: stream.ended
        let event = json!({
            "event_type": "stream.ended",
            "stream_id": stream.id,
            "creator_id": stream.creator_id,
            "duration_seconds": duration_seconds,
            "viewer_count": final_viewer_count,
            "timestamp": chrono::Utc::now().to_rfc3339()
        });

        if let Err(e) = self
            .kafka_producer
            .send_json(&stream.id.to_string(), &event.to_string())
            .await
        {
            tracing::warn!("Failed to publish stream.ended event: {}", e);
            // Non-blocking: continue even if Kafka fails
        }

        Ok(())
    }

    /// Viewer joins stream
    pub async fn join_stream(
        &mut self,
        stream_id: Uuid,
        _user_id: Uuid,
    ) -> Result<JoinStreamResponse> {
        let stream = self
            .repo
            .get_stream_by_id(stream_id)
            .await?
            .ok_or_else(|| anyhow!("Stream not found"))?;

        if stream.status != StreamStatus::Live {
            return Err(anyhow!("Stream is not live"));
        }

        // Increment viewer count in Redis
        let current_viewers = self.viewer_counter.increment_viewers(stream_id).await?;

        // Generate chat WebSocket URL
        let chat_ws_url = format!("wss://api.nova.com/ws/streams/{}/chat", stream_id);

        Ok(JoinStreamResponse {
            hls_url: stream.hls_url.unwrap_or_default(),
            chat_ws_url,
            current_viewers,
        })
    }

    /// Viewer leaves stream
    pub async fn leave_stream(&mut self, stream_id: Uuid, _user_id: Uuid) -> Result<()> {
        self.viewer_counter.decrement_viewers(stream_id).await?;
        Ok(())
    }

    /// Fetch stream details including creator info and current viewer count
    pub async fn get_stream_details(&mut self, stream_id: Uuid) -> Result<StreamDetails> {
        let stream = self
            .repo
            .get_stream_by_id(stream_id)
            .await?
            .ok_or_else(|| anyhow!("Stream not found"))?;

        let creator = self
            .repo
            .get_creator_info(stream.creator_id)
            .await?
            .ok_or_else(|| anyhow!("Creator not found"))?;

        let current_viewers = if stream.status == StreamStatus::Live {
            self.viewer_counter
                .get_viewer_count(stream.id)
                .await
                .unwrap_or(stream.current_viewers)
        } else {
            stream.current_viewers
        };

        let peak_viewers = if stream.status == StreamStatus::Live {
            self.viewer_counter
                .get_peak_viewers(stream.id)
                .await
                .unwrap_or(stream.peak_viewers)
        } else {
            stream.peak_viewers
        };

        Ok(StreamDetails {
            stream_id: stream.id,
            creator,
            title: stream.title,
            description: stream.description,
            category: stream.category,
            status: stream.status,
            hls_url: stream.hls_url,
            thumbnail_url: stream.thumbnail_url,
            current_viewers,
            peak_viewers,
            started_at: stream.started_at.map(|dt| dt.and_utc()),
            ended_at: stream.ended_at.map(|dt| dt.and_utc()),
            created_at: stream.created_at.and_utc(),
            total_unique_viewers: stream.total_unique_viewers as i64,
            total_messages: stream.total_messages,
        })
    }

    /// List live streams with pagination and optional category filter
    pub async fn list_live_streams(
        &mut self,
        category: Option<StreamCategory>,
        page: i32,
        limit: i32,
    ) -> Result<StreamListResponse> {
        let page = page.max(1);
        let limit = limit.clamp(1, 100);
        let offset = ((page - 1) * limit) as i64;

        let rows = self
            .repo
            .list_live_streams(category.clone(), limit as i64, offset)
            .await?;
        let total = self.repo.count_live_streams(category).await?;

        if rows.is_empty() {
            return Ok(StreamListResponse {
                streams: Vec::new(),
                total,
                page,
                limit,
            });
        }

        let stream_ids: Vec<Uuid> = rows.iter().map(|row| row.id).collect();
        let counts = self
            .viewer_counter
            .get_viewer_counts_batch(&stream_ids)
            .await
            .unwrap_or_else(|_| vec![0; stream_ids.len()]);

        let mut summaries = Vec::with_capacity(rows.len());
        for (idx, row) in rows.into_iter().enumerate() {
            let creator =
                self.repo
                    .get_creator_info(row.creator_id)
                    .await?
                    .unwrap_or(CreatorInfo {
                        id: row.creator_id,
                        username: "unknown".to_string(),
                        avatar_url: None,
                    });

            let current_viewers = counts.get(idx).copied().unwrap_or(row.current_viewers);

            summaries.push(StreamSummary {
                stream_id: row.id,
                creator,
                title: row.title.clone(),
                thumbnail_url: row.thumbnail_url.clone(),
                current_viewers,
                category: row.category,
                started_at: row.started_at.map(|dt| dt.and_utc()),
            });
        }

        Ok(StreamListResponse {
            streams: summaries,
            total,
            page,
            limit,
        })
    }

    /// Append a live comment to Redis history
    pub async fn post_comment(&mut self, comment: StreamComment) -> Result<StreamComment> {
        let stream = self
            .repo
            .get_stream_by_id(comment.stream_id)
            .await?
            .ok_or_else(|| anyhow!("Stream not found"))?;

        if stream.status != StreamStatus::Live {
            return Err(anyhow!("Stream is not live"));
        }

        self.chat_store.append_comment(&comment).await?;
        Ok(comment)
    }

    /// Fetch recent live comments (newest first)
    pub async fn recent_comments(
        &mut self,
        stream_id: Uuid,
        limit: usize,
    ) -> Result<Vec<StreamComment>> {
        self.chat_store.get_recent_comments(stream_id, limit).await
    }
}
