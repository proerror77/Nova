#![cfg(feature = "legacy_recommendation_tests")]
//! Recommendation v2 排序流程測試
//!
//! 利用 `rank_with_context` API 驗證混合排序在冷啟動與有互動資料時的表現，
//! 測試過程僅操作記憶體資料，不依賴實體資料庫或 ClickHouse。

use anyhow::Result;
use std::collections::HashMap;
use tempfile::tempdir;
use user_service::services::recommendation_v2::{
    ab_testing::ABTestingFramework,
    collaborative_filtering::{CollaborativeFilteringModel, SimilarityMetric},
    content_based::ContentBasedModel,
    hybrid_ranker::{HybridRanker, HybridWeights},
    onnx_serving::ONNXModelServer,
    RecommendationConfig, RecommendationServiceV2, UserContext,
};
use uuid::Uuid;

fn lazy_pool() -> sqlx::Pool<sqlx::Postgres> {
    use sqlx::postgres::{PgConnectOptions, PgPoolOptions};
    let opts = PgConnectOptions::new()
        .host("localhost")
        .username("postgres")
        .database("nova_test");
    PgPoolOptions::new()
        .max_connections(1)
        .connect_lazy_with(opts)
}

async fn build_service(
    item_similarity: HashMap<Uuid, Vec<(Uuid, f64)>>,
    post_features: HashMap<Uuid, Vec<f32>>,
    vocab_size: usize,
) -> Result<RecommendationServiceV2> {
    let cf_model = CollaborativeFilteringModel {
        user_similarity: HashMap::new(),
        item_similarity,
        k_neighbors: 50,
        metric: SimilarityMetric::Cosine,
    };

    let cb_model = ContentBasedModel {
        post_features,
        user_profiles: HashMap::new(),
        vocab_size,
    };

    let hybrid_ranker = HybridRanker::new(
        cf_model.clone(),
        cb_model.clone(),
        HybridWeights::balanced(),
    )?;
    let ab_framework = ABTestingFramework::new().await?;

    let tmp = tempdir()?;
    let model_path = tmp.path().join("mock.onnx");
    std::fs::write(&model_path, b"mock")?;
    let onnx_server = ONNXModelServer::load(model_path.to_string_lossy().as_ref())?;

    let config = RecommendationConfig {
        collaborative_model_path: "".to_string(),
        content_model_path: "".to_string(),
        onnx_model_path: model_path.to_string_lossy().into_owned(),
        hybrid_weights: HybridWeights::balanced(),
        enable_ab_testing: false,
    };

    Ok(RecommendationServiceV2 {
        cf_model,
        cb_model,
        hybrid_ranker,
        ab_framework,
        onnx_server,
        db_pool: lazy_pool(),
        config,
        model_loaded_at: chrono::Utc::now(),
    })
}

#[tokio::test]
async fn cold_start_keeps_trending_order() -> Result<()> {
    let service = build_service(HashMap::new(), HashMap::new(), 0).await?;
    let user_id = Uuid::new_v4();
    let candidates = vec![Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4()];

    let ranked = service
        .rank_with_context(
            user_id,
            UserContext::default(),
            candidates.clone(),
            candidates.len(),
        )
        .await?;

    assert_eq!(ranked, candidates);
    Ok(())
}

#[tokio::test]
async fn collaborative_signal_reorders_candidates() -> Result<()> {
    let liked_post = Uuid::new_v4();
    let recommended_post = Uuid::new_v4();
    let secondary_post = Uuid::new_v4();

    let mut item_sim = HashMap::new();
    item_sim.insert(liked_post, vec![(recommended_post, 0.92)]);

    let service = build_service(item_sim, HashMap::new(), 0).await?;

    let context = UserContext {
        recent_posts: vec![liked_post],
        seen_posts: vec![liked_post],
        user_profile: Some(Vec::new()),
    };

    let candidates = vec![secondary_post, recommended_post];
    let ranked = service
        .rank_with_context(
            Uuid::new_v4(),
            context,
            candidates.clone(),
            candidates.len(),
        )
        .await?;

    assert_eq!(ranked.first().copied().unwrap(), recommended_post);
    assert!(ranked.contains(&secondary_post));
    Ok(())
}
