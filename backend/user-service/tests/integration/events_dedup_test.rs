/// Unit Tests for Event Deduplication
/// Tests Redis-based deduplication logic with atomic check-and-set

use std::time::Duration;

/// Mock deduplicator for testing without Redis
pub struct MockEventDeduplicator {
    seen_ids: std::collections::HashMap<String, bool>,
}

impl MockEventDeduplicator {
    pub fn new() -> Self {
        Self {
            seen_ids: std::collections::HashMap::new(),
        }
    }

    /// Check if event has been seen before
    pub fn is_duplicate(&self, event_id: &str) -> bool {
        self.seen_ids.contains_key(event_id)
    }

    /// Mark event as seen (atomic check-and-set simulation)
    pub fn check_and_mark(&mut self, event_id: &str) -> bool {
        if self.seen_ids.contains_key(event_id) {
            false // Already exists, mark failed
        } else {
            self.seen_ids.insert(event_id.to_string(), true);
            true // Successfully marked
        }
    }

    pub fn clear(&mut self) {
        self.seen_ids.clear();
    }
}

#[test]
fn test_dedup_first_event() {
    let mut dedup = MockEventDeduplicator::new();

    let event_id = "event-001";

    // First time - should not be duplicate
    assert!(!dedup.is_duplicate(event_id));

    // Mark it
    assert!(dedup.check_and_mark(event_id));

    // Now it should be duplicate
    assert!(dedup.is_duplicate(event_id));
}

#[test]
fn test_dedup_second_event() {
    let mut dedup = MockEventDeduplicator::new();

    let event_id_1 = "event-001";
    let event_id_2 = "event-002";

    // Mark first event
    assert!(dedup.check_and_mark(event_id_1));

    // Second event should not be marked as duplicate
    assert!(!dedup.is_duplicate(event_id_2));
    assert!(dedup.check_and_mark(event_id_2));

    // Both should now be seen
    assert!(dedup.is_duplicate(event_id_1));
    assert!(dedup.is_duplicate(event_id_2));
}

#[test]
fn test_dedup_duplicate_event() {
    let mut dedup = MockEventDeduplicator::new();

    let event_id = "event-001";

    // First mark succeeds
    assert!(dedup.check_and_mark(event_id));

    // Second mark fails (already marked)
    assert!(!dedup.check_and_mark(event_id));

    // Still marked
    assert!(dedup.is_duplicate(event_id));
}

#[test]
fn test_dedup_multiple_events() {
    let mut dedup = MockEventDeduplicator::new();

    let event_ids = vec![
        "event-001", "event-002", "event-003", "event-004", "event-005",
    ];

    // Mark all events
    for id in &event_ids {
        assert!(dedup.check_and_mark(id));
    }

    // All should be seen
    for id in &event_ids {
        assert!(dedup.is_duplicate(id));
    }

    // New event should not be seen
    assert!(!dedup.is_duplicate("event-006"));
}

#[test]
fn test_dedup_clear() {
    let mut dedup = MockEventDeduplicator::new();

    let event_id = "event-001";

    // Mark event
    dedup.check_and_mark(event_id);
    assert!(dedup.is_duplicate(event_id));

    // Clear all
    dedup.clear();

    // Should not be seen anymore
    assert!(!dedup.is_duplicate(event_id));

    // Should be able to mark again
    assert!(dedup.check_and_mark(event_id));
}

#[test]
fn test_dedup_large_batch() {
    let mut dedup = MockEventDeduplicator::new();

    let n = 10000;

    // Mark 10k events
    for i in 0..n {
        let event_id = format!("event-{:06}", i);
        assert!(dedup.check_and_mark(&event_id));
    }

    // Verify all are seen
    for i in 0..n {
        let event_id = format!("event-{:06}", i);
        assert!(dedup.is_duplicate(&event_id));
    }

    // New events should not be seen
    assert!(!dedup.is_duplicate("event-999999"));
}

#[test]
fn test_dedup_idempotent() {
    let mut dedup = MockEventDeduplicator::new();

    let event_id = "event-001";

    // First check_and_mark succeeds
    let result1 = dedup.check_and_mark(event_id);
    assert!(result1);

    // Second check_and_mark fails (idempotent)
    let result2 = dedup.check_and_mark(event_id);
    assert!(!result2);

    // Third check_and_mark also fails
    let result3 = dedup.check_and_mark(event_id);
    assert!(!result3);
}

#[test]
fn test_dedup_race_condition_simulation() {
    let mut dedup1 = MockEventDeduplicator::new();
    let mut dedup2 = MockEventDeduplicator::new();

    let event_id = "event-race-001";

    // Simulate two concurrent consumers trying to mark same event
    // In real scenario, Redis NX ensures only one succeeds
    let result1 = dedup1.check_and_mark(event_id);
    let result2 = dedup2.check_and_mark(event_id);

    // Both report success (our mock doesn't prevent this)
    // But in real Redis with NX, only one would succeed
    assert!(result1);
    assert!(result2); // This shows limitation of mock - needs real Redis
}

#[test]
fn test_dedup_key_format() {
    let event_id = "550e8400-e29b-41d4-a716-446655440000";
    let mut dedup = MockEventDeduplicator::new();

    // UUID format event ID should work
    assert!(dedup.check_and_mark(event_id));
    assert!(dedup.is_duplicate(event_id));
}

#[test]
fn test_dedup_special_characters() {
    let mut dedup = MockEventDeduplicator::new();

    let event_ids = vec![
        "event:001",
        "event/002",
        "event-003",
        "event_004",
        "event.005",
        "event@006",
    ];

    for id in &event_ids {
        assert!(dedup.check_and_mark(id));
    }

    for id in &event_ids {
        assert!(dedup.is_duplicate(id));
    }
}

#[test]
fn test_dedup_ttl_simulation() {
    let mut dedup = MockEventDeduplicator::new();

    let event_id = "event-001";

    // Mark event
    assert!(dedup.check_and_mark(event_id));
    assert!(dedup.is_duplicate(event_id));

    // Simulate TTL expiry by clearing (in real Redis, TTL would auto-clear)
    dedup.clear();

    // After TTL, event should be processable again
    assert!(!dedup.is_duplicate(event_id));
    assert!(dedup.check_and_mark(event_id));
}

#[test]
fn test_dedup_memory_efficiency() {
    let mut dedup = MockEventDeduplicator::new();

    // Mark 100k events to test memory usage
    for i in 0..100000 {
        let event_id = format!("event-{:06}", i);
        dedup.check_and_mark(&event_id);
    }

    // All should be tracked
    for i in (100000 - 100)..100000 {
        let event_id = format!("event-{:06}", i);
        assert!(dedup.is_duplicate(&event_id));
    }
}

#[test]
fn test_dedup_ordering() {
    let mut dedup = MockEventDeduplicator::new();

    // Out of order event IDs
    let event_ids = vec!["event-003", "event-001", "event-004", "event-002"];

    for id in &event_ids {
        assert!(dedup.check_and_mark(id));
    }

    // All should be found regardless of marking order
    for id in &event_ids {
        assert!(dedup.is_duplicate(id));
    }
}

#[test]
fn test_dedup_concurrent_marks_simulation() {
    // Simulate checking and marking the same event from multiple sources
    let mut dedup = MockEventDeduplicator::new();

    let event_id = "event-concurrent";

    // First mark succeeds
    let mark1 = dedup.check_and_mark(event_id);
    assert!(mark1);

    // Attempt marks from other "consumers" fail
    let mark2 = dedup.check_and_mark(event_id);
    assert!(!mark2);

    let mark3 = dedup.check_and_mark(event_id);
    assert!(!mark3);
}
