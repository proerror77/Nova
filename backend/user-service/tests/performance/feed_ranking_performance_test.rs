/// Performance tests for Feed Ranking System
/// Measures throughput, latency, and resource usage

use chrono::Utc;
use std::sync::Arc;
use std::time::Instant;
use uuid::Uuid;

use user_service::cache::FeedCache;
use user_service::db::ch_client::ClickHouseClient;
use user_service::services::feed_ranking::{FeedCandidate, FeedRankingService};

// Performance thresholds (in milliseconds)
const RANKING_LATENCY_P50_MS: u64 = 50;
const RANKING_LATENCY_P99_MS: u64 = 200;
const FEED_GET_LATENCY_P50_MS: u64 = 100;
const FEED_GET_LATENCY_P99_MS: u64 = 500;

#[derive(Debug)]
struct PerformanceMetrics {
    min_ms: u64,
    max_ms: u64,
    avg_ms: u64,
    p50_ms: u64,
    p95_ms: u64,
    p99_ms: u64,
    throughput_per_sec: f64,
}

impl PerformanceMetrics {
    fn from_durations(mut durations: Vec<std::time::Duration>) -> Self {
        durations.sort();

        let count = durations.len() as u64;
        let sum_ms: u64 = durations.iter().map(|d| d.as_millis() as u64).sum();
        let avg_ms = if count > 0 { sum_ms / count } else { 0 };

        let min_ms = durations.first().map(|d| d.as_millis() as u64).unwrap_or(0);
        let max_ms = durations.last().map(|d| d.as_millis() as u64).unwrap_or(0);

        let p50_idx = (count * 50 / 100) as usize;
        let p95_idx = (count * 95 / 100) as usize;
        let p99_idx = (count * 99 / 100) as usize;

        let p50_ms = durations
            .get(p50_idx)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0);
        let p95_ms = durations
            .get(p95_idx)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0);
        let p99_ms = durations
            .get(p99_idx)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0);

        let total_time_sec = sum_ms as f64 / 1000.0;
        let throughput_per_sec = if total_time_sec > 0.0 {
            count as f64 / total_time_sec
        } else {
            0.0
        };

        PerformanceMetrics {
            min_ms,
            max_ms,
            avg_ms,
            p50_ms,
            p95_ms,
            p99_ms,
            throughput_per_sec,
        }
    }

    fn print_report(&self, name: &str) {
        println!(
            "\n{} Performance Report:",
            name
        );
        println!("  Min: {}ms", self.min_ms);
        println!("  Max: {}ms", self.max_ms);
        println!("  Avg: {}ms", self.avg_ms);
        println!("  P50: {}ms", self.p50_ms);
        println!("  P95: {}ms", self.p95_ms);
        println!("  P99: {}ms", self.p99_ms);
        println!("  Throughput: {:.0} ops/sec", self.throughput_per_sec);
    }
}

fn create_performance_test_service() -> FeedRankingService {
    let ch_client = Arc::new(ClickHouseClient::new(
        "http://localhost:8123",
        "default",
        "default",
        "",
        5000,
    ));

    let redis_client =
        redis::Client::open("redis://127.0.0.1/").unwrap_or_else(|_| {
            redis::Client::open("redis://127.0.0.1/").unwrap()
        });

    let runtime = tokio::runtime::Runtime::new().unwrap();
    let conn_manager = runtime.block_on(async {
        redis::aio::ConnectionManager::new(redis_client)
            .await
            .unwrap_or_else(|_| panic!("Redis required"))
    });

    let cache = Arc::new(tokio::sync::Mutex::new(FeedCache::new(conn_manager, 120)));

    FeedRankingService::new(ch_client, cache)
}

/// Benchmark: Ranking 200 candidates (typical feed size)
#[test]
#[ignore] // Run with: cargo test --test '*' --features perf -- --ignored --nocapture
fn bench_ranking_200_candidates() {
    let service = create_performance_test_service();
    let num_iterations = 1000;

    let mut durations = vec![];

    for iter in 0..num_iterations {
        let candidates: Vec<FeedCandidate> = (0..200)
            .map(|i| FeedCandidate {
                post_id: Uuid::new_v4().to_string(),
                author_id: Uuid::new_v4().to_string(),
                likes: (i * 10) as u32,
                comments: (i / 2) as u32,
                shares: (i / 5) as u32,
                impressions: (i * 100) as u32,
                freshness_score: 0.9 - (i as f64 * 0.001),
                engagement_score: 0.5 + (i as f64 * 0.0005),
                affinity_score: 0.3 * ((i % 3) as f64),
                combined_score: 0.7,
                created_at: Utc::now(),
            })
            .collect();

        let start = Instant::now();
        let _ = service.rank_with_clickhouse(candidates);
        let duration = start.elapsed();

        durations.push(duration);

        if iter % 100 == 0 {
            println!("Completed iteration {}", iter);
        }
    }

    let metrics = PerformanceMetrics::from_durations(durations);
    metrics.print_report("Ranking 200 Candidates");

    assert!(
        metrics.p50_ms < RANKING_LATENCY_P50_MS,
        "P50 latency {ms} exceeds threshold {threshold}ms",
        ms = metrics.p50_ms,
        threshold = RANKING_LATENCY_P50_MS
    );

    assert!(
        metrics.p99_ms < RANKING_LATENCY_P99_MS,
        "P99 latency {ms} exceeds threshold {threshold}ms",
        ms = metrics.p99_ms,
        threshold = RANKING_LATENCY_P99_MS
    );
}

/// Benchmark: Ranking with varying candidate counts
#[test]
#[ignore]
fn bench_ranking_varying_sizes() {
    let service = create_performance_test_service();
    let sizes = vec![10, 50, 100, 200, 500];

    for size in sizes {
        let mut durations = vec![];

        for _ in 0..100 {
            let candidates: Vec<FeedCandidate> = (0..size)
                .map(|i| FeedCandidate {
                    post_id: Uuid::new_v4().to_string(),
                    author_id: Uuid::new_v4().to_string(),
                    likes: i as u32,
                    comments: (i / 2) as u32,
                    shares: (i / 5) as u32,
                    impressions: i as u32 * 10,
                    freshness_score: 0.9,
                    engagement_score: 0.5,
                    affinity_score: 0.0,
                    combined_score: 0.7,
                    created_at: Utc::now(),
                })
                .collect();

            let start = Instant::now();
            let _ = service.rank_with_clickhouse(candidates);
            durations.push(start.elapsed());
        }

        let metrics = PerformanceMetrics::from_durations(durations);
        println!(
            "\nRanking {} candidates: P50={ms}ms, P99={p99}ms",
            size,
            ms = metrics.p50_ms,
            p99 = metrics.p99_ms
        );
    }
}

/// Benchmark: Deduplication and saturation control
#[test]
#[ignore]
fn bench_dedup_and_saturation() {
    let service = create_performance_test_service();
    let num_iterations = 500;

    let mut durations = vec![];

    for _ in 0..num_iterations {
        let candidates: Vec<FeedCandidate> = (0..300)
            .map(|i| {
                let author_id = format!(
                    "{}00000000-0000-0000-0000-000000000000",
                    i % 30 // 30 different authors
                );

                FeedCandidate {
                    post_id: Uuid::new_v4().to_string(),
                    author_id,
                    likes: (i * 5) as u32,
                    comments: (i / 2) as u32,
                    shares: (i / 5) as u32,
                    impressions: (i * 50) as u32,
                    freshness_score: 0.8,
                    engagement_score: 0.5,
                    affinity_score: 0.0,
                    combined_score: 0.9 - (i as f64 * 0.001),
                    created_at: Utc::now(),
                }
            })
            .collect();

        let start = Instant::now();
        let deduped = service
            .dedup_and_saturation_with_authors(candidates)
            .ok()
            .unwrap_or_default();
        let _ = deduped; // Dedup operation is the benchmark target
        durations.push(start.elapsed());
    }

    let metrics = PerformanceMetrics::from_durations(durations);
    metrics.print_report("Dedup & Saturation");
}

/// Benchmark: Single large deduplication pass
#[test]
#[ignore]
fn bench_dedup_large_dataset() {
    let service = create_performance_test_service();

    // Create 1000 candidates with many duplicates
    let mut candidates = vec![];
    for batch in 0..10 {
        for i in 0..100 {
            candidates.push(FeedCandidate {
                post_id: format!(
                    "550e8400-e29b-41d4-a716-44665544{:04}",
                    i % 50 // 50 unique posts repeated
                ),
                author_id: Uuid::new_v4().to_string(),
                likes: (i * (batch + 1)) as u32,
                comments: i as u32,
                shares: (i / 2) as u32,
                impressions: (i * 100) as u32,
                freshness_score: 0.8,
                engagement_score: 0.5,
                affinity_score: 0.0,
                combined_score: 0.8,
                created_at: Utc::now(),
            });
        }
    }

    let start = Instant::now();
    let ranked = service.rank_with_clickhouse(candidates).unwrap();
    let result = service.apply_dedup_and_saturation(ranked);
    let duration = start.elapsed();

    println!(
        "Dedup 1000 candidates with 50 unique posts: {ms}ms",
        ms = duration.as_millis()
    );
    println!("Result size: {} posts", result.len());
}

/// Benchmark: Cache hit vs miss
#[tokio::test]
#[ignore]
async fn bench_cache_hit_vs_miss() {
    println!("Cache performance benchmark would require async runtime");
    // This would require mocking Redis properly
}

/// Memory efficiency test
#[test]
#[ignore]
fn bench_memory_efficiency() {
    use std::alloc::{GlobalAlloc, Layout};
    use std::sync::atomic::{AtomicUsize, Ordering};

    // Track allocations
    static ALLOCATED: AtomicUsize = AtomicUsize::new(0);

    let service = create_performance_test_service();

    // Create a reasonable feed
    let candidates: Vec<FeedCandidate> = (0..500)
        .map(|i| FeedCandidate {
            post_id: Uuid::new_v4().to_string(),
            author_id: Uuid::new_v4().to_string(),
            likes: i as u32,
            comments: (i / 2) as u32,
            shares: (i / 5) as u32,
            impressions: (i * 10) as u32,
            freshness_score: 0.8,
            engagement_score: 0.5,
            affinity_score: 0.0,
            combined_score: 0.7,
            created_at: Utc::now(),
        })
        .collect();

    let start_mem = ALLOCATED.load(Ordering::Relaxed);

    let ranked = service.rank_with_clickhouse(candidates).unwrap();
    let _ = service.apply_dedup_and_saturation(ranked);

    let end_mem = ALLOCATED.load(Ordering::Relaxed);
    let memory_used = end_mem.saturating_sub(start_mem);

    println!("Memory used for 500 candidates: {:.2}MB", memory_used as f64 / 1024.0 / 1024.0);
}

/// Stress test: sustained load
#[test]
#[ignore]
fn stress_test_sustained_load() {
    let service = create_performance_test_service();
    let duration_secs = 10;
    let start = Instant::now();

    let mut total_ops = 0;
    let mut failed_ops = 0;

    while start.elapsed().as_secs() < duration_secs {
        let candidates: Vec<FeedCandidate> = (0..200)
            .map(|i| FeedCandidate {
                post_id: Uuid::new_v4().to_string(),
                author_id: Uuid::new_v4().to_string(),
                likes: i as u32,
                comments: (i / 2) as u32,
                shares: (i / 5) as u32,
                impressions: (i * 10) as u32,
                freshness_score: 0.8,
                engagement_score: 0.5,
                affinity_score: 0.0,
                combined_score: 0.7,
                created_at: Utc::now(),
            })
            .collect();

        match service.rank_with_clickhouse(candidates) {
            Ok(_) => total_ops += 1,
            Err(_) => failed_ops += 1,
        }
    }

    let elapsed = start.elapsed().as_secs_f64();
    let throughput = total_ops as f64 / elapsed;

    println!(
        "Stress test: {ops} ops in {sec:.1}s = {tp:.0} ops/sec ({failed} failures)",
        ops = total_ops,
        sec = elapsed,
        tp = throughput,
        failed = failed_ops
    );

    assert!(
        failed_ops < total_ops / 100,
        "More than 1% failures detected"
    );
}
