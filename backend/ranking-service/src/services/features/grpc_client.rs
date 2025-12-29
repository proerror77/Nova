// ============================================
// Feature Store gRPC Client Integration
// ============================================
// Provides feature retrieval through the feature-store gRPC service
// instead of direct Redis access.

use anyhow::Result;
use grpc_clients::feature_store::{
    feature_store_client::FeatureStoreClient, BatchGetFeaturesRequest, FeatureValue,
    GetFeaturesRequest,
};
use std::collections::HashMap;
use tonic::transport::Channel;
use tracing::{debug, warn};
use uuid::Uuid;

use super::ContentFeatures;

/// Feature source configuration
#[derive(Debug, Clone)]
pub enum FeatureSource {
    /// Use direct Redis access (legacy, faster for simple cases)
    Redis,
    /// Use feature-store gRPC service (recommended for ML features)
    FeatureStore,
}

impl Default for FeatureSource {
    fn default() -> Self {
        Self::Redis
    }
}

/// gRPC-based feature client using the feature-store service
pub struct GrpcFeatureClient {
    client: FeatureStoreClient<Channel>,
}

impl GrpcFeatureClient {
    /// Create new gRPC feature client from channel
    pub fn new(channel: Channel) -> Self {
        Self {
            client: FeatureStoreClient::new(channel),
        }
    }

    /// Create from grpc-clients pool
    pub fn from_pool(pool: &grpc_clients::GrpcClientPool) -> Self {
        Self {
            client: pool.feature_store(),
        }
    }

    /// Get features for a single user
    pub async fn get_user_features(&self, user_id: &str) -> Result<UserFeatureSet> {
        let mut client = self.client.clone();

        let request = GetFeaturesRequest {
            entity_id: user_id.to_string(),
            entity_type: "user".to_string(),
            feature_names: vec![
                "follower_count".to_string(),
                "post_count".to_string(),
                "engagement_rate".to_string(),
            ],
        };

        let response = client.get_features(request).await?;
        let features = response.into_inner().features;

        Ok(UserFeatureSet {
            follower_count: extract_int_feature(&features, "follower_count").unwrap_or(0) as u32,
            post_count: extract_int_feature(&features, "post_count").unwrap_or(0) as u32,
            engagement_rate: extract_double_feature(&features, "engagement_rate").unwrap_or(0.5)
                as f32,
        })
    }

    /// Batch get features for multiple posts
    pub async fn batch_get_post_features(
        &self,
        post_ids: &[String],
    ) -> Result<HashMap<String, PostFeatureSet>> {
        if post_ids.is_empty() {
            return Ok(HashMap::new());
        }

        let mut client = self.client.clone();

        let request = BatchGetFeaturesRequest {
            entity_ids: post_ids.to_vec(),
            entity_type: "post".to_string(),
            feature_names: vec![
                "like_count".to_string(),
                "comment_count".to_string(),
                "share_count".to_string(),
                "content_quality".to_string(),
                "author_id".to_string(),
            ],
        };

        let response = client.batch_get_features(request).await?;
        let entities = response.into_inner().entities;

        let mut result = HashMap::new();
        for (entity_id, entity_features) in entities {
            let features = &entity_features.features;
            result.insert(
                entity_id,
                PostFeatureSet {
                    like_count: extract_int_feature(features, "like_count").unwrap_or(0) as u32,
                    comment_count: extract_int_feature(features, "comment_count").unwrap_or(0)
                        as u32,
                    share_count: extract_int_feature(features, "share_count").unwrap_or(0) as u32,
                    content_quality: extract_double_feature(features, "content_quality")
                        .unwrap_or(0.5) as f32,
                    author_id: extract_string_feature(features, "author_id")
                        .and_then(|s| Uuid::parse_str(&s).ok()),
                },
            );
        }

        Ok(result)
    }

    /// Batch get author quality scores
    pub async fn batch_get_author_quality(
        &self,
        author_ids: &[String],
    ) -> Result<HashMap<String, f32>> {
        if author_ids.is_empty() {
            return Ok(HashMap::new());
        }

        let mut client = self.client.clone();

        let request = BatchGetFeaturesRequest {
            entity_ids: author_ids.to_vec(),
            entity_type: "user".to_string(),
            feature_names: vec!["author_quality".to_string()],
        };

        let response = client.batch_get_features(request).await?;
        let entities = response.into_inner().entities;

        let mut result = HashMap::new();
        for (entity_id, entity_features) in entities {
            let quality =
                extract_double_feature(&entity_features.features, "author_quality").unwrap_or(0.5);
            result.insert(entity_id, quality as f32);
        }

        Ok(result)
    }

    /// Get content features for ranking (combines post and author features)
    pub async fn batch_get_content_features(
        &self,
        content_ids: &[String],
    ) -> HashMap<String, ContentFeatures> {
        if content_ids.is_empty() {
            return HashMap::new();
        }

        // Fetch post features
        let post_features = match self.batch_get_post_features(content_ids).await {
            Ok(features) => features,
            Err(e) => {
                warn!("Failed to fetch post features from feature-store: {}", e);
                return HashMap::new();
            }
        };

        // Collect unique author IDs
        let author_ids: Vec<String> = post_features
            .values()
            .filter_map(|f| f.author_id.map(|id| id.to_string()))
            .collect();

        // Fetch author quality scores
        let author_quality = match self.batch_get_author_quality(&author_ids).await {
            Ok(quality) => quality,
            Err(e) => {
                warn!("Failed to fetch author quality from feature-store: {}", e);
                HashMap::new()
            }
        };

        // Combine into ContentFeatures
        let mut result = HashMap::new();
        for content_id in content_ids {
            if let Some(post) = post_features.get(content_id) {
                let author_quality_score = post
                    .author_id
                    .and_then(|id| author_quality.get(&id.to_string()).copied())
                    .unwrap_or(0.5);

                result.insert(
                    content_id.clone(),
                    ContentFeatures {
                        content_quality: post.content_quality,
                        author_quality: author_quality_score,
                        author_id: post.author_id,
                        completion_rate: 0.5, // TODO: Add to feature-store
                    },
                );
            }
        }

        debug!(
            "Fetched {} content features from feature-store",
            result.len()
        );
        result
    }
}

/// User feature set from feature-store
#[derive(Debug, Clone)]
pub struct UserFeatureSet {
    pub follower_count: u32,
    pub post_count: u32,
    pub engagement_rate: f32,
}

/// Post feature set from feature-store
#[derive(Debug, Clone)]
pub struct PostFeatureSet {
    pub like_count: u32,
    pub comment_count: u32,
    pub share_count: u32,
    pub content_quality: f32,
    pub author_id: Option<Uuid>,
}

// Helper functions to extract typed values from FeatureValue

fn extract_double_feature(features: &HashMap<String, FeatureValue>, name: &str) -> Option<f64> {
    features.get(name).and_then(|v| {
        v.value.as_ref().and_then(|val| {
            use grpc_clients::feature_store::feature_value::Value;
            match val {
                Value::DoubleValue(d) => Some(*d),
                Value::IntValue(i) => Some(*i as f64),
                _ => None,
            }
        })
    })
}

fn extract_int_feature(features: &HashMap<String, FeatureValue>, name: &str) -> Option<i64> {
    features.get(name).and_then(|v| {
        v.value.as_ref().and_then(|val| {
            use grpc_clients::feature_store::feature_value::Value;
            match val {
                Value::IntValue(i) => Some(*i),
                Value::DoubleValue(d) => Some(*d as i64),
                _ => None,
            }
        })
    })
}

fn extract_string_feature(features: &HashMap<String, FeatureValue>, name: &str) -> Option<String> {
    features.get(name).and_then(|v| {
        v.value.as_ref().and_then(|val| {
            use grpc_clients::feature_store::feature_value::Value;
            match val {
                Value::StringValue(s) => Some(s.clone()),
                _ => None,
            }
        })
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_feature_source_default() {
        let source = FeatureSource::default();
        assert!(matches!(source, FeatureSource::Redis));
    }
}
