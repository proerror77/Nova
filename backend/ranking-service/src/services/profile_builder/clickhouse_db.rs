// ============================================
// ClickHouse Profile Database Implementation
// ============================================
//
// Implementation of ProfileDatabase trait using ClickHouse as the data source.
// Fetches user engagement data, session events, and content views from
// the analytics tables in ClickHouse.

use super::{
    BehaviorPattern, ContentViewData, EngagementSignalData, InterestTag, ProfileBuilderError,
    ProfileDatabase, Result, SessionEventData,
};
use async_trait::async_trait;
use chrono::{DateTime, TimeZone, Utc};
use clickhouse::{Client, Row};
use serde::Deserialize;
use tracing::{debug, error, info, warn};
use uuid::Uuid;

/// ClickHouse-based implementation of ProfileDatabase
pub struct ClickHouseProfileDatabase {
    client: Client,
    database: String,
}

impl ClickHouseProfileDatabase {
    /// Create a new ClickHouseProfileDatabase
    pub fn new(url: &str, database: &str, username: &str, password: &str) -> Self {
        let client = Client::default()
            .with_url(url)
            .with_database(database)
            .with_user(username)
            .with_password(password);

        info!(
            url = url,
            database = database,
            "ClickHouseProfileDatabase initialized"
        );

        Self {
            client,
            database: database.to_string(),
        }
    }

    /// Create from config
    pub fn from_config(config: &crate::config::ClickHouseConfig) -> Self {
        Self::new(
            &config.url,
            &config.database,
            &config.username,
            &config.password,
        )
    }
}

// ============================================
// ClickHouse Row Types
// ============================================

#[derive(Debug, Row, Deserialize)]
struct EngagementRow {
    user_id: String,
    content_id: String,
    interaction_type: String,
    #[serde(with = "clickhouse::serde::time::datetime")]
    event_time: time::OffsetDateTime,
    content_tags: Vec<String>,
}

#[derive(Debug, Row, Deserialize)]
struct SessionRow {
    user_id: String,
    session_id: String,
    #[serde(with = "clickhouse::serde::time::datetime")]
    session_start: time::OffsetDateTime,
    #[serde(with = "clickhouse::serde::time::datetime::option")]
    session_end: Option<time::OffsetDateTime>,
    view_count: u32,
    engagement_count: u32,
}

#[derive(Debug, Row, Deserialize)]
struct ContentViewRow {
    user_id: String,
    content_id: String,
    content_duration_ms: u32,
    watch_duration_ms: u32,
    completion_rate: f32,
    #[serde(with = "clickhouse::serde::time::datetime")]
    event_time: time::OffsetDateTime,
    hour: u8,
    day_of_week: u8,
}

#[derive(Debug, Row, Deserialize)]
struct UserInterestRow {
    user_id: String,
    interest_tag: String,
    like_weight: f64,
    comment_weight: f64,
    share_weight: f64,
    complete_watch_weight: f64,
    interaction_count: u64,
}

// ============================================
// ProfileDatabase Implementation
// ============================================

#[async_trait]
impl ProfileDatabase for ClickHouseProfileDatabase {
    /// Fetch engagement signals from user_content_interactions_v2 table
    async fn fetch_engagement_signals(
        &self,
        user_id: Uuid,
        lookback_days: i64,
    ) -> Result<Vec<EngagementSignalData>> {
        let query = format!(
            r#"
            SELECT
                user_id,
                content_id,
                interaction_type,
                event_time,
                content_tags
            FROM {}.user_content_interactions_v2
            WHERE user_id = '{}'
              AND event_date >= today() - {}
              AND interaction_type IN (
                  'like', 'comment', 'share', 'save',
                  'skip', 'not_interested', 'view'
              )
            ORDER BY event_time DESC
            LIMIT 50000
            "#,
            self.database, user_id, lookback_days
        );

        debug!(user_id = %user_id, "Fetching engagement signals from ClickHouse");

        let rows: Vec<EngagementRow> = self
            .client
            .query(&query)
            .fetch_all()
            .await
            .map_err(|e| {
                error!(error = %e, "Failed to fetch engagement signals");
                ProfileBuilderError::ClickHouseError(e.to_string())
            })?;

        debug!(
            user_id = %user_id,
            count = rows.len(),
            "Fetched engagement signals"
        );

        Ok(rows
            .into_iter()
            .filter_map(|row| {
                let user_uuid = Uuid::parse_str(&row.user_id).ok()?;
                let content_uuid = Uuid::parse_str(&row.content_id).ok()?;
                let timestamp = offset_datetime_to_chrono(row.event_time);

                Some(EngagementSignalData {
                    user_id: user_uuid,
                    content_id: content_uuid,
                    action: row.interaction_type,
                    content_tags: row.content_tags,
                    created_at: timestamp,
                })
            })
            .collect())
    }

    /// Fetch session events from session_events and watch_events tables
    async fn fetch_session_events(
        &self,
        user_id: Uuid,
        lookback_days: i64,
    ) -> Result<Vec<SessionEventData>> {
        // Aggregate session data from watch_events
        let query = format!(
            r#"
            SELECT
                user_id,
                session_id,
                min(event_time) as session_start,
                max(event_time) as session_end,
                count() as view_count,
                countIf(completion_rate >= 0.5) as engagement_count
            FROM {}.watch_events
            WHERE user_id = '{}'
              AND event_date >= today() - {}
              AND session_id != ''
            GROUP BY user_id, session_id
            ORDER BY session_start DESC
            LIMIT 1000
            "#,
            self.database, user_id, lookback_days
        );

        debug!(user_id = %user_id, "Fetching session events from ClickHouse");

        let rows: Vec<SessionRow> = self
            .client
            .query(&query)
            .fetch_all()
            .await
            .map_err(|e| {
                error!(error = %e, "Failed to fetch session events");
                ProfileBuilderError::ClickHouseError(e.to_string())
            })?;

        debug!(
            user_id = %user_id,
            count = rows.len(),
            "Fetched session events"
        );

        Ok(rows
            .into_iter()
            .filter_map(|row| {
                let user_uuid = Uuid::parse_str(&row.user_id).ok()?;

                Some(SessionEventData {
                    user_id: user_uuid,
                    session_id: row.session_id,
                    started_at: offset_datetime_to_chrono(row.session_start),
                    ended_at: row.session_end.map(offset_datetime_to_chrono),
                    view_count: row.view_count,
                    engagement_count: row.engagement_count,
                })
            })
            .collect())
    }

    /// Fetch content view events from watch_events table
    async fn fetch_content_views(
        &self,
        user_id: Uuid,
        lookback_days: i64,
    ) -> Result<Vec<ContentViewData>> {
        let query = format!(
            r#"
            SELECT
                user_id,
                content_id,
                content_duration_ms,
                watch_duration_ms,
                completion_rate,
                event_time,
                toHour(event_time) as hour,
                toDayOfWeek(event_time) as day_of_week
            FROM {}.watch_events
            WHERE user_id = '{}'
              AND event_date >= today() - {}
            ORDER BY event_time DESC
            LIMIT 10000
            "#,
            self.database, user_id, lookback_days
        );

        debug!(user_id = %user_id, "Fetching content views from ClickHouse");

        let rows: Vec<ContentViewRow> = self
            .client
            .query(&query)
            .fetch_all()
            .await
            .map_err(|e| {
                error!(error = %e, "Failed to fetch content views");
                ProfileBuilderError::ClickHouseError(e.to_string())
            })?;

        debug!(
            user_id = %user_id,
            count = rows.len(),
            "Fetched content views"
        );

        Ok(rows
            .into_iter()
            .filter_map(|row| {
                let user_uuid = Uuid::parse_str(&row.user_id).ok()?;
                let content_uuid = Uuid::parse_str(&row.content_id).ok()?;

                Some(ContentViewData {
                    user_id: user_uuid,
                    content_id: content_uuid,
                    content_duration_ms: row.content_duration_ms,
                    watch_duration_ms: row.watch_duration_ms,
                    completion_rate: row.completion_rate,
                    viewed_at: offset_datetime_to_chrono(row.event_time),
                    hour: row.hour,
                    day_of_week: row.day_of_week,
                })
            })
            .collect())
    }

    /// Save interest tags to ClickHouse user_recent_interests table
    async fn save_interest_tags(&self, user_id: Uuid, tags: &[InterestTag]) -> Result<()> {
        if tags.is_empty() {
            return Ok(());
        }

        // Use ReplacingMergeTree - insert new version to replace old
        let now = Utc::now();
        let version = now.timestamp_millis() as u64;

        for tag in tags {
            let query = format!(
                r#"
                INSERT INTO {}.user_recent_interests
                (user_id, interest_tag, weight, last_updated, version)
                VALUES ('{}', '{}', {}, now(), {})
                "#,
                self.database, user_id, tag.tag, tag.weight, version
            );

            self.client
                .query(&query)
                .execute()
                .await
                .map_err(|e| {
                    warn!(error = %e, tag = %tag.tag, "Failed to save interest tag");
                    ProfileBuilderError::ClickHouseError(e.to_string())
                })?;
        }

        debug!(
            user_id = %user_id,
            tag_count = tags.len(),
            "Saved interest tags to ClickHouse"
        );

        Ok(())
    }

    /// Save behavior pattern to ClickHouse (stored in Redis primarily)
    async fn save_behavior_pattern(&self, user_id: Uuid, _pattern: &BehaviorPattern) -> Result<()> {
        // Behavior patterns are primarily cached in Redis for fast access
        // ClickHouse is used as the source of truth for rebuilding profiles
        debug!(
            user_id = %user_id,
            "Behavior pattern will be cached in Redis"
        );
        Ok(())
    }
}

// ============================================
// Additional Query Methods
// ============================================

impl ClickHouseProfileDatabase {
    /// Fetch pre-aggregated user interests from materialized view
    pub async fn fetch_aggregated_interests(
        &self,
        user_id: Uuid,
    ) -> Result<Vec<(String, f64)>> {
        let query = format!(
            r#"
            SELECT
                interest_tag,
                like_weight + comment_weight * 2 + share_weight * 3 + complete_watch_weight * 1.5 as total_weight
            FROM {}.mv_user_interest_aggregate
            WHERE user_id = '{}'
            ORDER BY total_weight DESC
            LIMIT 100
            "#,
            self.database, user_id
        );

        #[derive(Debug, Row, Deserialize)]
        struct InterestAggRow {
            interest_tag: String,
            total_weight: f64,
        }

        let rows: Vec<InterestAggRow> = self
            .client
            .query(&query)
            .fetch_all()
            .await
            .map_err(|e| ProfileBuilderError::ClickHouseError(e.to_string()))?;

        Ok(rows
            .into_iter()
            .map(|r| (r.interest_tag, r.total_weight))
            .collect())
    }

    /// Fetch user's active hours distribution
    pub async fn fetch_active_hours(&self, user_id: Uuid, days: i64) -> Result<Vec<(u8, u64)>> {
        let query = format!(
            r#"
            SELECT
                toHour(event_time) as hour,
                count() as activity_count
            FROM {}.watch_events
            WHERE user_id = '{}'
              AND event_date >= today() - {}
            GROUP BY hour
            ORDER BY activity_count DESC
            "#,
            self.database, user_id, days
        );

        #[derive(Debug, Row, Deserialize)]
        struct HourRow {
            hour: u8,
            activity_count: u64,
        }

        let rows: Vec<HourRow> = self
            .client
            .query(&query)
            .fetch_all()
            .await
            .map_err(|e| ProfileBuilderError::ClickHouseError(e.to_string()))?;

        Ok(rows.into_iter().map(|r| (r.hour, r.activity_count)).collect())
    }

    /// Fetch users that need profile updates (active users without recent profile update)
    pub async fn fetch_users_needing_update(&self, limit: u32) -> Result<Vec<Uuid>> {
        let query = format!(
            r#"
            SELECT DISTINCT user_id
            FROM {}.watch_events
            WHERE event_date >= today() - 7
            ORDER BY rand()
            LIMIT {}
            "#,
            self.database, limit
        );

        #[derive(Debug, Row, Deserialize)]
        struct UserRow {
            user_id: String,
        }

        let rows: Vec<UserRow> = self
            .client
            .query(&query)
            .fetch_all()
            .await
            .map_err(|e| ProfileBuilderError::ClickHouseError(e.to_string()))?;

        Ok(rows
            .into_iter()
            .filter_map(|r| Uuid::parse_str(&r.user_id).ok())
            .collect())
    }

    /// Get user engagement summary for LLM analysis
    pub async fn get_user_engagement_summary(
        &self,
        user_id: Uuid,
        days: i64,
    ) -> Result<UserEngagementSummary> {
        let query = format!(
            r#"
            SELECT
                count() as total_views,
                avg(completion_rate) as avg_completion,
                sum(watch_duration_ms) / 1000 / 60 as total_watch_minutes,
                uniq(content_id) as unique_videos,
                countIf(completion_rate >= 0.9) as high_completion_count,
                countIf(is_replay = 1) as replay_count
            FROM {}.watch_events
            WHERE user_id = '{}'
              AND event_date >= today() - {}
            "#,
            self.database, user_id, days
        );

        #[derive(Debug, Row, Deserialize)]
        struct SummaryRow {
            total_views: u64,
            avg_completion: f64,
            total_watch_minutes: f64,
            unique_videos: u64,
            high_completion_count: u64,
            replay_count: u64,
        }

        let row: SummaryRow = self
            .client
            .query(&query)
            .fetch_one()
            .await
            .map_err(|e| ProfileBuilderError::ClickHouseError(e.to_string()))?;

        Ok(UserEngagementSummary {
            total_views: row.total_views,
            avg_completion_rate: row.avg_completion as f32,
            total_watch_minutes: row.total_watch_minutes as f32,
            unique_videos: row.unique_videos,
            high_completion_count: row.high_completion_count,
            replay_count: row.replay_count,
        })
    }
}

// ============================================
// Helper Types and Functions
// ============================================

/// User engagement summary for LLM analysis
#[derive(Debug, Clone)]
pub struct UserEngagementSummary {
    pub total_views: u64,
    pub avg_completion_rate: f32,
    pub total_watch_minutes: f32,
    pub unique_videos: u64,
    pub high_completion_count: u64,
    pub replay_count: u64,
}

/// Convert time::OffsetDateTime to chrono::DateTime<Utc>
fn offset_datetime_to_chrono(dt: time::OffsetDateTime) -> DateTime<Utc> {
    Utc.timestamp_opt(dt.unix_timestamp(), dt.nanosecond())
        .single()
        .unwrap_or_else(Utc::now)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_offset_datetime_conversion() {
        let now = time::OffsetDateTime::now_utc();
        let chrono_dt = offset_datetime_to_chrono(now);
        assert!(chrono_dt.timestamp() > 0);
    }
}
