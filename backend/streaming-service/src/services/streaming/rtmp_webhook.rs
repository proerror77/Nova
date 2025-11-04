//! RTMP webhook handlers
//!
//! Nginx-RTMP calls these endpoints when streams start/stop

use super::models::StreamStatus;
use super::redis_counter::ViewerCounter;
use super::repository::StreamRepository;
use anyhow::{Context, Result};
use tracing::{info, warn};

/// RTMP webhook handler invoked by Nginx-RTMP events
pub struct RtmpWebhookHandler {
    repo: StreamRepository,
    viewer_counter: ViewerCounter,
    hls_cdn_url: String,
}

impl RtmpWebhookHandler {
    pub fn new(repo: StreamRepository, viewer_counter: ViewerCounter, hls_cdn_url: String) -> Self {
        Self {
            repo,
            viewer_counter,
            hls_cdn_url,
        }
    }

    /// Authenticate RTMP publish request based on stream key
    pub async fn authenticate_stream(&mut self, stream_key: &str, client_ip: &str) -> Result<bool> {
        let stream_opt = self.repo.get_stream_by_key(stream_key).await?;
        let Some(stream) = stream_opt else {
            warn!(%stream_key, %client_ip, "RTMP auth failed: stream key not found");
            return Ok(false);
        };

        if stream.status == StreamStatus::Live {
            info!(%stream_key, %client_ip, stream_id=%stream.id, "Stream already live - allowing reconnect");
            return Ok(true);
        }

        let hls_url = format!("{}/hls/{}/index.m3u8", self.hls_cdn_url, stream.id);
        self.repo
            .start_stream(stream.id, hls_url)
            .await
            .context("failed to mark stream live")?;
        self.viewer_counter
            .add_active_stream(stream.id)
            .await
            .context("failed to register active stream in redis")?;

        info!(%stream_key, %client_ip, stream_id=%stream.id, "RTMP authentication succeeded");
        Ok(true)
    }

    /// Handle RTMP disconnect event
    pub async fn on_stream_done(&mut self, stream_key: &str) -> Result<()> {
        if let Some(stream) = self.repo.get_stream_by_key(stream_key).await? {
            self.repo
                .end_stream(stream.id)
                .await
                .context("failed to mark stream ended")?;
            self.viewer_counter
                .cleanup_stream(stream.id)
                .await
                .context("failed to cleanup redis state")?;
            info!(%stream_key, stream_id=%stream.id, "Stream ended via RTMP webhook");
        } else {
            warn!(%stream_key, "RTMP done webhook received for unknown stream key");
        }
        Ok(())
    }
}
