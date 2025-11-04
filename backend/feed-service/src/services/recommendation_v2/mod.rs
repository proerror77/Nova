// ============================================
// Recommendation Algorithm v2.0 - Module Root
// ============================================
//
// This module implements a hybrid recommendation engine combining:
// 1. Collaborative Filtering (user-user, item-item)
// 2. Content-Based Filtering (TF-IDF features + user profiles)
// 3. Hybrid Ranking (weighted combination + diversity optimization)
// 4. A/B Testing Framework (user bucketing + experiment tracking)
// 5. Real-Time Model Serving (ONNX inference with fallback)
//
// Architecture:
//   User Request → A/B Framework → Hybrid Ranker → ONNX Inference → Ranked Feed
//                                     ↓
//                         Collaborative Model + Content Model
//                                     ↓
//                         Fallback to v1.0 (if failure)

pub mod ab_testing;
pub mod collaborative_filtering;
pub mod content_based;
pub mod hybrid_ranker;
pub mod onnx_serving;

pub use ab_testing::{ABTestingFramework, Experiment, ExperimentEvent, Variant};
pub use collaborative_filtering::{CollaborativeFilteringModel, SimilarityMetric};
pub use content_based::{ContentBasedModel, PostFeatures, UserProfile};
pub use hybrid_ranker::{HybridRanker, HybridWeights, RankedPost, RankingStrategy};
pub use onnx_serving::{LatencyStats, ONNXModelServer};

use crate::error::Result;
use chrono::{DateTime, Utc};
use sqlx::{PgPool, Row};
use std::collections::{HashMap, HashSet};
use tracing::{info, warn};
use uuid::Uuid;

const DEFAULT_K_NEIGHBORS: usize = 50;
const MAX_RECOMMENDATION_LIMIT: usize = 100;
const CANDIDATE_MULTIPLIER: usize = 4;
const MIN_CANDIDATE_POOL: usize = 32;
const USER_HISTORY_MIN: i64 = 50;
const USER_HISTORY_MAX: i64 = 200;

/// Unified recommendation service v2.0
pub struct RecommendationServiceV2 {
    pub cf_model: CollaborativeFilteringModel,
    pub cb_model: ContentBasedModel,
    pub hybrid_ranker: HybridRanker,
    pub ab_framework: ABTestingFramework,
    pub onnx_server: ONNXModelServer,
    pub vector_search: Option<crate::services::VectorSearchService>,
    db_pool: PgPool,
    config: RecommendationConfig,
    model_loaded_at: DateTime<Utc>,
}

impl RecommendationServiceV2 {
    /// Initialize recommendation service (load models)
    pub async fn new(config: RecommendationConfig, db_pool: PgPool) -> Result<Self> {
        let (cf_model, cb_model) = Self::load_models_from_config(&config)?;
        let hybrid_ranker =
            HybridRanker::new(cf_model.clone(), cb_model.clone(), config.hybrid_weights)?;

        let ab_framework = ABTestingFramework::new().await?;
        let onnx_server = ONNXModelServer::load(&config.onnx_model_path)?;

        // Initialize vector search service with Milvus
        let vector_search = match std::env::var("MILVUS_URL") {
            Ok(milvus_url) => {
                let vs = crate::services::VectorSearchService::new(milvus_url, 768);
                if let Err(e) = vs.initialize_collection().await {
                    warn!("Failed to initialize Milvus collection: {:?}", e);
                    None
                } else {
                    info!("Vector search service initialized successfully");
                    Some(vs)
                }
            }
            Err(_) => {
                info!("MILVUS_URL not configured, vector search disabled");
                None
            }
        };

        Ok(Self {
            cf_model,
            cb_model,
            hybrid_ranker,
            ab_framework,
            onnx_server,
            vector_search,
            db_pool,
            config,
            model_loaded_at: Utc::now(),
        })
    }

    /// Get personalized recommendations for user
    pub async fn get_recommendations(&self, user_id: Uuid, limit: usize) -> Result<Vec<Uuid>> {
        if limit == 0 {
            return Ok(Vec::new());
        }

        let limit = limit.min(MAX_RECOMMENDATION_LIMIT).max(1);

        let context = match self.build_user_context(user_id, limit).await {
            Ok(ctx) => ctx,
            Err(err) => {
                warn!("Failed to build user context for {}: {}", user_id, err);
                UserContext::default()
            }
        };

        let candidates = match self.collect_candidates(user_id, limit, &context).await {
            Ok(list) if !list.is_empty() => list,
            Ok(_) => {
                self.fetch_trending_posts(Some(user_id), limit.saturating_mul(2))
                    .await?
            }
            Err(err) => {
                warn!("Candidate collection failed: {}", err);
                self.fetch_trending_posts(Some(user_id), limit.saturating_mul(2))
                    .await?
            }
        };

        if candidates.is_empty() {
            return Ok(Vec::new());
        }

        let ranked = match self
            .hybrid_ranker
            .recommend(user_id, candidates.clone(), limit, Some(&context))
            .await
        {
            Ok(res) if !res.is_empty() => res,
            Ok(_) => Vec::new(),
            Err(err) => {
                warn!("Hybrid ranking failed: {}", err);
                Vec::new()
            }
        };

        let mut ordered: Vec<Uuid> = ranked.into_iter().map(|p| p.post_id).collect();
        if ordered.len() < limit {
            let mut existing: HashSet<Uuid> = ordered.iter().copied().collect();
            for post_id in &candidates {
                if ordered.len() >= limit {
                    break;
                }
                if existing.insert(*post_id) {
                    ordered.push(*post_id);
                }
            }
        } else {
            ordered.truncate(limit);
        }

        Ok(ordered)
    }

    /// 直接使用既有候選與使用者上下文進行排序（測試與工具用途）
    pub async fn rank_with_context(
        &self,
        user_id: Uuid,
        context: UserContext,
        candidates: Vec<Uuid>,
        limit: usize,
    ) -> Result<Vec<Uuid>> {
        if candidates.is_empty() {
            return Ok(Vec::new());
        }

        let limit = limit.min(MAX_RECOMMENDATION_LIMIT).max(1);
        let ranked = self
            .hybrid_ranker
            .recommend(user_id, candidates.clone(), limit, Some(&context))
            .await?;

        let mut ordered: Vec<Uuid> = ranked.into_iter().map(|p| p.post_id).collect();
        if ordered.len() < limit {
            let mut existing: HashSet<Uuid> = ordered.iter().copied().collect();
            for post_id in &candidates {
                if ordered.len() >= limit {
                    break;
                }
                if existing.insert(*post_id) {
                    ordered.push(*post_id);
                }
            }
        } else {
            ordered.truncate(limit);
        }

        Ok(ordered)
    }

    /// Reload models (hot-reload for version updates)
    pub async fn reload_models(&mut self) -> Result<()> {
        let (cf_model, cb_model) = Self::load_models_from_config(&self.config)?;
        self.hybrid_ranker = HybridRanker::new(
            cf_model.clone(),
            cb_model.clone(),
            self.config.hybrid_weights,
        )?;
        self.cf_model = cf_model;
        self.cb_model = cb_model;
        self.model_loaded_at = Utc::now();
        info!("Recommendation models reloaded");
        Ok(())
    }

    /// Get model version info
    pub async fn get_model_info(&self) -> ModelInfo {
        let meta = self.cf_model.metadata();
        let collaborative_version = format!(
            "users:{} items:{} k:{}",
            meta.user_count, meta.item_count, meta.k_neighbors
        );

        let content_version = format!(
            "posts:{} vocab:{}",
            self.cb_model.post_features.len(),
            self.cb_model.vocab_size
        );

        ModelInfo {
            collaborative_version,
            content_version,
            onnx_version: self.onnx_server.version().await,
            deployed_at: self.model_loaded_at,
        }
    }

    /// Search semantically similar posts using vector embeddings
    pub async fn search_semantically_similar(
        &self,
        post_id: Uuid,
        limit: usize,
    ) -> Result<Vec<crate::services::VectorSearchResult>> {
        if let Some(ref vector_search) = self.vector_search {
            vector_search
                .search_similar_by_post(post_id, limit, 0.5)
                .await
        } else {
            warn!("Vector search service not available");
            Ok(Vec::new())
        }
    }

    /// Index a post embedding for semantic search
    pub async fn index_post_embedding(
        &self,
        embedding: crate::services::PostEmbedding,
    ) -> Result<()> {
        if let Some(ref vector_search) = self.vector_search {
            vector_search.index_embedding(embedding).await
        } else {
            warn!("Vector search service not available, skipping embedding index");
            Ok(())
        }
    }

    /// Batch index multiple post embeddings
    pub async fn batch_index_embeddings(
        &self,
        embeddings: Vec<crate::services::PostEmbedding>,
    ) -> Result<usize> {
        if let Some(ref vector_search) = self.vector_search {
            vector_search.batch_index_embeddings(embeddings).await
        } else {
            warn!("Vector search service not available, skipping batch embedding index");
            Ok(0)
        }
    }

    /// Get vector search cache statistics
    pub async fn get_vector_cache_stats(&self) -> (usize, usize) {
        if let Some(ref vector_search) = self.vector_search {
            vector_search.cache_stats().await
        } else {
            (0, 0)
        }
    }

    /// Clear vector search cache
    pub async fn clear_vector_cache(&self) {
        if let Some(ref vector_search) = self.vector_search {
            vector_search.clear_cache().await;
        }
    }

    fn load_models_from_config(
        config: &RecommendationConfig,
    ) -> Result<(CollaborativeFilteringModel, ContentBasedModel)> {
        let cf_model = CollaborativeFilteringModel::load(
            config.collaborative_model_path.as_str(),
            config.collaborative_model_path.as_str(),
            DEFAULT_K_NEIGHBORS,
        )?;

        let post_features = if config.content_model_path.is_empty() {
            HashMap::new()
        } else {
            ContentBasedModel::load_post_features(&config.content_model_path)?
        };

        let vocab_size = post_features
            .values()
            .next()
            .map(|vec| vec.len())
            .unwrap_or(0);

        let cb_model = ContentBasedModel {
            post_features,
            user_profiles: HashMap::new(),
            vocab_size,
        };

        Ok((cf_model, cb_model))
    }

    async fn build_user_context(&self, user_id: Uuid, limit: usize) -> Result<UserContext> {
        let fetch_limit = (limit as i64 * 3).clamp(USER_HISTORY_MIN, USER_HISTORY_MAX);

        let mut seen_posts: HashSet<Uuid> = HashSet::new();
        let mut recent_posts = Vec::new();
        let mut weights: HashMap<Uuid, f32> = HashMap::new();

        let like_rows = sqlx::query(
            "SELECT post_id FROM likes WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2",
        )
        .bind(user_id)
        .bind(fetch_limit)
        .fetch_all(&self.db_pool)
        .await?;

        for row in like_rows {
            let post_id: Uuid = row.try_get("post_id")?;
            if seen_posts.insert(post_id) {
                recent_posts.push(post_id);
            }
            *weights.entry(post_id).or_insert(0.0) += 1.0;
        }

        let comment_rows = sqlx::query(
            "SELECT post_id FROM comments WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2",
        )
        .bind(user_id)
        .bind(fetch_limit)
        .fetch_all(&self.db_pool)
        .await?;

        for row in comment_rows {
            let post_id: Uuid = row.try_get("post_id")?;
            if seen_posts.insert(post_id) {
                recent_posts.push(post_id);
            }
            *weights.entry(post_id).or_insert(0.0) += 2.0;
        }

        let own_posts = sqlx::query(
            "SELECT id FROM posts WHERE user_id = $1 AND soft_delete IS NULL ORDER BY created_at DESC LIMIT $2",
        )
        .bind(user_id)
        .bind(fetch_limit)
        .fetch_all(&self.db_pool)
        .await?;

        for row in own_posts {
            let post_id: Uuid = row.try_get("id")?;
            seen_posts.insert(post_id);
        }

        if recent_posts.len() > USER_HISTORY_MAX as usize {
            recent_posts.truncate(USER_HISTORY_MAX as usize);
        }

        let weighted_posts: Vec<(Uuid, f32)> = weights.into_iter().collect();
        let user_profile = self.cb_model.aggregate_profile(&weighted_posts);

        Ok(UserContext {
            recent_posts,
            seen_posts: seen_posts.into_iter().collect(),
            user_profile,
        })
    }

    async fn collect_candidates(
        &self,
        user_id: Uuid,
        limit: usize,
        context: &UserContext,
    ) -> Result<Vec<Uuid>> {
        let target = std::cmp::max(
            limit.saturating_mul(CANDIDATE_MULTIPLIER),
            MIN_CANDIDATE_POOL,
        );

        let seen: HashSet<Uuid> = context.seen_posts.iter().copied().collect();
        let mut added: HashSet<Uuid> = HashSet::new();
        let mut ordered = Vec::new();

        if !context.recent_posts.is_empty() {
            let cf_candidates = self.cf_model.recommend_item_based(
                &context.recent_posts,
                &context.seen_posts,
                target,
            )?;

            for (post_id, _) in cf_candidates {
                if seen.contains(&post_id) {
                    continue;
                }
                if added.insert(post_id) {
                    ordered.push(post_id);
                }
            }
        }

        let trending = self.fetch_trending_posts(Some(user_id), target).await?;
        for post_id in trending {
            if seen.contains(&post_id) {
                continue;
            }
            if added.insert(post_id) {
                ordered.push(post_id);
            }
        }

        if ordered.len() < target {
            let recent = self.fetch_recent_posts(Some(user_id), target).await?;
            for post_id in recent {
                if seen.contains(&post_id) {
                    continue;
                }
                if added.insert(post_id) {
                    ordered.push(post_id);
                }
                if ordered.len() >= target {
                    break;
                }
            }
        }

        ordered.truncate(target);
        Ok(ordered)
    }

    async fn fetch_trending_posts(
        &self,
        exclude_user: Option<Uuid>,
        limit: usize,
    ) -> Result<Vec<Uuid>> {
        let limit = std::cmp::max(limit, MIN_CANDIDATE_POOL) as i64;

        let rows = if let Some(user_id) = exclude_user {
            sqlx::query(
                "SELECT p.id
                 FROM posts p
                 JOIN post_metadata pm ON pm.post_id = p.id
                 WHERE p.status = 'published'
                   AND p.soft_delete IS NULL
                   AND p.user_id <> $1
                 ORDER BY (pm.like_count * 3 + pm.comment_count * 2 + pm.view_count) DESC,
                          p.created_at DESC
                 LIMIT $2",
            )
            .bind(user_id)
            .bind(limit)
            .fetch_all(&self.db_pool)
            .await?
        } else {
            sqlx::query(
                "SELECT p.id
                 FROM posts p
                 JOIN post_metadata pm ON pm.post_id = p.id
                 WHERE p.status = 'published' AND p.soft_delete IS NULL
                 ORDER BY (pm.like_count * 3 + pm.comment_count * 2 + pm.view_count) DESC,
                          p.created_at DESC
                 LIMIT $1",
            )
            .bind(limit)
            .fetch_all(&self.db_pool)
            .await?
        };

        let mut posts = Vec::new();
        for row in rows {
            let post_id: Uuid = row.try_get("id")?;
            posts.push(post_id);
        }

        Ok(posts)
    }

    async fn fetch_recent_posts(
        &self,
        exclude_user: Option<Uuid>,
        limit: usize,
    ) -> Result<Vec<Uuid>> {
        let limit = std::cmp::max(limit, MIN_CANDIDATE_POOL) as i64;

        let rows = if let Some(user_id) = exclude_user {
            sqlx::query(
                "SELECT id
                 FROM posts
                 WHERE status = 'published'
                   AND soft_delete IS NULL
                   AND user_id <> $1
                 ORDER BY created_at DESC
                 LIMIT $2",
            )
            .bind(user_id)
            .bind(limit)
            .fetch_all(&self.db_pool)
            .await?
        } else {
            sqlx::query(
                "SELECT id
                 FROM posts
                 WHERE status = 'published' AND soft_delete IS NULL
                 ORDER BY created_at DESC
                 LIMIT $1",
            )
            .bind(limit)
            .fetch_all(&self.db_pool)
            .await?
        };

        let mut posts = Vec::new();
        for row in rows {
            let post_id: Uuid = row.try_get("id")?;
            posts.push(post_id);
        }

        Ok(posts)
    }
}

#[derive(Debug, Clone)]
pub struct RecommendationConfig {
    pub collaborative_model_path: String,
    pub content_model_path: String,
    pub onnx_model_path: String,
    pub hybrid_weights: HybridWeights,
    pub enable_ab_testing: bool,
}

#[derive(Debug, Clone)]
pub struct ModelInfo {
    pub collaborative_version: String,
    pub content_version: String,
    pub onnx_version: String,
    pub deployed_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Default, Clone)]
pub struct UserContext {
    pub recent_posts: Vec<Uuid>,
    pub seen_posts: Vec<Uuid>,
    pub user_profile: Option<Vec<f32>>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_recommendation_service_init() {
        // TODO: Test initialization
    }

    #[tokio::test]
    async fn test_get_recommendations() {
        // TODO: Test recommendation pipeline
    }
}
