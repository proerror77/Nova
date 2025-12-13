// ============================================
// Interest Builder (兴趣标签构建器)
// ============================================
//
// Builds user interest tags from engagement history with time decay
//
// Interest scoring formula:
// score = SUM(action_weight * exp(-decay_rate * days_ago))
//
// Action weights:
// - Like: 1.0
// - Comment: 2.0
// - Share: 3.0
// - Save: 2.5
// - Complete watch (>80%): 1.5
// - Partial watch (50-80%): 0.8
// - Skip (<20%): -0.5
// - Not interested: -2.0

use super::{ProfileBuilderError, Result};
use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tracing::{debug, info};
use uuid::Uuid;

/// User interest tag with weight and metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InterestTag {
    /// Tag name/category
    pub tag: String,
    /// Current weight after decay
    pub weight: f64,
    /// Source of interest (engagement, content, explicit)
    pub source: InterestSource,
    /// Number of interactions with this interest
    pub interaction_count: u32,
    /// Last interaction time
    pub last_interaction: DateTime<Utc>,
    /// Decay rate (how fast interest fades)
    pub decay_rate: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum InterestSource {
    /// From engagement actions (like, comment, share)
    Engagement,
    /// From content watched
    ContentWatch,
    /// From explicit user preference
    Explicit,
    /// From social graph (followed creators)
    Social,
}

/// Engagement action with weight for interest calculation
#[derive(Debug, Clone)]
pub struct EngagementSignal {
    pub user_id: Uuid,
    pub content_id: Uuid,
    pub content_tags: Vec<String>,
    pub action: EngagementAction,
    pub timestamp: DateTime<Utc>,
}

#[derive(Debug, Clone)]
pub enum EngagementAction {
    Like,
    Comment,
    Share,
    Save,
    CompleteWatch,     // >80% completion
    PartialWatch,      // 50-80% completion
    Skip,              // <20% completion
    NotInterested,
}

impl EngagementAction {
    pub fn weight(&self) -> f64 {
        match self {
            EngagementAction::Like => 1.0,
            EngagementAction::Comment => 2.0,
            EngagementAction::Share => 3.0,
            EngagementAction::Save => 2.5,
            EngagementAction::CompleteWatch => 1.5,
            EngagementAction::PartialWatch => 0.8,
            EngagementAction::Skip => -0.5,
            EngagementAction::NotInterested => -2.0,
        }
    }
}

/// Configuration for interest building
#[derive(Debug, Clone)]
pub struct InterestBuilderConfig {
    /// Time window to consider (days)
    pub lookback_days: i64,
    /// Decay rate per day (0.95 means 5% decay per day)
    pub daily_decay_rate: f64,
    /// Minimum weight threshold to keep interest
    pub min_weight_threshold: f64,
    /// Maximum number of interests per user
    pub max_interests: usize,
}

impl Default for InterestBuilderConfig {
    fn default() -> Self {
        Self {
            lookback_days: 30,
            daily_decay_rate: 0.95,
            min_weight_threshold: 0.1,
            max_interests: 100,
        }
    }
}

/// Interest builder that aggregates engagement signals into interest tags
pub struct InterestBuilder {
    config: InterestBuilderConfig,
}

impl InterestBuilder {
    pub fn new(config: InterestBuilderConfig) -> Self {
        Self { config }
    }

    /// Build interest tags from engagement signals
    ///
    /// This is the core algorithm for computing user interests:
    /// 1. Group signals by tag
    /// 2. Apply time decay to each signal
    /// 3. Aggregate weighted signals
    /// 4. Filter by threshold and limit
    pub fn build_interests(
        &self,
        signals: Vec<EngagementSignal>,
    ) -> Result<Vec<InterestTag>> {
        if signals.is_empty() {
            return Ok(Vec::new());
        }

        let now = Utc::now();

        // Aggregate signals by tag
        let mut tag_signals: HashMap<String, Vec<(f64, DateTime<Utc>, u32)>> = HashMap::new();

        for signal in signals {
            let weight = signal.action.weight();
            for tag in signal.content_tags {
                tag_signals
                    .entry(tag)
                    .or_insert_with(Vec::new)
                    .push((weight, signal.timestamp, 1));
            }
        }

        // Calculate decayed weights for each tag
        let mut interests: Vec<InterestTag> = tag_signals
            .into_iter()
            .filter_map(|(tag, signals)| {
                let (total_weight, interaction_count, last_interaction) =
                    self.aggregate_signals(&signals, now);

                if total_weight.abs() < self.config.min_weight_threshold {
                    return None;
                }

                Some(InterestTag {
                    tag,
                    weight: total_weight,
                    source: InterestSource::Engagement,
                    interaction_count,
                    last_interaction,
                    decay_rate: self.config.daily_decay_rate,
                })
            })
            .collect();

        // Sort by absolute weight (descending)
        interests.sort_by(|a, b| {
            b.weight
                .abs()
                .partial_cmp(&a.weight.abs())
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        // Limit to max interests
        interests.truncate(self.config.max_interests);

        info!(
            interest_count = interests.len(),
            "Built user interest tags"
        );

        Ok(interests)
    }

    /// Aggregate signals with time decay
    fn aggregate_signals(
        &self,
        signals: &[(f64, DateTime<Utc>, u32)],
        now: DateTime<Utc>,
    ) -> (f64, u32, DateTime<Utc>) {
        let mut total_weight = 0.0;
        let mut interaction_count = 0u32;
        let mut last_interaction = signals.first().map(|(_, t, _)| *t).unwrap_or(now);

        for (weight, timestamp, count) in signals {
            let days_ago = (now - *timestamp).num_days() as f64;
            if days_ago > self.config.lookback_days as f64 {
                continue;
            }

            // Apply exponential decay
            let decay_factor = self.config.daily_decay_rate.powf(days_ago);
            total_weight += weight * decay_factor;
            interaction_count += count;

            if *timestamp > last_interaction {
                last_interaction = *timestamp;
            }
        }

        (total_weight, interaction_count, last_interaction)
    }

    /// Merge new interests with existing profile interests
    pub fn merge_interests(
        &self,
        existing: Vec<InterestTag>,
        new: Vec<InterestTag>,
    ) -> Vec<InterestTag> {
        let mut merged: HashMap<String, InterestTag> = HashMap::new();

        // Add existing interests
        for interest in existing {
            merged.insert(interest.tag.clone(), interest);
        }

        // Merge new interests
        for interest in new {
            if let Some(existing) = merged.get_mut(&interest.tag) {
                // Combine weights
                existing.weight += interest.weight;
                existing.interaction_count += interest.interaction_count;
                if interest.last_interaction > existing.last_interaction {
                    existing.last_interaction = interest.last_interaction;
                }
            } else {
                merged.insert(interest.tag.clone(), interest);
            }
        }

        // Filter and sort
        let mut result: Vec<InterestTag> = merged
            .into_values()
            .filter(|i| i.weight.abs() >= self.config.min_weight_threshold)
            .collect();

        result.sort_by(|a, b| {
            b.weight
                .abs()
                .partial_cmp(&a.weight.abs())
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        result.truncate(self.config.max_interests);

        result
    }

    /// Apply decay to existing interests (call periodically)
    pub fn apply_decay(&self, interests: &mut [InterestTag], days: f64) {
        for interest in interests {
            let decay_factor = interest.decay_rate.powf(days);
            interest.weight *= decay_factor;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_engagement_weights() {
        assert_eq!(EngagementAction::Like.weight(), 1.0);
        assert_eq!(EngagementAction::Comment.weight(), 2.0);
        assert_eq!(EngagementAction::Share.weight(), 3.0);
        assert!(EngagementAction::NotInterested.weight() < 0.0);
    }

    #[test]
    fn test_build_interests() {
        let builder = InterestBuilder::new(InterestBuilderConfig::default());
        let user_id = Uuid::new_v4();
        let content_id = Uuid::new_v4();

        let signals = vec![
            EngagementSignal {
                user_id,
                content_id,
                content_tags: vec!["music".to_string(), "pop".to_string()],
                action: EngagementAction::Like,
                timestamp: Utc::now(),
            },
            EngagementSignal {
                user_id,
                content_id,
                content_tags: vec!["music".to_string(), "dance".to_string()],
                action: EngagementAction::Comment,
                timestamp: Utc::now(),
            },
        ];

        let interests = builder.build_interests(signals).unwrap();
        assert!(!interests.is_empty());

        // Music should have highest weight (1.0 + 2.0 = 3.0)
        let music_interest = interests.iter().find(|i| i.tag == "music").unwrap();
        assert!(music_interest.weight > 2.0);
    }

    #[test]
    fn test_time_decay() {
        let config = InterestBuilderConfig {
            daily_decay_rate: 0.9, // 10% decay per day
            ..Default::default()
        };
        let builder = InterestBuilder::new(config);
        let user_id = Uuid::new_v4();
        let content_id = Uuid::new_v4();

        // Signal from 10 days ago
        let old_time = Utc::now() - Duration::days(10);
        let signals = vec![EngagementSignal {
            user_id,
            content_id,
            content_tags: vec!["old_topic".to_string()],
            action: EngagementAction::Like,
            timestamp: old_time,
        }];

        let interests = builder.build_interests(signals).unwrap();
        if !interests.is_empty() {
            // Weight should be decayed: 1.0 * 0.9^10 ≈ 0.35
            assert!(interests[0].weight < 0.5);
        }
    }
}
