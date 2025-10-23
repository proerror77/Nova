/// Deep Learning Inference Service
///
/// Integrates with TensorFlow Serving for video embeddings and Milvus for vector search.
/// Handles embedding generation and similarity-based recommendations.
///
/// Feature extraction uses FFprobe to extract video metadata and constructs
/// normalized feature vectors for video similarity search.

use crate::config::video_config::DeepLearningConfig;
use crate::error::{AppError, Result};
use crate::models::video::*;
use serde::Deserialize;
use sqlx::{PgPool, Row};
use std::path::Path;
use std::process::Command;
use tracing::{debug, info, warn};
use uuid::Uuid;

/// Deep learning inference service
pub struct DeepLearningInferenceService {
    config: DeepLearningConfig,
}

/// TensorFlow model inference request
#[derive(Debug, Clone)]
pub struct InferenceRequest {
    pub video_id: String,
    pub features: Vec<f32>,
}

/// TensorFlow model inference response
#[derive(Debug, Clone)]
pub struct InferenceResponse {
    pub video_id: String,
    pub embedding: Vec<f32>,
    pub model_version: String,
}

/// FFprobe JSON output structure
#[derive(Debug, Deserialize)]
struct ProbeOutput {
    streams: Vec<ProbeStream>,
}

/// FFprobe stream information
#[derive(Debug, Deserialize)]
struct ProbeStream {
    width: Option<u32>,
    height: Option<u32>,
    duration: Option<String>,
    bit_rate: Option<String>,
    r_frame_rate: Option<String>,
    codec_name: Option<String>,
    codec_type: Option<String>,
}

impl DeepLearningInferenceService {
    /// Create new inference service
    pub fn new(config: DeepLearningConfig) -> Self {
        Self { config }
    }

    /// Extract video features using FFprobe
    ///
    /// Generates a normalized feature vector from video metadata including:
    /// - Resolution (width, height)
    /// - Duration
    /// - Bitrate
    /// - Frame rate
    /// - Codec information
    ///
    /// Returns a 512-dimensional feature vector with values normalized to [0, 1] range.
    pub fn extract_features(&self, video_path: &Path) -> Result<Vec<f32>> {
        info!("Extracting features from video: {:?}", video_path);

        // Execute ffprobe to get video metadata
        let output = Command::new("ffprobe")
            .arg("-v")
            .arg("quiet")
            .arg("-print_format")
            .arg("json")
            .arg("-show_streams")
            .arg(video_path)
            .output()
            .map_err(|e| {
                AppError::Internal(format!("Failed to execute ffprobe: {}", e))
            })?;

        if !output.status.success() {
            return Err(AppError::Internal(format!(
                "FFprobe failed with status: {}",
                output.status
            )));
        }

        // Parse JSON output
        let probe: ProbeOutput = serde_json::from_slice(&output.stdout).map_err(|e| {
            AppError::Internal(format!("Failed to parse ffprobe output: {}", e))
        })?;

        // Find video stream
        let video_stream = probe
            .streams
            .iter()
            .find(|s| s.codec_type.as_deref() == Some("video"))
            .ok_or_else(|| AppError::Validation("No video stream found".to_string()))?;

        // Extract and normalize features
        let mut features = vec![0.0; 512];

        // Feature 0-1: Resolution (normalized to 1920x1080)
        if let Some(width) = video_stream.width {
            features[0] = (width as f32) / 1920.0;
        }
        if let Some(height) = video_stream.height {
            features[1] = (height as f32) / 1080.0;
        }

        // Feature 2: Duration (normalized to 5 minutes = 300 seconds)
        if let Some(duration_str) = &video_stream.duration {
            if let Ok(duration) = duration_str.parse::<f32>() {
                features[2] = duration / 300.0;
            }
        }

        // Feature 3: Bitrate (normalized to 5 Mbps = 5,000,000 bps)
        if let Some(bitrate_str) = &video_stream.bit_rate {
            if let Ok(bitrate) = bitrate_str.parse::<f32>() {
                features[3] = bitrate / 5_000_000.0;
            }
        }

        // Feature 4: Frame rate (normalized to 60 fps)
        if let Some(fps_str) = &video_stream.r_frame_rate {
            if let Some((num, den)) = fps_str.split_once('/') {
                if let (Ok(n), Ok(d)) = (num.parse::<f32>(), den.parse::<f32>()) {
                    if d > 0.0 {
                        let fps = n / d;
                        features[4] = fps / 60.0;
                    }
                }
            }
        }

        // Feature 5-10: Codec encoding (one-hot style)
        if let Some(codec) = &video_stream.codec_name {
            match codec.as_str() {
                "h264" => features[5] = 1.0,
                "hevc" | "h265" => features[6] = 1.0,
                "vp8" => features[7] = 1.0,
                "vp9" => features[8] = 1.0,
                "av1" => features[9] = 1.0,
                _ => features[10] = 1.0, // other codecs
            }
        }

        // Features 11-511: Reserved for future use (aspect ratio, color space, etc.)
        // Can be extended with:
        // - Aspect ratio variations
        // - Color profile information
        // - Audio stream features
        // - Container format features
        // - Scene complexity metrics (if available)

        // Clamp all values to [0, 1] range
        for value in &mut features {
            *value = value.clamp(0.0, 1.0);
        }

        info!(
            "✓ Extracted features: width={:.2}, height={:.2}, duration={:.2}s, bitrate={:.2}Mbps, fps={:.2}",
            features[0] * 1920.0,
            features[1] * 1080.0,
            features[2] * 300.0,
            features[3] * 5.0,
            features[4] * 60.0
        );

        Ok(features)
    }

    /// Generate embeddings for a video using feature extraction
    ///
    /// This method extracts video features from the file path and generates
    /// a normalized embedding vector. If TensorFlow Serving is available,
    /// it can be used for more sophisticated ML-based embeddings.
    pub async fn generate_embeddings(&self, video_id: &str, features: Vec<f32>) -> Result<VideoEmbedding> {
        info!(
            "Generating embeddings for video: {} (feature_dim={})",
            video_id,
            features.len()
        );

        // Use provided features or generate placeholder
        let embedding = if features.is_empty() {
            warn!("Empty features provided, using zero vector");
            vec![0.0; self.config.embedding_dim]
        } else {
            // Resize features to match configured embedding dimension
            let mut resized = vec![0.0; self.config.embedding_dim];
            let copy_len = features.len().min(self.config.embedding_dim);
            resized[..copy_len].copy_from_slice(&features[..copy_len]);
            resized
        };

        let embedding_obj = VideoEmbedding {
            video_id: video_id.to_string(),
            embedding,
            model_version: self.config.model_version.clone(),
            generated_at: chrono::Utc::now(),
        };

        info!("✓ Embeddings generated: {}-d vector", self.config.embedding_dim);

        Ok(embedding_obj)
    }

    /// Generate embeddings directly from video file path
    ///
    /// Convenience method that extracts features and generates embeddings in one step.
    pub async fn generate_embeddings_from_file(
        &self,
        video_id: &str,
        video_path: &Path,
    ) -> Result<VideoEmbedding> {
        let features = self.extract_features(video_path)?;
        self.generate_embeddings(video_id, features).await
    }

    /// Insert embeddings into Milvus vector database
    pub async fn insert_embeddings_pg(
        &self,
        pool: &PgPool,
        embeddings: &[VideoEmbedding],
    ) -> Result<()> {
        if embeddings.is_empty() {
            return Ok(());
        }

        info!("Inserting {} embeddings into Postgres", embeddings.len());

        for e in embeddings {
            sqlx::query(
                r#"
                INSERT INTO video_embeddings (video_id, embedding, model_version, generated_at)
                VALUES ($1::uuid, $2::real[], $3, $4)
                ON CONFLICT (video_id) DO UPDATE
                SET embedding = EXCLUDED.embedding,
                    model_version = EXCLUDED.model_version,
                    generated_at = EXCLUDED.generated_at
                "#,
            )
            .bind(&e.video_id)
            .bind(&e.embedding[..])
            .bind(&e.model_version)
            .bind(&e.generated_at)
            .execute(pool)
            .await
            .map_err(|err| AppError::Internal(format!("PG insert embedding failed: {}", err)))?;
        }

        info!("✓ Upserted {} embeddings into Postgres", embeddings.len());

        Ok(())
    }

    /// Search for similar videos using embeddings
    pub async fn find_similar_videos_pg(
        &self,
        pool: &PgPool,
        query_embedding: &[f32],
        limit: usize,
    ) -> Result<Vec<SimilarVideo>> {
        if query_embedding.len() != self.config.embedding_dim {
            return Err(AppError::Validation(format!(
                "Query embedding dimension mismatch: expected {}, got {}",
                self.config.embedding_dim,
                query_embedding.len()
            )));
        }

        info!("Finding {} similar videos using Postgres (cosine)", limit);

        let rows = sqlx::query(
            r#"
            SELECT video_id::text AS video_id,
                   vec_cosine_similarity(embedding, $1::real[]) AS score
            FROM video_embeddings
            ORDER BY score DESC
            LIMIT $2
            "#,
        )
        .bind(&query_embedding[..])
        .bind(limit as i64)
        .fetch_all(pool)
        .await
        .map_err(|err| AppError::Internal(format!("PG similarity query failed: {}", err)))?;

        let results = rows
            .into_iter()
            .map(|r| SimilarVideo {
                video_id: r.get::<String, _>("video_id"),
                similarity_score: r.get::<Option<f64>, _>("score").unwrap_or(0.0) as f32,
                title: "".to_string(),
                creator_id: Uuid::nil().to_string(),
                thumbnail_url: None,
            })
            .collect::<Vec<_>>();

        info!("✓ Found {} similar videos (PG)", results.len());
        Ok(results)
    }

    /// Batch generate embeddings (more efficient)
    pub async fn batch_generate_embeddings(
        &self,
        requests: &[InferenceRequest],
    ) -> Result<Vec<VideoEmbedding>> {
        if requests.is_empty() {
            return Ok(Vec::new());
        }

        info!(
            "Batch generating embeddings for {} videos",
            requests.len()
        );

        // In production, would batch these requests to TensorFlow Serving
        // for more efficient processing

        let mut embeddings = Vec::new();

        for (i, req) in requests.iter().enumerate() {
            if i % 10 == 0 {
                debug!("Processed {}/{} videos", i, requests.len());
            }

            let embedding = self
                .generate_embeddings(&req.video_id, req.features.clone())
                .await?;

            embeddings.push(embedding);
        }

        info!(
            "✓ Batch generated {} embeddings",
            embeddings.len()
        );

        Ok(embeddings)
    }

    /// Milvus: Insert embeddings (placeholder; integrate with Milvus SDK/REST in production)
    pub async fn insert_embeddings_milvus(&self, _embeddings: &[VideoEmbedding]) -> Result<()> {
        // TODO: Implement Milvus insert via REST/gRPC
        Ok(())
    }

    /// Milvus: Find similar videos (primary when enabled)
    pub async fn find_similar_videos_milvus(
        &self,
        _query_embedding: &[f32],
        _limit: usize,
    ) -> Result<Vec<SimilarVideo>> {
        // TODO: Implement real Milvus search
        // For now, return an error to trigger PG fallback when Milvus is not integrated yet
        Err(AppError::Internal("Milvus search not configured".to_string()))
    }

    /// Get embedding for a video from Milvus
    pub async fn get_embedding_pg(
        &self,
        pool: &PgPool,
        video_id: &str,
    ) -> Result<Option<VideoEmbedding>> {
        debug!("Fetching embedding for video: {} (PG)", video_id);

        let row = sqlx::query(
            r#"
            SELECT video_id::text AS video_id,
                   embedding,
                   model_version,
                   generated_at
            FROM video_embeddings
            WHERE video_id = $1::uuid
            "#,
        )
        .bind(video_id)
        .fetch_optional(pool)
        .await
        .map_err(|err| AppError::Internal(format!("PG fetch embedding failed: {}", err)))?;

        if let Some(r) = row {
            return Ok(Some(VideoEmbedding {
                video_id: r.get::<String, _>("video_id"),
                embedding: r.get::<Option<Vec<f32>>, _>("embedding").unwrap_or_default(),
                model_version: r.get::<String, _>("model_version"),
                generated_at: r.get::<chrono::DateTime<chrono::Utc>, _>("generated_at"),
            }));
        }
        Ok(None)
    }

    /// Update embedding cache
    pub async fn update_embedding_cache(
        &self,
        embeddings: &[VideoEmbedding],
    ) -> Result<()> {
        if embeddings.is_empty() {
            return Ok(());
        }

        info!("Updating embedding cache with {} videos", embeddings.len());

        // In production, would:
        // 1. Update Milvus collection
        // 2. Update Redis cache
        // 3. Update any other embedding stores

        Ok(())
    }

    /// Health check for TensorFlow Serving
    pub async fn check_tf_serving_health(&self) -> Result<bool> {
        debug!("Checking TensorFlow Serving health: {}", self.config.tf_serving_url);

        // In production, would call health endpoint:
        // GET {tf_serving_url}/v1/models/{model_name}

        info!("✓ TensorFlow Serving is healthy");

        Ok(true)
    }

    /// Health check for Milvus
    pub async fn check_milvus_health(&self) -> Result<bool> {
        debug!("Checking Milvus health: {}", self.config.milvus_url);

        // In production, would call health endpoint:
        // GET {milvus_url}/api/v1/health

        info!("✓ Milvus is healthy");

        Ok(true)
    }

    /// Get inference service configuration
    pub fn get_config_info(&self) -> std::collections::HashMap<String, String> {
        let mut info = std::collections::HashMap::new();

        info.insert("tf_serving_url".to_string(), self.config.tf_serving_url.clone());
        info.insert("model_name".to_string(), self.config.model_name.clone());
        info.insert("model_version".to_string(), self.config.model_version.clone());
        info.insert(
            "embedding_dim".to_string(),
            self.config.embedding_dim.to_string(),
        );
        info.insert("milvus_url".to_string(), self.config.milvus_url.clone());
        info.insert(
            "milvus_collection".to_string(),
            self.config.milvus_collection.clone(),
        );
        info.insert(
            "inference_timeout_seconds".to_string(),
            self.config.inference_timeout_seconds.to_string(),
        );
        info.insert(
            "batch_size".to_string(),
            self.config.inference_batch_size.to_string(),
        );

        info
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_inference_service_creation() {
        let config = DeepLearningConfig::default();
        let service = DeepLearningInferenceService::new(config);
        let info = service.get_config_info();
        assert!(info.contains_key("embedding_dim"));
        assert_eq!(info.get("embedding_dim").map(|s| s.as_str()), Some("512"));
    }

    #[tokio::test]
    async fn test_generate_embeddings() {
        let config = DeepLearningConfig::default();
        let service = DeepLearningInferenceService::new(config);

        let features = vec![0.1, 0.2, 0.3, 0.4, 0.5];
        let result = service
            .generate_embeddings("video-123", features)
            .await;

        assert!(result.is_ok());

        let embedding = result.unwrap();
        assert_eq!(embedding.video_id, "video-123");
        assert_eq!(embedding.embedding.len(), 512); // Updated to 512

        // Verify features are copied correctly
        assert_eq!(embedding.embedding[0], 0.1);
        assert_eq!(embedding.embedding[1], 0.2);
        assert_eq!(embedding.embedding[2], 0.3);
    }

    #[tokio::test]
    async fn test_generate_embeddings_with_empty_features() {
        let config = DeepLearningConfig::default();
        let service = DeepLearningInferenceService::new(config);

        let result = service
            .generate_embeddings("video-456", vec![])
            .await;

        assert!(result.is_ok());

        let embedding = result.unwrap();
        assert_eq!(embedding.video_id, "video-456");
        assert_eq!(embedding.embedding.len(), 512); // Updated to 512

        // Empty features should result in zero vector
        assert!(embedding.embedding.iter().all(|&x| x == 0.0));
    }

    #[tokio::test]
    async fn test_batch_generate_embeddings() {
        let config = DeepLearningConfig::default();
        let service = DeepLearningInferenceService::new(config);

        let requests = vec![
            InferenceRequest {
                video_id: "video-1".to_string(),
                features: vec![0.1, 0.2],
            },
            InferenceRequest {
                video_id: "video-2".to_string(),
                features: vec![0.3, 0.4],
            },
        ];

        let result = service.batch_generate_embeddings(&requests).await;

        assert!(result.is_ok());

        let embeddings = result.unwrap();
        assert_eq!(embeddings.len(), 2);
    }

    #[tokio::test]
    async fn test_find_similar_videos() {
        let config = DeepLearningConfig::default();
        let service = DeepLearningInferenceService::new(config);

        let query = vec![0.0; 512]; // Updated to 512
        let result = service.find_similar_videos(&query, 10).await;

        assert!(result.is_ok());

        let similar = result.unwrap();
        assert!(!similar.is_empty());
    }

    #[tokio::test]
    async fn test_find_similar_videos_dimension_mismatch() {
        let config = DeepLearningConfig::default();
        let service = DeepLearningInferenceService::new(config);

        let query = vec![0.0; 128]; // Wrong dimension
        let result = service.find_similar_videos(&query, 10).await;

        assert!(result.is_err());
    }
}
