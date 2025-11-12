// Utility functions for feature store

use crate::models::FeatureValueData;
use ndarray::Array1;

/// Convert feature value to embedding vector (ndarray)
pub fn feature_to_vector(value: &FeatureValueData) -> Option<Array1<f64>> {
    match value {
        FeatureValueData::DoubleList(values) => Some(Array1::from_vec(values.clone())),
        _ => None,
    }
}

/// Calculate cosine similarity between two vectors
pub fn cosine_similarity(a: &Array1<f64>, b: &Array1<f64>) -> f64 {
    if a.len() != b.len() {
        return 0.0;
    }

    let dot_product = a.dot(b);
    let norm_a = a.dot(a).sqrt();
    let norm_b = b.dot(b).sqrt();

    if norm_a == 0.0 || norm_b == 0.0 {
        return 0.0;
    }

    dot_product / (norm_a * norm_b)
}

/// Normalize vector to unit length
pub fn normalize_vector(vec: &mut Array1<f64>) {
    let norm = vec.dot(vec).sqrt();
    if norm > 0.0 {
        *vec /= norm;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cosine_similarity() {
        let a = Array1::from_vec(vec![1.0, 0.0, 0.0]);
        let b = Array1::from_vec(vec![1.0, 0.0, 0.0]);
        assert!((cosine_similarity(&a, &b) - 1.0).abs() < 1e-6);

        let c = Array1::from_vec(vec![1.0, 0.0, 0.0]);
        let d = Array1::from_vec(vec![0.0, 1.0, 0.0]);
        assert!((cosine_similarity(&c, &d)).abs() < 1e-6);
    }

    #[test]
    fn test_normalize_vector() {
        let mut vec = Array1::from_vec(vec![3.0, 4.0]);
        normalize_vector(&mut vec);
        assert!((vec[0] - 0.6).abs() < 1e-6);
        assert!((vec[1] - 0.8).abs() < 1e-6);
    }

    #[test]
    fn test_feature_to_vector() {
        let feature = FeatureValueData::DoubleList(vec![1.0, 2.0, 3.0]);
        let vec = feature_to_vector(&feature).unwrap();
        assert_eq!(vec.len(), 3);
        assert_eq!(vec[0], 1.0);
    }
}
