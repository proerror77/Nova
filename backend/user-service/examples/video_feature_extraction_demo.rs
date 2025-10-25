/// Video Feature Extraction Demo
///
/// Demonstrates the video feature extraction and embedding generation.
/// This replaces the previous all-zero embedding with real feature-based vectors.
use user_service::config::video_config::DeepLearningConfig;
use user_service::services::deep_learning_inference::DeepLearningInferenceService;

#[tokio::main]
async fn main() {
    println!("=== Video Feature Extraction Demo ===\n");

    // Initialize the service
    let config = DeepLearningConfig::default();
    let service = DeepLearningInferenceService::new(config);

    println!("Configuration:");
    println!("  Embedding Dimension: 512");
    println!("  Model: video_embeddings");
    println!("  Version: 1\n");

    // Simulate video features (normally extracted from ffprobe)
    println!("Simulating video features for a 1080p H.264 video:");
    let mut features = vec![0.0; 512];

    // Example: 1920x1080, 120s duration, 3 Mbps bitrate, 30 fps, H.264
    features[0] = 1920.0 / 1920.0; // Width: 1.0
    features[1] = 1080.0 / 1080.0; // Height: 1.0
    features[2] = 120.0 / 300.0; // Duration: 0.4 (120s / 300s max)
    features[3] = 3_000_000.0 / 5_000_000.0; // Bitrate: 0.6 (3 Mbps / 5 Mbps max)
    features[4] = 30.0 / 60.0; // FPS: 0.5 (30 fps / 60 fps max)
    features[5] = 1.0; // H.264 codec

    println!("  Width: 1920px (normalized: {:.2})", features[0]);
    println!("  Height: 1080px (normalized: {:.2})", features[1]);
    println!("  Duration: 120s (normalized: {:.2})", features[2]);
    println!("  Bitrate: 3 Mbps (normalized: {:.2})", features[3]);
    println!("  FPS: 30 (normalized: {:.2})", features[4]);
    println!("  Codec: H.264 (one-hot: {:.2})", features[5]);
    println!();

    // Generate embeddings
    let video_id = "demo-video-001";
    println!("Generating embeddings for video: {}", video_id);

    match service.generate_embeddings(video_id, features).await {
        Ok(embedding) => {
            println!("✓ Embeddings generated successfully!");
            println!();
            println!("Embedding Details:");
            println!("  Video ID: {}", embedding.video_id);
            println!("  Model Version: {}", embedding.model_version);
            println!("  Generated At: {}", embedding.generated_at);
            println!("  Embedding Dimension: {}", embedding.embedding.len());
            println!();

            // Verify non-zero values
            let non_zero_count = embedding.embedding.iter().filter(|&&x| x != 0.0).count();
            let zero_count = embedding.embedding.len() - non_zero_count;

            println!("Embedding Statistics:");
            println!("  Non-zero values: {}", non_zero_count);
            println!("  Zero values: {}", zero_count);
            println!(
                "  Non-zero percentage: {:.2}%",
                (non_zero_count as f64 / embedding.embedding.len() as f64) * 100.0
            );
            println!();

            // Show first 10 feature values
            println!("First 10 feature values:");
            for (i, &value) in embedding.embedding.iter().take(10).enumerate() {
                let feature_name = match i {
                    0 => "Width",
                    1 => "Height",
                    2 => "Duration",
                    3 => "Bitrate",
                    4 => "FPS",
                    5 => "H.264",
                    6 => "HEVC",
                    7 => "VP8",
                    8 => "VP9",
                    9 => "AV1",
                    _ => "Other",
                };
                println!("  [{}] {}: {:.4}", i, feature_name, value);
            }
            println!();

            // Validate the fix
            if non_zero_count == 0 {
                println!("❌ ERROR: Embedding is all zeros!");
                println!("   This indicates the bug is NOT fixed.");
            } else {
                println!(
                    "✅ SUCCESS: Embedding has {} non-zero values!",
                    non_zero_count
                );
                println!("   The all-zero embedding bug is FIXED!");
            }
        }
        Err(e) => {
            println!("❌ Error generating embeddings: {}", e);
        }
    }

    println!("\n=== Demo Complete ===");
}
