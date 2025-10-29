//! Stream analytics (ClickHouse queries)
//!
//! Provides analytics for creators (viewer count timeline, demographics, etc.)

use super::models::{CountryStats, StreamAnalytics, ViewerTimelinePoint};
use super::repository::StreamRepository;
use anyhow::{anyhow, Result};
use chrono::Utc;
use uuid::Uuid;

/// Analytics service backed by PostgreSQL aggregates
pub struct StreamAnalyticsService {
    repo: StreamRepository,
}

impl StreamAnalyticsService {
    pub fn new(repo: StreamRepository) -> Self {
        Self { repo }
    }

    /// Fetch analytics snapshot for a stream (best-effort using OLTP data)
    pub async fn get_stream_analytics(&self, stream_id: Uuid) -> Result<StreamAnalytics> {
        let stream = self
            .repo
            .get_stream_by_id(stream_id)
            .await?
            .ok_or_else(|| anyhow!("Stream not found"))?;

        let started_at = stream.started_at.map(|dt| dt.and_utc());
        let ended_at = stream.ended_at.map(|dt| dt.and_utc());

        let avg_watch = match (started_at, ended_at, stream.total_unique_viewers) {
            (Some(start), Some(end), viewers) if viewers > 0 => {
                let total = end.signed_duration_since(start).num_seconds().max(0);
                (total as f64 / viewers as f64).round() as i32
            }
            (Some(start), None, viewers) if viewers > 0 => {
                let total = Utc::now().signed_duration_since(start).num_seconds().max(0);
                (total as f64 / viewers as f64).round() as i32
            }
            (Some(start), Some(end), _) => end.signed_duration_since(start).num_seconds() as i32,
            _ => 0,
        };

        let timeline = if let Some(start_at) = started_at {
            let mut points = Vec::new();
            points.push(ViewerTimelinePoint {
                timestamp: start_at,
                viewers: stream.current_viewers,
            });
            points.push(ViewerTimelinePoint {
                timestamp: Utc::now(),
                viewers: stream.current_viewers,
            });
            points
        } else {
            Vec::new()
        };

        Ok(StreamAnalytics {
            stream_id,
            total_unique_viewers: stream.total_unique_viewers as i64,
            peak_viewers: stream.peak_viewers,
            average_watch_duration_secs: avg_watch.max(0),
            total_messages: stream.total_messages,
            viewer_timeline: timeline,
            top_countries: Vec::<CountryStats>::new(),
        })
    }
}
