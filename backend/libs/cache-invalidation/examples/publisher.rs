//! Example: Publishing cache invalidation events
//!
//! Run with: cargo run --example publisher

use cache_invalidation::InvalidationPublisher;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    let redis_url = "redis://127.0.0.1:6379";
    let service_name = "user-service".to_string();

    println!("Creating publisher for service: {}", service_name);
    let publisher = InvalidationPublisher::new(redis_url, service_name).await?;

    // Example 1: Invalidate single user
    println!("\n1. Invalidating single user...");
    let subscribers = publisher.invalidate_user("user_123").await?;
    println!("   ✓ Notified {} subscribers", subscribers);

    // Example 2: Invalidate single post
    println!("\n2. Invalidating single post...");
    let subscribers = publisher.invalidate_post("post_456").await?;
    println!("   ✓ Notified {} subscribers", subscribers);

    // Example 3: Pattern-based invalidation (all feeds)
    println!("\n3. Invalidating all feeds...");
    let subscribers = publisher.invalidate_pattern("feed:*").await?;
    println!("   ✓ Notified {} subscribers", subscribers);

    // Example 4: Batch invalidation
    println!("\n4. Batch invalidating users...");
    let batch = vec![
        "user:1".to_string(),
        "user:2".to_string(),
        "user:3".to_string(),
        "user:4".to_string(),
        "user:5".to_string(),
    ];
    let subscribers = publisher.invalidate_batch(batch).await?;
    println!("   ✓ Notified {} subscribers", subscribers);

    // Example 5: Custom entity type
    println!("\n5. Invalidating custom entity...");
    let subscribers = publisher
        .invalidate_custom("session", "session_abc123")
        .await?;
    println!("   ✓ Notified {} subscribers", subscribers);

    // Example 6: Multiple rapid invalidations
    println!("\n6. Rapid invalidations (stress test)...");
    for i in 0..10 {
        publisher
            .invalidate_user(&format!("rapid_user_{}", i))
            .await?;
    }
    println!("   ✓ Sent 10 rapid invalidations");

    println!("\n✅ All examples completed successfully!");

    Ok(())
}
