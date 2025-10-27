//! StreamActor - message-passing concurrency for stream operations
//!
//! The actor runs in its own task and processes commands sequentially.
//! This eliminates race conditions without needing locks.
//!
//! Pattern:
//! 1. Handler sends command through channel
//! 2. Actor receives command, processes it
//! 3. Actor sends response back through oneshot channel
//! 4. Handler awaits response

use super::chat_store::{StreamChatStore, StreamComment};
use super::commands::*;
use super::models::*;
use super::redis_counter::ViewerCounter;
use super::repository::StreamRepository;
use crate::services::kafka_producer::EventProducer;
use anyhow::{anyhow, Result};
use serde_json::json;
use std::sync::Arc;
use tokio::sync::mpsc;
use uuid::Uuid;

/// Stream actor - processes all stream commands
/// 
/// Runs in a dedicated task and handles all stream operations sequentially.
/// No locks needed - just message passing.
pub struct StreamActor {
    repo: StreamRepository,
    viewer_counter: ViewerCounter,
    chat_store: StreamChatStore,
    kafka_producer: Arc<EventProducer>,
    rtmp_base_url: String,
    hls_cdn_url: String,
    rx: mpsc::Receiver<StreamCommand>,
}

impl StreamActor {
    /// Create new StreamActor
    pub fn new(
        repo: StreamRepository,
        viewer_counter: ViewerCounter,
        chat_store: StreamChatStore,
        kafka_producer: Arc<EventProducer>,
        rtmp_base_url: String,
        hls_cdn_url: String,
    ) -> (Self, mpsc::Sender<StreamCommand>) {
        let (tx, rx) = mpsc::channel(100); // Buffer 100 commands
        
        (
            Self {
                repo,
                viewer_counter,
                chat_store,
                kafka_producer,
                rtmp_base_url,
                hls_cdn_url,
                rx,
            },
            tx,
        )
    }

    /// Run the actor - process commands until channel closes
    /// 
    /// This should be spawned in a dedicated tokio task:
    /// ```ignore
    /// let (actor, tx) = StreamActor::new(...);
    /// tokio::spawn(actor.run());
    /// ```
    pub async fn run(mut self) {
        tracing::info!("StreamActor started");
        
        while let Some(cmd) = self.rx.recv().await {
            match cmd {
                StreamCommand::CreateStream {
                    creator_id,
                    request,
                    responder,
                } => {
                    let result = self.handle_create_stream(creator_id, request).await;
                    let _ = responder.send(result);
                }

                StreamCommand::StartStream { stream_key, responder } => {
                    let result = self.handle_start_stream(&stream_key).await;
                    let _ = responder.send(result);
                }

                StreamCommand::StopStream { stream_id, responder } => {
                    let result = self.handle_stop_stream(stream_id).await;
                    let _ = responder.send(result);
                }

                StreamCommand::GetStreamDetails { stream_id, responder } => {
                    let result = self.handle_get_stream_details(stream_id).await;
                    let _ = responder.send(result);
                }

                StreamCommand::GetActiveStreams { responder } => {
                    let result = self.handle_get_active_streams().await;
                    let _ = responder.send(result);
                }

                StreamCommand::SearchStreams {
                    query,
                    category,
                    limit,
                    offset,
                    responder,
                } => {
                    let result = self
                        .handle_search_streams(&query, category, limit, offset)
                        .await;
                    let _ = responder.send(result);
                }

                StreamCommand::JoinStream {
                    stream_id,
                    user_id,
                    responder,
                } => {
                    let result = self.handle_join_stream(stream_id, user_id).await;
                    let _ = responder.send(result);
                }

                StreamCommand::LeaveStream {
                    stream_id,
                    user_id,
                    responder,
                } => {
                    let result = self.handle_leave_stream(stream_id, user_id).await;
                    let _ = responder.send(result);
                }

                StreamCommand::GetViewerCount { stream_id, responder } => {
                    let result = self.handle_get_viewer_count(stream_id).await;
                    let _ = responder.send(result);
                }

                StreamCommand::PostStreamComment {
                    stream_id,
                    user_id,
                    text,
                    responder,
                } => {
                    let result = self
                        .handle_post_stream_comment(stream_id, user_id, text)
                        .await;
                    let _ = responder.send(result);
                }

                StreamCommand::GetStreamComments {
                    stream_id,
                    limit,
                    offset,
                    responder,
                } => {
                    let result = self.handle_get_stream_comments(stream_id, limit, offset).await;
                    let _ = responder.send(result);
                }

                StreamCommand::GetStreamAnalytics { stream_id, responder } => {
                    let result = self.handle_get_stream_analytics(stream_id).await;
                    let _ = responder.send(result);
                }

                StreamCommand::UpdateStream {
                    stream_id,
                    request,
                    responder,
                } => {
                    let result = self.handle_update_stream(stream_id, request).await;
                    let _ = responder.send(result);
                }
            }
        }
        
        tracing::info!("StreamActor stopped");
    }

    // === Command Handlers ===

    async fn handle_create_stream(
        &self,
        creator_id: Uuid,
        request: CreateStreamRequest,
    ) -> Result<CreateStreamResponse> {
        if self.repo.has_active_stream(creator_id).await? {
            return Err(anyhow!("Creator already has an active stream"));
        }

        let stream_key = Uuid::new_v4().to_string();
        let rtmp_url = self.rtmp_base_url.clone();
        let stream_url = format!("{}/{}", rtmp_url, stream_key);

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

        // Emit event
        let _ = self
            .kafka_producer
            .send_event("stream.created", &json!({ "stream_id": stream.id }).to_string())
            .await;

        Ok(CreateStreamResponse {
            stream_id: stream.id,
            stream_key,
            rtmp_url,
            stream_url,
            hls_url: None,
            status: stream.status,
            created_at: stream.created_at.and_utc(),
        })
    }

    async fn handle_start_stream(&self, stream_key: &str) -> Result<()> {
        let stream = self
            .repo
            .get_stream_by_key(stream_key)
            .await?
            .ok_or_else(|| anyhow!("Stream not found"))?;

        let hls_url = format!("{}/hls/{}/index.m3u8", self.hls_cdn_url, stream.id);
        self.repo.start_stream(stream.id, hls_url).await?;
        self.viewer_counter.add_active_stream(stream.id).await?;

        let _ = self
            .kafka_producer
            .send_event("stream.started", &json!({ "stream_id": stream.id }).to_string())
            .await;

        Ok(())
    }

    async fn handle_stop_stream(&self, stream_id: Uuid) -> Result<()> {
        self.repo.stop_stream(stream_id).await?;
        self.viewer_counter.remove_active_stream(stream_id).await?;

        let _ = self
            .kafka_producer
            .send_event("stream.stopped", &json!({ "stream_id": stream_id }).to_string())
            .await;

        Ok(())
    }

    async fn handle_get_stream_details(&self, stream_id: Uuid) -> Result<StreamDetails> {
        let stream = self
            .repo
            .get_stream(stream_id)
            .await?
            .ok_or_else(|| anyhow!("Stream not found"))?;

        let viewer_count = self.viewer_counter.get_viewer_count(stream_id).await.unwrap_or(0);

        Ok(StreamDetails {
            id: stream.id,
            creator_id: stream.creator_id,
            title: stream.title,
            description: stream.description,
            category: stream.category,
            status: stream.status,
            viewer_count,
            stream_key: stream.stream_key,
            rtmp_url: stream.rtmp_url,
            hls_url: stream.hls_url,
            created_at: stream.created_at.and_utc(),
            started_at: stream.started_at.map(|t| t.and_utc()),
            ended_at: stream.ended_at.map(|t| t.and_utc()),
            thumbnail_url: stream.thumbnail_url,
        })
    }

    async fn handle_get_active_streams(&self) -> Result<Vec<StreamSummary>> {
        let streams = self.repo.get_active_streams(100).await?;

        let mut summaries = Vec::new();
        for stream in streams {
            let viewer_count = self
                .viewer_counter
                .get_viewer_count(stream.id)
                .await
                .unwrap_or(0);
            summaries.push(StreamSummary {
                id: stream.id,
                creator_id: stream.creator_id,
                title: stream.title,
                category: stream.category,
                status: stream.status,
                viewer_count,
                created_at: stream.created_at.and_utc(),
                thumbnail_url: stream.thumbnail_url,
            });
        }

        Ok(summaries)
    }

    async fn handle_search_streams(
        &self,
        query: &str,
        category: Option<String>,
        limit: i64,
        offset: i64,
    ) -> Result<SearchStreamsResponse> {
        let (streams, total) = self
            .repo
            .search_streams(query, category, limit, offset)
            .await?;

        let mut summaries = Vec::new();
        for stream in streams {
            let viewer_count = self
                .viewer_counter
                .get_viewer_count(stream.id)
                .await
                .unwrap_or(0);
            summaries.push(StreamSummary {
                id: stream.id,
                creator_id: stream.creator_id,
                title: stream.title,
                category: stream.category,
                status: stream.status,
                viewer_count,
                created_at: stream.created_at.and_utc(),
                thumbnail_url: stream.thumbnail_url,
            });
        }

        Ok(SearchStreamsResponse {
            streams: summaries,
            total,
        })
    }

    async fn handle_join_stream(&self, stream_id: Uuid, _user_id: Uuid) -> Result<()> {
        self.viewer_counter.increment(stream_id).await?;
        Ok(())
    }

    async fn handle_leave_stream(&self, stream_id: Uuid, _user_id: Uuid) -> Result<()> {
        self.viewer_counter.decrement(stream_id).await?;
        Ok(())
    }

    async fn handle_get_viewer_count(&self, stream_id: Uuid) -> Result<i64> {
        let count = self.viewer_counter.get_viewer_count(stream_id).await?;
        Ok(count)
    }

    async fn handle_post_stream_comment(
        &self,
        stream_id: Uuid,
        user_id: Uuid,
        text: String,
    ) -> Result<StreamComment> {
        let comment = self
            .chat_store
            .add_comment(stream_id, user_id, text)
            .await?;

        let _ = self
            .kafka_producer
            .send_event(
                "stream.comment.posted",
                &json!({
                    "stream_id": stream_id,
                    "comment_id": comment.id,
                    "user_id": user_id
                })
                .to_string(),
            )
            .await;

        Ok(comment)
    }

    async fn handle_get_stream_comments(
        &self,
        stream_id: Uuid,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<StreamComment>> {
        self.chat_store
            .get_comments(stream_id, limit, offset)
            .await
    }

    async fn handle_get_stream_analytics(&self, stream_id: Uuid) -> Result<StreamAnalytics> {
        // TODO: Implement analytics calculation
        Ok(StreamAnalytics {
            stream_id,
            total_viewers: 0,
            peak_viewers: 0,
            average_viewers: 0.0,
            total_comments: 0,
            duration_seconds: 0,
        })
    }

    async fn handle_update_stream(
        &self,
        stream_id: Uuid,
        request: UpdateStreamRequest,
    ) -> Result<()> {
        self.repo.update_stream(stream_id, request).await?;

        let _ = self
            .kafka_producer
            .send_event("stream.updated", &json!({ "stream_id": stream_id }).to_string())
            .await;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_actor_lifecycle() {
        // TODO: Add actor integration tests
    }
}
