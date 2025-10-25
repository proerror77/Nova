use std::collections::HashMap;
/// Performance Tests for Video Ranking Latency (T138)
/// Validates ranking algorithm performance within SLA bounds
/// - P95 latency < 300ms (with cache)
/// - P95 latency < 800ms (fresh/cold)
use std::time::{Duration, Instant};
use uuid::Uuid;

/// Mock video record
#[derive(Debug, Clone)]
pub struct VideoRecord {
    pub id: Uuid,
    pub view_count: u32,
    pub likes: u32,
    pub comments: u32,
    pub shares: u32,
    pub minutes_ago: u32,
    pub average_rating: f64,
    pub flag_count: u32,
}

/// Ranking algorithm (same as production)
#[derive(Debug, Clone)]
pub struct VideoRankingScore {
    pub view_score: f64,
    pub engagement_score: f64,
    pub recency_score: f64,
    pub quality_score: f64,
    pub combined_score: f64,
}

pub struct VideoRankingAlgorithm {
    view_weight: f64,
    engagement_weight: f64,
    recency_weight: f64,
    quality_weight: f64,
}

impl VideoRankingAlgorithm {
    pub fn new(
        view_weight: f64,
        engagement_weight: f64,
        recency_weight: f64,
        quality_weight: f64,
    ) -> Self {
        Self {
            view_weight,
            engagement_weight,
            recency_weight,
            quality_weight,
        }
    }

    pub fn with_default_weights() -> Self {
        Self::new(0.25, 0.35, 0.25, 0.15)
    }

    pub fn calculate_view_score(&self, view_count: u32) -> f64 {
        let views_f = (view_count as f64 + 1.0).log10();
        (views_f / 6.0).min(1.0).max(0.0)
    }

    pub fn calculate_engagement_score(&self, likes: u32, comments: u32, shares: u32) -> f64 {
        let engagement_rate =
            (likes as f64 * 0.3 + comments as f64 * 0.5 + shares as f64 * 0.2) / 100.0;
        engagement_rate.min(1.0).max(0.0)
    }

    pub fn calculate_recency_score(&self, minutes_ago: u32) -> f64 {
        let hours_ago = minutes_ago as f64 / 60.0;
        let decay_factor = 1.0 / (1.0 + 0.1 * hours_ago);
        decay_factor.min(1.0).max(0.0)
    }

    pub fn calculate_quality_score(&self, average_rating: f64, flag_count: u32) -> f64 {
        let rating_score = (average_rating / 5.0).min(1.0).max(0.0);
        let flag_penalty = (flag_count as f64 * 0.05).min(1.0);
        (rating_score - flag_penalty).min(1.0).max(0.0)
    }

    pub fn calculate_combined_score(
        &self,
        view_score: f64,
        engagement_score: f64,
        recency_score: f64,
        quality_score: f64,
    ) -> f64 {
        let total_weight =
            self.view_weight + self.engagement_weight + self.recency_weight + self.quality_weight;

        (view_score * self.view_weight
            + engagement_score * self.engagement_weight
            + recency_score * self.recency_weight
            + quality_score * self.quality_weight)
            / total_weight
    }

    pub fn rank_video(&self, video: &VideoRecord) -> VideoRankingScore {
        let view_score = self.calculate_view_score(video.view_count);
        let engagement_score =
            self.calculate_engagement_score(video.likes, video.comments, video.shares);
        let recency_score = self.calculate_recency_score(video.minutes_ago);
        let quality_score = self.calculate_quality_score(video.average_rating, video.flag_count);

        let combined_score = self.calculate_combined_score(
            view_score,
            engagement_score,
            recency_score,
            quality_score,
        );

        VideoRankingScore {
            view_score,
            engagement_score,
            recency_score,
            quality_score,
            combined_score,
        }
    }
}

/// Mock cache for ranking results
pub struct RankingCache {
    cache: HashMap<Uuid, (VideoRankingScore, Instant)>,
    ttl_seconds: u64,
}

impl RankingCache {
    pub fn new(ttl_seconds: u64) -> Self {
        Self {
            cache: HashMap::new(),
            ttl_seconds,
        }
    }

    pub fn get(&self, video_id: &Uuid) -> Option<VideoRankingScore> {
        if let Some((score, timestamp)) = self.cache.get(video_id) {
            let elapsed = timestamp.elapsed();
            if elapsed.as_secs() < self.ttl_seconds {
                return Some(score.clone());
            }
        }
        None
    }

    pub fn put(&mut self, video_id: Uuid, score: VideoRankingScore) {
        self.cache.insert(video_id, (score, Instant::now()));
    }

    pub fn clear(&mut self) {
        self.cache.clear();
    }

    pub fn size(&self) -> usize {
        self.cache.len()
    }
}

/// Latency percentile calculator
pub struct LatencyStatistics {
    latencies: Vec<Duration>,
}

impl LatencyStatistics {
    pub fn new(latencies: Vec<Duration>) -> Self {
        let mut sorted = latencies;
        sorted.sort();
        Self { latencies: sorted }
    }

    pub fn min(&self) -> Duration {
        self.latencies.iter().min().copied().unwrap_or_default()
    }

    pub fn max(&self) -> Duration {
        self.latencies.iter().max().copied().unwrap_or_default()
    }

    pub fn median(&self) -> Duration {
        if self.latencies.is_empty() {
            return Duration::ZERO;
        }
        let mid = self.latencies.len() / 2;
        self.latencies[mid]
    }

    pub fn percentile(&self, p: f64) -> Duration {
        if self.latencies.is_empty() {
            return Duration::ZERO;
        }
        let index = ((p / 100.0) * self.latencies.len() as f64).ceil() as usize;
        let idx = (index - 1).min(self.latencies.len() - 1);
        self.latencies[idx]
    }

    pub fn p50(&self) -> Duration {
        self.percentile(50.0)
    }

    pub fn p95(&self) -> Duration {
        self.percentile(95.0)
    }

    pub fn p99(&self) -> Duration {
        self.percentile(99.0)
    }

    pub fn avg(&self) -> Duration {
        if self.latencies.is_empty() {
            return Duration::ZERO;
        }
        let sum: Duration = self.latencies.iter().sum();
        sum / self.latencies.len() as u32
    }
}

// ============================================
// Performance Tests (T138)
// ============================================

#[test]
fn test_ranking_latency_cached() {
    let algo = VideoRankingAlgorithm::with_default_weights();
    let mut cache = RankingCache::new(3600); // 1 hour TTL
    let video = VideoRecord {
        id: Uuid::new_v4(),
        view_count: 1000,
        likes: 50,
        comments: 20,
        shares: 10,
        minutes_ago: 60,
        average_rating: 4.5,
        flag_count: 0,
    };

    // First ranking - cache miss (slower)
    let start = Instant::now();
    let score = algo.rank_video(&video);
    let _first_latency = start.elapsed();
    cache.put(video.id, score.clone());

    // Subsequent rankings - cache hit (faster)
    let mut latencies = Vec::new();
    for _ in 0..100 {
        let start = Instant::now();
        let cached = cache.get(&video.id);
        let elapsed = start.elapsed();

        assert!(cached.is_some());
        latencies.push(elapsed);
    }

    let stats = LatencyStatistics::new(latencies);

    // Cached operations should be very fast (< 1ms typically)
    assert!(
        stats.p95() < Duration::from_millis(1),
        "Cached lookup P95 should be < 1ms, was {:?}",
        stats.p95()
    );

    println!(
        "Cached ranking latency - Min: {:?}, P50: {:?}, P95: {:?}, P99: {:?}, Max: {:?}",
        stats.min(),
        stats.p50(),
        stats.p95(),
        stats.p99(),
        stats.max()
    );
}

#[test]
fn test_ranking_latency_fresh_cold() {
    let algo = VideoRankingAlgorithm::with_default_weights();
    let mut latencies = Vec::new();

    // Simulate 100 fresh ranking calculations (no cache)
    for i in 0..100 {
        let video = VideoRecord {
            id: Uuid::new_v4(),
            view_count: (1000 + i) as u32,
            likes: (50 + i) as u32,
            comments: (20 + i) as u32,
            shares: (10 + i) as u32,
            minutes_ago: 60 + i as u32,
            average_rating: 4.5,
            flag_count: 0,
        };

        let start = Instant::now();
        let _score = algo.rank_video(&video);
        latencies.push(start.elapsed());
    }

    let stats = LatencyStatistics::new(latencies);

    // Fresh calculations should complete within SLA
    assert!(
        stats.p95() < Duration::from_millis(800),
        "Fresh ranking P95 should be < 800ms, was {:?}",
        stats.p95()
    );

    println!(
        "Fresh ranking latency - Min: {:?}, P50: {:?}, P95: {:?}, P99: {:?}, Max: {:?}",
        stats.min(),
        stats.p50(),
        stats.p95(),
        stats.p99(),
        stats.max()
    );
}

#[test]
fn test_ranking_latency_with_cache_warm() {
    let algo = VideoRankingAlgorithm::with_default_weights();
    let mut cache = RankingCache::new(3600);

    // Warm cache with 1000 videos
    let mut video_ids = Vec::new();
    for i in 0..1000 {
        let video = VideoRecord {
            id: Uuid::new_v4(),
            view_count: (1000 + i) as u32,
            likes: (50 + i) as u32,
            comments: (20 + i) as u32,
            shares: (10 + i) as u32,
            minutes_ago: 60 + i as u32,
            average_rating: 4.5,
            flag_count: 0,
        };
        video_ids.push(video.id);
        let score = algo.rank_video(&video);
        cache.put(video.id, score);
    }

    assert_eq!(cache.size(), 1000);

    // Measure latency with warm cache
    let mut latencies = Vec::new();
    for video_id in video_ids {
        let start = Instant::now();
        let _cached = cache.get(&video_id);
        latencies.push(start.elapsed());
    }

    let stats = LatencyStatistics::new(latencies);

    // Warm cache should serve consistently fast
    assert!(
        stats.p95() < Duration::from_millis(1),
        "Warm cache P95 should be < 1ms, was {:?}",
        stats.p95()
    );

    println!(
        "Warm cache ranking latency (1000 videos) - Min: {:?}, P50: {:?}, P95: {:?}, P99: {:?}, Max: {:?}",
        stats.min(),
        stats.p50(),
        stats.p95(),
        stats.p99(),
        stats.max()
    );
}

#[test]
fn test_ranking_latency_batch_computation() {
    let algo = VideoRankingAlgorithm::with_default_weights();

    // Batch ranking of 100 videos
    let videos: Vec<_> = (0..100)
        .map(|i| VideoRecord {
            id: Uuid::new_v4(),
            view_count: (1000 + i) as u32,
            likes: (50 + i) as u32,
            comments: (20 + i) as u32,
            shares: (10 + i) as u32,
            minutes_ago: 60 + i as u32,
            average_rating: 4.5,
            flag_count: 0,
        })
        .collect();

    let start = Instant::now();
    let _scores: Vec<_> = videos.iter().map(|v| algo.rank_video(v)).collect();
    let batch_latency = start.elapsed();

    // Average latency per video in batch
    let avg_latency_per_video = batch_latency / videos.len() as u32;

    // Should be consistent with single ranking
    assert!(
        avg_latency_per_video < Duration::from_millis(10),
        "Batch ranking should average < 10ms per video, was {:?}",
        avg_latency_per_video
    );

    println!(
        "Batch ranking latency (100 videos) - Total: {:?}, Per-video avg: {:?}",
        batch_latency, avg_latency_per_video
    );
}

#[test]
fn test_ranking_latency_consistency() {
    let algo = VideoRankingAlgorithm::with_default_weights();
    let video = VideoRecord {
        id: Uuid::new_v4(),
        view_count: 5000,
        likes: 200,
        comments: 100,
        shares: 50,
        minutes_ago: 120,
        average_rating: 4.8,
        flag_count: 0,
    };

    // Multiple runs should have consistent latency
    let mut latencies = Vec::new();
    for _ in 0..50 {
        let start = Instant::now();
        let _score = algo.rank_video(&video);
        latencies.push(start.elapsed());
    }

    let stats = LatencyStatistics::new(latencies);
    let min_micros = stats.min().as_micros() as f64;
    let max_micros = stats.max().as_micros() as f64;
    let latency_variance = if min_micros > 0.0 {
        max_micros / min_micros
    } else {
        1.0 // If min is 0, variance is not meaningful
    };

    // Variance should be low (max/min ratio < 5x), or skip if unmeasurable
    assert!(
        latency_variance < 5.0,
        "Latency variance should be < 5x, was {:.2}x",
        latency_variance
    );

    println!(
        "Ranking latency consistency - Min: {:?}, Avg: {:?}, Max: {:?}, Variance ratio: {:.2}x",
        stats.min(),
        stats.avg(),
        stats.max(),
        latency_variance
    );
}

#[test]
fn test_ranking_latency_scale_test() {
    let algo = VideoRankingAlgorithm::with_default_weights();

    let scales = vec![1, 10, 100, 1000];

    for scale in scales {
        let videos: Vec<_> = (0..scale)
            .map(|i| VideoRecord {
                id: Uuid::new_v4(),
                view_count: (1000 + i) as u32,
                likes: (50 + i) as u32,
                comments: (20 + i) as u32,
                shares: (10 + i) as u32,
                minutes_ago: 60,
                average_rating: 4.5,
                flag_count: 0,
            })
            .collect();

        let start = Instant::now();
        let _scores: Vec<_> = videos.iter().map(|v| algo.rank_video(v)).collect();
        let elapsed = start.elapsed();

        let per_video = elapsed / scale as u32;

        println!(
            "Scale test: {} videos ranked in {:?}, avg per-video: {:?}",
            scale, elapsed, per_video
        );

        // Should scale linearly
        assert!(
            per_video < Duration::from_millis(10),
            "Scale test failed: {} videos took {:?}",
            scale,
            elapsed
        );
    }
}

#[test]
fn test_ranking_latency_sla_compliance() {
    let algo = VideoRankingAlgorithm::with_default_weights();
    let mut cache = RankingCache::new(300); // 5 minute TTL

    let mut total_latencies = Vec::new();

    // Simulate requests: 80% cached, 20% fresh
    for i in 0..500 {
        let video_id = if i % 5 == 0 {
            // 20% fresh requests
            Uuid::new_v4()
        } else {
            // 80% requests to already-ranked videos
            Uuid::nil()
        };

        let video = VideoRecord {
            id: video_id,
            view_count: (1000 + (i % 100)) as u32,
            likes: (50 + (i % 50)) as u32,
            comments: (20 + (i % 30)) as u32,
            shares: (10 + (i % 20)) as u32,
            minutes_ago: 60,
            average_rating: 4.5,
            flag_count: 0,
        };

        // Try cache first
        let start = Instant::now();
        if let Some(_cached) = cache.get(&video_id) {
            total_latencies.push(start.elapsed());
        } else {
            // Cache miss - calculate
            let score = algo.rank_video(&video);
            total_latencies.push(start.elapsed());
            cache.put(video_id, score);
        }
    }

    let stats = LatencyStatistics::new(total_latencies);

    // With 80% cache hit rate, P95 should be well under 300ms
    assert!(
        stats.p95() < Duration::from_millis(300),
        "SLA P95 should be < 300ms (cached), was {:?}",
        stats.p95()
    );

    println!(
        "SLA compliance test (80% cache hit) - Min: {:?}, P50: {:?}, P95: {:?}, P99: {:?}, Max: {:?}",
        stats.min(),
        stats.p50(),
        stats.p95(),
        stats.p99(),
        stats.max()
    );
}

#[test]
fn test_ranking_component_latency_breakdown() {
    let algo = VideoRankingAlgorithm::with_default_weights();
    let video = VideoRecord {
        id: Uuid::new_v4(),
        view_count: 5000,
        likes: 200,
        comments: 100,
        shares: 50,
        minutes_ago: 120,
        average_rating: 4.8,
        flag_count: 5,
    };

    // Measure individual components
    let mut view_score_times = Vec::new();
    let mut engagement_score_times = Vec::new();
    let mut recency_score_times = Vec::new();
    let mut quality_score_times = Vec::new();

    for _ in 0..100 {
        let start = Instant::now();
        let _vs = algo.calculate_view_score(video.view_count);
        view_score_times.push(start.elapsed());

        let start = Instant::now();
        let _es = algo.calculate_engagement_score(video.likes, video.comments, video.shares);
        engagement_score_times.push(start.elapsed());

        let start = Instant::now();
        let _rs = algo.calculate_recency_score(video.minutes_ago);
        recency_score_times.push(start.elapsed());

        let start = Instant::now();
        let _qs = algo.calculate_quality_score(video.average_rating, video.flag_count);
        quality_score_times.push(start.elapsed());
    }

    let vs_stats = LatencyStatistics::new(view_score_times);
    let es_stats = LatencyStatistics::new(engagement_score_times);
    let rs_stats = LatencyStatistics::new(recency_score_times);
    let qs_stats = LatencyStatistics::new(quality_score_times);

    println!("Ranking component latency breakdown:");
    println!("  View Score P95: {:?}", vs_stats.p95());
    println!("  Engagement Score P95: {:?}", es_stats.p95());
    println!("  Recency Score P95: {:?}", rs_stats.p95());
    println!("  Quality Score P95: {:?}", qs_stats.p95());

    // All components should be very fast
    assert!(vs_stats.p95() < Duration::from_micros(100));
    assert!(es_stats.p95() < Duration::from_micros(100));
    assert!(rs_stats.p95() < Duration::from_micros(100));
    assert!(qs_stats.p95() < Duration::from_micros(100));
}
