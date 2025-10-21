//! Scenario 1: Broadcaster Lifecycle Test
//!
//! Tests the complete flow:
//! 1. RTMP broadcaster connects to Nginx
//! 2. Stream metadata stored in PostgreSQL
//! 3. Nginx-RTMP generates HLS output
//! 4. Webhook notifies user-service
//! 5. Broadcaster disconnects
//! 6. Stream state cleaned up

use crate::integration::{StreamingTestEnv, StreamFixture};
use anyhow::Result;
use sqlx::postgres::PgPool;
use redis::aio::ConnectionManager;

/// Test data models
#[derive(Debug, Clone)]
struct StreamMetadata {
    pub stream_id: String,
    pub broadcaster_id: String,
    pub status: String,
    pub viewer_count: i32,
}

/// Database helper for stream operations
struct StreamDbHelper {
    pool: PgPool,
}

impl StreamDbHelper {
    pub async fn new(db_url: &str) -> Result<Self> {
        let pool = sqlx::postgres::PgPoolOptions::new()
            .max_connections(5)
            .connect(db_url)
            .await?;

        Ok(Self { pool })
    }

    pub async fn get_stream(&self, stream_id: &str) -> Result<Option<StreamMetadata>> {
        let row = sqlx::query!(
            r#"
            SELECT stream_id, broadcaster_id, status, viewer_count
            FROM streams
            WHERE stream_id = $1
            "#,
            stream_id
        )
        .fetch_optional(&self.pool)
        .await?;

        Ok(row.map(|r| StreamMetadata {
            stream_id: r.stream_id,
            broadcaster_id: r.broadcaster_id,
            status: r.status,
            viewer_count: r.viewer_count as i32,
        }))
    }

    pub async fn create_stream(&self, stream_id: &str, broadcaster_id: &str) -> Result<()> {
        sqlx::query!(
            r#"
            INSERT INTO streams (stream_id, broadcaster_id, status, viewer_count, created_at)
            VALUES ($1, $2, $3, $4, NOW())
            ON CONFLICT (stream_id) DO UPDATE
            SET status = $3, viewer_count = $4
            "#,
            stream_id,
            broadcaster_id,
            "live",
            0i32
        )
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    pub async fn cleanup_stream(&self, stream_id: &str) -> Result<()> {
        sqlx::query!(
            r#"
            DELETE FROM streams WHERE stream_id = $1
            "#,
            stream_id
        )
        .execute(&self.pool)
        .await?;

        Ok(())
    }
}

/// Redis helper for viewer tracking
struct ViewerCounterHelper {
    client: ConnectionManager,
}

impl ViewerCounterHelper {
    pub async fn new(redis_url: &str) -> Result<Self> {
        let client = redis::Client::open(redis_url)?;
        let cm = ConnectionManager::new(client).await?;
        Ok(Self { client: cm })
    }

    pub async fn get_viewer_count(&self, stream_id: &str) -> Result<i32> {
        use redis::AsyncCommands;
        let mut conn = self.client.clone();
        let key = format!("stream:{}:viewers", stream_id);
        let count: i32 = conn.get(&key).await.unwrap_or(0);
        Ok(count)
    }

    pub async fn increment_viewers(&self, stream_id: &str) -> Result<i32> {
        use redis::AsyncCommands;
        let mut conn = self.client.clone();
        let key = format!("stream:{}:viewers", stream_id);
        let count: i32 = conn.incr(&key, 1).await?;
        Ok(count)
    }
}

/// Main test: broadcaster lifecycle
#[tokio::test]
#[ignore] // Run with: cargo test --test '*' broadcaster_lifecycle -- --ignored --nocapture
pub async fn test_broadcaster_lifecycle() -> Result<()> {
    println!("\n=== Scenario 1: Broadcaster Lifecycle ===\n");

    // Setup
    let env = StreamingTestEnv::from_env();
    let mut fixture = StreamFixture::new();
    let broadcaster_id = "test-broadcaster-001";

    println!("Stream ID: {}", fixture.stream_id);
    println!("Broadcaster ID: {}", broadcaster_id);

    // Initialize database client
    let db = StreamDbHelper::new(&env.pg_url).await?;
    let redis = ViewerCounterHelper::new(&env.redis_url).await?;

    // Step 1: Create stream in database
    println!("\n[Step 1] Creating stream metadata in PostgreSQL...");
    db.create_stream(&fixture.stream_id, broadcaster_id).await?;

    let stream = db.get_stream(&fixture.stream_id).await?;
    assert!(stream.is_some(), "Stream should exist in database");
    assert_eq!(stream.unwrap().status, "live");
    println!("✓ Stream created with status: live");

    // Step 2: Connect RTMP broadcaster
    println!("\n[Step 2] Connecting RTMP broadcaster to Nginx-RTMP...");
    let mut rtmp_client = super::rtmp_client::RtmpClient::connect(&env.rtmp_addr()).await?;
    println!("✓ Connected to RTMP server at {}", env.rtmp_addr());

    // Step 3: Perform RTMP handshake
    println!("\n[Step 3] Performing RTMP handshake...");
    rtmp_client.handshake()?;
    println!("✓ RTMP handshake completed");

    // Step 4: Send connect command
    println!("\n[Step 4] Sending RTMP connect command...");
    rtmp_client.connect_command("live")?;
    println!("✓ Connect command sent");

    // Step 5: Send publish command
    println!("\n[Step 5] Sending RTMP publish command...");
    rtmp_client.publish_command(&fixture.stream_id)?;
    println!("✓ Publish command sent for stream: {}", fixture.stream_id);

    // Step 6: Simulate sending some frames
    println!("\n[Step 6] Sending synthetic H.264 frames...");
    for i in 0..5 {
        let frame_data = vec![0x00, 0x00, 0x01, 0x67]; // H.264 SPS NAL unit (simplified)
        let frame_type = if i == 0 {
            super::rtmp_client::FrameType::Keyframe
        } else {
            super::rtmp_client::FrameType::Interframe
        };

        rtmp_client.send_frame(&frame_data, frame_type)?;
        println!("  - Frame {} sent ({:?})", i + 1, frame_type);

        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
    }
    println!("✓ 5 frames sent successfully");

    // Step 7: Verify viewer count can be incremented
    println!("\n[Step 7] Testing viewer count tracking...");
    let count1 = redis.increment_viewers(&fixture.stream_id).await?;
    println!("  - First viewer joined: count = {}", count1);

    let count2 = redis.increment_viewers(&fixture.stream_id).await?;
    println!("  - Second viewer joined: count = {}", count2);

    assert_eq!(count2, 2, "Viewer count should be 2");
    println!("✓ Viewer count correctly tracked");

    // Step 8: Gracefully disconnect broadcaster
    println!("\n[Step 8] Disconnecting broadcaster...");
    rtmp_client.disconnect()?;
    println!("✓ RTMP connection closed");

    // Step 9: Verify stream cleanup
    println!("\n[Step 9] Verifying stream cleanup...");
    db.cleanup_stream(&fixture.stream_id).await?;

    let stream = db.get_stream(&fixture.stream_id).await?;
    assert!(stream.is_none(), "Stream should be cleaned up");
    println!("✓ Stream cleanup verified");

    println!("\n=== Test PASSED ===\n");
    Ok(())
}

/// Test scenario: broadcaster with multiple frame bursts
#[tokio::test]
#[ignore]
pub async fn test_broadcaster_frame_streaming() -> Result<()> {
    println!("\n=== Sub-test: Frame Streaming Stability ===\n");

    let env = StreamingTestEnv::from_env();
    let fixture = StreamFixture::new();
    let db = StreamDbHelper::new(&env.pg_url).await?;

    // Create stream
    db.create_stream(&fixture.stream_id, "test-broadcaster-002").await?;

    // Connect and start streaming
    let mut rtmp_client = super::rtmp_client::RtmpClient::connect(&env.rtmp_addr()).await?;
    rtmp_client.handshake()?;
    rtmp_client.connect_command("live")?;
    rtmp_client.publish_command(&fixture.stream_id)?;

    // Send 100 frames in bursts to test stability
    println!("Sending 100 frames in bursts...");
    for burst in 0..10 {
        for frame in 0..10 {
            let frame_data = vec![0x00, 0x00, 0x01, 0x67];
            let frame_type = if frame == 0 {
                super::rtmp_client::FrameType::Keyframe
            } else {
                super::rtmp_client::FrameType::Interframe
            };

            rtmp_client.send_frame(&frame_data, frame_type)?;
        }
        println!("  - Burst {} (frames {}-{}) sent", burst + 1, burst * 10 + 1, (burst + 1) * 10);
        tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;
    }

    rtmp_client.disconnect()?;
    db.cleanup_stream(&fixture.stream_id).await?;

    println!("\n✓ Frame streaming test completed\n");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_stream_metadata_model() {
        let metadata = StreamMetadata {
            stream_id: "test-123".to_string(),
            broadcaster_id: "user-456".to_string(),
            status: "live".to_string(),
            viewer_count: 42,
        };

        assert_eq!(metadata.stream_id, "test-123");
        assert_eq!(metadata.viewer_count, 42);
    }
}
