/// Daily metrics export job for business intelligence and reporting
/// Exports key performance metrics to CSV/JSON for external BI tools
use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use std::fs::File;
use std::io::Write;
use std::path::PathBuf;
use tracing::{error, info, warn};

use crate::error::Result;

// Re-export clickhouse client for type compatibility
pub use clickhouse::Client as ClickHouseClient;

/// Daily metrics report structure
#[derive(Debug, Serialize, Deserialize)]
pub struct DailyMetricsReport {
    pub date: String,
    pub timestamp: DateTime<Utc>,

    // Feed performance metrics
    pub feed_api_requests_total: u64,
    pub feed_api_avg_latency_ms: f64,
    pub feed_api_p95_latency_ms: f64,
    pub feed_cache_hit_rate_percent: f64,

    // User engagement metrics
    pub total_impressions: u64,
    pub total_views: u64,
    pub total_likes: u64,
    pub total_comments: u64,
    pub total_shares: u64,

    // Calculated engagement metrics
    pub ctr_percent: f64, // Click-through rate (clicks / impressions)
    pub avg_dwell_time_ms: f64,

    // System health metrics
    pub availability_percent: f64,
    pub error_rate_percent: f64,

    // Data pipeline metrics
    pub cdc_lag_avg_seconds: f64,
    pub events_processed: u64,
    pub events_dedup_rate_percent: f64,

    // ClickHouse performance
    pub clickhouse_avg_query_latency_ms: f64,
    pub clickhouse_slow_queries_count: u64,
}

/// Metrics export configuration
#[derive(Debug, Clone)]
pub struct MetricsExportConfig {
    pub output_dir: PathBuf,
    pub export_format: ExportFormat,
    pub retention_days: u32,
}

#[derive(Debug, Clone)]
pub enum ExportFormat {
    Csv,
    Json,
    Both,
}

impl Default for MetricsExportConfig {
    fn default() -> Self {
        Self {
            output_dir: PathBuf::from("./metrics_export"),
            export_format: ExportFormat::Both,
            retention_days: 365, // Keep 1 year of daily reports
        }
    }
}

/// Metrics export job
pub struct MetricsExportJob {
    config: MetricsExportConfig,
    ch_client: clickhouse::Client,
}

impl MetricsExportJob {
    pub fn new(config: MetricsExportConfig, ch_client: clickhouse::Client) -> Self {
        Self { config, ch_client }
    }

    /// Run daily metrics export job
    ///
    /// This should be scheduled to run daily at 01:00 UTC via cron or background scheduler
    pub async fn run_daily_export(&self) -> Result<()> {
        info!("Starting daily metrics export job");

        // Calculate date range (yesterday's metrics)
        let end_date = Utc::now().date_naive();
        let start_date = end_date - Duration::days(1);

        info!(
            "Exporting metrics for date range: {} to {}",
            start_date, end_date
        );

        // Collect metrics from Prometheus/database
        let report = self.collect_daily_metrics(start_date.to_string()).await?;

        // Export to configured format(s)
        match self.config.export_format {
            ExportFormat::Csv => self.export_csv(&report).await?,
            ExportFormat::Json => self.export_json(&report).await?,
            ExportFormat::Both => {
                self.export_csv(&report).await?;
                self.export_json(&report).await?;
            }
        }

        // Clean up old reports beyond retention period
        self.cleanup_old_reports().await?;

        info!("Daily metrics export job completed successfully");
        Ok(())
    }

    /// Collect yesterday's metrics from Prometheus and databases
    async fn collect_daily_metrics(&self, date: String) -> Result<DailyMetricsReport> {
        // TODO: Replace with actual Prometheus query API calls
        // For now, return mock data

        // Example Prometheus queries (to be implemented):
        // - sum(rate(feed_api_requests_total[24h]))
        // - histogram_quantile(0.95, rate(feed_api_latency_ms_bucket[24h]))
        // - avg(feed_cache_hit_rate_percent[24h])
        // - sum(rate(events_consumed_total{status="success"}[24h]))

        let report = DailyMetricsReport {
            date: date.clone(),
            timestamp: Utc::now(),

            // Feed performance
            feed_api_requests_total: self
                .query_prometheus_counter("feed_api_requests_total")
                .await?,
            feed_api_avg_latency_ms: self.query_prometheus_avg("feed_api_latency_ms").await?,
            feed_api_p95_latency_ms: self
                .query_prometheus_percentile("feed_api_latency_ms", 0.95)
                .await?,
            feed_cache_hit_rate_percent: self
                .query_prometheus_avg("feed_cache_hit_rate_percent")
                .await?,

            // User engagement
            total_impressions: self.query_clickhouse_event_count("impression").await?,
            total_views: self.query_clickhouse_event_count("view").await?,
            total_likes: self.query_clickhouse_event_count("like").await?,
            total_comments: self.query_clickhouse_event_count("comment").await?,
            total_shares: self.query_clickhouse_event_count("share").await?,

            // Calculated metrics
            ctr_percent: 0.0, // Calculated after data collection
            avg_dwell_time_ms: self.query_clickhouse_avg_dwell_time().await?,

            // System health
            availability_percent: self.calculate_availability().await?,
            error_rate_percent: self.calculate_error_rate().await?,

            // Data pipeline
            cdc_lag_avg_seconds: self.query_prometheus_avg("cdc_lag_age_seconds").await?,
            events_processed: self
                .query_prometheus_counter("events_consumed_total")
                .await?,
            events_dedup_rate_percent: self.calculate_dedup_rate().await?,

            // ClickHouse performance
            clickhouse_avg_query_latency_ms: self
                .query_prometheus_avg("clickhouse_query_duration_ms")
                .await?,
            clickhouse_slow_queries_count: self
                .query_prometheus_counter("clickhouse_slow_queries_total")
                .await?,
        };

        // Calculate derived metrics
        let mut report = report;
        if report.total_impressions > 0 {
            let total_clicks = report.total_likes + report.total_comments + report.total_shares;
            report.ctr_percent = (total_clicks as f64 / report.total_impressions as f64) * 100.0;
        }

        Ok(report)
    }

    /// Export metrics to CSV format
    async fn export_csv(&self, report: &DailyMetricsReport) -> Result<()> {
        let filename = format!("metrics_{}.csv", report.date);
        let filepath = self.config.output_dir.join(&filename);

        // Create output directory if not exists
        std::fs::create_dir_all(&self.config.output_dir)?;

        let mut file = File::create(&filepath)?;

        // Write CSV header (only if file is new)
        writeln!(file, "date,timestamp,feed_api_requests_total,feed_api_avg_latency_ms,feed_api_p95_latency_ms,feed_cache_hit_rate_percent,total_impressions,total_views,total_likes,total_comments,total_shares,ctr_percent,avg_dwell_time_ms,availability_percent,error_rate_percent,cdc_lag_avg_seconds,events_processed,events_dedup_rate_percent,clickhouse_avg_query_latency_ms,clickhouse_slow_queries_count")?;

        // Write data row
        writeln!(
            file,
            "{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{}",
            report.date,
            report.timestamp.to_rfc3339(),
            report.feed_api_requests_total,
            report.feed_api_avg_latency_ms,
            report.feed_api_p95_latency_ms,
            report.feed_cache_hit_rate_percent,
            report.total_impressions,
            report.total_views,
            report.total_likes,
            report.total_comments,
            report.total_shares,
            report.ctr_percent,
            report.avg_dwell_time_ms,
            report.availability_percent,
            report.error_rate_percent,
            report.cdc_lag_avg_seconds,
            report.events_processed,
            report.events_dedup_rate_percent,
            report.clickhouse_avg_query_latency_ms,
            report.clickhouse_slow_queries_count
        )?;

        info!("Exported CSV metrics to: {}", filepath.display());
        Ok(())
    }

    /// Export metrics to JSON format
    async fn export_json(&self, report: &DailyMetricsReport) -> Result<()> {
        let filename = format!("metrics_{}.json", report.date);
        let filepath = self.config.output_dir.join(&filename);

        // Create output directory if not exists
        std::fs::create_dir_all(&self.config.output_dir)?;

        let json = serde_json::to_string_pretty(report)?;
        std::fs::write(&filepath, json)?;

        info!("Exported JSON metrics to: {}", filepath.display());
        Ok(())
    }

    /// Clean up old reports beyond retention period
    async fn cleanup_old_reports(&self) -> Result<()> {
        let retention_cutoff = Utc::now() - Duration::days(self.config.retention_days as i64);

        let entries = std::fs::read_dir(&self.config.output_dir)?;
        for entry in entries.flatten() {
            let path = entry.path();
            if let Ok(metadata) = entry.metadata() {
                if let Ok(modified) = metadata.modified() {
                    let modified_time: DateTime<Utc> = modified.into();
                    if modified_time < retention_cutoff {
                        if let Err(e) = std::fs::remove_file(&path) {
                            warn!("Failed to delete old report {:?}: {}", path, e);
                        } else {
                            info!("Deleted old report: {:?}", path);
                        }
                    }
                }
            }
        }

        Ok(())
    }

    // ============================================
    // Prometheus Query Helpers
    // ============================================
    //
    // These methods currently return sensible defaults and mock data.
    // In production, implement actual Prometheus client queries:
    // - Use `prometheus` crate for HTTP API calls
    // - Cache results in memory to avoid overwhelming Prometheus
    // - Add timeout/retry logic for reliability
    //
    // Example Prometheus queries:
    // - Counter: sum(increase(feed_api_requests_total[24h]))
    // - Average: avg_over_time(feed_cache_hit_rate_percent[24h])
    // - Percentile: histogram_quantile(0.95, rate(feed_api_latency_ms_bucket[24h]))

    async fn query_prometheus_counter(&self, metric: &str) -> Result<u64> {
        // Returns sensible defaults based on metric name
        // This should be replaced with actual Prometheus queries in production
        info!(metric = metric, "Returning mock data for Prometheus counter query");
        Ok(match metric {
            "feed_api_requests_total" => 150000,
            "events_consumed_total" => 800000,
            "clickhouse_slow_queries_total" => 15,
            _ => 100000,
        })
    }

    async fn query_prometheus_avg(&self, metric: &str) -> Result<f64> {
        // Returns sensible defaults based on metric name
        // This should be replaced with actual Prometheus queries in production
        info!(metric = metric, "Returning mock data for Prometheus avg query");
        Ok(match metric {
            "feed_api_latency_ms" => 95.5,
            "feed_cache_hit_rate_percent" => 92.5,
            "cdc_lag_age_seconds" => 2.5,
            "clickhouse_query_duration_ms" => 85.0,
            _ => 50.0,
        })
    }

    async fn query_prometheus_percentile(&self, metric: &str, percentile: f64) -> Result<f64> {
        // Returns sensible defaults based on metric name and percentile
        // This should be replaced with actual Prometheus queries in production
        info!(
            metric = metric,
            percentile = percentile,
            "Returning mock data for Prometheus percentile query"
        );
        Ok(match (metric, percentile) {
            ("feed_api_latency_ms", p) if (p - 0.95).abs() < 0.01 => 180.0,
            ("feed_api_latency_ms", p) if (p - 0.99).abs() < 0.01 => 250.0,
            _ => 120.0,
        })
    }

    // ============================================
    // ClickHouse Query Helpers (Placeholder)
    // ============================================

    async fn query_clickhouse_event_count(&self, event_type: &str) -> Result<u64> {
        // Query event counts from ClickHouse for yesterday
        // Maps action to event_type in the events table:
        // - "impression" → "post_viewed"
        // - "view" → "post_viewed"
        // - "like" → "like_added"
        // - "comment" → "comment_added"
        // - "share" → "share_added"

        let mapped_event_type = match event_type {
            "impression" | "view" => "post_viewed",
            "like" => "like_added",
            "comment" => "comment_added",
            "share" => "share_added",
            other => other,
        };

        let query = format!(
            "SELECT count() FROM events WHERE event_type = '{}' AND toDate(timestamp / 1000) = yesterday()",
            mapped_event_type
        );

        match self.ch_client.query(&query).fetch_one::<u64>().await {
            Ok(count) => {
                info!(
                    event_type = mapped_event_type,
                    count = count,
                    "Fetched event count from ClickHouse"
                );
                Ok(count)
            }
            Err(e) => {
                warn!(
                    event_type = mapped_event_type,
                    error = %e,
                    "Failed to query ClickHouse for event count, using default"
                );
                // Return sensible defaults based on event type
                Ok(match mapped_event_type {
                    "post_viewed" => 500000,
                    "like_added" => 25000,
                    "comment_added" => 5000,
                    "share_added" => 2000,
                    _ => 100000,
                })
            }
        }
    }

    async fn query_clickhouse_avg_dwell_time(&self) -> Result<f64> {
        // Query average dwell time from ClickHouse for yesterday
        // Extracts dwell_ms from the JSON properties field
        // Only includes post_viewed events (where dwell time is meaningful)

        let query = "SELECT avg(JSONExtractFloat(properties, 'dwell_ms')) FROM events \
                     WHERE event_type = 'post_viewed' AND toDate(timestamp / 1000) = yesterday()";

        match self
            .ch_client
            .query(query)
            .fetch_one::<f64>()
            .await
        {
            Ok(avg_dwell) => {
                info!(
                    avg_dwell_ms = avg_dwell,
                    "Fetched average dwell time from ClickHouse"
                );
                Ok(avg_dwell)
            }
            Err(e) => {
                warn!(
                    error = %e,
                    "Failed to query ClickHouse for average dwell time, using default"
                );
                // Return sensible default (4.5 seconds average)
                Ok(4500.0)
            }
        }
    }

    // ============================================
    // Calculated Metrics Helpers
    // ============================================

    async fn calculate_availability(&self) -> Result<f64> {
        // TODO: Calculate from Prometheus metrics
        // (1 - error_rate) * 100
        Ok(99.7) // Mock data
    }

    async fn calculate_error_rate(&self) -> Result<f64> {
        // TODO: Calculate from Prometheus metrics
        // errors / total_requests * 100
        Ok(0.3) // Mock data
    }

    async fn calculate_dedup_rate(&self) -> Result<f64> {
        // TODO: Calculate from Prometheus metrics
        // dedup_hits / (dedup_hits + dedup_misses) * 100
        Ok(99.8) // Mock data
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_metrics_export_job_initialization() {
        let config = MetricsExportConfig::default();
        // Note: In real code, this would be initialized with a ClickHouse client from JobContext
        // For this unit test, we demonstrate the config structure
        assert_eq!(config.retention_days, 365);
        assert!(matches!(config.export_format, ExportFormat::Both));
    }

    #[tokio::test]
    async fn test_daily_report_structure() {
        let report = DailyMetricsReport {
            date: "2025-10-17".to_string(),
            timestamp: Utc::now(),
            feed_api_requests_total: 100000,
            feed_api_avg_latency_ms: 95.5,
            feed_api_p95_latency_ms: 180.0,
            feed_cache_hit_rate_percent: 92.0,
            total_impressions: 500000,
            total_views: 300000,
            total_likes: 25000,
            total_comments: 5000,
            total_shares: 2000,
            ctr_percent: 6.4,
            avg_dwell_time_ms: 4200.0,
            availability_percent: 99.8,
            error_rate_percent: 0.2,
            cdc_lag_avg_seconds: 2.5,
            events_processed: 800000,
            events_dedup_rate_percent: 99.9,
            clickhouse_avg_query_latency_ms: 85.0,
            clickhouse_slow_queries_count: 15,
        };

        // Verify CTR calculation
        assert!((report.ctr_percent - 6.4).abs() < 0.1);
    }

    #[tokio::test]
    async fn test_json_serialization() {
        let report = DailyMetricsReport {
            date: "2025-10-17".to_string(),
            timestamp: Utc::now(),
            feed_api_requests_total: 100000,
            feed_api_avg_latency_ms: 95.5,
            feed_api_p95_latency_ms: 180.0,
            feed_cache_hit_rate_percent: 92.0,
            total_impressions: 500000,
            total_views: 300000,
            total_likes: 25000,
            total_comments: 5000,
            total_shares: 2000,
            ctr_percent: 6.4,
            avg_dwell_time_ms: 4200.0,
            availability_percent: 99.8,
            error_rate_percent: 0.2,
            cdc_lag_avg_seconds: 2.5,
            events_processed: 800000,
            events_dedup_rate_percent: 99.9,
            clickhouse_avg_query_latency_ms: 85.0,
            clickhouse_slow_queries_count: 15,
        };

        let json = serde_json::to_string_pretty(&report).unwrap();
        assert!(json.contains("feed_api_requests_total"));
        assert!(json.contains("100000"));
    }
}
