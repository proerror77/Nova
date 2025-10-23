use messaging_service::cache::new_redis_client;

#[test]
fn builds_redis_client_from_url() {
    let url = "redis://127.0.0.1:6379";
    // Client build should not panic; connection may fail later which is fine for unit test
    let client = new_redis_client(url);
    assert!(client.is_ok());
}

