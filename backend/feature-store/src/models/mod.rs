// Domain models for feature store

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Feature definition (metadata)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeatureDefinition {
    pub id: Uuid,
    pub name: String,
    pub entity_type: String,
    pub feature_type: FeatureType,
    pub description: Option<String>,
    pub default_ttl_seconds: i64,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Feature type enumeration
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum FeatureType {
    Double,
    Int,
    String,
    Bool,
    DoubleList,  // For embedding vectors
    Timestamp,
}

impl From<i32> for FeatureType {
    fn from(value: i32) -> Self {
        match value {
            1 => FeatureType::Double,
            2 => FeatureType::Int,
            3 => FeatureType::String,
            4 => FeatureType::Bool,
            5 => FeatureType::DoubleList,
            6 => FeatureType::Timestamp,
            _ => panic!("Invalid feature type: {}", value),
        }
    }
}

impl From<FeatureType> for i32 {
    fn from(value: FeatureType) -> Self {
        match value {
            FeatureType::Double => 1,
            FeatureType::Int => 2,
            FeatureType::String => 3,
            FeatureType::Bool => 4,
            FeatureType::DoubleList => 5,
            FeatureType::Timestamp => 6,
        }
    }
}

/// Entity type definition
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EntityType {
    pub id: Uuid,
    pub name: String,
    pub description: Option<String>,
    pub created_at: DateTime<Utc>,
}

/// Feature value wrapper (used internally)
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum FeatureValueData {
    Double(f64),
    Int(i64),
    String(String),
    Bool(bool),
    DoubleList(Vec<f64>),
    Timestamp(i64),
}

/// Feature value (matches proto definition, used for gRPC)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum FeatureValue {
    Double(f64),
    Int(i64),
    String(String),
    Bool(bool),
    DoubleList(Vec<f64>),
    Timestamp(i64),
}

/// Feature with metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Feature {
    pub entity_id: String,
    pub entity_type: String,
    pub feature_name: String,
    pub value: FeatureValueData,
    pub updated_at: DateTime<Utc>,
}

/// Batch feature request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BatchFeatureRequest {
    pub entity_ids: Vec<String>,
    pub feature_names: Vec<String>,
    pub entity_type: String,
}

/// Batch feature response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BatchFeatureResponse {
    pub features: Vec<Feature>,
    pub missing: Vec<MissingFeature>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MissingFeature {
    pub entity_id: String,
    pub feature_name: String,
}

/// Feature metadata (returned by get_feature_metadata RPC)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeatureMetadata {
    pub feature_name: String,
    pub feature_type: FeatureType,
    pub ttl_seconds: Option<u64>,
    pub last_updated_timestamp: i64,
    pub description: String,
}
