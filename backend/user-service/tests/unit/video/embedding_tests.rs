#![cfg(feature = "legacy_video_tests")]
/// Unit Tests for Embedding Similarity (T133)
/// Tests vector distance calculations, normalization, similarity metrics

/// Vector embedding (e.g., 256-dimensional)
pub type VideoEmbedding = Vec<f32>;

/// Embedding similarity calculator
pub struct EmbeddingSimilarityCalculator {
    embedding_dim: usize,
}

impl EmbeddingSimilarityCalculator {
    pub fn new(embedding_dim: usize) -> Self {
        Self { embedding_dim }
    }

    /// Calculate Euclidean distance between two embeddings
    pub fn euclidean_distance(&self, a: &VideoEmbedding, b: &VideoEmbedding) -> f32 {
        if a.len() != b.len() || a.len() != self.embedding_dim {
            return f32::NAN;
        }

        a.iter()
            .zip(b.iter())
            .map(|(x, y)| (x - y).powi(2))
            .sum::<f32>()
            .sqrt()
    }

    /// Calculate cosine similarity (requires normalized embeddings)
    pub fn cosine_similarity(&self, a: &VideoEmbedding, b: &VideoEmbedding) -> f32 {
        if a.len() != b.len() || a.len() != self.embedding_dim {
            return f32::NAN;
        }

        let dot_product: f32 = a.iter().zip(b.iter()).map(|(x, y)| x * y).sum();

        let norm_a: f32 = a.iter().map(|x| x * x).sum::<f32>().sqrt();
        let norm_b: f32 = b.iter().map(|x| x * x).sum::<f32>().sqrt();

        if norm_a == 0.0 || norm_b == 0.0 {
            return 0.0;
        }

        dot_product / (norm_a * norm_b)
    }

    /// Normalize embedding to unit length
    pub fn normalize(&self, embedding: &mut VideoEmbedding) {
        let norm: f32 = embedding.iter().map(|x| x * x).sum::<f32>().sqrt();

        if norm > 0.0 {
            for x in embedding.iter_mut() {
                *x /= norm;
            }
        }
    }

    /// Calculate Manhattan (L1) distance
    pub fn manhattan_distance(&self, a: &VideoEmbedding, b: &VideoEmbedding) -> f32 {
        if a.len() != b.len() || a.len() != self.embedding_dim {
            return f32::NAN;
        }

        a.iter().zip(b.iter()).map(|(x, y)| (x - y).abs()).sum()
    }

    /// Calculate Chebyshev (L∞) distance
    pub fn chebyshev_distance(&self, a: &VideoEmbedding, b: &VideoEmbedding) -> f32 {
        if a.len() != b.len() || a.len() != self.embedding_dim {
            return f32::NAN;
        }

        a.iter()
            .zip(b.iter())
            .map(|(x, y)| (x - y).abs())
            .max_by(|x, y| x.partial_cmp(y).unwrap_or(std::cmp::Ordering::Equal))
            .unwrap_or(0.0)
    }

    /// Get top K similar embeddings
    pub fn get_top_k_similar(
        &self,
        query: &VideoEmbedding,
        candidates: &[VideoEmbedding],
        k: usize,
    ) -> Vec<(usize, f32)> {
        let mut similarities: Vec<(usize, f32)> = candidates
            .iter()
            .enumerate()
            .map(|(idx, emb)| (idx, self.cosine_similarity(query, emb)))
            .collect();

        similarities.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
        similarities.into_iter().take(k).collect()
    }
}

// ============================================
// Unit Tests (T133)
// ============================================

#[test]
fn test_euclidean_distance_identical() {
    let calc = EmbeddingSimilarityCalculator::new(3);

    let emb = vec![1.0, 2.0, 3.0];
    let distance = calc.euclidean_distance(&emb, &emb);

    assert!(distance < 0.0001); // Should be near zero
}

#[test]
fn test_euclidean_distance_orthogonal() {
    let calc = EmbeddingSimilarityCalculator::new(2);

    let a = vec![1.0, 0.0];
    let b = vec![0.0, 1.0];

    let distance = calc.euclidean_distance(&a, &b);
    assert!((distance - std::f32::consts::SQRT_2).abs() < 0.0001);
}

#[test]
fn test_euclidean_distance_commutative() {
    let calc = EmbeddingSimilarityCalculator::new(4);

    let a = vec![1.0, 2.0, 3.0, 4.0];
    let b = vec![5.0, 6.0, 7.0, 8.0];

    let dist_ab = calc.euclidean_distance(&a, &b);
    let dist_ba = calc.euclidean_distance(&b, &a);

    assert!((dist_ab - dist_ba).abs() < 0.0001);
}

#[test]
fn test_cosine_similarity_identical() {
    let calc = EmbeddingSimilarityCalculator::new(3);

    let emb = vec![1.0, 0.0, 0.0];
    let similarity = calc.cosine_similarity(&emb, &emb);

    assert!((similarity - 1.0).abs() < 0.0001); // Should be 1.0
}

#[test]
fn test_cosine_similarity_opposite() {
    let calc = EmbeddingSimilarityCalculator::new(2);

    let a = vec![1.0, 0.0];
    let b = vec![-1.0, 0.0];

    let similarity = calc.cosine_similarity(&a, &b);
    assert!((-similarity - 1.0).abs() < 0.0001); // Should be -1.0
}

#[test]
fn test_cosine_similarity_orthogonal() {
    let calc = EmbeddingSimilarityCalculator::new(2);

    let a = vec![1.0, 0.0];
    let b = vec![0.0, 1.0];

    let similarity = calc.cosine_similarity(&a, &b);
    assert!(similarity.abs() < 0.0001); // Should be 0.0
}

#[test]
fn test_normalize_unit_vector() {
    let calc = EmbeddingSimilarityCalculator::new(2);

    let mut emb = vec![3.0, 4.0];
    calc.normalize(&mut emb);

    // Should normalize to [0.6, 0.8]
    assert!((emb[0] - 0.6).abs() < 0.0001);
    assert!((emb[1] - 0.8).abs() < 0.0001);

    // Check norm is 1
    let norm: f32 = emb.iter().map(|x| x * x).sum::<f32>().sqrt();
    assert!((norm - 1.0).abs() < 0.0001);
}

#[test]
fn test_normalize_zero_vector() {
    let calc = EmbeddingSimilarityCalculator::new(2);

    let mut emb = vec![0.0, 0.0];
    calc.normalize(&mut emb);

    // Should remain zero
    assert_eq!(emb[0], 0.0);
    assert_eq!(emb[1], 0.0);
}

#[test]
fn test_manhattan_distance_basic() {
    let calc = EmbeddingSimilarityCalculator::new(2);

    let a = vec![0.0, 0.0];
    let b = vec![3.0, 4.0];

    let distance = calc.manhattan_distance(&a, &b);
    assert!((distance - 7.0).abs() < 0.0001); // |3| + |4| = 7
}

#[test]
fn test_manhattan_vs_euclidean() {
    let calc = EmbeddingSimilarityCalculator::new(2);

    let a = vec![0.0, 0.0];
    let b = vec![3.0, 4.0];

    let euclidean = calc.euclidean_distance(&a, &b);
    let manhattan = calc.manhattan_distance(&a, &b);

    // Manhattan distance should be >= Euclidean distance
    assert!(manhattan >= euclidean - 0.0001);
}

#[test]
fn test_chebyshev_distance_basic() {
    let calc = EmbeddingSimilarityCalculator::new(3);

    let a = vec![0.0, 0.0, 0.0];
    let b = vec![3.0, 4.0, 2.0];

    let distance = calc.chebyshev_distance(&a, &b);
    assert!((distance - 4.0).abs() < 0.0001); // max(3, 4, 2) = 4
}

#[test]
fn test_chebyshev_vs_manhattan() {
    let calc = EmbeddingSimilarityCalculator::new(3);

    let a = vec![0.0, 0.0, 0.0];
    let b = vec![3.0, 4.0, 2.0];

    let chebyshev = calc.chebyshev_distance(&a, &b);
    let manhattan = calc.manhattan_distance(&a, &b);

    // Chebyshev should be <= Manhattan
    assert!(chebyshev <= manhattan + 0.0001);
}

#[test]
fn test_dimension_mismatch_euclidean() {
    let calc = EmbeddingSimilarityCalculator::new(2);

    let a = vec![1.0, 2.0];
    let b = vec![1.0, 2.0, 3.0]; // Wrong dimension

    let distance = calc.euclidean_distance(&a, &b);
    assert!(distance.is_nan());
}

#[test]
fn test_dimension_mismatch_cosine() {
    let calc = EmbeddingSimilarityCalculator::new(2);

    let a = vec![1.0, 2.0];
    let b = vec![1.0, 2.0, 3.0]; // Wrong dimension

    let similarity = calc.cosine_similarity(&a, &b);
    assert!(similarity.is_nan());
}

#[test]
fn test_top_k_similar_retrieval() {
    let calc = EmbeddingSimilarityCalculator::new(2);

    let query = vec![1.0, 0.0];
    let candidates = vec![
        vec![0.9, 0.1],  // Similar to query
        vec![0.1, 0.9],  // Dissimilar
        vec![1.0, 0.0],  // Very similar
        vec![-1.0, 0.0], // Opposite
    ];

    let top_k = calc.get_top_k_similar(&query, &candidates, 2);

    // Should return indices 2 (identical) and 0 (similar)
    assert_eq!(top_k.len(), 2);
    assert_eq!(top_k[0].0, 2); // Most similar
    assert_eq!(top_k[1].0, 0); // Second most similar
}

#[test]
fn test_top_k_boundary_k_greater_than_candidates() {
    let calc = EmbeddingSimilarityCalculator::new(2);

    let query = vec![1.0, 0.0];
    let candidates = vec![vec![0.9, 0.1], vec![0.1, 0.9]];

    let top_k = calc.get_top_k_similar(&query, &candidates, 5);

    // Should return only available candidates
    assert_eq!(top_k.len(), 2);
}

#[test]
fn test_high_dimensional_embedding() {
    let calc = EmbeddingSimilarityCalculator::new(256);

    let emb1: VideoEmbedding = (0..256).map(|i| (i as f32) / 256.0).collect();
    let emb2: VideoEmbedding = (0..256).map(|i| ((255 - i) as f32) / 256.0).collect();

    let distance = calc.euclidean_distance(&emb1, &emb2);
    assert!(!distance.is_nan());
    assert!(distance > 0.0);
}

#[test]
fn test_embedding_clustering_similarity() {
    let calc = EmbeddingSimilarityCalculator::new(3);

    let center = vec![0.0, 0.0, 0.0];
    let close_1 = vec![0.1, 0.1, 0.1];
    let close_2 = vec![0.15, 0.05, 0.1];
    let far = vec![1.0, 1.0, 1.0];

    let dist_close_1 = calc.euclidean_distance(&center, &close_1);
    let dist_close_2 = calc.euclidean_distance(&center, &close_2);
    let dist_far = calc.euclidean_distance(&center, &far);

    assert!(dist_close_1 < dist_close_2);
    assert!(dist_close_2 < dist_far);
}

#[test]
fn test_similarity_range() {
    let calc = EmbeddingSimilarityCalculator::new(100);

    let mut similarities = vec![];

    for i in 0..10 {
        let emb1: VideoEmbedding = (0..100).map(|j| if j == i { 1.0 } else { 0.0 }).collect();
        let emb2: VideoEmbedding = (0..100)
            .map(|j| if j == (i + 1) % 100 { 1.0 } else { 0.0 })
            .collect();

        let sim = calc.cosine_similarity(&emb1, &emb2);
        similarities.push(sim);

        // All should be between -1 and 1
        assert!(sim >= -1.0 && sim <= 1.0);
    }
}

#[test]
fn test_embedding_metric_properties_symmetry() {
    let calc = EmbeddingSimilarityCalculator::new(5);

    let a: VideoEmbedding = vec![1.0, 2.0, 3.0, 4.0, 5.0];
    let b: VideoEmbedding = vec![5.0, 4.0, 3.0, 2.0, 1.0];

    let dist_ab = calc.euclidean_distance(&a, &b);
    let dist_ba = calc.euclidean_distance(&b, &a);

    assert!((dist_ab - dist_ba).abs() < 0.0001);
}

#[test]
fn test_embedding_triangle_inequality() {
    let calc = EmbeddingSimilarityCalculator::new(2);

    let a = vec![0.0, 0.0];
    let b = vec![3.0, 0.0];
    let c = vec![3.0, 4.0];

    let dist_ab = calc.euclidean_distance(&a, &b);
    let dist_bc = calc.euclidean_distance(&b, &c);
    let dist_ac = calc.euclidean_distance(&a, &c);

    // Triangle inequality: d(a,c) <= d(a,b) + d(b,c)
    assert!(dist_ac <= dist_ab + dist_bc + 0.0001);
}

#[test]
fn test_sparse_embedding_similarity() {
    let calc = EmbeddingSimilarityCalculator::new(100);

    let sparse_1: VideoEmbedding = (0..100)
        .map(|i| if i < 5 { 1.0 / 5.0 } else { 0.0 })
        .collect();
    let sparse_2: VideoEmbedding = (0..100)
        .map(|i| if i < 5 { 1.0 / 5.0 } else { 0.0 })
        .collect();

    let similarity = calc.cosine_similarity(&sparse_1, &sparse_2);
    assert!((similarity - 1.0).abs() < 0.0001); // Should be identical
}

#[test]
fn test_embedding_normalization_preserves_direction() {
    let calc = EmbeddingSimilarityCalculator::new(3);

    let mut orig = vec![3.0, 4.0, 0.0];
    let mut norm = orig.clone();

    calc.normalize(&mut norm);

    // Cosine similarity should be 1.0 (same direction)
    let similarity = calc.cosine_similarity(&orig, &norm);
    assert!((similarity - 1.0).abs() < 0.0001);
}
