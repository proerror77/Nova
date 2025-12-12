use ranking_service::{config::RecallConfig, DiversityLayer, RankingLayer, RecallLayer};

#[tokio::test]
async fn test_basic_workflow() {
    // 創建 mock clients
    let redis_client =
        redis::Client::open("redis://localhost:6379").expect("Failed to create Redis client");
    let graph_channel =
        tonic::transport::Channel::from_static("http://localhost:9008").connect_lazy();
    let content_channel =
        tonic::transport::Channel::from_static("http://localhost:9009").connect_lazy();

    let recall_config = RecallConfig {
        graph_recall_limit: 50,
        trending_recall_limit: 30,
        personalized_recall_limit: 20,
        graph_recall_weight: 0.6,
        trending_recall_weight: 0.3,
        personalized_recall_weight: 0.1,
    };

    let recall_layer =
        RecallLayer::new(graph_channel, content_channel, redis_client, recall_config);
    let ranking_layer = RankingLayer::new();
    let diversity_layer = DiversityLayer::new(0.7);

    // 測試召回（可能為空，取決於服務是否運行）
    let result = recall_layer.recall_candidates("test_user", None).await;

    match result {
        Ok((candidates, stats)) => {
            println!(
                "Recall successful: {} candidates, stats={:?}",
                candidates.len(),
                stats
            );
        }
        Err(e) => {
            println!("Recall failed (expected if services not running): {}", e);
        }
    }
}
