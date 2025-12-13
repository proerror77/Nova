// ============================================
// Behavior Pattern Builder (行为模式构建器)
// ============================================
//
// Analyzes user behavior patterns from session data:
// 1. Active hours (when user is most active)
// 2. Session patterns (length, frequency)
// 3. Content consumption (video length preferences)
// 4. Scroll behavior (fast/slow scrolling)

use super::{ProfileBuilderError, Result};
use chrono::{DateTime, Datelike, Duration, Timelike, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tracing::{debug, info};
use uuid::Uuid;

/// User behavior pattern profile
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BehaviorPattern {
    /// User ID
    pub user_id: Uuid,
    /// Active hours bitmap (24 bits, one for each hour)
    /// Bit set = user is typically active during that hour
    pub active_hours_bitmap: u32,
    /// Peak active hours (top 3)
    pub peak_hours: Vec<u8>,
    /// Average session length in seconds
    pub avg_session_length: f64,
    /// Average sessions per day
    pub avg_daily_sessions: f64,
    /// Preferred video length category
    pub preferred_video_length: VideoLengthPreference,
    /// Average scroll speed (pixels per second)
    pub avg_scroll_speed: f64,
    /// Engagement rate (interactions / views)
    pub engagement_rate: f64,
    /// Content completion rate
    pub avg_completion_rate: f64,
    /// Most active days of week (0 = Sunday, 6 = Saturday)
    pub active_days: Vec<u8>,
    /// Last computed timestamp
    pub computed_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum VideoLengthPreference {
    /// < 15 seconds
    VeryShort,
    /// 15-60 seconds
    Short,
    /// 1-3 minutes
    Medium,
    /// 3-10 minutes
    Long,
    /// > 10 minutes
    VeryLong,
    /// No clear preference
    Mixed,
}

impl VideoLengthPreference {
    pub fn from_duration_seconds(avg_seconds: f64) -> Self {
        if avg_seconds < 15.0 {
            VideoLengthPreference::VeryShort
        } else if avg_seconds < 60.0 {
            VideoLengthPreference::Short
        } else if avg_seconds < 180.0 {
            VideoLengthPreference::Medium
        } else if avg_seconds < 600.0 {
            VideoLengthPreference::Long
        } else {
            VideoLengthPreference::VeryLong
        }
    }
}

/// Session event for behavior analysis
#[derive(Debug, Clone)]
pub struct SessionEvent {
    pub user_id: Uuid,
    pub session_id: String,
    pub started_at: DateTime<Utc>,
    pub ended_at: Option<DateTime<Utc>>,
    pub view_count: u32,
    pub engagement_count: u32,
}

/// Content view event for behavior analysis
#[derive(Debug, Clone)]
pub struct ContentViewEvent {
    pub user_id: Uuid,
    pub content_id: Uuid,
    pub content_duration_ms: u32,
    pub watch_duration_ms: u32,
    pub completion_rate: f32,
    pub viewed_at: DateTime<Utc>,
    pub hour: u8,
    pub day_of_week: u8,
}

/// Configuration for behavior pattern building
#[derive(Debug, Clone)]
pub struct BehaviorBuilderConfig {
    /// Days to look back for analysis
    pub lookback_days: i64,
    /// Minimum sessions needed for reliable patterns
    pub min_sessions: usize,
    /// Minimum views needed for video length preference
    pub min_views_for_preference: usize,
    /// Threshold for considering an hour "active" (ratio of sessions)
    pub active_hour_threshold: f64,
}

impl Default for BehaviorBuilderConfig {
    fn default() -> Self {
        Self {
            lookback_days: 30,
            min_sessions: 5,
            min_views_for_preference: 20,
            active_hour_threshold: 0.05, // 5% of sessions
        }
    }
}

/// Behavior pattern builder
pub struct BehaviorBuilder {
    config: BehaviorBuilderConfig,
}

impl BehaviorBuilder {
    pub fn new(config: BehaviorBuilderConfig) -> Self {
        Self { config }
    }

    /// Build behavior pattern from session and view events
    pub fn build_pattern(
        &self,
        user_id: Uuid,
        sessions: Vec<SessionEvent>,
        views: Vec<ContentViewEvent>,
    ) -> Result<BehaviorPattern> {
        let now = Utc::now();

        // Calculate active hours
        let (active_hours_bitmap, peak_hours) = self.compute_active_hours(&views);

        // Calculate session statistics
        let (avg_session_length, avg_daily_sessions) = self.compute_session_stats(&sessions);

        // Calculate video length preference
        let preferred_video_length = self.compute_video_preference(&views);

        // Calculate engagement rate
        let engagement_rate = self.compute_engagement_rate(&sessions);

        // Calculate completion rate
        let avg_completion_rate = self.compute_avg_completion_rate(&views);

        // Calculate active days
        let active_days = self.compute_active_days(&views);

        Ok(BehaviorPattern {
            user_id,
            active_hours_bitmap,
            peak_hours,
            avg_session_length,
            avg_daily_sessions,
            preferred_video_length,
            avg_scroll_speed: 0.0, // TODO: Implement scroll tracking
            engagement_rate,
            avg_completion_rate,
            active_days,
            computed_at: now,
        })
    }

    /// Compute active hours bitmap and peak hours
    fn compute_active_hours(&self, views: &[ContentViewEvent]) -> (u32, Vec<u8>) {
        if views.is_empty() {
            return (0, Vec::new());
        }

        // Count views per hour
        let mut hour_counts: [u32; 24] = [0; 24];
        for view in views {
            if view.hour < 24 {
                hour_counts[view.hour as usize] += 1;
            }
        }

        let total_views = views.len() as f64;
        let threshold = (total_views * self.config.active_hour_threshold) as u32;

        // Build bitmap
        let mut bitmap: u32 = 0;
        for (hour, &count) in hour_counts.iter().enumerate() {
            if count >= threshold.max(1) {
                bitmap |= 1 << hour;
            }
        }

        // Find peak hours (top 3)
        let mut hour_vec: Vec<(u8, u32)> = hour_counts
            .iter()
            .enumerate()
            .map(|(h, &c)| (h as u8, c))
            .collect();
        hour_vec.sort_by(|a, b| b.1.cmp(&a.1));
        let peak_hours: Vec<u8> = hour_vec.iter().take(3).map(|(h, _)| *h).collect();

        (bitmap, peak_hours)
    }

    /// Compute session statistics
    fn compute_session_stats(&self, sessions: &[SessionEvent]) -> (f64, f64) {
        if sessions.is_empty() {
            return (0.0, 0.0);
        }

        let mut total_length = 0.0;
        let mut session_count = 0;

        for session in sessions {
            if let Some(ended_at) = session.ended_at {
                let duration = (ended_at - session.started_at).num_seconds() as f64;
                if duration > 0.0 && duration < 86400.0 {
                    // Max 24 hours
                    total_length += duration;
                    session_count += 1;
                }
            }
        }

        let avg_session_length = if session_count > 0 {
            total_length / session_count as f64
        } else {
            0.0
        };

        // Calculate sessions per day
        let days = self.config.lookback_days as f64;
        let avg_daily_sessions = sessions.len() as f64 / days;

        (avg_session_length, avg_daily_sessions)
    }

    /// Compute preferred video length
    fn compute_video_preference(&self, views: &[ContentViewEvent]) -> VideoLengthPreference {
        if views.len() < self.config.min_views_for_preference {
            return VideoLengthPreference::Mixed;
        }

        // Weight by completion rate (prefer videos user actually watches)
        let mut weighted_sum = 0.0;
        let mut total_weight = 0.0;

        for view in views {
            let weight = view.completion_rate as f64;
            let duration_seconds = view.content_duration_ms as f64 / 1000.0;
            weighted_sum += duration_seconds * weight;
            total_weight += weight;
        }

        if total_weight == 0.0 {
            return VideoLengthPreference::Mixed;
        }

        let avg_duration = weighted_sum / total_weight;
        VideoLengthPreference::from_duration_seconds(avg_duration)
    }

    /// Compute engagement rate
    fn compute_engagement_rate(&self, sessions: &[SessionEvent]) -> f64 {
        if sessions.is_empty() {
            return 0.0;
        }

        let total_views: u32 = sessions.iter().map(|s| s.view_count).sum();
        let total_engagements: u32 = sessions.iter().map(|s| s.engagement_count).sum();

        if total_views == 0 {
            return 0.0;
        }

        total_engagements as f64 / total_views as f64
    }

    /// Compute average completion rate
    fn compute_avg_completion_rate(&self, views: &[ContentViewEvent]) -> f64 {
        if views.is_empty() {
            return 0.0;
        }

        let sum: f64 = views.iter().map(|v| v.completion_rate as f64).sum();
        sum / views.len() as f64
    }

    /// Compute most active days of week
    fn compute_active_days(&self, views: &[ContentViewEvent]) -> Vec<u8> {
        if views.is_empty() {
            return Vec::new();
        }

        let mut day_counts: [u32; 7] = [0; 7];
        for view in views {
            if view.day_of_week < 7 {
                day_counts[view.day_of_week as usize] += 1;
            }
        }

        // Find top 3 active days
        let mut day_vec: Vec<(u8, u32)> = day_counts
            .iter()
            .enumerate()
            .map(|(d, &c)| (d as u8, c))
            .collect();
        day_vec.sort_by(|a, b| b.1.cmp(&a.1));

        let threshold = views.len() as u32 / 10; // At least 10% of views
        day_vec
            .iter()
            .take(3)
            .filter(|(_, c)| *c >= threshold)
            .map(|(d, _)| *d)
            .collect()
    }

    /// Check if user is typically active at given hour
    pub fn is_active_hour(pattern: &BehaviorPattern, hour: u8) -> bool {
        if hour >= 24 {
            return false;
        }
        (pattern.active_hours_bitmap & (1 << hour)) != 0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_video_length_preference() {
        assert_eq!(
            VideoLengthPreference::from_duration_seconds(10.0),
            VideoLengthPreference::VeryShort
        );
        assert_eq!(
            VideoLengthPreference::from_duration_seconds(30.0),
            VideoLengthPreference::Short
        );
        assert_eq!(
            VideoLengthPreference::from_duration_seconds(120.0),
            VideoLengthPreference::Medium
        );
        assert_eq!(
            VideoLengthPreference::from_duration_seconds(300.0),
            VideoLengthPreference::Long
        );
        assert_eq!(
            VideoLengthPreference::from_duration_seconds(900.0),
            VideoLengthPreference::VeryLong
        );
    }

    #[test]
    fn test_is_active_hour() {
        let pattern = BehaviorPattern {
            user_id: Uuid::new_v4(),
            active_hours_bitmap: 0b111111110000000000000000, // Hours 18-23 active
            peak_hours: vec![20, 21, 22],
            avg_session_length: 300.0,
            avg_daily_sessions: 2.0,
            preferred_video_length: VideoLengthPreference::Short,
            avg_scroll_speed: 0.0,
            engagement_rate: 0.1,
            avg_completion_rate: 0.6,
            active_days: vec![5, 6, 0], // Fri, Sat, Sun
            computed_at: Utc::now(),
        };

        assert!(BehaviorBuilder::is_active_hour(&pattern, 20));
        assert!(!BehaviorBuilder::is_active_hour(&pattern, 8));
    }
}
