use graphql_gateway::security::{PersistedQueries, SecurityConfig};

#[tokio::test]
async fn test_sha256_hash_computation() {
    let query = "query GetUser { user { id name } }";
    let hash = PersistedQueries::compute_hash(query);

    // Hash should be 64 hex characters (256 bits)
    assert_eq!(hash.len(), 64);

    // Same query should produce same hash
    let hash2 = PersistedQueries::compute_hash(query);
    assert_eq!(hash, hash2);

    // Different query should produce different hash
    let different_query = "query GetPost { post { id title } }";
    let different_hash = PersistedQueries::compute_hash(different_query);
    assert_ne!(hash, different_hash);
}

#[tokio::test]
async fn test_persisted_queries_registration() {
    let pq = PersistedQueries::new(false, true);

    let query = "query GetUser { user { id name } }";
    let hash = PersistedQueries::compute_hash(query);

    // Register query
    pq.register(hash.clone(), query.to_string()).await;

    // Should be able to retrieve it
    let retrieved = pq.get(&hash).await;
    assert!(retrieved.is_some());
    assert_eq!(retrieved.unwrap(), query);
}

#[tokio::test]
async fn test_persisted_queries_load_from_file() {
    use std::io::Write;
    use tempfile::NamedTempFile;

    // Create temporary JSON file
    let mut temp_file = NamedTempFile::new().unwrap();
    let queries_json = r#"{
        "abc123": "query GetUser { user { id } }",
        "def456": "query GetPost { post { title } }"
    }"#;
    temp_file.write_all(queries_json.as_bytes()).unwrap();
    let path = temp_file.path().to_str().unwrap();

    // Load queries from file
    let pq = PersistedQueries::new(false, true);
    let result = pq.load_from_file(path).await;
    assert!(result.is_ok());

    // Should be able to retrieve queries
    let query1 = pq.get("abc123").await;
    assert!(query1.is_some());
    assert_eq!(query1.unwrap(), "query GetUser { user { id } }");

    let query2 = pq.get("def456").await;
    assert!(query2.is_some());
    assert_eq!(query2.unwrap(), "query GetPost { post { title } }");
}

#[tokio::test]
async fn test_persisted_queries_not_found() {
    let pq = PersistedQueries::new(false, true);

    // Query that was never registered
    let result = pq.get("nonexistent_hash").await;
    assert!(result.is_none());
}

#[tokio::test]
async fn test_allows_arbitrary_flag() {
    let pq_strict = PersistedQueries::new(false, true);
    assert!(!pq_strict.allows_arbitrary());

    let pq_permissive = PersistedQueries::new(true, true);
    assert!(pq_permissive.allows_arbitrary());
}

#[tokio::test]
async fn test_apq_enabled_flag() {
    let pq_with_apq = PersistedQueries::new(false, true);
    assert!(pq_with_apq.is_apq_enabled());

    let pq_without_apq = PersistedQueries::new(false, false);
    assert!(!pq_without_apq.is_apq_enabled());
}

#[test]
fn test_security_config_defaults() {
    let config = SecurityConfig::default();

    // Persisted queries enabled by default
    assert!(config.use_persisted_queries);

    // Arbitrary queries disabled in production
    assert!(!config.allow_arbitrary_queries);

    // APQ enabled by default
    assert!(config.enable_apq);

    // No default path
    assert!(config.persisted_queries_path.is_none());
}

#[test]
fn test_security_config_from_env() {
    // Set environment variables
    std::env::set_var("GRAPHQL_USE_PERSISTED_QUERIES", "true");
    std::env::set_var("GRAPHQL_ALLOW_ARBITRARY_QUERIES", "false");
    std::env::set_var("GRAPHQL_ENABLE_APQ", "true");
    std::env::set_var("GRAPHQL_PERSISTED_QUERIES_PATH", "/path/to/queries.json");

    let config = SecurityConfig::from_env().unwrap();

    assert!(config.use_persisted_queries);
    assert!(!config.allow_arbitrary_queries);
    assert!(config.enable_apq);
    assert_eq!(config.persisted_queries_path, Some("/path/to/queries.json".to_string()));

    // Cleanup
    std::env::remove_var("GRAPHQL_USE_PERSISTED_QUERIES");
    std::env::remove_var("GRAPHQL_ALLOW_ARBITRARY_QUERIES");
    std::env::remove_var("GRAPHQL_ENABLE_APQ");
    std::env::remove_var("GRAPHQL_PERSISTED_QUERIES_PATH");
}

#[tokio::test]
async fn test_concurrent_query_registration() {
    use std::sync::Arc;

    let pq = Arc::new(PersistedQueries::new(false, true));

    // Spawn 10 concurrent tasks registering queries
    let mut handles = vec![];
    for i in 0..10 {
        let pq_clone = Arc::clone(&pq);
        let handle = tokio::spawn(async move {
            let query = format!("query Test{} {{ user {{ id }} }}", i);
            let hash = PersistedQueries::compute_hash(&query);
            pq_clone.register(hash.clone(), query).await;
            hash
        });
        handles.push(handle);
    }

    // Wait for all tasks to complete
    let mut hashes = vec![];
    for handle in handles {
        let hash = handle.await.unwrap();
        hashes.push(hash);
    }

    // All queries should be retrievable
    for (i, hash) in hashes.iter().enumerate() {
        let query = pq.get(hash).await;
        assert!(query.is_some());
        assert_eq!(query.unwrap(), format!("query Test{} {{ user {{ id }} }}", i));
    }
}

#[tokio::test]
async fn test_hash_collision_resistance() {
    // Two very similar queries should have different hashes
    let query1 = "query GetUser { user { id name } }";
    let query2 = "query GetUser { user { id name  } }";  // Extra space

    let hash1 = PersistedQueries::compute_hash(query1);
    let hash2 = PersistedQueries::compute_hash(query2);

    // Even slight differences should produce different hashes
    assert_ne!(hash1, hash2);
}

#[tokio::test]
async fn test_empty_query_hash() {
    let empty_query = "";
    let hash = PersistedQueries::compute_hash(empty_query);

    // Should still produce a valid hash
    assert_eq!(hash.len(), 64);

    // Known SHA-256 hash of empty string
    let expected = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
    assert_eq!(hash, expected);
}
