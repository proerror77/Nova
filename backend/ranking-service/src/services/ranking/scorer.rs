/// Candidate Scoring Module
///
/// Orchestrates feature extraction, model inference, and batch scoring for feed ranking.

use super::{RankingError, RankingModel, Result};
use crate::services::features::GrpcFeatureClient;
use ndarray::Array2;
use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use tracing::{debug, info, warn};
use uuid::Uuid;

/// Maximum batch size for scoring (to prevent memory issues)
const MAX_BATCH_SIZE: usize = 100;

/// Scored candidate post
#[derive(Debug, Clone)]
pub struct ScoredCandidate {
    pub post_id: Uuid,
    pub author_id: Uuid,
    pub score: f32,
    pub features: CandidateFeatures,
}

/// Features for a candidate post
#[derive(Debug, Clone)]
pub struct CandidateFeatures {
    // User features
    pub user_follower_count: f32,
    pub user_post_count: f32,
    pub user_engagement_rate: f32,

    // Post features
    pub post_like_count: f32,
    pub post_comment_count: f32,
    pub post_share_count: f32,
    pub post_age_hours: f32,

    // Interaction features
    pub author_is_following: bool,
    pub previous_interactions: f32,
}

impl CandidateFeatures {
    /// Convert to feature vector for model inference
    ///
    /// Layout: [user_features (3), post_features (4), interaction_features (2)]
    fn to_vector(&self) -> Vec<f32> {
        vec![
            self.user_follower_count,
            self.user_post_count,
            self.user_engagement_rate,
            self.post_like_count,
            self.post_comment_count,
            self.post_share_count,
            self.post_age_hours,
            if self.author_is_following { 1.0 } else { 0.0 },
            self.previous_interactions,
        ]
    }
}

/// Ranking Scorer
///
/// Integrates with feature-store to extract features and score candidates using ML model.
pub struct RankingScorer {
    model: Arc<RankingModel>,
    /// Optional feature-store gRPC client for ML feature retrieval
    feature_store_client: Option<Arc<GrpcFeatureClient>>,
}

impl RankingScorer {
    /// Create new scorer with model (no feature-store integration)
    pub fn new(model: Arc<RankingModel>) -> Self {
        Self {
            model,
            feature_store_client: None,
        }
    }

    /// Create scorer with feature-store gRPC client
    pub fn with_feature_store(
        model: Arc<RankingModel>,
        feature_store_client: Arc<GrpcFeatureClient>,
    ) -> Self {
        Self {
            model,
            feature_store_client: Some(feature_store_client),
        }
    }

    /// Check if feature-store is available
    pub fn has_feature_store(&self) -> bool {
        self.feature_store_client.is_some()
    }

    /// Score a batch of candidate posts for a user
    ///
    /// # Arguments
    /// * `user_id` - Target user ID
    /// * `candidates` - List of candidate posts (post_id, author_id, created_at)
    /// * `user_features` - Pre-fetched user features
    /// * `post_features_map` - Pre-fetched post features by post_id
    /// * `following_set` - Set of author_ids that user follows
    /// * `interaction_history` - Map of author_id → interaction count
    ///
    /// # Returns
    /// * List of scored candidates, sorted by score (descending)
    pub async fn score_candidates(
        &self,
        user_id: Uuid,
        candidates: Vec<CandidatePost>,
        user_features: UserFeatures,
        post_features_map: HashMap<Uuid, PostFeatures>,
        following_set: HashSet<Uuid>,
        interaction_history: HashMap<Uuid, u32>,
    ) -> Result<Vec<ScoredCandidate>> {
        if candidates.is_empty() {
            return Ok(vec![]);
        }

        if candidates.len() > MAX_BATCH_SIZE {
            warn!(
                "Batch size {} exceeds limit {}, truncating",
                candidates.len(),
                MAX_BATCH_SIZE
            );
        }

        let candidates = &candidates[..candidates.len().min(MAX_BATCH_SIZE)];

        debug!(
            user_id = %user_id,
            candidate_count = candidates.len(),
            "Scoring candidates"
        );

        // Extract features for all candidates
        let features = self.extract_features(
            &candidates,
            &user_features,
            &post_features_map,
            &following_set,
            &interaction_history,
        )?;

        // Convert to 2D array for model inference
        let feature_vectors: Vec<f32> = features.iter().flat_map(|f| f.to_vector()).collect();
        let feature_matrix =
            Array2::from_shape_vec((candidates.len(), 9), feature_vectors).map_err(|e| {
                RankingError::FeatureExtractionError(format!("Failed to build feature matrix: {}", e))
            })?;

        // Run model inference
        let scores = self.model.predict(feature_matrix)?;

        // Combine candidates with scores
        let mut scored_candidates: Vec<ScoredCandidate> = candidates
            .iter()
            .zip(scores.iter())
            .zip(features.iter())
            .map(|((candidate, &score), features)| ScoredCandidate {
                post_id: candidate.post_id,
                author_id: candidate.author_id,
                score,
                features: features.clone(),
            })
            .collect();

        // Sort by score descending
        // Note: NaN scores are treated as less than any valid score
        scored_candidates.sort_by(|a, b| {
            b.score
                .partial_cmp(&a.score)
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        debug!(
            user_id = %user_id,
            scored_count = scored_candidates.len(),
            top_score = scored_candidates.first().map(|c| c.score),
            "Scoring complete"
        );

        Ok(scored_candidates)
    }

    /// Extract features for all candidates
    fn extract_features(
        &self,
        candidates: &[CandidatePost],
        user_features: &UserFeatures,
        post_features_map: &HashMap<Uuid, PostFeatures>,
        following_set: &HashSet<Uuid>,
        interaction_history: &HashMap<Uuid, u32>,
    ) -> Result<Vec<CandidateFeatures>> {
        let now = chrono::Utc::now();

        candidates
            .iter()
            .map(|candidate| {
                let post_features = post_features_map
                    .get(&candidate.post_id)
                    .ok_or_else(|| {
                        RankingError::FeatureExtractionError(format!(
                            "Post features not found for post_id: {}",
                            candidate.post_id
                        ))
                    })?;

                let post_age_hours = (now - candidate.created_at).num_hours() as f32;

                Ok(CandidateFeatures {
                    // User features
                    user_follower_count: user_features.follower_count as f32,
                    user_post_count: user_features.post_count as f32,
                    user_engagement_rate: user_features.engagement_rate,

                    // Post features
                    post_like_count: post_features.like_count as f32,
                    post_comment_count: post_features.comment_count as f32,
                    post_share_count: post_features.share_count as f32,
                    post_age_hours,

                    // Interaction features
                    author_is_following: following_set.contains(&candidate.author_id),
                    previous_interactions: interaction_history
                        .get(&candidate.author_id)
                        .copied()
                        .unwrap_or(0) as f32,
                })
            })
            .collect()
    }

    /// Score candidates using feature-store gRPC client
    ///
    /// Fetches features from the feature-store service instead of requiring
    /// pre-fetched data. This is the recommended method when feature-store is deployed.
    ///
    /// # Arguments
    /// * `user_id` - Target user ID
    /// * `candidates` - List of candidate posts
    /// * `following_set` - Set of author_ids that user follows (from graph-service)
    /// * `interaction_history` - Map of author_id → interaction count (from analytics)
    pub async fn score_with_feature_store(
        &self,
        user_id: Uuid,
        candidates: Vec<CandidatePost>,
        following_set: HashSet<Uuid>,
        interaction_history: HashMap<Uuid, u32>,
    ) -> Result<Vec<ScoredCandidate>> {
        let feature_client = self.feature_store_client.as_ref().ok_or_else(|| {
            RankingError::FeatureExtractionError(
                "Feature-store client not configured".to_string(),
            )
        })?;

        if candidates.is_empty() {
            return Ok(vec![]);
        }

        if candidates.len() > MAX_BATCH_SIZE {
            warn!(
                "Batch size {} exceeds limit {}, truncating",
                candidates.len(),
                MAX_BATCH_SIZE
            );
        }

        let candidates = &candidates[..candidates.len().min(MAX_BATCH_SIZE)];

        info!(
            user_id = %user_id,
            candidate_count = candidates.len(),
            "Scoring candidates with feature-store"
        );

        // 1. Fetch user features from feature-store
        let user_features = match feature_client.get_user_features(&user_id.to_string()).await {
            Ok(features) => UserFeatures {
                follower_count: features.follower_count,
                post_count: features.post_count,
                engagement_rate: features.engagement_rate,
            },
            Err(e) => {
                warn!("Failed to fetch user features from feature-store: {}", e);
                // Fallback to defaults
                UserFeatures {
                    follower_count: 100,
                    post_count: 50,
                    engagement_rate: 0.5,
                }
            }
        };

        // 2. Batch fetch post features from feature-store
        let post_ids: Vec<String> = candidates.iter().map(|c| c.post_id.to_string()).collect();
        let post_features_result = feature_client.batch_get_post_features(&post_ids).await;

        let post_features_map: HashMap<Uuid, PostFeatures> = match post_features_result {
            Ok(features) => features
                .into_iter()
                .filter_map(|(id, f)| {
                    Uuid::parse_str(&id).ok().map(|uuid| {
                        (
                            uuid,
                            PostFeatures {
                                like_count: f.like_count,
                                comment_count: f.comment_count,
                                share_count: f.share_count,
                            },
                        )
                    })
                })
                .collect(),
            Err(e) => {
                warn!("Failed to fetch post features from feature-store: {}", e);
                HashMap::new()
            }
        };

        debug!(
            user_id = %user_id,
            user_follower_count = user_features.follower_count,
            post_features_count = post_features_map.len(),
            "Features fetched from feature-store"
        );

        // 3. Call the existing score_candidates with fetched data
        self.score_candidates(
            user_id,
            candidates.to_vec(),
            user_features,
            post_features_map,
            following_set,
            interaction_history,
        )
        .await
    }
}

/// Candidate post input
#[derive(Debug, Clone)]
pub struct CandidatePost {
    pub post_id: Uuid,
    pub author_id: Uuid,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

/// User features from feature-store
#[derive(Debug, Clone)]
pub struct UserFeatures {
    pub follower_count: u32,
    pub post_count: u32,
    pub engagement_rate: f32,
}

/// Post features from feature-store
#[derive(Debug, Clone)]
pub struct PostFeatures {
    pub like_count: u32,
    pub comment_count: u32,
    pub share_count: u32,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_test_scorer() -> RankingScorer {
        let model = Arc::new(RankingModel::heuristic());
        RankingScorer::new(model)
    }

    fn create_test_candidates() -> Vec<CandidatePost> {
        vec![
            CandidatePost {
                post_id: Uuid::new_v4(),
                author_id: Uuid::new_v4(),
                created_at: chrono::Utc::now() - chrono::Duration::hours(2),
            },
            CandidatePost {
                post_id: Uuid::new_v4(),
                author_id: Uuid::new_v4(),
                created_at: chrono::Utc::now() - chrono::Duration::hours(24),
            },
            CandidatePost {
                post_id: Uuid::new_v4(),
                author_id: Uuid::new_v4(),
                created_at: chrono::Utc::now() - chrono::Duration::hours(6),
            },
        ]
    }

    #[tokio::test]
    async fn test_score_candidates_basic() {
        let scorer = create_test_scorer();
        let candidates = create_test_candidates();

        let user_features = UserFeatures {
            follower_count: 1000,
            post_count: 500,
            engagement_rate: 0.8,
        };

        let post_features_map: HashMap<Uuid, PostFeatures> = candidates
            .iter()
            .enumerate()
            .map(|(i, c)| {
                (
                    c.post_id,
                    PostFeatures {
                        // Vary engagement: first post has high engagement
                        like_count: [100, 10, 50][i],
                        comment_count: [50, 5, 25][i],
                        share_count: [20, 2, 10][i],
                    },
                )
            })
            .collect();

        let following_set: HashSet<Uuid> = [candidates[0].author_id].iter().copied().collect();

        let interaction_history: HashMap<Uuid, u32> =
            [(candidates[0].author_id, 5)].iter().copied().collect();

        let scored = scorer
            .score_candidates(
                Uuid::new_v4(),
                candidates.clone(),
                user_features,
                post_features_map,
                following_set,
                interaction_history,
            )
            .await
            .unwrap();

        assert_eq!(scored.len(), 3);

        // First post should rank highest (high engagement + recent + following)
        assert_eq!(scored[0].post_id, candidates[0].post_id);

        // Scores should be in descending order
        assert!(scored[0].score >= scored[1].score);
        assert!(scored[1].score >= scored[2].score);
    }

    #[tokio::test]
    async fn test_score_empty_candidates() {
        let scorer = create_test_scorer();

        let scored = scorer
            .score_candidates(
                Uuid::new_v4(),
                vec![],
                UserFeatures {
                    follower_count: 100,
                    post_count: 50,
                    engagement_rate: 0.5,
                },
                HashMap::new(),
                HashSet::new(),
                HashMap::new(),
            )
            .await
            .unwrap();

        assert!(scored.is_empty());
    }

    #[tokio::test]
    async fn test_score_missing_post_features() {
        let scorer = create_test_scorer();
        let candidates = create_test_candidates();

        let user_features = UserFeatures {
            follower_count: 1000,
            post_count: 500,
            engagement_rate: 0.8,
        };

        // Missing post features for all candidates
        let result = scorer
            .score_candidates(
                Uuid::new_v4(),
                candidates,
                user_features,
                HashMap::new(), // Empty post features
                HashSet::new(),
                HashMap::new(),
            )
            .await;

        assert!(result.is_err());
        assert!(matches!(
            result,
            Err(RankingError::FeatureExtractionError(_))
        ));
    }

    #[tokio::test]
    async fn test_following_boost_effect() {
        let scorer = create_test_scorer();

        let author_id = Uuid::new_v4();
        let candidates = vec![CandidatePost {
            post_id: Uuid::new_v4(),
            author_id,
            created_at: chrono::Utc::now() - chrono::Duration::hours(5),
        }];

        let user_features = UserFeatures {
            follower_count: 1000,
            post_count: 500,
            engagement_rate: 0.8,
        };

        let post_features_map: HashMap<Uuid, PostFeatures> = [(
            candidates[0].post_id,
            PostFeatures {
                like_count: 50,
                comment_count: 25,
                share_count: 10,
            },
        )]
        .iter()
        .cloned()
        .collect();

        // Score with following
        let following_set: HashSet<Uuid> = [author_id].iter().copied().collect();
        let scored_with_following = scorer
            .score_candidates(
                Uuid::new_v4(),
                candidates.clone(),
                user_features.clone(),
                post_features_map.clone(),
                following_set,
                HashMap::new(),
            )
            .await
            .unwrap();

        // Score without following
        let scored_without_following = scorer
            .score_candidates(
                Uuid::new_v4(),
                candidates,
                user_features,
                post_features_map,
                HashSet::new(),
                HashMap::new(),
            )
            .await
            .unwrap();

        // Following should boost score by ~1.2x
        let ratio = scored_with_following[0].score / scored_without_following[0].score;
        assert!(
            (ratio - 1.2).abs() < 0.01,
            "Following boost should be ~1.2x, got {}",
            ratio
        );
    }

    #[test]
    fn test_feature_vector_conversion() {
        let features = CandidateFeatures {
            user_follower_count: 1000.0,
            user_post_count: 500.0,
            user_engagement_rate: 0.8,
            post_like_count: 100.0,
            post_comment_count: 50.0,
            post_share_count: 20.0,
            post_age_hours: 5.0,
            author_is_following: true,
            previous_interactions: 10.0,
        };

        let vector = features.to_vector();

        assert_eq!(vector.len(), 9);
        assert_eq!(vector[0], 1000.0); // user_follower_count
        assert_eq!(vector[3], 100.0); // post_like_count
        assert_eq!(vector[7], 1.0); // author_is_following (boolean → 1.0)
        assert_eq!(vector[8], 10.0); // previous_interactions
    }
}
