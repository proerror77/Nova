//! Example: Integration with service (user-service)
//!
//! Shows how to integrate cache invalidation into a service
//! Run with: cargo run --example integration

use cache_invalidation::InvalidationPublisher;
use std::sync::Arc;

/// Simulated user service with cache invalidation
struct UserService {
    publisher: Arc<InvalidationPublisher>,
}

impl UserService {
    async fn new(redis_url: &str) -> anyhow::Result<Self> {
        let publisher = InvalidationPublisher::new(redis_url, "user-service".to_string()).await?;

        Ok(Self {
            publisher: Arc::new(publisher),
        })
    }

    /// Update user profile (after DB commit)
    async fn update_user_profile(
        &self,
        user_id: &str,
        _new_data: serde_json::Value,
    ) -> anyhow::Result<()> {
        println!("📝 Updating user profile in database: {}", user_id);

        // 1. Update database (simulated)
        tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;
        println!("   ✓ Database updated");

        // 2. Invalidate cache AFTER successful DB commit
        println!("   🗑️  Invalidating cache for user:{}", user_id);
        self.publisher.invalidate_user(user_id).await?;
        println!("   ✓ Cache invalidation published");

        Ok(())
    }

    /// Delete user (cascade invalidation)
    async fn delete_user(&self, user_id: &str) -> anyhow::Result<()> {
        println!("🗑️  Deleting user: {}", user_id);

        // 1. Delete from database
        tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;
        println!("   ✓ Database deletion completed");

        // 2. Invalidate user cache
        self.publisher.invalidate_user(user_id).await?;
        println!("   ✓ User cache invalidated");

        // 3. Invalidate related caches (feeds, notifications, etc.)
        self.publisher
            .invalidate_pattern(&format!("feed:{}:*", user_id))
            .await?;
        println!("   ✓ Feed cache invalidated");

        self.publisher
            .invalidate_pattern(&format!("notification:{}:*", user_id))
            .await?;
        println!("   ✓ Notification cache invalidated");

        Ok(())
    }

    /// Batch update users
    async fn batch_update_users(&self, user_ids: Vec<String>) -> anyhow::Result<()> {
        println!("📝 Batch updating {} users", user_ids.len());

        // 1. Batch update database
        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
        println!("   ✓ Batch database update completed");

        // 2. Batch invalidate caches
        let cache_keys: Vec<String> = user_ids.iter().map(|id| format!("user:{}", id)).collect();

        self.publisher.invalidate_batch(cache_keys).await?;
        println!("   ✓ Batch cache invalidation published");

        Ok(())
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    let redis_url = "redis://127.0.0.1:6379";

    println!("🚀 Starting User Service with Cache Invalidation\n");

    let service = UserService::new(redis_url).await?;

    // Example 1: Single user update
    println!("\n=== Example 1: Single User Update ===");
    service
        .update_user_profile("user_123", serde_json::json!({"name": "John Doe"}))
        .await?;

    tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;

    // Example 2: User deletion (cascade)
    println!("\n=== Example 2: User Deletion (Cascade) ===");
    service.delete_user("user_456").await?;

    tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;

    // Example 3: Batch update
    println!("\n=== Example 3: Batch User Update ===");
    let user_ids = vec![
        "user_001".to_string(),
        "user_002".to_string(),
        "user_003".to_string(),
        "user_004".to_string(),
        "user_005".to_string(),
    ];
    service.batch_update_users(user_ids).await?;

    println!("\n✅ All service operations completed successfully!");
    println!("\n💡 Best Practices Demonstrated:");
    println!("   1. Invalidate AFTER database commit (not before)");
    println!("   2. Use cascade invalidation for related entities");
    println!("   3. Use batch invalidation for multiple entities");
    println!("   4. Always handle invalidation errors gracefully");

    Ok(())
}
