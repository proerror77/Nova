//! Background jobs for content-service.
//!
//! Currently only includes the feed candidate refresh task that keeps the
//! ClickHouse materialized candidate tables up to date.

pub mod feed_candidates;
