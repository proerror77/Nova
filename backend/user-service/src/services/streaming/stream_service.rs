//! Stream service (business logic layer)
//!
//! Orchestrates repository + Redis + Kafka to implement stream lifecycle

use super::models::*;
use super::redis_counter::ViewerCounter;
use super::repository::StreamRepository;
use anyhow::{anyhow, Result};
use uuid::Uuid;

/// Stream service (business logic)
pub struct StreamService {
    repo: StreamRepository,
    viewer_counter: ViewerCounter,
    // kafka_producer: KafkaProducer, // TODO: Add Kafka integration
    rtmp_base_url: String,
    hls_cdn_url: String,
}

impl StreamService {
    pub fn new(
        repo: StreamRepository,
        viewer_counter: ViewerCounter,
        rtmp_base_url: String,
        hls_cdn_url: String,
    ) -> Self {
        Self {
            repo,
            viewer_counter,
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
            created_at: stream.created_at,
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

        // TODO: Publish Kafka event: stream.started

        Ok(())
    }

    /// End stream (called by RTMP webhook)
    pub async fn end_stream(&mut self, stream_key: &str) -> Result<()> {
        let stream = self
            .repo
            .get_stream_by_key(stream_key)
            .await?
            .ok_or_else(|| anyhow!("Stream not found"))?;

        // Update database
        self.repo.end_stream(stream.id).await?;

        // Cleanup Redis
        self.viewer_counter.cleanup_stream(stream.id).await?;

        // TODO: Publish Kafka event: stream.ended

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

        // Generate chat WebSocket URL (TODO: integrate with WebSocket service)
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

    // TODO: Add more methods (get_stream_details, list_live_streams, etc.)
}
