// ============================================
// ONNX Model Serving (T249)
// ============================================
//
// Real-time model inference using ONNX Runtime (tract) with:
// - Model versioning
// - Hot-reload capability
// - Graceful degradation to fallback scoring
// - Performance target: < 100ms inference latency

use crate::error::{AppError, Result};
use ndarray::Array2;
use serde::{Deserialize, Serialize};
use std::path::Path;
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::RwLock;
use tract_onnx::prelude::*;
use tracing::{debug, error, info, warn};

/// Type alias for the optimized tract model
type TractModel = SimplePlan<TypedFact, Box<dyn TypedOp>, Graph<TypedFact, Box<dyn TypedOp>>>;

/// ONNX model server (using tract runtime)
///
/// Uses Arc+RwLock to allow model reloading while serving requests
pub struct ONNXModelServer {
    /// Loaded tract model (None if not loaded or failed)
    model: Arc<RwLock<Option<TractModel>>>,

    /// Model file path
    model_path: Arc<RwLock<String>>,

    /// Current model version
    model_version: Arc<RwLock<String>>,

    /// Performance metrics (inference times in nanoseconds)
    inference_times: Arc<RwLock<Vec<u128>>>,

    /// Flag to indicate if model is loaded
    is_loaded: Arc<RwLock<bool>>,

    /// Input dimension expected by the model
    input_dim: Arc<RwLock<usize>>,

    /// Use fallback scoring when model unavailable
    enable_fallback: bool,
}

/// Model metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelMetadata {
    pub name: String,
    pub version: String,
    pub deployed_at: chrono::DateTime<chrono::Utc>,
    pub model_path: String,
    pub metrics: Option<serde_json::Value>,
}

/// Model input configuration
#[derive(Debug, Clone)]
pub struct ModelInputConfig {
    /// Expected embedding dimension
    pub embedding_dim: usize,
    /// Number of candidate features per item
    pub candidate_features: usize,
    /// Additional context features
    pub context_features: usize,
}

impl Default for ModelInputConfig {
    fn default() -> Self {
        Self {
            embedding_dim: 128,
            candidate_features: 64,
            context_features: 32,
        }
    }
}

impl ONNXModelServer {
    /// Load ONNX model from file
    ///
    /// This validates that the model file exists and loads it into memory.
    /// If loading fails, the server operates in fallback mode with heuristic scoring.
    pub fn load(model_path: &str) -> Result<Self> {
        let mut loaded_model: Option<TractModel> = None;
        let mut detected_input_dim: usize = 128; // default

        if !model_path.is_empty() && Path::new(model_path).exists() {
            match Self::load_tract_model(model_path) {
                Ok((model, input_dim)) => {
                    info!("ONNX model loaded successfully from: {}", model_path);
                    loaded_model = Some(model);
                    detected_input_dim = input_dim;
                }
                Err(e) => {
                    error!("Failed to load ONNX model: {}. Using fallback scoring.", e);
                }
            }
        } else {
            warn!(
                "ONNX model file not found at: {}. Using fallback scoring.",
                model_path
            );
        }

        let is_loaded = loaded_model.is_some();

        Ok(Self {
            model: Arc::new(RwLock::new(loaded_model)),
            model_path: Arc::new(RwLock::new(model_path.to_string())),
            model_version: Arc::new(RwLock::new("1.0.0".to_string())),
            inference_times: Arc::new(RwLock::new(Vec::new())),
            is_loaded: Arc::new(RwLock::new(is_loaded)),
            input_dim: Arc::new(RwLock::new(detected_input_dim)),
            enable_fallback: true,
        })
    }

    /// Internal function to load tract model
    fn load_tract_model(model_path: &str) -> anyhow::Result<(TractModel, usize)> {
        let model = tract_onnx::onnx()
            .model_for_path(model_path)?
            .with_input_fact(0, f32::fact([1, 128]).into())? // Batch=1, Features=128
            .into_optimized()?
            .into_runnable()?;

        // Extract input dimension from model
        let input_dim = 128; // Default, could be extracted from model metadata

        Ok((model, input_dim))
    }

    /// Run inference on embedding input
    ///
    /// Returns predicted scores for candidates.
    /// If model is not loaded, uses fallback heuristic scoring.
    pub async fn infer(&self, embeddings: Vec<f32>, candidates_count: usize) -> Result<Vec<f32>> {
        if embeddings.is_empty() {
            return Err(AppError::BadRequest("Empty embeddings".to_string()));
        }

        let start = Instant::now();
        let scores = self.infer_internal(&embeddings, candidates_count).await?;
        let latency_ns = start.elapsed().as_nanos();

        // Record latency
        self.record_latency(latency_ns).await;

        debug!(
            "ONNX inference completed: {} candidates in {:.2}ms",
            candidates_count,
            latency_ns as f64 / 1_000_000.0
        );

        Ok(scores)
    }

    /// Internal inference logic
    async fn infer_internal(
        &self,
        embeddings: &[f32],
        candidates_count: usize,
    ) -> Result<Vec<f32>> {
        let model_guard = self.model.read().await;

        if let Some(ref model) = *model_guard {
            // Real ONNX inference
            self.run_tract_inference(model, embeddings, candidates_count)
        } else if self.enable_fallback {
            // Fallback heuristic scoring
            Ok(self.fallback_scoring(embeddings, candidates_count))
        } else {
            Err(AppError::Internal("ONNX model not loaded".to_string()))
        }
    }

    /// Run actual tract inference
    fn run_tract_inference(
        &self,
        model: &TractModel,
        embeddings: &[f32],
        candidates_count: usize,
    ) -> Result<Vec<f32>> {
        let input_dim = 128; // Must match model expectation

        // Prepare input tensor
        // For ranking models, we typically batch candidate embeddings
        let mut scores = Vec::with_capacity(candidates_count);

        // Process each candidate
        for i in 0..candidates_count {
            // Create input for this candidate
            // Combine user embedding with candidate features
            let mut input_data = vec![0.0f32; input_dim];

            // Copy user embeddings (first half)
            let user_embed_len = embeddings.len().min(input_dim / 2);
            input_data[..user_embed_len].copy_from_slice(&embeddings[..user_embed_len]);

            // Add candidate index as feature (normalized)
            input_data[input_dim / 2] = (i as f32) / (candidates_count as f32);

            // Create tensor
            let input_array: Array2<f32> = Array2::from_shape_vec((1, input_dim), input_data)
                .map_err(|e| AppError::Internal(format!("Failed to create input tensor: {}", e)))?;

            let input_tensor: Tensor = input_array.into();

            // Run inference
            let result = model
                .run(tvec!(input_tensor.into()))
                .map_err(|e| AppError::Internal(format!("Tract inference failed: {}", e)))?;

            // Extract score from output
            let output = result[0]
                .to_array_view::<f32>()
                .map_err(|e| AppError::Internal(format!("Failed to extract output: {}", e)))?;

            let score = output.iter().next().copied().unwrap_or(0.5);
            scores.push(score.clamp(0.0, 1.0));
        }

        Ok(scores)
    }

    /// Fallback scoring when model is unavailable
    ///
    /// Uses heuristic scoring based on embedding characteristics:
    /// - Magnitude: Higher magnitude embeddings often indicate stronger signals
    /// - Variance: More varied embeddings may indicate more distinctive content
    /// - Position: Slight preference for earlier candidates (recency bias)
    fn fallback_scoring(&self, embeddings: &[f32], candidates_count: usize) -> Vec<f32> {
        let mut scores = Vec::with_capacity(candidates_count);

        // Calculate embedding statistics
        let magnitude = embeddings.iter().map(|x| x * x).sum::<f32>().sqrt();
        let mean = embeddings.iter().sum::<f32>() / embeddings.len().max(1) as f32;
        let variance = embeddings
            .iter()
            .map(|x| (x - mean).powi(2))
            .sum::<f32>()
            / embeddings.len().max(1) as f32;

        // Base score from embedding quality
        let base_score = 0.3 + (magnitude / 20.0).min(0.3) + (variance.sqrt() / 5.0).min(0.2);

        for i in 0..candidates_count {
            // Position decay (earlier candidates get slight boost)
            let position_factor = 1.0 - (i as f32 / candidates_count as f32) * 0.1;

            // Add deterministic variation based on position
            let variation = ((i * 7 + 11) % 100) as f32 / 500.0;

            let score = (base_score * position_factor + variation).clamp(0.0, 1.0);
            scores.push(score);
        }

        scores
    }

    /// Batch inference for multiple users
    ///
    /// More efficient than individual calls when scoring for multiple users
    pub async fn infer_batch(
        &self,
        user_embeddings: Vec<Vec<f32>>,
        candidates_count: usize,
    ) -> Result<Vec<Vec<f32>>> {
        let mut results = Vec::with_capacity(user_embeddings.len());

        for embeddings in user_embeddings {
            let scores = self.infer(embeddings, candidates_count).await?;
            results.push(scores);
        }

        Ok(results)
    }

    /// Reload model from disk (hot-reload)
    pub async fn reload(&self, model_path: &str) -> Result<()> {
        if !Path::new(model_path).exists() {
            return Err(AppError::NotFound(format!(
                "Model file not found: {}",
                model_path
            )));
        }

        // Load new model
        let (new_model, new_input_dim) = Self::load_tract_model(model_path)
            .map_err(|e| AppError::Internal(format!("Failed to load model: {}", e)))?;

        // Swap model atomically
        {
            let mut model_guard = self.model.write().await;
            *model_guard = Some(new_model);
        }

        // Update metadata
        {
            let mut path = self.model_path.write().await;
            *path = model_path.to_string();
        }

        {
            let mut dim = self.input_dim.write().await;
            *dim = new_input_dim;
        }

        {
            let mut is_loaded = self.is_loaded.write().await;
            *is_loaded = true;
        }

        // Increment version
        {
            let mut version = self.model_version.write().await;
            let parts: Vec<&str> = version.split('.').collect();
            if let Some(patch) = parts.last().and_then(|p| p.parse::<u32>().ok()) {
                *version = format!("{}.{}.{}", parts[0], parts[1], patch + 1);
            }
        }

        info!("ONNX model hot-reloaded from: {}", model_path);
        Ok(())
    }

    /// Unload model (for testing or memory management)
    pub async fn unload(&self) {
        let mut model_guard = self.model.write().await;
        *model_guard = None;

        let mut is_loaded = self.is_loaded.write().await;
        *is_loaded = false;

        info!("ONNX model unloaded");
    }

    /// Check if model is currently loaded
    pub async fn is_model_loaded(&self) -> bool {
        *self.is_loaded.read().await
    }

    /// Get current model version
    pub async fn version(&self) -> String {
        self.model_version.read().await.clone()
    }

    /// Get model path
    pub async fn get_model_path(&self) -> String {
        self.model_path.read().await.clone()
    }

    /// Get inference performance stats (P50, P95, P99 latency)
    pub async fn get_latency_stats(&self) -> LatencyStats {
        let times = self.inference_times.read().await;

        if times.is_empty() {
            return LatencyStats {
                p50_ms: 0.0,
                p95_ms: 0.0,
                p99_ms: 0.0,
                avg_ms: 0.0,
                total_inferences: 0,
            };
        }

        let mut sorted = times.clone();
        sorted.sort();

        let len = sorted.len();
        let p50_idx = len / 2;
        let p95_idx = ((len as f64) * 0.95) as usize;
        let p99_idx = ((len as f64) * 0.99) as usize;

        let avg: u128 = sorted.iter().sum::<u128>() / len as u128;

        LatencyStats {
            p50_ms: sorted[p50_idx] as f64 / 1_000_000.0,
            p95_ms: sorted[p95_idx.min(len - 1)] as f64 / 1_000_000.0,
            p99_ms: sorted[p99_idx.min(len - 1)] as f64 / 1_000_000.0,
            avg_ms: avg as f64 / 1_000_000.0,
            total_inferences: len,
        }
    }

    /// Record inference latency
    pub async fn record_latency(&self, latency_ns: u128) {
        let mut times = self.inference_times.write().await;
        times.push(latency_ns);

        // Keep only last 10k measurements to avoid unbounded growth
        if times.len() > 10_000 {
            *times = times[times.len() - 5_000..].to_vec();
        }
    }

    /// Clear latency metrics
    pub async fn clear_metrics(&self) {
        let mut times = self.inference_times.write().await;
        times.clear();
    }
}

/// Latency statistics
#[derive(Debug, Clone, Serialize)]
pub struct LatencyStats {
    pub p50_ms: f64,
    pub p95_ms: f64,
    pub p99_ms: f64,
    pub avg_ms: f64,
    pub total_inferences: usize,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_onnx_server_creation() {
        let server = ONNXModelServer::load("nonexistent_model.onnx");
        assert!(server.is_ok());
        // Should create successfully even with missing file (fallback mode)
    }

    #[tokio::test]
    async fn test_model_version() {
        let server = ONNXModelServer::load("test_model.onnx").unwrap();
        let version = server.version().await;
        assert_eq!(version, "1.0.0");
    }

    #[tokio::test]
    async fn test_fallback_scoring() {
        let server = ONNXModelServer::load("nonexistent.onnx").unwrap();

        // Model not loaded, should use fallback
        let embeddings = vec![0.1, 0.2, 0.3, 0.4, 0.5];
        let scores = server.infer(embeddings, 10).await.unwrap();

        assert_eq!(scores.len(), 10);
        for score in &scores {
            assert!(*score >= 0.0 && *score <= 1.0);
        }
    }

    #[tokio::test]
    async fn test_fallback_scoring_consistency() {
        let server = ONNXModelServer::load("nonexistent.onnx").unwrap();

        let embeddings = vec![0.1, 0.2, 0.3, 0.4, 0.5];
        let scores1 = server.infer(embeddings.clone(), 10).await.unwrap();
        let scores2 = server.infer(embeddings, 10).await.unwrap();

        // Fallback scoring should be deterministic
        assert_eq!(scores1, scores2);
    }

    #[tokio::test]
    async fn test_latency_stats() {
        let server = ONNXModelServer::load("test_model.onnx").unwrap();

        // Record some mock latencies (in nanoseconds)
        for i in 1..=100 {
            server.record_latency(i * 1_000_000).await; // 1ms - 100ms
        }

        let stats = server.get_latency_stats().await;
        assert!(stats.p50_ms > 0.0);
        assert!(stats.p95_ms > stats.p50_ms);
        assert!(stats.p99_ms >= stats.p95_ms);
        assert_eq!(stats.total_inferences, 100);
    }

    #[tokio::test]
    async fn test_metrics_clear() {
        let server = ONNXModelServer::load("test_model.onnx").unwrap();

        server.record_latency(1_000_000).await;
        server.record_latency(2_000_000).await;

        let stats = server.get_latency_stats().await;
        assert_eq!(stats.total_inferences, 2);

        server.clear_metrics().await;

        let stats = server.get_latency_stats().await;
        assert_eq!(stats.total_inferences, 0);
    }

    #[tokio::test]
    async fn test_empty_embeddings_error() {
        let server = ONNXModelServer::load("test_model.onnx").unwrap();
        let result = server.infer(vec![], 10).await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_batch_inference() {
        let server = ONNXModelServer::load("nonexistent.onnx").unwrap();

        let user_embeddings = vec![
            vec![0.1, 0.2, 0.3],
            vec![0.4, 0.5, 0.6],
            vec![0.7, 0.8, 0.9],
        ];

        let results = server.infer_batch(user_embeddings, 5).await.unwrap();

        assert_eq!(results.len(), 3);
        for scores in &results {
            assert_eq!(scores.len(), 5);
        }
    }
}
