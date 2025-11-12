// Utility functions for ranking-service

/// Normalize a score to [0, 1] range
pub fn normalize_score(score: f32, min: f32, max: f32) -> f32 {
    if max - min < f32::EPSILON {
        0.5
    } else {
        ((score - min) / (max - min)).clamp(0.0, 1.0)
    }
}

/// Compute exponential decay for time-based scoring
pub fn exponential_decay(age_hours: f32, half_life_hours: f32) -> f32 {
    (-age_hours / half_life_hours * 0.693).exp()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_normalize_score() {
        assert!((normalize_score(5.0, 0.0, 10.0) - 0.5).abs() < 0.001);
        assert!((normalize_score(10.0, 0.0, 10.0) - 1.0).abs() < 0.001);
        assert!((normalize_score(0.0, 0.0, 10.0) - 0.0).abs() < 0.001);
    }

    #[test]
    fn test_exponential_decay() {
        // 半衰期後應該約為 0.5
        let score = exponential_decay(24.0, 24.0);
        assert!((score - 0.5).abs() < 0.01);

        // 0 小時衰減應該為 1.0
        let score_fresh = exponential_decay(0.0, 24.0);
        assert!((score_fresh - 1.0).abs() < 0.001);
    }
}
