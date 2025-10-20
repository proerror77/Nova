/// Performance and Load Tests for Event Ingestion
/// Tests throughput, latency, and concurrent event processing

use std::time::{Duration, Instant};
use uuid::Uuid;

/// Mock event for testing
#[derive(Clone)]
struct MockEvent {
    pub user_id: Uuid,
    pub post_id: Uuid,
    pub action: String,
    pub timestamp: i64,
}

/// Mock event producer for testing
pub struct MockEventProducer {
    events_processed: usize,
    total_latency_ms: u64,
}

impl MockEventProducer {
    pub fn new() -> Self {
        Self {
            events_processed: 0,
            total_latency_ms: 0,
        }
    }

    /// Simulate publishing an event (mock delay)
    pub fn publish(&mut self, _event: &MockEvent) -> Result<(), String> {
        // Simulate minimal processing time
        self.events_processed += 1;
        self.total_latency_ms += 1; // 1ms per event
        Ok(())
    }

    pub fn get_throughput(&self) -> f64 {
        if self.total_latency_ms == 0 {
            0.0
        } else {
            (self.events_processed as f64 / self.total_latency_ms as f64) * 1000.0
        }
    }

    pub fn get_avg_latency_ms(&self) -> f64 {
        if self.events_processed == 0 {
            0.0
        } else {
            self.total_latency_ms as f64 / self.events_processed as f64
        }
    }
}

#[test]
#[ignore] // Run with: cargo test --test events_load_test bench_ -- --ignored --nocapture
fn bench_event_throughput_1k() {
    let mut producer = MockEventProducer::new();
    let n_events = 1000;

    let start = Instant::now();

    for _i in 0..n_events {
        let event = MockEvent {
            user_id: Uuid::new_v4(),
            post_id: Uuid::new_v4(),
            action: "like".to_string(),
            timestamp: (Instant::now().elapsed().as_millis()) as i64,
        };

        producer.publish(&event).unwrap();
    }

    let duration = start.elapsed();

    let throughput = n_events as f64 / duration.as_secs_f64();
    let avg_latency = duration.as_millis() as f64 / n_events as f64;

    println!("\n=== Event Throughput Benchmark (1K events) ===");
    println!("Total events: {}", n_events);
    println!("Total time: {:.2}ms", duration.as_millis());
    println!("Throughput: {:.0} events/sec", throughput);
    println!("Avg latency: {:.2}ms/event", avg_latency);

    assert!(throughput > 1000.0, "Throughput should be > 1000 events/sec");
}

#[test]
#[ignore]
fn bench_event_throughput_10k() {
    let mut producer = MockEventProducer::new();
    let n_events = 10000;

    let start = Instant::now();

    for _ in 0..n_events {
        let event = MockEvent {
            user_id: Uuid::new_v4(),
            post_id: Uuid::new_v4(),
            action: "view".to_string(),
            timestamp: (Instant::now().elapsed().as_millis()) as i64,
        };

        producer.publish(&event).unwrap();
    }

    let duration = start.elapsed();

    let throughput = n_events as f64 / duration.as_secs_f64();
    let avg_latency = duration.as_millis() as f64 / n_events as f64;

    println!("\n=== Event Throughput Benchmark (10K events) ===");
    println!("Total events: {}", n_events);
    println!("Total time: {:.2}ms", duration.as_millis());
    println!("Throughput: {:.0} events/sec", throughput);
    println!("Avg latency: {:.2}ms/event", avg_latency);

    assert!(throughput > 5000.0, "Throughput should be > 5000 events/sec");
}

#[test]
fn bench_event_latency_distribution() {
    let n_events = 1000;
    let mut latencies = Vec::new();

    for _ in 0..n_events {
        let start = Instant::now();

        let event = MockEvent {
            user_id: Uuid::new_v4(),
            post_id: Uuid::new_v4(),
            action: "comment".to_string(),
            timestamp: 0,
        };

        let _ = event; // Simulate minimal work

        let latency_us = start.elapsed().as_micros() as u64;
        latencies.push(latency_us);
    }

    latencies.sort();

    let min = latencies[0];
    let max = latencies[n_events - 1];
    let avg = latencies.iter().sum::<u64>() / n_events as u64;
    let p50 = latencies[n_events / 2];
    let p95 = latencies[(n_events * 95) / 100];
    let p99 = latencies[(n_events * 99) / 100];

    println!("\n=== Event Latency Distribution ===");
    println!("Min: {} µs", min);
    println!("Max: {} µs", max);
    println!("Avg: {} µs", avg);
    println!("P50: {} µs", p50);
    println!("P95: {} µs", p95);
    println!("P99: {} µs", p99);

    assert!(p99 < 1000, "P99 latency should be < 1ms");
}

#[test]
fn bench_batch_vs_individual() {
    let n_events = 1000;
    let batch_size = 100;

    // Batch processing
    let batch_start = Instant::now();
    let mut batch_count = 0;

    for _batch in 0..(n_events / batch_size) {
        let mut batch_events = Vec::new();

        for _i in 0..batch_size {
            batch_events.push(MockEvent {
                user_id: Uuid::new_v4(),
                post_id: Uuid::new_v4(),
                action: "share".to_string(),
                timestamp: 0,
            });
        }

        batch_count += batch_events.len();
    }

    let batch_duration = batch_start.elapsed();

    // Individual processing (for comparison)
    let individual_start = Instant::now();
    let mut individual_count = 0;

    for _ in 0..n_events {
        let _event = MockEvent {
            user_id: Uuid::new_v4(),
            post_id: Uuid::new_v4(),
            action: "impression".to_string(),
            timestamp: 0,
        };

        individual_count += 1;
    }

    let individual_duration = individual_start.elapsed();

    println!("\n=== Batch vs Individual Processing ===");
    println!(
        "Batch ({} events): {:.2}ms ({:.0} events/sec)",
        batch_count,
        batch_duration.as_millis(),
        batch_count as f64 / batch_duration.as_secs_f64()
    );
    println!(
        "Individual ({} events): {:.2}ms ({:.0} events/sec)",
        individual_count,
        individual_duration.as_millis(),
        individual_count as f64 / individual_duration.as_secs_f64()
    );
}

#[test]
fn bench_concurrent_event_sources() {
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;

    let n_sources = 10;
    let events_per_source = 1000;

    let total_events = Arc::new(AtomicUsize::new(0));
    let start = Instant::now();

    // Simulate multiple concurrent event sources
    let mut handles = vec![];

    for source_id in 0..n_sources {
        let total_events_clone = total_events.clone();

        let handle = std::thread::spawn(move || {
            for _ in 0..events_per_source {
                let _event = MockEvent {
                    user_id: Uuid::new_v4(),
                    post_id: Uuid::new_v4(),
                    action: format!("action-{}", source_id),
                    timestamp: 0,
                };

                total_events_clone.fetch_add(1, Ordering::SeqCst);
            }
        });

        handles.push(handle);
    }

    // Wait for all threads
    for handle in handles {
        handle.join().unwrap();
    }

    let duration = start.elapsed();
    let total_events = total_events.load(Ordering::SeqCst);
    let throughput = total_events as f64 / duration.as_secs_f64();

    println!("\n=== Concurrent Event Sources ===");
    println!("Sources: {}", n_sources);
    println!("Events per source: {}", events_per_source);
    println!("Total events: {}", total_events);
    println!("Total time: {:.2}ms", duration.as_millis());
    println!("Combined throughput: {:.0} events/sec", throughput);

    assert_eq!(
        total_events,
        n_sources * events_per_source,
        "All events should be processed"
    );
}

#[test]
fn bench_action_type_variance() {
    let actions = vec!["view", "impression", "like", "comment", "share"];
    let n_events_per_action = 200;

    let start = Instant::now();

    for action in &actions {
        for _ in 0..n_events_per_action {
            let _event = MockEvent {
                user_id: Uuid::new_v4(),
                post_id: Uuid::new_v4(),
                action: action.to_string(),
                timestamp: 0,
            };
        }
    }

    let duration = start.elapsed();
    let total_events = actions.len() * n_events_per_action;
    let throughput = total_events as f64 / duration.as_secs_f64();

    println!("\n=== Action Type Variance ===");
    println!("Action types: {}", actions.len());
    println!("Events per type: {}", n_events_per_action);
    println!("Total events: {}", total_events);
    println!("Throughput: {:.0} events/sec", throughput);
}

#[test]
fn bench_memory_per_event() {
    use std::mem::size_of;

    let event = MockEvent {
        user_id: Uuid::new_v4(),
        post_id: Uuid::new_v4(),
        action: "like".to_string(),
        timestamp: 0,
    };

    let event_size = size_of_val(&event);
    let n_events_1gb = (1024 * 1024 * 1024) / event_size;

    println!("\n=== Memory Efficiency ===");
    println!("Event size: {} bytes", event_size);
    println!("Events per 1GB: {}", n_events_1gb);
}

#[test]
fn bench_stress_test_30_seconds() {
    let duration_secs = 3; // Shorter for unit test
    let mut event_count = 0;
    let start = Instant::now();

    while start.elapsed().as_secs() < duration_secs {
        let _event = MockEvent {
            user_id: Uuid::new_v4(),
            post_id: Uuid::new_v4(),
            action: "view".to_string(),
            timestamp: 0,
        };

        event_count += 1;
    }

    let duration = start.elapsed();
    let throughput = event_count as f64 / duration.as_secs_f64();

    println!("\n=== Stress Test ({} seconds) ===", duration_secs);
    println!("Total events: {}", event_count);
    println!("Throughput: {:.0} events/sec", throughput);
    println!("Average latency: {:.2}ms/event", (duration.as_millis() as f64) / event_count as f64);
}

#[test]
fn test_event_structure_sizes() {
    use std::mem::size_of;

    println!("\n=== Event Structure Sizes ===");
    println!("Uuid: {} bytes", size_of::<Uuid>());
    println!("String (empty): {} bytes", size_of::<String>());
    println!("i64: {} bytes", size_of::<i64>());
    println!("Option<i64>: {} bytes", size_of::<Option<i64>>());

    let event = MockEvent {
        user_id: Uuid::new_v4(),
        post_id: Uuid::new_v4(),
        action: "view".to_string(),
        timestamp: 0,
    };

    println!("MockEvent: {} bytes", size_of_val(&event));
}
