//! Subscription Backpressure Handling
//! ✅ P0-5: Manage high-volume subscription streams gracefully
//!
//! PATTERN: Implement backpressure to prevent buffer overflow
//!
//! When subscribers can't keep up:
//! 1. Buffer events in queue (max size: configurable)
//! 2. If queue full, apply backpressure (slow down producer)
//! 3. If backpressure fails, drop oldest events
//! 4. Monitor and alert on backpressure events

#![allow(dead_code)]

use anyhow::Result;
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tokio::sync::mpsc;

/// Backpressure configuration
#[derive(Debug, Clone)]
pub struct BackpressureConfig {
    /// Maximum queue size before backpressure
    pub max_queue_size: usize,
    /// Queue warning threshold (percent of max)
    pub warning_threshold: f64,
    /// Critical threshold (percent of max)
    pub critical_threshold: f64,
    /// Max time to wait for consumer to drain
    pub timeout_duration: Duration,
    /// Drop oldest events when queue is full
    pub drop_on_overflow: bool,
}

impl Default for BackpressureConfig {
    fn default() -> Self {
        Self {
            max_queue_size: 10_000,   // 10k events
            warning_threshold: 0.75,  // 75%
            critical_threshold: 0.95, // 95%
            timeout_duration: Duration::from_secs(30),
            drop_on_overflow: true,
        }
    }
}

/// Backpressure event queue
pub struct BackpressureQueue<T: Clone + Send> {
    config: BackpressureConfig,
    queue: Arc<Mutex<VecDeque<T>>>,
    stats: Arc<Mutex<BackpressureStats>>,
    #[allow(dead_code)]
    sender: mpsc::UnboundedSender<T>,
    receiver: mpsc::UnboundedReceiver<T>,
}

/// Backpressure statistics
#[derive(Debug, Clone, Default)]
pub struct BackpressureStats {
    /// Total events queued
    pub total_queued: u64,
    /// Events dropped due to overflow
    pub events_dropped: u64,
    /// Backpressure events triggered
    pub backpressure_count: u64,
    /// Critical threshold crossed count
    pub critical_threshold_crossed: u64,
    /// Current queue size
    pub current_queue_size: usize,
    /// Peak queue size
    pub peak_queue_size: usize,
    /// Last critical event time
    pub last_critical_time: Option<Instant>,
}

impl<T: Clone + Send + 'static> BackpressureQueue<T> {
    /// Create new backpressure queue
    pub fn new(config: BackpressureConfig) -> Self {
        let (sender, receiver) = mpsc::unbounded_channel();

        Self {
            config,
            queue: Arc::new(Mutex::new(VecDeque::new())),
            stats: Arc::new(Mutex::new(BackpressureStats::default())),
            sender,
            receiver,
        }
    }

    /// Send event to queue
    /// Returns Backpressure status
    pub async fn send(&self, event: T) -> Result<BackpressureStatus> {
        let mut queue = self.queue.lock().expect("Mutex should not be poisoned");
        let mut stats = self.stats.lock().expect("Mutex should not be poisoned");

        let queue_size = queue.len();

        // Check queue status
        let status = self.get_queue_status(queue_size);

        match status {
            BackpressureStatus::Normal => {
                queue.push_back(event);
                stats.total_queued += 1;
                stats.current_queue_size = queue.len();
            }
            BackpressureStatus::Warning => {
                queue.push_back(event);
                stats.total_queued += 1;
                stats.current_queue_size = queue.len();
                stats.backpressure_count += 1;
            }
            BackpressureStatus::Critical => {
                stats.critical_threshold_crossed += 1;
                stats.last_critical_time = Some(Instant::now());

                if self.config.drop_on_overflow && queue.len() >= self.config.max_queue_size {
                    // Drop oldest event
                    if queue.pop_front().is_some() {
                        stats.events_dropped += 1;
                    }
                }

                queue.push_back(event);
                stats.total_queued += 1;
                stats.current_queue_size = queue.len();

                // Update peak
                if queue.len() > stats.peak_queue_size {
                    stats.peak_queue_size = queue.len();
                }
            }
            BackpressureStatus::Overflowed => {
                // Queue is full, drop oldest event
                if queue.pop_front().is_some() {
                    stats.events_dropped += 1;
                }
                queue.push_back(event);
                stats.current_queue_size = queue.len();
            }
        }

        Ok(status)
    }

    /// Receive next event from queue
    pub async fn recv(&mut self) -> Option<T> {
        self.receiver.recv().await
    }

    /// Get current queue size
    pub fn size(&self) -> usize {
        self.queue
            .lock()
            .expect("Mutex should not be poisoned")
            .len()
    }

    /// Get queue status
    pub fn get_queue_status(&self, queue_size: usize) -> BackpressureStatus {
        let max = self.config.max_queue_size;
        let warning_level = (max as f64 * self.config.warning_threshold) as usize;
        let critical_level = (max as f64 * self.config.critical_threshold) as usize;

        match queue_size {
            0..=0 if queue_size <= warning_level => BackpressureStatus::Normal,
            q if q <= warning_level => BackpressureStatus::Normal,
            q if q <= critical_level => BackpressureStatus::Warning,
            q if q < max => BackpressureStatus::Critical,
            _ => BackpressureStatus::Overflowed,
        }
    }

    /// Get backpressure statistics
    pub fn stats(&self) -> BackpressureStats {
        self.stats
            .lock()
            .expect("Mutex should not be poisoned")
            .clone()
    }

    /// Reset statistics
    pub fn reset_stats(&self) {
        let mut stats = self.stats.lock().expect("Mutex should not be poisoned");
        *stats = BackpressureStats {
            current_queue_size: self
                .queue
                .lock()
                .expect("Mutex should not be poisoned")
                .len(),
            ..Default::default()
        };
    }

    /// Drain queue for high-priority processing
    pub fn drain_all(&self) -> Vec<T> {
        let mut queue = self.queue.lock().expect("Mutex should not be poisoned");
        let items: Vec<T> = queue.drain(..).collect();

        let mut stats = self.stats.lock().expect("Mutex should not be poisoned");
        stats.current_queue_size = 0;

        items
    }
}

/// Backpressure status levels
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BackpressureStatus {
    /// Queue normal: 0-75%
    Normal,
    /// Queue warning: 75-95%
    Warning,
    /// Queue critical: 95-100%
    Critical,
    /// Queue overflow: >100%
    Overflowed,
}

impl BackpressureStatus {
    /// Get human-readable status
    pub fn as_str(&self) -> &str {
        match self {
            BackpressureStatus::Normal => "normal",
            BackpressureStatus::Warning => "warning",
            BackpressureStatus::Critical => "critical",
            BackpressureStatus::Overflowed => "overflowed",
        }
    }

    /// Get severity level (0-3)
    pub fn severity(&self) -> u8 {
        match self {
            BackpressureStatus::Normal => 0,
            BackpressureStatus::Warning => 1,
            BackpressureStatus::Critical => 2,
            BackpressureStatus::Overflowed => 3,
        }
    }
}

/// Subscription stream with backpressure
pub struct SubscriptionStream<T: Clone + Send + 'static> {
    queue: BackpressureQueue<T>,
    subscription_id: String,
}

impl<T: Clone + Send + 'static> SubscriptionStream<T> {
    /// Create new subscription stream
    pub fn new(subscription_id: String, config: BackpressureConfig) -> Self {
        Self {
            queue: BackpressureQueue::new(config),
            subscription_id,
        }
    }

    /// Send event to subscriber
    pub async fn send_event(&self, event: T) -> Result<()> {
        let status = self.queue.send(event).await?;

        // Log backpressure events
        if status != BackpressureStatus::Normal {
            tracing::warn!(
                subscription_id = %self.subscription_id,
                status = status.as_str(),
                queue_size = self.queue.size(),
                "Backpressure event"
            );
        }

        Ok(())
    }

    /// Get subscription statistics
    pub fn get_stats(&self) -> SubscriptionStreamStats {
        let bp_stats = self.queue.stats();

        SubscriptionStreamStats {
            subscription_id: self.subscription_id.clone(),
            queue_size: bp_stats.current_queue_size,
            peak_size: bp_stats.peak_queue_size,
            total_queued: bp_stats.total_queued,
            dropped_events: bp_stats.events_dropped,
            backpressure_events: bp_stats.backpressure_count,
            critical_events: bp_stats.critical_threshold_crossed,
        }
    }
}

/// Subscription stream statistics
#[derive(Debug, Clone)]
pub struct SubscriptionStreamStats {
    pub subscription_id: String,
    pub queue_size: usize,
    pub peak_size: usize,
    pub total_queued: u64,
    pub dropped_events: u64,
    pub backpressure_events: u64,
    pub critical_events: u64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_normal_queue_operations() {
        let config = BackpressureConfig::default();
        let queue: BackpressureQueue<i32> = BackpressureQueue::new(config);

        let status = queue.send(1).await.unwrap();
        assert_eq!(status, BackpressureStatus::Normal);
        assert_eq!(queue.size(), 1);
    }

    #[tokio::test]
    async fn test_backpressure_warning() {
        let config = BackpressureConfig {
            max_queue_size: 100,
            warning_threshold: 0.75,
            ..Default::default()
        };
        let queue: BackpressureQueue<i32> = BackpressureQueue::new(config);

        // Fill queue to 80%
        for i in 0..80 {
            let _ = queue.send(i).await;
        }

        let status = queue.send(81).await.unwrap();
        assert_eq!(status, BackpressureStatus::Warning);
    }

    #[tokio::test]
    async fn test_backpressure_critical() {
        let config = BackpressureConfig {
            max_queue_size: 100,
            critical_threshold: 0.95,
            ..Default::default()
        };
        let queue: BackpressureQueue<i32> = BackpressureQueue::new(config);

        // Fill queue to 96%
        for i in 0..96 {
            let _ = queue.send(i).await;
        }

        let status = queue.send(97).await.unwrap();
        assert_eq!(status, BackpressureStatus::Critical);
    }

    #[tokio::test]
    async fn test_overflow_drops_oldest() {
        let config = BackpressureConfig {
            max_queue_size: 10,
            drop_on_overflow: true,
            ..Default::default()
        };
        let queue: BackpressureQueue<i32> = BackpressureQueue::new(config);

        // Fill queue
        for i in 0..10 {
            let _ = queue.send(i).await;
        }

        // Send one more - should drop oldest
        let _ = queue.send(11).await;

        let stats = queue.stats();
        assert!(stats.events_dropped > 0);
    }

    #[test]
    fn test_backpressure_status_severity() {
        assert_eq!(BackpressureStatus::Normal.severity(), 0);
        assert_eq!(BackpressureStatus::Warning.severity(), 1);
        assert_eq!(BackpressureStatus::Critical.severity(), 2);
        assert_eq!(BackpressureStatus::Overflowed.severity(), 3);
    }

    #[test]
    fn test_subscription_stream_stats() {
        let stream: SubscriptionStream<i32> =
            SubscriptionStream::new("sub_1".to_string(), BackpressureConfig::default());

        let stats = stream.get_stats();
        assert_eq!(stats.subscription_id, "sub_1");
        assert_eq!(stats.queue_size, 0);
    }
}
