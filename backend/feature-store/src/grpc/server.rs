// gRPC server implementation for FeatureStore service
use crate::services::near_line::NearLineFeatureService;
use crate::services::online::OnlineFeatureStore;
use sqlx::PgPool;
use std::collections::HashMap;
use std::sync::Arc;
use tonic::{Request, Response, Status};
use tracing::{error, info, warn};

// Generated proto code
pub mod feature_store {
    tonic::include_proto!("feature_store");
}

use feature_store::feature_store_server::FeatureStore;
use feature_store::*;

/// AppState holds shared resources for the gRPC service
#[derive(Clone)]
pub struct AppState {
    pub online_store: Arc<OnlineFeatureStore>,
    pub near_line_service: Arc<NearLineFeatureService>,
    pub pg_pool: PgPool,
}

impl AppState {
    pub fn new(
        online_store: Arc<OnlineFeatureStore>,
        near_line_service: Arc<NearLineFeatureService>,
        pg_pool: PgPool,
    ) -> Self {
        Self {
            online_store,
            near_line_service,
            pg_pool,
        }
    }
}

/// FeatureStoreImpl - gRPC service implementation
#[derive(Clone)]
pub struct FeatureStoreImpl {
    state: Arc<AppState>,
}

impl FeatureStoreImpl {
    pub fn new(state: Arc<AppState>) -> Self {
        Self { state }
    }

    /// Helper: Validate entity_id
    fn validate_entity_id(entity_id: &str) -> std::result::Result<(), Status> {
        if entity_id.is_empty() {
            return Err(Status::invalid_argument("entity_id cannot be empty"));
        }
        if entity_id.len() > 255 {
            return Err(Status::invalid_argument(
                "entity_id exceeds max length of 255",
            ));
        }
        Ok(())
    }

    /// Helper: Validate entity_type
    fn validate_entity_type(entity_type: &str) -> std::result::Result<(), Status> {
        if entity_type.is_empty() {
            return Err(Status::invalid_argument("entity_type cannot be empty"));
        }
        if !matches!(entity_type, "user" | "post" | "video" | "creator" | "topic" | "comment") {
            return Err(Status::invalid_argument(format!(
                "Invalid entity_type: {}. Must be one of: user, post, video, creator, topic, comment",
                entity_type
            )));
        }
        Ok(())
    }

    /// Helper: Validate feature names list
    fn validate_feature_names(feature_names: &[String]) -> std::result::Result<(), Status> {
        if feature_names.is_empty() {
            return Err(Status::invalid_argument("feature_names cannot be empty"));
        }
        if feature_names.len() > 100 {
            return Err(Status::invalid_argument(
                "Cannot request more than 100 features at once",
            ));
        }
        for name in feature_names {
            if name.is_empty() {
                return Err(Status::invalid_argument("feature_name cannot be empty"));
            }
        }
        Ok(())
    }

    /// Helper: Validate batch size
    fn validate_batch_size(entity_ids: &[String]) -> std::result::Result<(), Status> {
        if entity_ids.is_empty() {
            return Err(Status::invalid_argument("entity_ids cannot be empty"));
        }
        if entity_ids.len() > 100 {
            return Err(Status::invalid_argument(
                "Cannot fetch features for more than 100 entities at once",
            ));
        }
        Ok(())
    }

    /// Helper: Convert internal FeatureValue to proto FeatureValue
    fn convert_to_proto_value(
        value: crate::models::FeatureValue,
    ) -> Option<feature_store::FeatureValue> {
        use crate::models::FeatureValue as InternalValue;

        let proto_value = match value {
            InternalValue::Double(v) => feature_store::FeatureValue {
                value: Some(feature_store::feature_value::Value::DoubleValue(v)),
            },
            InternalValue::Int(v) => feature_store::FeatureValue {
                value: Some(feature_store::feature_value::Value::IntValue(v)),
            },
            InternalValue::String(v) => feature_store::FeatureValue {
                value: Some(feature_store::feature_value::Value::StringValue(v)),
            },
            InternalValue::Bool(v) => feature_store::FeatureValue {
                value: Some(feature_store::feature_value::Value::BoolValue(v)),
            },
            InternalValue::DoubleList(v) => feature_store::FeatureValue {
                value: Some(feature_store::feature_value::Value::DoubleListValue(
                    feature_store::DoubleList { values: v },
                )),
            },
            InternalValue::Timestamp(v) => feature_store::FeatureValue {
                value: Some(feature_store::feature_value::Value::TimestampValue(v)),
            },
        };

        Some(proto_value)
    }

    /// Helper: Convert proto FeatureValue to internal FeatureValue
    #[allow(dead_code)]
    fn convert_from_proto_value(
        proto_value: feature_store::FeatureValue,
    ) -> std::result::Result<crate::models::FeatureValue, Status> {
        use crate::models::FeatureValue as InternalValue;

        match proto_value.value {
            Some(feature_store::feature_value::Value::DoubleValue(v)) => {
                Ok(InternalValue::Double(v))
            }
            Some(feature_store::feature_value::Value::IntValue(v)) => Ok(InternalValue::Int(v)),
            Some(feature_store::feature_value::Value::StringValue(v)) => {
                Ok(InternalValue::String(v))
            }
            Some(feature_store::feature_value::Value::BoolValue(v)) => Ok(InternalValue::Bool(v)),
            Some(feature_store::feature_value::Value::DoubleListValue(v)) => {
                Ok(InternalValue::DoubleList(v.values))
            }
            Some(feature_store::feature_value::Value::TimestampValue(v)) => {
                Ok(InternalValue::Timestamp(v))
            }
            None => Err(Status::invalid_argument("Feature value cannot be empty")),
        }
    }

    /// Extract correlation_id from request metadata
    fn extract_correlation_id<T>(req: &Request<T>) -> Option<String> {
        req.metadata()
            .get("correlation-id")
            .and_then(|v| v.to_str().ok())
            .map(|s| s.to_string())
    }

    /// Convert FeatureType to proto FeatureType
    fn feature_type_to_proto(ft: crate::models::FeatureType) -> i32 {
        match ft {
            crate::models::FeatureType::Double => 1,
            crate::models::FeatureType::Int => 2,
            crate::models::FeatureType::String => 3,
            crate::models::FeatureType::Bool => 4,
            crate::models::FeatureType::DoubleList => 5,
            crate::models::FeatureType::Timestamp => 6,
        }
    }
}

#[tonic::async_trait]
impl FeatureStore for FeatureStoreImpl {
    /// Get features for a single entity
    ///
    /// Process:
    /// 1. Validate request parameters
    /// 2. Call OnlineFeatureStore to fetch features from Redis
    /// 3. Build response with features and missing_features list
    ///
    /// Performance: Redis GET operations, typically < 5ms
    async fn get_features(
        &self,
        request: Request<GetFeaturesRequest>,
    ) -> Result<Response<GetFeaturesResponse>, Status> {
        // Extract correlation_id for tracing (before consuming request)
        let correlation_id = Self::extract_correlation_id(&request);
        if let Some(ref cid) = correlation_id {
            info!("get_features correlation_id: {}", cid);
        }

        let req = request.into_inner();

        // Validate input
        Self::validate_entity_id(&req.entity_id)?;
        Self::validate_entity_type(&req.entity_type)?;
        Self::validate_feature_names(&req.feature_names)?;

        info!(
            "get_features: entity_id={}, entity_type={}, feature_count={}",
            req.entity_id,
            req.entity_type,
            req.feature_names.len()
        );

        // Parse entity_id as UUID
        let user_id = uuid::Uuid::parse_str(&req.entity_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid entity_id UUID: {}", e)))?;

        // Fetch features from online store
        let result = self
            .state
            .online_store
            .get_features(user_id, &req.feature_names)
            .await
            .map_err(|e| {
                error!("Failed to get features: {}", e);
                Status::internal(format!("Failed to get features: {}", e))
            })?;

        // Build response
        let mut features = HashMap::new();
        let mut missing_features = Vec::new();

        for feature_name in &req.feature_names {
            if let Some(&value) = result.get(feature_name) {
                features.insert(
                    feature_name.clone(),
                    feature_store::FeatureValue {
                        value: Some(feature_store::feature_value::Value::DoubleValue(value)),
                    },
                );
            } else {
                missing_features.push(feature_name.clone());
            }
        }

        if !missing_features.is_empty() {
            warn!(
                "get_features: {} features not found for entity {}",
                missing_features.len(),
                req.entity_id
            );
        }

        Ok(Response::new(GetFeaturesResponse {
            entity_id: req.entity_id,
            features,
            missing_features,
        }))
    }

    /// Get features for multiple entities in a single request
    ///
    /// Process:
    /// 1. Validate batch size (max 100 entities)
    /// 2. Validate feature names
    /// 3. Call OnlineFeatureStore for each entity (parallelized internally)
    /// 4. Build response map with per-entity features
    ///
    /// Performance: Redis MGET operations, typically < 20ms for 100 entities
    async fn batch_get_features(
        &self,
        request: Request<BatchGetFeaturesRequest>,
    ) -> Result<Response<BatchGetFeaturesResponse>, Status> {
        // Extract correlation_id (before consuming request)
        let correlation_id = Self::extract_correlation_id(&request);
        if let Some(ref cid) = correlation_id {
            info!("batch_get_features correlation_id: {}", cid);
        }

        let req = request.into_inner();

        // Validate input
        Self::validate_batch_size(&req.entity_ids)?;
        Self::validate_entity_type(&req.entity_type)?;
        Self::validate_feature_names(&req.feature_names)?;

        info!(
            "batch_get_features: entity_count={}, entity_type={}, feature_count={}",
            req.entity_ids.len(),
            req.entity_type,
            req.feature_names.len()
        );

        // Validate and parse all entity IDs
        let mut user_ids = Vec::new();
        for entity_id in &req.entity_ids {
            Self::validate_entity_id(entity_id)?;
            let user_id = uuid::Uuid::parse_str(entity_id)
                .map_err(|e| Status::invalid_argument(format!("Invalid entity_id UUID: {}", e)))?;
            user_ids.push(user_id);
        }

        // Fetch features for all entities (parallelized)
        let results = self
            .state
            .online_store
            .batch_get_features(&user_ids, &req.feature_names)
            .await
            .map_err(|e| {
                error!("Failed to batch get features: {}", e);
                Status::internal(format!("Failed to batch get features: {}", e))
            })?;

        // Build response
        let mut entities = HashMap::new();

        for (user_id, feature_map) in results {
            let mut features = HashMap::new();
            let mut missing_features = Vec::new();

            for feature_name in &req.feature_names {
                if let Some(&value) = feature_map.get(feature_name) {
                    features.insert(
                        feature_name.clone(),
                        feature_store::FeatureValue {
                            value: Some(feature_store::feature_value::Value::DoubleValue(value)),
                        },
                    );
                } else {
                    missing_features.push(feature_name.clone());
                }
            }

            let entity_id_str = user_id.to_string();
            entities.insert(
                entity_id_str.clone(),
                EntityFeatures {
                    entity_id: entity_id_str,
                    features,
                    missing_features,
                },
            );
        }

        info!("batch_get_features: returned {} entities", entities.len());

        Ok(Response::new(BatchGetFeaturesResponse { entities }))
    }

    /// Set/update a feature value for an entity
    ///
    /// Process:
    /// 1. Validate request parameters
    /// 2. Convert proto FeatureValue to internal FeatureValue
    /// 3. Call OnlineFeatureStore to SET in Redis with TTL
    /// 4. Return success response
    ///
    /// Performance: Redis SET operation, typically < 2ms
    ///
    /// Security: No authentication in this layer (handled by mTLS)
    async fn set_feature(
        &self,
        request: Request<SetFeatureRequest>,
    ) -> Result<Response<SetFeatureResponse>, Status> {
        // Extract correlation_id (before consuming request)
        let correlation_id = Self::extract_correlation_id(&request);
        if let Some(ref cid) = correlation_id {
            info!("set_feature correlation_id: {}", cid);
        }

        let req = request.into_inner();

        // Validate input
        Self::validate_entity_id(&req.entity_id)?;
        Self::validate_entity_type(&req.entity_type)?;

        if req.feature_name.is_empty() {
            return Err(Status::invalid_argument("feature_name cannot be empty"));
        }

        if req.value.is_none() {
            return Err(Status::invalid_argument("value is required"));
        }

        if req.ttl_seconds < 0 {
            return Err(Status::invalid_argument("ttl_seconds cannot be negative"));
        }

        info!(
            "set_feature: entity_id={}, entity_type={}, feature_name={}, ttl={}",
            req.entity_id, req.entity_type, req.feature_name, req.ttl_seconds
        );

        // Parse entity_id as UUID
        let user_id = uuid::Uuid::parse_str(&req.entity_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid entity_id UUID: {}", e)))?;

        // Extract value (only double values supported for now)
        let value = match req.value.and_then(|v| v.value) {
            Some(feature_store::feature_value::Value::DoubleValue(v)) => v,
            Some(feature_store::feature_value::Value::IntValue(v)) => v as f64,
            _ => {
                return Err(Status::invalid_argument(
                    "Only numeric values are supported for set_feature",
                ))
            }
        };

        // Set feature in online store
        let feature_name = req.feature_name.clone();
        self.state
            .online_store
            .set_feature(user_id, req.feature_name, value)
            .await
            .map_err(|e| {
                error!("Failed to set feature: {}", e);
                Status::internal(format!("Failed to set feature: {}", e))
            })?;

        info!(
            "set_feature: success for entity {} feature {}",
            req.entity_id, feature_name
        );

        Ok(Response::new(SetFeatureResponse {
            success: true,
            message: "Feature set successfully".to_string(),
        }))
    }

    /// Get feature metadata (type, TTL, update time)
    ///
    /// Process:
    /// 1. Validate request parameters
    /// 2. Query PostgreSQL metadata table via NearLineFeatureService
    /// 3. Return feature metadata
    ///
    /// Note: This is a low-frequency operation (used for debugging/monitoring)
    async fn get_feature_metadata(
        &self,
        request: Request<GetFeatureMetadataRequest>,
    ) -> Result<Response<GetFeatureMetadataResponse>, Status> {
        // Extract correlation_id (before consuming request)
        let correlation_id = Self::extract_correlation_id(&request);
        if let Some(ref cid) = correlation_id {
            info!("get_feature_metadata correlation_id: {}", cid);
        }

        let req = request.into_inner();

        // Validate input
        Self::validate_entity_type(&req.entity_type)?;

        if req.feature_name.is_empty() {
            return Err(Status::invalid_argument("feature_name cannot be empty"));
        }

        info!(
            "get_feature_metadata: entity_type={}, feature_name={}",
            req.entity_type, req.feature_name
        );

        // Fetch metadata from NearLineFeatureService
        let metadata = self
            .state
            .near_line_service
            .get_feature_metadata(&req.entity_type, &req.feature_name)
            .await
            .map_err(|e| {
                error!("Failed to get feature metadata: {}", e);
                Status::internal(format!("Failed to get feature metadata: {}", e))
            })?;

        match metadata {
            Some(def) => {
                info!(
                    "get_feature_metadata: found metadata for {}/{}",
                    req.entity_type, req.feature_name
                );

                Ok(Response::new(GetFeatureMetadataResponse {
                    feature_name: def.name,
                    r#type: Self::feature_type_to_proto(def.feature_type),
                    ttl_seconds: def.default_ttl_seconds,
                    last_updated_timestamp: def.updated_at.timestamp(),
                    description: def.description.unwrap_or_default(),
                }))
            }
            None => {
                warn!(
                    "get_feature_metadata: no metadata found for {}/{}",
                    req.entity_type, req.feature_name
                );
                Err(Status::not_found(format!(
                    "Feature metadata not found for {}/{}",
                    req.entity_type, req.feature_name
                )))
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_validate_entity_id() {
        assert!(FeatureStoreImpl::validate_entity_id("user_123").is_ok());
        assert!(FeatureStoreImpl::validate_entity_id("").is_err());
        assert!(FeatureStoreImpl::validate_entity_id(&"a".repeat(256)).is_err());
    }

    #[test]
    fn test_validate_entity_type() {
        assert!(FeatureStoreImpl::validate_entity_type("user").is_ok());
        assert!(FeatureStoreImpl::validate_entity_type("post").is_ok());
        assert!(FeatureStoreImpl::validate_entity_type("video").is_ok());
        assert!(FeatureStoreImpl::validate_entity_type("creator").is_ok());
        assert!(FeatureStoreImpl::validate_entity_type("topic").is_ok());
        assert!(FeatureStoreImpl::validate_entity_type("comment").is_ok());
        assert!(FeatureStoreImpl::validate_entity_type("invalid").is_err());
        assert!(FeatureStoreImpl::validate_entity_type("").is_err());
    }

    #[test]
    fn test_validate_feature_names() {
        assert!(FeatureStoreImpl::validate_feature_names(&vec!["f1".to_string()]).is_ok());
        assert!(FeatureStoreImpl::validate_feature_names(&vec![]).is_err());
        assert!(FeatureStoreImpl::validate_feature_names(&vec!["".to_string()]).is_err());
        assert!(FeatureStoreImpl::validate_feature_names(&vec!["f".to_string(); 101]).is_err());
    }

    #[test]
    fn test_validate_batch_size() {
        assert!(FeatureStoreImpl::validate_batch_size(&vec!["e1".to_string()]).is_ok());
        assert!(FeatureStoreImpl::validate_batch_size(&vec![]).is_err());
        assert!(FeatureStoreImpl::validate_batch_size(&vec!["e".to_string(); 101]).is_err());
    }

    #[test]
    fn test_feature_type_to_proto() {
        assert_eq!(
            FeatureStoreImpl::feature_type_to_proto(crate::models::FeatureType::Double),
            1
        );
        assert_eq!(
            FeatureStoreImpl::feature_type_to_proto(crate::models::FeatureType::Int),
            2
        );
        assert_eq!(
            FeatureStoreImpl::feature_type_to_proto(crate::models::FeatureType::String),
            3
        );
    }
}
