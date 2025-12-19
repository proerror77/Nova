// Near-line feature service - ClickHouse cold/warm storage
// Provides medium-latency access to historical and less frequently accessed features

use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use clickhouse::{Client, Row};
use serde::{Deserialize, Serialize};
use sqlx::{PgPool, Row as SqlxRow};
use std::collections::HashMap;
use tracing::{debug, info, warn};
use uuid::Uuid;

use crate::models::{FeatureDefinition, FeatureType, FeatureValueData};

/// ClickHouse row for features table
#[derive(Debug, Row, Deserialize)]
struct FeatureRow {
    feature_name: String,
    feature_value: String,
    value_type: u8,
    #[serde(with = "clickhouse::serde::time::datetime")]
    updated_at: time::OffsetDateTime,
}

/// Insert row for ClickHouse features table
#[derive(Debug, Row, Serialize)]
struct InsertFeatureRow {
    entity_type: String,
    entity_id: String,
    feature_name: String,
    feature_value: String,
    value_type: u8,
}

pub struct NearLineFeatureService {
    clickhouse_client: Client,
    pg_pool: PgPool,
}

impl NearLineFeatureService {
    pub fn new(clickhouse_client: Client, pg_pool: PgPool) -> Self {
        info!("Initializing NearLineFeatureService with ClickHouse backend");
        Self {
            clickhouse_client,
            pg_pool,
        }
    }

    /// Get feature value from ClickHouse
    pub async fn get_feature(
        &self,
        entity_id: &str,
        entity_type: &str,
        feature_name: &str,
    ) -> Result<Option<FeatureValueData>> {
        debug!(
            entity_id = %entity_id,
            entity_type = %entity_type,
            feature_name = %feature_name,
            "Fetching feature from ClickHouse"
        );

        let query = r#"
            SELECT feature_name, feature_value, value_type, updated_at
            FROM features
            WHERE entity_type = ? AND entity_id = ? AND feature_name = ?
            ORDER BY updated_at DESC
            LIMIT 1
        "#;

        let result: Option<FeatureRow> = self
            .clickhouse_client
            .query(query)
            .bind(entity_type)
            .bind(entity_id)
            .bind(feature_name)
            .fetch_optional()
            .await
            .context("Failed to fetch feature from ClickHouse")?;

        match result {
            Some(row) => {
                let value = Self::parse_feature_value(&row.feature_value, row.value_type)?;
                Ok(Some(value))
            }
            None => Ok(None),
        }
    }

    /// Get multiple features for a single entity from ClickHouse
    pub async fn get_features(
        &self,
        entity_id: &str,
        entity_type: &str,
        feature_names: &[String],
    ) -> Result<HashMap<String, FeatureValueData>> {
        if feature_names.is_empty() {
            return Ok(HashMap::new());
        }

        debug!(
            entity_id = %entity_id,
            entity_type = %entity_type,
            feature_count = feature_names.len(),
            "Batch fetching features from ClickHouse"
        );

        // Build IN clause with placeholders
        let placeholders: Vec<&str> = feature_names.iter().map(|_| "?").collect();
        let in_clause = placeholders.join(", ");

        let query = format!(
            r#"
            SELECT feature_name, feature_value, value_type, updated_at
            FROM features
            WHERE entity_type = ? AND entity_id = ? AND feature_name IN ({})
            ORDER BY feature_name, updated_at DESC
            LIMIT 1 BY feature_name
            "#,
            in_clause
        );

        let mut cursor = self
            .clickhouse_client
            .query(&query)
            .bind(entity_type)
            .bind(entity_id);

        // Bind each feature name
        for name in feature_names {
            cursor = cursor.bind(name.as_str());
        }

        let rows: Vec<FeatureRow> = cursor
            .fetch_all()
            .await
            .context("Failed to batch fetch features from ClickHouse")?;

        let mut result = HashMap::new();
        for row in rows {
            match Self::parse_feature_value(&row.feature_value, row.value_type) {
                Ok(value) => {
                    result.insert(row.feature_name, value);
                }
                Err(e) => {
                    warn!(
                        feature_name = %row.feature_name,
                        error = %e,
                        "Failed to parse feature value"
                    );
                }
            }
        }

        Ok(result)
    }

    /// Batch get features for multiple entities from ClickHouse
    pub async fn batch_get_features(
        &self,
        entity_ids: &[String],
        entity_type: &str,
        feature_names: &[String],
    ) -> Result<HashMap<String, HashMap<String, FeatureValueData>>> {
        if entity_ids.is_empty() || feature_names.is_empty() {
            return Ok(HashMap::new());
        }

        debug!(
            entity_count = entity_ids.len(),
            entity_type = %entity_type,
            feature_count = feature_names.len(),
            "Batch fetching features for multiple entities from ClickHouse"
        );

        // Build IN clauses
        let entity_placeholders: Vec<&str> = entity_ids.iter().map(|_| "?").collect();
        let feature_placeholders: Vec<&str> = feature_names.iter().map(|_| "?").collect();
        let entity_in_clause = entity_placeholders.join(", ");
        let feature_in_clause = feature_placeholders.join(", ");

        // Extended row type to include entity_id
        #[derive(Debug, Row, Deserialize)]
        struct BatchFeatureRow {
            entity_id: String,
            feature_name: String,
            feature_value: String,
            value_type: u8,
        }

        let query = format!(
            r#"
            SELECT entity_id, feature_name, feature_value, value_type
            FROM features
            WHERE entity_type = ? AND entity_id IN ({}) AND feature_name IN ({})
            ORDER BY entity_id, feature_name, updated_at DESC
            LIMIT 1 BY entity_id, feature_name
            "#,
            entity_in_clause, feature_in_clause
        );

        let mut cursor = self.clickhouse_client.query(&query).bind(entity_type);

        for entity_id in entity_ids {
            cursor = cursor.bind(entity_id.as_str());
        }
        for name in feature_names {
            cursor = cursor.bind(name.as_str());
        }

        let rows: Vec<BatchFeatureRow> = cursor
            .fetch_all()
            .await
            .context("Failed to batch fetch features from ClickHouse")?;

        let mut result: HashMap<String, HashMap<String, FeatureValueData>> = HashMap::new();

        for row in rows {
            match Self::parse_feature_value(&row.feature_value, row.value_type) {
                Ok(value) => {
                    result
                        .entry(row.entity_id)
                        .or_default()
                        .insert(row.feature_name, value);
                }
                Err(e) => {
                    warn!(
                        entity_id = %row.entity_id,
                        feature_name = %row.feature_name,
                        error = %e,
                        "Failed to parse feature value in batch operation"
                    );
                }
            }
        }

        Ok(result)
    }

    /// Sync feature from Redis to ClickHouse (called by background worker)
    pub async fn sync_feature(
        &self,
        entity_id: &str,
        entity_type: &str,
        feature_name: &str,
        value: FeatureValueData,
    ) -> Result<()> {
        debug!(
            entity_id = %entity_id,
            entity_type = %entity_type,
            feature_name = %feature_name,
            "Syncing feature to ClickHouse"
        );

        let (value_str, value_type) = Self::serialize_feature_value(&value);

        let row = InsertFeatureRow {
            entity_type: entity_type.to_string(),
            entity_id: entity_id.to_string(),
            feature_name: feature_name.to_string(),
            feature_value: value_str,
            value_type,
        };

        let mut insert = self.clickhouse_client.insert("features")?;
        insert.write(&row).await?;
        insert.end().await.context("Failed to insert feature into ClickHouse")?;

        info!(
            entity_id = %entity_id,
            feature_name = %feature_name,
            "Successfully synced feature to ClickHouse"
        );

        Ok(())
    }

    /// Batch sync multiple features to ClickHouse
    pub async fn batch_sync_features(
        &self,
        features: Vec<(String, String, String, FeatureValueData)>, // (entity_type, entity_id, feature_name, value)
    ) -> Result<usize> {
        if features.is_empty() {
            return Ok(0);
        }

        debug!(
            feature_count = features.len(),
            "Batch syncing features to ClickHouse"
        );

        let mut insert = self.clickhouse_client.insert("features")?;

        for (entity_type, entity_id, feature_name, value) in &features {
            let (value_str, value_type) = Self::serialize_feature_value(value);

            let row = InsertFeatureRow {
                entity_type: entity_type.clone(),
                entity_id: entity_id.clone(),
                feature_name: feature_name.clone(),
                feature_value: value_str,
                value_type,
            };

            insert.write(&row).await?;
        }

        insert.end().await.context("Failed to batch insert features into ClickHouse")?;

        let count = features.len();
        info!(
            synced_count = count,
            "Successfully batch synced features to ClickHouse"
        );

        Ok(count)
    }

    /// Get feature metadata from PostgreSQL
    pub async fn get_feature_metadata(
        &self,
        entity_type: &str,
        feature_name: &str,
    ) -> Result<Option<FeatureDefinition>> {
        let row = sqlx::query(
            r#"
            SELECT id, name, entity_type, feature_type,
                   description, default_ttl_seconds, created_at, updated_at
            FROM feature_definitions
            WHERE entity_type = $1 AND name = $2
            "#,
        )
        .bind(entity_type)
        .bind(feature_name)
        .fetch_optional(&self.pg_pool)
        .await
        .context("Failed to fetch feature metadata")?;

        Ok(row.map(|r| FeatureDefinition {
            id: r.get::<Uuid, _>("id"),
            name: r.get::<String, _>("name"),
            entity_type: r.get::<String, _>("entity_type"),
            feature_type: FeatureType::from(r.get::<i32, _>("feature_type")),
            description: r.get::<Option<String>, _>("description"),
            default_ttl_seconds: r.get::<i64, _>("default_ttl_seconds"),
            created_at: r.get::<DateTime<Utc>, _>("created_at"),
            updated_at: r.get::<DateTime<Utc>, _>("updated_at"),
        }))
    }

    /// List all features for an entity type
    pub async fn list_features_by_entity_type(
        &self,
        entity_type: &str,
    ) -> Result<Vec<FeatureDefinition>> {
        let rows = sqlx::query(
            r#"
            SELECT id, name, entity_type, feature_type,
                   description, default_ttl_seconds, created_at, updated_at
            FROM feature_definitions
            WHERE entity_type = $1
            ORDER BY name
            "#,
        )
        .bind(entity_type)
        .fetch_all(&self.pg_pool)
        .await
        .context("Failed to list features")?;

        let results = rows
            .into_iter()
            .map(|r| FeatureDefinition {
                id: r.get::<Uuid, _>("id"),
                name: r.get::<String, _>("name"),
                entity_type: r.get::<String, _>("entity_type"),
                feature_type: FeatureType::from(r.get::<i32, _>("feature_type")),
                description: r.get::<Option<String>, _>("description"),
                default_ttl_seconds: r.get::<i64, _>("default_ttl_seconds"),
                created_at: r.get::<DateTime<Utc>, _>("created_at"),
                updated_at: r.get::<DateTime<Utc>, _>("updated_at"),
            })
            .collect();

        Ok(results)
    }

    /// Create a new feature definition
    pub async fn create_feature_definition(
        &self,
        name: &str,
        entity_type: &str,
        feature_type: FeatureType,
        description: Option<&str>,
        default_ttl_seconds: i64,
    ) -> Result<FeatureDefinition> {
        let row = sqlx::query(
            r#"
            INSERT INTO feature_definitions (name, entity_type, feature_type, description, default_ttl_seconds)
            VALUES ($1, $2, $3, $4, $5)
            RETURNING id, name, entity_type, feature_type, description, default_ttl_seconds, created_at, updated_at
            "#,
        )
        .bind(name)
        .bind(entity_type)
        .bind(i32::from(feature_type))
        .bind(description)
        .bind(default_ttl_seconds)
        .fetch_one(&self.pg_pool)
        .await
        .context("Failed to create feature definition")?;

        Ok(FeatureDefinition {
            id: row.get::<Uuid, _>("id"),
            name: row.get::<String, _>("name"),
            entity_type: row.get::<String, _>("entity_type"),
            feature_type: FeatureType::from(row.get::<i32, _>("feature_type")),
            description: row.get::<Option<String>, _>("description"),
            default_ttl_seconds: row.get::<i64, _>("default_ttl_seconds"),
            created_at: row.get::<DateTime<Utc>, _>("created_at"),
            updated_at: row.get::<DateTime<Utc>, _>("updated_at"),
        })
    }

    /// Check ClickHouse connectivity
    pub async fn health_check(&self) -> Result<bool> {
        let result: u8 = self
            .clickhouse_client
            .query("SELECT 1")
            .fetch_one()
            .await
            .context("ClickHouse health check failed")?;

        Ok(result == 1)
    }

    /// Parse feature value from ClickHouse storage format
    fn parse_feature_value(value_str: &str, value_type: u8) -> Result<FeatureValueData> {
        match value_type {
            1 => {
                // Double
                let val: f64 = value_str.parse().context("Failed to parse double value")?;
                Ok(FeatureValueData::Double(val))
            }
            2 => {
                // Int
                let val: i64 = value_str.parse().context("Failed to parse int value")?;
                Ok(FeatureValueData::Int(val))
            }
            3 => {
                // String
                Ok(FeatureValueData::String(value_str.to_string()))
            }
            4 => {
                // Bool
                let val: bool = value_str.parse().context("Failed to parse bool value")?;
                Ok(FeatureValueData::Bool(val))
            }
            5 => {
                // DoubleList (JSON array)
                let val: Vec<f64> =
                    serde_json::from_str(value_str).context("Failed to parse double list")?;
                Ok(FeatureValueData::DoubleList(val))
            }
            6 => {
                // Timestamp
                let val: i64 = value_str.parse().context("Failed to parse timestamp")?;
                Ok(FeatureValueData::Timestamp(val))
            }
            _ => anyhow::bail!("Unknown value type: {}", value_type),
        }
    }

    /// Serialize feature value to ClickHouse storage format
    fn serialize_feature_value(value: &FeatureValueData) -> (String, u8) {
        match value {
            FeatureValueData::Double(v) => (v.to_string(), 1),
            FeatureValueData::Int(v) => (v.to_string(), 2),
            FeatureValueData::String(v) => (v.clone(), 3),
            FeatureValueData::Bool(v) => (v.to_string(), 4),
            FeatureValueData::DoubleList(v) => (serde_json::to_string(v).unwrap_or_default(), 5),
            FeatureValueData::Timestamp(v) => (v.to_string(), 6),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_double_value() {
        let result = NearLineFeatureService::parse_feature_value("3.14159", 1).unwrap();
        match result {
            FeatureValueData::Double(v) => assert!((v - 3.14159).abs() < 0.0001),
            _ => panic!("Expected Double"),
        }
    }

    #[test]
    fn test_parse_int_value() {
        let result = NearLineFeatureService::parse_feature_value("42", 2).unwrap();
        match result {
            FeatureValueData::Int(v) => assert_eq!(v, 42),
            _ => panic!("Expected Int"),
        }
    }

    #[test]
    fn test_parse_string_value() {
        let result = NearLineFeatureService::parse_feature_value("hello", 3).unwrap();
        match result {
            FeatureValueData::String(v) => assert_eq!(v, "hello"),
            _ => panic!("Expected String"),
        }
    }

    #[test]
    fn test_parse_bool_value() {
        let result = NearLineFeatureService::parse_feature_value("true", 4).unwrap();
        match result {
            FeatureValueData::Bool(v) => assert!(v),
            _ => panic!("Expected Bool"),
        }
    }

    #[test]
    fn test_parse_double_list_value() {
        let result = NearLineFeatureService::parse_feature_value("[1.0, 2.0, 3.0]", 5).unwrap();
        match result {
            FeatureValueData::DoubleList(v) => assert_eq!(v, vec![1.0, 2.0, 3.0]),
            _ => panic!("Expected DoubleList"),
        }
    }

    #[test]
    fn test_serialize_feature_value() {
        let (s, t) = NearLineFeatureService::serialize_feature_value(&FeatureValueData::Double(3.14));
        assert_eq!(s, "3.14");
        assert_eq!(t, 1);

        let (s, t) = NearLineFeatureService::serialize_feature_value(&FeatureValueData::Int(42));
        assert_eq!(s, "42");
        assert_eq!(t, 2);
    }
}
