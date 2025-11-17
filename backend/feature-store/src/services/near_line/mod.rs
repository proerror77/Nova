// Near-line feature service - ClickHouse cold/warm storage
// Provides medium-latency access to historical and less frequently accessed features

use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use clickhouse::Client;
use serde_json::json;
use sqlx::{PgPool, Row};
use std::collections::HashMap;
use tracing::{info, warn};
use uuid::Uuid;

use crate::models::{FeatureDefinition, FeatureType, FeatureValueData};

pub struct NearLineFeatureService {
    clickhouse_client: Client,
    pg_pool: PgPool,
}

impl NearLineFeatureService {
    pub fn new(clickhouse_client: Client, pg_pool: PgPool) -> Self {
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
        let row = self
            .clickhouse_client
            .query(
                "SELECT feature_value, value_type \
                 FROM features \
                 WHERE entity_type = ? AND entity_id = ? AND feature_name = ? \
                 ORDER BY updated_at DESC \
                 LIMIT 1",
            )
            .bind(entity_type)
            .bind(entity_id)
            .bind(feature_name)
            .fetch_optional::<(String, u8)>()
            .await
            .context("Failed to query ClickHouse for feature")?;

        match row {
            Some((value, value_type)) => Ok(Some(decode_feature_value(value, value_type)?)),
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
        let mut result = HashMap::new();
        for name in feature_names {
            if let Some(value) = self
                .get_feature(entity_id, entity_type, name)
                .await
                .context("Failed to fetch feature")?
            {
                result.insert(name.clone(), value);
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
        let mut result = HashMap::new();
        for entity_id in entity_ids {
            let features = self
                .get_features(entity_id, entity_type, feature_names)
                .await
                .context("Failed to batch fetch features")?;
            result.insert(entity_id.clone(), features);
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
        let (value_str, value_type) = encode_feature_value(&value);

        self.clickhouse_client
            .query(
                "INSERT INTO features (entity_type, entity_id, feature_name, feature_value, value_type, updated_at) \
                 VALUES (?, ?, ?, ?, ?, now())",
            )
            .bind(entity_type)
            .bind(entity_id)
            .bind(feature_name)
            .bind(value_str)
            .bind(value_type as u8)
            .execute()
            .await
            .context("Failed to sync feature to ClickHouse")?;

        info!(
            entity_type = %entity_type,
            entity_id = %entity_id,
            feature_name = %feature_name,
            "Synced feature to ClickHouse"
        );

        Ok(())
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
}

fn decode_feature_value(value: String, value_type: u8) -> Result<FeatureValueData> {
    match value_type {
        1 => {
            let parsed = value.parse::<f64>()?;
            Ok(FeatureValueData::Double(parsed))
        }
        2 => {
            let parsed = value.parse::<i64>()?;
            Ok(FeatureValueData::Int(parsed))
        }
        3 => Ok(FeatureValueData::String(value)),
        4 => {
            let parsed = value.parse::<bool>()?;
            Ok(FeatureValueData::Bool(parsed))
        }
        5 => {
            let parsed: Vec<f64> = serde_json::from_str(&value)?;
            Ok(FeatureValueData::DoubleList(parsed))
        }
        6 => {
            let parsed = value.parse::<i64>()?;
            Ok(FeatureValueData::Timestamp(parsed))
        }
        _ => anyhow::bail!("Unknown feature value type: {}", value_type),
    }
}

fn encode_feature_value(value: &FeatureValueData) -> (String, u8) {
    match value {
        FeatureValueData::Double(v) => (v.to_string(), 1),
        FeatureValueData::Int(v) => (v.to_string(), 2),
        FeatureValueData::String(v) => (v.clone(), 3),
        FeatureValueData::Bool(v) => (v.to_string(), 4),
        FeatureValueData::DoubleList(v) => {
            (serde_json::to_string(v).unwrap_or_else(|_| "[]".into()), 5)
        }
        FeatureValueData::Timestamp(v) => (v.to_string(), 6),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // TODO: Add integration tests with ClickHouse and PostgreSQL
}
