use chrono::{DateTime, Utc};
use clickhouse::{Client, Row};
use serde::{Deserialize, Serialize};
use std::time::Duration;
use thiserror::Error;
use uuid::Uuid;

#[derive(Debug, Error)]
pub enum ClickHouseError {
    #[error("ClickHouse client error: {0}")]
    Client(#[from] clickhouse::error::Error),
    #[error("serialization error: {0}")]
    Serde(#[from] serde_json::Error),
    #[error("invalid time window: {0}")]
    InvalidTimeWindow(String),
}

#[derive(Clone)]
pub struct ClickHouseClient {
    client: Client,
}

#[derive(Debug, Clone, Serialize, Deserialize, Row)]
pub struct SearchEvent {
    pub timestamp: DateTime<Utc>,
    pub user_id: Uuid,
    pub query: String,
    pub results_count: u32,
    pub clicked_type: Option<String>,
    pub clicked_id: Option<Uuid>,
    pub session_id: Uuid,
}

#[derive(Debug, Deserialize, Row)]
pub struct TrendingSearch {
    pub query: String,
    pub search_count: u32,
    pub trend_score: f32,
}

#[derive(Debug, Deserialize, Row)]
pub struct SearchAnalytics {
    pub total_searches: u32,
    pub avg_results: f64,
    pub click_through_rate: f64,
}

impl ClickHouseClient {
    pub async fn new(url: &str) -> Result<Self, ClickHouseError> {
        let client = Client::default()
            .with_url(url)
            .with_compression(clickhouse::Compression::Lz4);

        let instance = Self { client };
        instance.ensure_schema().await?;
        Ok(instance)
    }

    async fn ensure_schema(&self) -> Result<(), ClickHouseError> {
        // Create search_analytics table with MergeTree engine optimized for time-series queries
        self.client
            .query(
                r#"
                CREATE TABLE IF NOT EXISTS search_analytics (
                    timestamp DateTime64(3),
                    user_id String,
                    query String,
                    results_count UInt32,
                    clicked_type Nullable(String),
                    clicked_id Nullable(String),
                    session_id String,
                    INDEX query_idx query TYPE tokenbf_v1(32768, 3, 0) GRANULARITY 4
                ) ENGINE = MergeTree()
                PARTITION BY toYYYYMM(timestamp)
                ORDER BY (timestamp, user_id)
                TTL timestamp + INTERVAL 90 DAY
                SETTINGS index_granularity = 8192
                "#,
            )
            .execute()
            .await?;

        // Create materialized view for trending searches (hourly aggregation)
        self.client
            .query(
                r#"
                CREATE MATERIALIZED VIEW IF NOT EXISTS trending_searches_1h
                ENGINE = SummingMergeTree()
                PARTITION BY toYYYYMMDD(hour_bucket)
                ORDER BY (hour_bucket, query)
                TTL hour_bucket + INTERVAL 7 DAY
                AS SELECT
                    toStartOfHour(timestamp) AS hour_bucket,
                    query,
                    count() AS search_count,
                    1.0 * search_count / (toUnixTimestamp(now()) - toUnixTimestamp(hour_bucket) + 1) AS trend_score
                FROM search_analytics
                WHERE timestamp >= now() - INTERVAL 24 HOUR
                GROUP BY hour_bucket, query
                "#,
            )
            .execute()
            .await?;

        // Create materialized view for daily trending searches
        self.client
            .query(
                r#"
                CREATE MATERIALIZED VIEW IF NOT EXISTS trending_searches_1d
                ENGINE = SummingMergeTree()
                PARTITION BY toYYYYMMDD(day_bucket)
                ORDER BY (day_bucket, query)
                TTL day_bucket + INTERVAL 30 DAY
                AS SELECT
                    toDate(timestamp) AS day_bucket,
                    query,
                    count() AS search_count,
                    1.0 * search_count / (toUnixTimestamp(now()) - toUnixTimestamp(day_bucket) + 1) AS trend_score
                FROM search_analytics
                WHERE timestamp >= now() - INTERVAL 7 DAY
                GROUP BY day_bucket, query
                "#,
            )
            .execute()
            .await?;

        Ok(())
    }

    pub async fn record_search_event(&self, event: SearchEvent) -> Result<(), ClickHouseError> {
        let mut insert = self.client.insert("search_analytics")?;
        insert.write(&event).await?;
        insert.end().await?;
        Ok(())
    }

    pub async fn record_search_events_batch(
        &self,
        events: Vec<SearchEvent>,
    ) -> Result<(), ClickHouseError> {
        if events.is_empty() {
            return Ok(());
        }

        let mut insert = self.client.insert("search_analytics")?;
        for event in events {
            insert.write(&event).await?;
        }
        insert.end().await?;
        Ok(())
    }

    pub async fn get_trending_searches(
        &self,
        limit: u32,
        time_window: &str,
    ) -> Result<Vec<TrendingSearch>, ClickHouseError> {
        let (view_name, interval) = match time_window {
            "1h" => ("trending_searches_1h", "INTERVAL 1 HOUR"),
            "24h" => ("trending_searches_1h", "INTERVAL 24 HOUR"),
            "7d" => ("trending_searches_1d", "INTERVAL 7 DAY"),
            _ => {
                return Err(ClickHouseError::InvalidTimeWindow(format!(
                    "Invalid time window: {}. Must be one of: 1h, 24h, 7d",
                    time_window
                )))
            }
        };

        let query = format!(
            r#"
            SELECT
                query,
                sum(search_count) AS search_count,
                avg(trend_score) AS trend_score
            FROM {}
            WHERE hour_bucket >= now() - {}
            GROUP BY query
            ORDER BY search_count DESC, trend_score DESC
            LIMIT ?
            "#,
            view_name, interval
        );

        let results = self
            .client
            .query(&query)
            .bind(limit)
            .fetch_all::<TrendingSearch>()
            .await?;

        Ok(results)
    }

    pub async fn get_search_analytics(
        &self,
        query: &str,
        time_window_hours: u32,
    ) -> Result<SearchAnalytics, ClickHouseError> {
        let sql = r#"
            SELECT
                count(*) AS total_searches,
                avg(results_count) AS avg_results,
                countIf(clicked_id IS NOT NULL) * 100.0 / count(*) AS click_through_rate
            FROM search_analytics
            WHERE query = ?
              AND timestamp >= now() - INTERVAL ? HOUR
        "#;

        let result = self
            .client
            .query(sql)
            .bind(query)
            .bind(time_window_hours)
            .fetch_one::<SearchAnalytics>()
            .await?;

        Ok(result)
    }

    pub async fn get_popular_filters(
        &self,
        query: &str,
        limit: u32,
    ) -> Result<Vec<String>, ClickHouseError> {
        // For now, return empty as we don't track filters in events yet
        // This can be extended when filter tracking is added
        Ok(vec![])
    }

    pub async fn health_check(&self) -> Result<(), ClickHouseError> {
        self.client.query("SELECT 1").execute().await?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    #[ignore] // Requires running ClickHouse instance
    async fn test_clickhouse_connection() {
        let client = ClickHouseClient::new("http://localhost:8123")
            .await
            .expect("Failed to connect to ClickHouse");

        client.health_check().await.expect("Health check failed");
    }

    #[tokio::test]
    #[ignore]
    async fn test_record_search_event() {
        let client = ClickHouseClient::new("http://localhost:8123")
            .await
            .unwrap();

        let event = SearchEvent {
            timestamp: Utc::now(),
            user_id: Uuid::new_v4(),
            query: "test query".to_string(),
            results_count: 42,
            clicked_type: Some("post".to_string()),
            clicked_id: Some(Uuid::new_v4()),
            session_id: Uuid::new_v4(),
        };

        client
            .record_search_event(event)
            .await
            .expect("Failed to record event");
    }
}
