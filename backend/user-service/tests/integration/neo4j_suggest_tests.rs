use user_service::services::graph::GraphService;
use user_service::config::GraphConfig;
use uuid::Uuid;

// This test requires a running Neo4j. It is ignored by default.
// Run with: cargo test --test neo4j_suggest_tests -- --ignored
#[actix_rt::test]
#[ignore]
async fn test_neo4j_friends_of_friends() {
    let uri = std::env::var("NEO4J_URI").unwrap_or_else(|_| "bolt://localhost:7687".into());
    let user = std::env::var("NEO4J_USER").unwrap_or_else(|_| "neo4j".into());
    let pass = std::env::var("NEO4J_PASSWORD").unwrap_or_else(|_| "neo4j".into());

    let cfg = GraphConfig {
        enabled: true,
        neo4j_uri: uri,
        neo4j_user: user,
        neo4j_password: pass,
    };

    let graph = GraphService::new(&cfg).await.expect("graph init");
    assert!(graph.is_enabled());

    // Users: A -> B -> C, expect suggestion for A => C
    let a = Uuid::new_v4();
    let b = Uuid::new_v4();
    let c = Uuid::new_v4();

    graph.follow(a, b).await.expect("A->B");
    graph.follow(b, c).await.expect("B->C");

    let suggestions = graph.suggested_friends(a, 10).await.expect("suggest");
    let ids: Vec<Uuid> = suggestions.into_iter().map(|(id, _)| id).collect();
    assert!(ids.contains(&c));
}

