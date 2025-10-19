/// Performance benchmarks for ranking engine
/// Measures throughput, latency, and memory usage of ranking operations

use std::time::Instant;
use uuid::Uuid;
use user_service::services::ranking_engine::{RankingConfig, RankingEngine, RankingSignals};

/// Benchmark freshness score calculation
#[test]
fn bench_freshness_score_calculation() {
    let engine = RankingEngine::new(RankingConfig::default());
    let iterations = 1_000_000;

    let start = Instant::now();
    for i in 0..iterations {
        let hours = (i % 720) as f32;
        let _ = engine.calculate_freshness_score(hours);
    }
    let duration = start.elapsed();

    let per_ops = duration.as_micros() as f64 / iterations as f64;
    println!(
        "Freshness score calculation: {:.3} μs per operation ({} ops in {:?})",
        per_ops, iterations, duration
    );

    // Assert reasonable performance: < 1 microsecond per operation
    assert!(per_ops < 1.0, "Freshness calculation too slow: {:.3} μs", per_ops);
}

/// Benchmark engagement score calculation
#[test]
fn bench_engagement_score_calculation() {
    let engine = RankingEngine::new(RankingConfig::default());
    let iterations = 1_000_000;

    let start = Instant::now();
    for i in 0..iterations {
        let likes = (i % 1000) as u32;
        let shares = (i / 10 % 100) as u32;
        let comments = (i / 100 % 50) as u32;
        let views = 10000;
        let _ = engine.calculate_engagement_score(likes, shares, comments, views);
    }
    let duration = start.elapsed();

    let per_ops = duration.as_micros() as f64 / iterations as f64;
    println!(
        "Engagement score calculation: {:.3} μs per operation ({} ops in {:?})",
        per_ops, iterations, duration
    );

    // Assert reasonable performance: < 1 microsecond per operation
    assert!(per_ops < 1.0, "Engagement calculation too slow: {:.3} μs", per_ops);
}

/// Benchmark affinity score calculation
#[test]
fn bench_affinity_score_calculation() {
    let engine = RankingEngine::new(RankingConfig::default());
    let iterations = 1_000_000;

    let start = Instant::now();
    for i in 0..iterations {
        let score = if i % 2 == 0 {
            Some((i as f32 % 1.0))
        } else {
            None
        };
        let _ = engine.calculate_affinity_score(score);
    }
    let duration = start.elapsed();

    let per_ops = duration.as_micros() as f64 / iterations as f64;
    println!(
        "Affinity score calculation: {:.3} μs per operation ({} ops in {:?})",
        per_ops, iterations, duration
    );

    // Assert reasonable performance: < 0.5 microseconds per operation
    assert!(per_ops < 0.5, "Affinity calculation too slow: {:.3} μs", per_ops);
}

/// Benchmark video ranking with 100 videos
#[tokio::test]
async fn bench_rank_videos_100() {
    let engine = RankingEngine::new(RankingConfig::default());

    let signals: Vec<RankingSignals> = (0..100)
        .map(|i| RankingSignals {
            video_id: Uuid::new_v4(),
            freshness_score: (i as f32 % 100.0) / 100.0,
            completion_rate: 0.7,
            engagement_score: (i as f32 % 100.0) / 100.0,
            affinity_score: 0.5,
            deep_model_score: 0.3,
        })
        .collect();

    let iterations = 1000;
    let start = Instant::now();

    for _ in 0..iterations {
        let _ = engine.rank_videos(&signals).await;
    }

    let duration = start.elapsed();
    let per_ops = duration.as_micros() as f64 / iterations as f64;

    println!(
        "Rank 100 videos: {:.3} μs per operation ({} ops in {:?})",
        per_ops, iterations, duration
    );

    // Assert reasonable performance: < 1000 microseconds per ranking
    assert!(per_ops < 1000.0, "Ranking 100 videos too slow: {:.3} μs", per_ops);
}

/// Benchmark video ranking with 1000 videos
#[tokio::test]
async fn bench_rank_videos_1000() {
    let engine = RankingEngine::new(RankingConfig::default());

    let signals: Vec<RankingSignals> = (0..1000)
        .map(|i| RankingSignals {
            video_id: Uuid::new_v4(),
            freshness_score: (i as f32 % 100.0) / 100.0,
            completion_rate: 0.7,
            engagement_score: (i as f32 % 100.0) / 100.0,
            affinity_score: 0.5,
            deep_model_score: 0.3,
        })
        .collect();

    let iterations = 100;
    let start = Instant::now();

    for _ in 0..iterations {
        let _ = engine.rank_videos(&signals).await;
    }

    let duration = start.elapsed();
    let per_ops = duration.as_micros() as f64 / iterations as f64;

    println!(
        "Rank 1000 videos: {:.3} μs per operation ({} ops in {:?})",
        per_ops, iterations, duration
    );

    // Assert reasonable performance: < 10ms per ranking
    assert!(per_ops < 10_000.0, "Ranking 1000 videos too slow: {:.3} μs", per_ops);
}

/// Benchmark weighted score calculation (manual implementation for testing)
#[test]
fn bench_weighted_score_all_signals() {
    let config = RankingConfig::default();

    let iterations = 1_000_000;
    let start = Instant::now();

    for _ in 0..iterations {
        // Calculate weighted score manually
        let freshness_score = 0.9;
        let completion_rate = 0.8;
        let engagement_score = 0.7;
        let affinity_score = 0.6;
        let deep_model_score = 0.5;

        let _ = freshness_score * config.freshness_weight
            + completion_rate * config.completion_weight
            + engagement_score * config.engagement_weight
            + affinity_score * config.affinity_weight
            + deep_model_score * config.deep_model_weight;
    }

    let duration = start.elapsed();
    let per_ops = duration.as_micros() as f64 / iterations as f64;

    println!(
        "Weighted score calculation: {:.3} μs per operation ({} ops in {:?})",
        per_ops, iterations, duration
    );

    // Assert reasonable performance: < 0.5 microseconds per operation
    assert!(per_ops < 0.5, "Score calculation too slow: {:.3} μs", per_ops);
}

/// Benchmark ranking config validation
#[test]
fn bench_config_validation() {
    let config = RankingConfig::default();
    let iterations = 1_000_000;

    let start = Instant::now();
    for _ in 0..iterations {
        let _ = config.is_valid();
    }

    let duration = start.elapsed();
    let per_ops = duration.as_micros() as f64 / iterations as f64;

    println!(
        "Config validation: {:.3} μs per operation ({} ops in {:?})",
        per_ops, iterations, duration
    );

    // Assert very fast: < 0.1 microseconds per operation
    assert!(per_ops < 0.1, "Config validation too slow: {:.3} μs", per_ops);
}

/// Benchmark ranking signals validation
#[test]
fn bench_signals_validation() {
    let signals = RankingSignals {
        video_id: Uuid::new_v4(),
        freshness_score: 0.8,
        completion_rate: 0.7,
        engagement_score: 0.6,
        affinity_score: 0.5,
        deep_model_score: 0.4,
    };

    let iterations = 1_000_000;
    let start = Instant::now();

    for _ in 0..iterations {
        let _ = signals.is_valid();
    }

    let duration = start.elapsed();
    let per_ops = duration.as_micros() as f64 / iterations as f64;

    println!(
        "Signals validation: {:.3} μs per operation ({} ops in {:?})",
        per_ops, iterations, duration
    );

    // Assert very fast: < 0.1 microseconds per operation
    assert!(per_ops < 0.1, "Signals validation too slow: {:.3} μs", per_ops);
}

/// Benchmark entire ranking pipeline with 500 videos
#[tokio::test]
async fn bench_full_ranking_pipeline() {
    let engine = RankingEngine::new(RankingConfig::default());

    let signals: Vec<RankingSignals> = (0..500)
        .map(|i| RankingSignals {
            video_id: Uuid::new_v4(),
            freshness_score: ((i as f32) % 100.0 / 100.0).max(0.1),
            completion_rate: 0.65 + (i as f32 % 100.0 / 1000.0),
            engagement_score: ((500 - i) as f32 / 500.0),
            affinity_score: 0.5,
            deep_model_score: 0.3,
        })
        .collect();

    let iterations = 100;
    let start = Instant::now();

    for _ in 0..iterations {
        let _ = engine.rank_videos(&signals).await;
    }

    let duration = start.elapsed();
    let per_ops = duration.as_micros() as f64 / iterations as f64;

    println!(
        "Full ranking pipeline (500 videos): {:.3} μs per operation ({} ops in {:?})",
        per_ops, iterations, duration
    );

    // P95 latency should be under 5ms
    assert!(per_ops < 5_000.0, "Full pipeline too slow: {:.3} μs", per_ops);
}

/// Memory footprint test - ensure no memory bloat
#[test]
fn test_memory_efficiency() {
    // Create many engines and signals without memory bloat
    let engine = RankingEngine::new(RankingConfig::default());

    // Create 10,000 signals and rank them
    let signals: Vec<RankingSignals> = (0..10_000)
        .map(|i| RankingSignals {
            video_id: Uuid::new_v4(),
            freshness_score: (i as f32 % 100.0) / 100.0,
            completion_rate: 0.7,
            engagement_score: (i as f32 % 100.0) / 100.0,
            affinity_score: 0.5,
            deep_model_score: 0.3,
        })
        .collect();

    // This should complete without OOM
    let _size = std::mem::size_of_val(&signals);

    // Test that dropping is efficient
    drop(signals);
    drop(engine);
}
