use criterion::{black_box, criterion_group, criterion_main, Criterion};
use uuid::Uuid;

// Mock the RankedPost struct for benchmarking
#[derive(Debug, Clone)]
pub struct RankedPost {
    pub post_id: Uuid,
    pub combined_score: f64,
    pub reason: &'static str,
}

// Mock FeedCandidate for benchmarking
#[derive(Debug, Clone)]
pub struct FeedCandidate {
    pub post_id: String,
    pub author_id: String,
    pub combined_score: f64,
}

impl FeedCandidate {
    pub fn post_id_uuid(&self) -> Result<Uuid, uuid::Error> {
        Uuid::parse_str(&self.post_id)
    }
}

/// Benchmark the optimized rank_candidates function (pre-allocated with_capacity)
fn bench_rank_candidates_optimized(c: &mut Criterion) {
    let mut group = c.benchmark_group("rank_candidates");

    for candidate_count in [100, 1000, 10000].iter() {
        let candidates: Vec<FeedCandidate> = (0..*candidate_count)
            .map(|i| FeedCandidate {
                post_id: Uuid::new_v4().to_string(),
                author_id: Uuid::new_v4().to_string(),
                combined_score: (i as f64) * 0.5,
            })
            .collect();

        group.bench_with_input(
            format!("optimized_{}_candidates", candidate_count),
            &candidates,
            |b, cands| {
                b.iter(|| {
                    let mut ranked = Vec::with_capacity(cands.len());
                    for candidate in cands {
                        if let Ok(post_id) = candidate.post_id_uuid() {
                            ranked.push(RankedPost {
                                post_id,
                                combined_score: black_box(candidate.combined_score),
                                reason: "combined_score",
                            });
                        }
                    }
                    ranked
                });
            },
        );
    }

    group.finish();
}

/// Benchmark the naive implementation (Vec::new() without capacity)
fn bench_rank_candidates_naive(c: &mut Criterion) {
    let mut group = c.benchmark_group("rank_candidates_naive");

    for candidate_count in [100, 1000, 10000].iter() {
        let candidates: Vec<FeedCandidate> = (0..*candidate_count)
            .map(|i| FeedCandidate {
                post_id: Uuid::new_v4().to_string(),
                author_id: Uuid::new_v4().to_string(),
                combined_score: (i as f64) * 0.5,
            })
            .collect();

        group.bench_with_input(
            format!("naive_{}_candidates", candidate_count),
            &candidates,
            |b, cands| {
                b.iter(|| {
                    let mut ranked = Vec::new(); // No pre-allocation
                    for candidate in cands {
                        if let Ok(post_id) = candidate.post_id_uuid() {
                            ranked.push(RankedPost {
                                post_id,
                                combined_score: black_box(candidate.combined_score),
                                reason: "combined_score",
                            });
                        }
                    }
                    ranked
                });
            },
        );
    }

    group.finish();
}

/// Benchmark UUID parsing performance
fn bench_uuid_parsing(c: &mut Criterion) {
    let mut group = c.benchmark_group("uuid_parsing");

    let uuid_strs: Vec<String> = (0..1000)
        .map(|_| Uuid::new_v4().to_string())
        .collect();

    group.bench_with_input(
        "parse_1000_uuids",
        &uuid_strs,
        |b, strs| {
            b.iter(|| {
                strs.iter()
                    .filter_map(|s| Uuid::parse_str(s).ok())
                    .collect::<Vec<_>>()
            });
        },
    );

    group.finish();
}

/// Benchmark string allocation impact
fn bench_string_allocation(c: &mut Criterion) {
    c.bench_function("string_alloc_1000", |b| {
        b.iter(|| {
            (0..1000)
                .map(|_| "combined_score".to_string()) // Heap allocation
                .collect::<Vec<_>>()
        });
    });

    c.bench_function("static_str_1000", |b| {
        b.iter(|| {
            (0..1000)
                .map(|_| "combined_score" as &'static str) // No allocation
                .collect::<Vec<_>>()
        });
    });
}

criterion_group!(
    benches,
    bench_rank_candidates_optimized,
    bench_rank_candidates_naive,
    bench_uuid_parsing,
    bench_string_allocation
);
criterion_main!(benches);
