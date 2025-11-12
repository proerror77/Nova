//! Example: Subscribing to cache invalidation events
//!
//! Run with: cargo run --example subscriber

use cache_invalidation::{EntityType, InvalidationAction, InvalidationSubscriber};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    let redis_url = "redis://127.0.0.1:6379";

    println!("Creating subscriber...");
    let subscriber = InvalidationSubscriber::new(redis_url).await?;

    println!("✓ Subscriber created. Listening for invalidation events...\n");

    // Subscribe with callback that handles different message types
    let handle = subscriber
        .subscribe(|msg| async move {
            println!("\n📨 Received invalidation from {}:", msg.source_service);
            println!("   Message ID: {}", msg.message_id);
            println!("   Entity Type: {}", msg.entity_type);
            println!("   Action: {:?}", msg.action);
            println!("   Timestamp: {}", msg.timestamp);

            match msg.action {
                InvalidationAction::Delete => {
                    if let Some(entity_id) = &msg.entity_id {
                        println!("   → Deleting cache for: {}:{}", msg.entity_type, entity_id);
                        // Simulate cache deletion
                        simulate_cache_deletion(&msg.entity_type, entity_id).await;
                    }
                }
                InvalidationAction::Update => {
                    if let Some(entity_id) = &msg.entity_id {
                        println!(
                            "   → Refreshing cache for: {}:{}",
                            msg.entity_type, entity_id
                        );
                        // Simulate cache refresh
                        simulate_cache_refresh(&msg.entity_type, entity_id).await;
                    }
                }
                InvalidationAction::Pattern => {
                    if let Some(pattern) = &msg.pattern {
                        println!("   → Deleting cache with pattern: {}", pattern);
                        // Simulate pattern-based deletion
                        simulate_pattern_deletion(pattern).await;
                    }
                }
                InvalidationAction::Batch => {
                    if let Some(entity_ids) = &msg.entity_ids {
                        println!("   → Batch deleting {} cache entries", entity_ids.len());
                        for entity_id in entity_ids {
                            simulate_cache_deletion(&msg.entity_type, entity_id).await;
                        }
                    }
                }
            }

            println!("   ✓ Cache invalidation completed");

            Ok(())
        })
        .await?;

    println!("\n🎧 Subscriber running. Press Ctrl+C to stop.\n");

    // Wait for Ctrl+C
    tokio::signal::ctrl_c().await?;

    println!("\n\n👋 Shutting down subscriber...");
    handle.abort();

    Ok(())
}

// Simulate cache deletion from Redis + in-memory cache
async fn simulate_cache_deletion(entity_type: &EntityType, entity_id: &str) {
    // In real implementation:
    // 1. Delete from Redis: redis.del(format!("{}:{}", entity_type, entity_id)).await?
    // 2. Delete from memory cache: dashmap.remove(&format!("{}:{}", entity_type, entity_id))

    tokio::time::sleep(tokio::time::Duration::from_millis(5)).await;
    println!("      • Deleted from Redis");
    println!("      • Deleted from memory cache");
}

// Simulate cache refresh
async fn simulate_cache_refresh(entity_type: &EntityType, entity_id: &str) {
    // In real implementation:
    // 1. Fetch fresh data from database
    // 2. Update Redis cache
    // 3. Update memory cache if exists

    tokio::time::sleep(tokio::time::Duration::from_millis(10)).await;
    println!(
        "      • Refreshed {}:{} from database",
        entity_type, entity_id
    );
}

// Simulate pattern-based deletion
async fn simulate_pattern_deletion(pattern: &str) {
    // In real implementation:
    // 1. KEYS pattern -> get all matching keys
    // 2. DEL all matching keys from Redis
    // 3. Clear matching entries from memory cache

    tokio::time::sleep(tokio::time::Duration::from_millis(20)).await;
    println!("      • Found and deleted all matching keys: {}", pattern);
}
