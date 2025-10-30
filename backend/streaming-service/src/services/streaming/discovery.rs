//! Stream discovery and listing
//!
//! Handles live stream discovery, sorting, filtering

use super::models::{CreatorInfo, StreamSummary};
use super::redis_counter::ViewerCounter;
use super::repository::StreamRepository;
use anyhow::Result;

/// Service responsible for stream discovery (search, filtering)
pub struct StreamDiscoveryService {
    repo: StreamRepository,
    viewer_counter: ViewerCounter,
}

impl StreamDiscoveryService {
    pub fn new(repo: StreamRepository, viewer_counter: ViewerCounter) -> Self {
        Self {
            repo,
            viewer_counter,
        }
    }

    /// Search live streams by query (title/description)
    pub async fn search_streams(&mut self, query: &str, limit: i32) -> Result<Vec<StreamSummary>> {
        if query.trim().is_empty() {
            return Ok(Vec::new());
        }

        let limit = limit.clamp(1, 50) as i64;
        let rows = self.repo.search_streams(query, limit).await?;
        if rows.is_empty() {
            return Ok(Vec::new());
        }

        let stream_ids: Vec<uuid::Uuid> = rows.iter().map(|row| row.id).collect();
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

        Ok(summaries)
    }
}
