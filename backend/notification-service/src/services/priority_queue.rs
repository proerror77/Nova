/// Priority Queue for Notification Batch Processing
///
/// Implements intelligent prioritization and batch management for notifications.
/// Supports:
/// - Priority-based ordering (high priority first)
/// - Adaptive flush strategies based on load
/// - Rate limiting per user
/// - Configurable batch parameters
/// - Metrics collection

use super::kafka_consumer::KafkaNotification;
use std::cmp::Ordering;
use std::collections::{BinaryHeap, HashMap};
use std::time::{Duration, Instant};
use uuid::Uuid;

/// Notification with priority wrapper
#[derive(Debug, Clone)]
pub struct PriorityNotification {
    /// The actual notification
    pub notification: KafkaNotification,
    /// Priority level (0-255, higher = more important)
    pub priority: u8,
    /// Timestamp when enqueued
    pub enqueued_at: Instant,
    /// User ID for rate limiting
    pub user_id: Uuid,
}

impl PriorityNotification {
    /// Create a new priority notification
    pub fn new(notification: KafkaNotification, priority: u8, user_id: Uuid) -> Self {
        Self {
            notification,
            priority,
            enqueued_at: Instant::now(),
            user_id,
        }
    }

    /// Default priority (medium)
    pub fn with_default_priority(notification: KafkaNotification) -> Self {
        let user_id = notification.user_id;
        Self {
            notification,
            priority: 128, // Medium priority (0-255 scale)
            enqueued_at: Instant::now(),
            user_id,
        }
    }

    /// High priority (for important notifications)
    pub fn high_priority(notification: KafkaNotification) -> Self {
        let user_id = notification.user_id;
        Self {
            notification,
            priority: 200,
            enqueued_at: Instant::now(),
            user_id,
        }
    }

    /// Low priority (for batch-friendly notifications)
    pub fn low_priority(notification: KafkaNotification) -> Self {
        let user_id = notification.user_id;
        Self {
            notification,
            priority: 50,
            enqueued_at: Instant::now(),
            user_id,
        }
    }

    /// Get queue wait time
    pub fn wait_time(&self) -> Duration {
        self.enqueued_at.elapsed()
    }
}

impl Eq for PriorityNotification {}

impl PartialEq for PriorityNotification {
    fn eq(&self, other: &Self) -> bool {
        self.notification.id == other.notification.id
    }
}

impl Ord for PriorityNotification {
    fn cmp(&self, other: &Self) -> Ordering {
        // Higher priority first (reverse comparison)
        match self.priority.cmp(&other.priority) {
            Ordering::Equal => {
                // If same priority, older first (FIFO)
                other.enqueued_at.cmp(&self.enqueued_at)
            }
            ord => ord,
        }
    }
}

impl PartialOrd for PriorityNotification {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

/// Adaptive flush strategy parameters
#[derive(Debug, Clone)]
pub struct AdaptiveFlushStrategy {
    /// Minimum batch size to trigger flush
    pub min_batch_size: usize,
    /// Maximum batch size (soft limit)
    pub max_batch_size: usize,
    /// Maximum wait time before forced flush
    pub max_wait_time: Duration,
    /// Flush when high-priority count exceeds threshold
    pub high_priority_threshold: usize,
    /// Flush when queue size exceeds this multiplier of normal batch size
    pub queue_size_multiplier: f64,
}

impl Default for AdaptiveFlushStrategy {
    fn default() -> Self {
        Self {
            min_batch_size: 10,
            max_batch_size: 100,
            max_wait_time: Duration::from_secs(5),
            high_priority_threshold: 5,
            queue_size_multiplier: 2.0,
        }
    }
}

impl AdaptiveFlushStrategy {
    /// Create a custom flush strategy
    pub fn custom(
        min_batch_size: usize,
        max_batch_size: usize,
        max_wait_time: Duration,
        high_priority_threshold: usize,
        queue_size_multiplier: f64,
    ) -> Self {
        Self {
            min_batch_size,
            max_batch_size,
            max_wait_time,
            high_priority_threshold,
            queue_size_multiplier,
        }
    }

    /// Aggressive strategy (flush more frequently)
    pub fn aggressive() -> Self {
        Self {
            min_batch_size: 5,
            max_batch_size: 50,
            max_wait_time: Duration::from_secs(2),
            high_priority_threshold: 2,
            queue_size_multiplier: 1.5,
        }
    }

    /// Conservative strategy (batch more, flush less frequently)
    pub fn conservative() -> Self {
        Self {
            min_batch_size: 50,
            max_batch_size: 200,
            max_wait_time: Duration::from_secs(10),
            high_priority_threshold: 20,
            queue_size_multiplier: 3.0,
        }
    }

    /// Real-time strategy (low latency, high throughput)
    pub fn real_time() -> Self {
        Self {
            min_batch_size: 1,
            max_batch_size: 25,
            max_wait_time: Duration::from_millis(500),
            high_priority_threshold: 1,
            queue_size_multiplier: 1.2,
        }
    }
}

/// Rate limiter for notifications per user
#[derive(Debug)]
pub struct RateLimiter {
    /// Map of user_id -> (count, window_start_time)
    windows: HashMap<Uuid, (usize, Instant)>,
    /// Max notifications per window
    max_per_window: usize,
    /// Window duration
    window_duration: Duration,
}

impl RateLimiter {
    /// Create a new rate limiter
    pub fn new(max_per_window: usize, window_duration: Duration) -> Self {
        Self {
            windows: HashMap::new(),
            max_per_window,
            window_duration,
        }
    }

    /// Default rate limiter (100 notifications per minute per user)
    pub fn default_per_user() -> Self {
        Self::new(100, Duration::from_secs(60))
    }

    /// Check if user can send a notification
    pub fn can_notify(&mut self, user_id: Uuid) -> bool {
        let now = Instant::now();

        let (count, window_start) = self.windows.entry(user_id).or_insert((0, now));

        // Reset window if expired
        if now.duration_since(*window_start) > self.window_duration {
            *count = 0;
            *window_start = now;
        }

        // Check rate limit
        if *count >= self.max_per_window {
            return false;
        }

        *count += 1;
        true
    }

    /// Get current rate for user
    pub fn current_rate(&self, user_id: Uuid) -> (usize, usize) {
        if let Some((count, window_start)) = self.windows.get(&user_id) {
            let remaining = self
                .window_duration
                .saturating_sub(window_start.elapsed());

            if remaining > Duration::from_secs(0) {
                return (*count, self.max_per_window);
            }
        }

        (0, self.max_per_window)
    }

    /// Clear expired windows
    pub fn cleanup(&mut self) {
        let now = Instant::now();
        self.windows.retain(|_, (_, window_start)| {
            now.duration_since(*window_start) <= self.window_duration
        });
    }
}

/// Priority queue for notifications
pub struct NotificationPriorityQueue {
    /// Binary heap of priority notifications
    queue: BinaryHeap<PriorityNotification>,
    /// Flush strategy
    strategy: AdaptiveFlushStrategy,
    /// Rate limiter
    rate_limiter: RateLimiter,
    /// Metrics
    metrics: QueueMetrics,
}

/// Metrics for queue monitoring
#[derive(Debug, Clone, Default)]
pub struct QueueMetrics {
    pub total_enqueued: usize,
    pub total_dequeued: usize,
    pub total_dropped: usize,
    pub peak_queue_size: usize,
}

impl NotificationPriorityQueue {
    /// Create a new priority queue with default strategy
    pub fn new() -> Self {
        Self {
            queue: BinaryHeap::new(),
            strategy: AdaptiveFlushStrategy::default(),
            rate_limiter: RateLimiter::default_per_user(),
            metrics: QueueMetrics::default(),
        }
    }

    /// Create a new priority queue with custom strategy
    pub fn with_strategy(strategy: AdaptiveFlushStrategy) -> Self {
        Self {
            queue: BinaryHeap::new(),
            strategy,
            rate_limiter: RateLimiter::default_per_user(),
            metrics: QueueMetrics::default(),
        }
    }

    /// Enqueue a notification
    pub fn enqueue(&mut self, notification: KafkaNotification, priority: u8) -> bool {
        // Apply rate limiting
        if !self.rate_limiter.can_notify(notification.user_id) {
            self.metrics.total_dropped += 1;
            return false;
        }

        let user_id = notification.user_id;
        let priority_notif = PriorityNotification::new(notification, priority, user_id);
        self.queue.push(priority_notif);

        self.metrics.total_enqueued += 1;
        self.metrics.peak_queue_size = self.metrics.peak_queue_size.max(self.queue.len());

        true
    }

    /// Dequeue next notification
    pub fn dequeue(&mut self) -> Option<PriorityNotification> {
        if let Some(notif) = self.queue.pop() {
            self.metrics.total_dequeued += 1;
            Some(notif)
        } else {
            None
        }
    }

    /// Dequeue multiple notifications up to limit
    pub fn dequeue_batch(&mut self, limit: usize) -> Vec<PriorityNotification> {
        let mut batch = Vec::new();
        for _ in 0..limit {
            if let Some(notif) = self.dequeue() {
                batch.push(notif);
            } else {
                break;
            }
        }
        batch
    }

    /// Check if queue should flush based on strategy
    pub fn should_flush(&self) -> bool {
        let queue_size = self.queue.len();

        // Always flush if exceeds max size
        if queue_size >= self.strategy.max_batch_size {
            return true;
        }

        // Count high-priority items
        let high_priority_count = self
            .queue
            .iter()
            .filter(|n| n.priority >= 180) // High priority threshold
            .count();

        if high_priority_count >= self.strategy.high_priority_threshold {
            return true;
        }

        // Check queue multiplier
        if queue_size as f64 >= self.strategy.min_batch_size as f64 * self.strategy.queue_size_multiplier
        {
            return true;
        }

        false
    }

    /// Check if queue has minimum batch size
    pub fn has_min_batch(&self) -> bool {
        self.queue.len() >= self.strategy.min_batch_size
    }

    /// Get current queue size
    pub fn len(&self) -> usize {
        self.queue.len()
    }

    /// Check if queue is empty
    pub fn is_empty(&self) -> bool {
        self.queue.is_empty()
    }

    /// Get metrics
    pub fn metrics(&self) -> &QueueMetrics {
        &self.metrics
    }

    /// Get mutable metrics (for testing)
    pub fn metrics_mut(&mut self) -> &mut QueueMetrics {
        &mut self.metrics
    }

    /// Clear the queue
    pub fn clear(&mut self) {
        self.queue.clear();
    }

    /// Get oldest notification wait time
    pub fn oldest_wait_time(&self) -> Option<Duration> {
        self.queue.iter().map(|n| n.wait_time()).min()
    }

    /// Check if oldest notification exceeds max wait time
    pub fn exceeds_max_wait_time(&self) -> bool {
        if let Some(wait_time) = self.oldest_wait_time() {
            wait_time > self.strategy.max_wait_time
        } else {
            false
        }
    }

    /// Update rate limiter
    pub fn update_rate_limit(&mut self, max_per_window: usize, window_duration: Duration) {
        self.rate_limiter = RateLimiter::new(max_per_window, window_duration);
    }

    /// Cleanup rate limiter windows
    pub fn cleanup(&mut self) {
        self.rate_limiter.cleanup();
    }
}

impl Default for NotificationPriorityQueue {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_test_notification(user_id: Uuid, title: &str) -> KafkaNotification {
        KafkaNotification {
            id: Uuid::new_v4().to_string(),
            user_id,
            event_type: super::super::kafka_consumer::NotificationEventType::Like,
            title: title.to_string(),
            body: "Test body".to_string(),
            data: None,
            timestamp: chrono::Utc::now().timestamp(),
        }
    }

    #[test]
    fn test_priority_notification_creation() {
        let user_id = Uuid::new_v4();
        let notif = create_test_notification(user_id, "Test");
        let pn = PriorityNotification::new(notif, 150, user_id);

        assert_eq!(pn.priority, 150);
        assert_eq!(pn.user_id, user_id);
    }

    #[test]
    fn test_priority_notification_helpers() {
        let user_id = Uuid::new_v4();
        let notif = create_test_notification(user_id, "Test");

        let high = PriorityNotification::high_priority(notif.clone());
        assert_eq!(high.priority, 200);

        let low = PriorityNotification::low_priority(notif.clone());
        assert_eq!(low.priority, 50);

        let default = PriorityNotification::with_default_priority(notif);
        assert_eq!(default.priority, 128);
    }

    #[test]
    fn test_priority_ordering() {
        let user_id = Uuid::new_v4();
        let notif1 = create_test_notification(user_id, "Low");
        let notif2 = create_test_notification(user_id, "High");

        let low = PriorityNotification::new(notif1, 50, user_id);
        let high = PriorityNotification::new(notif2, 200, user_id);

        assert!(high > low);
    }

    #[test]
    fn test_queue_enqueue_dequeue() {
        let mut queue = NotificationPriorityQueue::new();
        let user_id = Uuid::new_v4();
        let notif = create_test_notification(user_id, "Test");

        assert!(queue.enqueue(notif, 100));
        assert_eq!(queue.len(), 1);

        let dequeued = queue.dequeue();
        assert!(dequeued.is_some());
        assert_eq!(queue.len(), 0);
    }

    #[test]
    fn test_queue_priority_order() {
        let mut queue = NotificationPriorityQueue::new();
        let user_id = Uuid::new_v4();

        let notif1 = create_test_notification(user_id, "Low");
        let notif2 = create_test_notification(user_id, "High");
        let notif3 = create_test_notification(user_id, "Medium");

        queue.enqueue(notif1, 50);
        queue.enqueue(notif2, 200);
        queue.enqueue(notif3, 100);

        assert_eq!(queue.len(), 3);

        // Should dequeue in priority order: 200, 100, 50
        let first = queue.dequeue().unwrap();
        assert_eq!(first.priority, 200);

        let second = queue.dequeue().unwrap();
        assert_eq!(second.priority, 100);

        let third = queue.dequeue().unwrap();
        assert_eq!(third.priority, 50);
    }

    #[test]
    fn test_rate_limiter() {
        let mut limiter = RateLimiter::new(3, Duration::from_secs(1));
        let user_id = Uuid::new_v4();

        assert!(limiter.can_notify(user_id)); // 1
        assert!(limiter.can_notify(user_id)); // 2
        assert!(limiter.can_notify(user_id)); // 3
        assert!(!limiter.can_notify(user_id)); // Exceeded
    }

    #[test]
    fn test_adaptive_flush_strategy_default() {
        let strategy = AdaptiveFlushStrategy::default();
        assert_eq!(strategy.min_batch_size, 10);
        assert_eq!(strategy.max_batch_size, 100);
    }

    #[test]
    fn test_adaptive_flush_strategy_aggressive() {
        let strategy = AdaptiveFlushStrategy::aggressive();
        assert_eq!(strategy.min_batch_size, 5);
        assert_eq!(strategy.max_batch_size, 50);
    }

    #[test]
    fn test_adaptive_flush_strategy_conservative() {
        let strategy = AdaptiveFlushStrategy::conservative();
        assert_eq!(strategy.min_batch_size, 50);
        assert_eq!(strategy.max_batch_size, 200);
    }

    #[test]
    fn test_adaptive_flush_strategy_real_time() {
        let strategy = AdaptiveFlushStrategy::real_time();
        assert_eq!(strategy.min_batch_size, 1);
        assert_eq!(strategy.max_batch_size, 25);
    }

    #[test]
    fn test_should_flush_by_size() {
        let mut queue = NotificationPriorityQueue::new();
        let user_id = Uuid::new_v4();

        for i in 0..100 {
            let notif = create_test_notification(user_id, &format!("Test {}", i));
            queue.enqueue(notif, 100);
        }

        assert!(queue.should_flush());
    }

    #[test]
    fn test_has_min_batch() {
        let mut queue = NotificationPriorityQueue::new();
        let user_id = Uuid::new_v4();

        assert!(!queue.has_min_batch());

        for i in 0..10 {
            let notif = create_test_notification(user_id, &format!("Test {}", i));
            queue.enqueue(notif, 100);
        }

        assert!(queue.has_min_batch());
    }

    #[test]
    fn test_dequeue_batch() {
        let mut queue = NotificationPriorityQueue::new();
        let user_id = Uuid::new_v4();

        for i in 0..15 {
            let notif = create_test_notification(user_id, &format!("Test {}", i));
            queue.enqueue(notif, 100);
        }

        let batch = queue.dequeue_batch(10);
        assert_eq!(batch.len(), 10);
        assert_eq!(queue.len(), 5);
    }

    #[test]
    fn test_metrics() {
        let mut queue = NotificationPriorityQueue::new();
        let user_id = Uuid::new_v4();

        let notif = create_test_notification(user_id, "Test");
        queue.enqueue(notif, 100);

        assert_eq!(queue.metrics().total_enqueued, 1);
        assert_eq!(queue.metrics().total_dropped, 0);

        queue.dequeue();
        assert_eq!(queue.metrics().total_dequeued, 1);
    }

    #[test]
    fn test_exceeds_max_wait_time() {
        let strategy = AdaptiveFlushStrategy::custom(
            1,
            100,
            Duration::from_millis(100),
            5,
            2.0,
        );
        let mut queue = NotificationPriorityQueue::with_strategy(strategy);
        let user_id = Uuid::new_v4();

        let notif = create_test_notification(user_id, "Test");
        queue.enqueue(notif, 100);

        // Initially should not exceed
        assert!(!queue.exceeds_max_wait_time());

        // Wait for max time to elapse
        std::thread::sleep(Duration::from_millis(150));

        // Now should exceed
        assert!(queue.exceeds_max_wait_time());
    }
}
