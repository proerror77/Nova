//! Concurrency tests for atomic rate limiter using Redis + Lua via testcontainers
#![cfg(test)]

use testcontainers::{clients::Cli, images::generic::GenericImage, RunnableImage, core::WaitFor};
use redis::aio::ConnectionManager;
use user_service::middleware::rate_limit::{RateLimitConfig, RateLimiter};
use std::sync::Arc;

async fn make_rate_limiter(redis_url: &str, max_requests: u32, window_secs: u64) -> RateLimiter {
    let client = redis::Client::open(redis_url).expect("redis client");
    let manager = ConnectionManager::new(client)
        .await
        .expect("redis connection manager");
    let cfg = RateLimitConfig {
        max_requests,
        window_seconds: window_secs,
    };
    RateLimiter::new(manager, cfg)
}

#[tokio::test]
async fn test_atomic_rate_limit_under_concurrency() {
    let docker = Cli::default();
    let image = GenericImage::new("redis", "7-alpine").with_wait_for(WaitFor::message("Ready to accept connections"));
    let node = docker.run(RunnableImage::from(image));
    let port = node.get_host_port_ipv4(6379);
    let redis_url = format!("redis://127.0.0.1:{}", port);

    let limiter = make_rate_limiter(&redis_url, 30, 10).await;
    let limiter = Arc::new(limiter);

    let client_id = "concurrent-client";
    let total = 100usize;
    let mut handles = Vec::with_capacity(total);

    for _ in 0..total {
        let l = limiter.clone();
        let cid = client_id.to_string();
        handles.push(tokio::spawn(async move { l.is_rate_limited(&cid).await.unwrap() }));
    }

    let results = futures::future::join_all(handles).await;
    let mut allowed = 0usize;
    let mut denied = 0usize;
    for r in results {
        let limited = r.expect("join ok");
        if limited { denied += 1 } else { allowed += 1 }
    }

    // At most max_requests should pass within window
    assert!(allowed <= 30, "allowed {} should be <= 30", allowed);
    assert!(denied + allowed == total);
}

