//! Channel matching based on VLM-generated tags
use serde::{Deserialize, Serialize};
use tracing::debug;
use uuid::Uuid;

/// Channel with VLM keywords for matching
#[derive(Debug, Clone, Deserialize)]
pub struct Channel {
    pub id: Uuid,
    pub name: String,
    pub slug: String,
    pub vlm_keywords: Vec<KeywordWeight>,
}

/// A keyword with its matching weight
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct KeywordWeight {
    pub keyword: String,
    pub weight: f32,
}

/// A matched channel with confidence score
#[derive(Debug, Clone, Serialize)]
pub struct ChannelMatch {
    /// Channel ID
    pub channel_id: Uuid,
    /// Channel name
    pub channel_name: String,
    /// Channel slug
    pub channel_slug: String,
    /// Confidence score for this match (0.0 - 1.0)
    pub confidence: f32,
    /// Keywords that matched
    pub matched_keywords: Vec<String>,
}

/// Match tags to channels
///
/// # Arguments
/// * `tags` - List of (tag, confidence) tuples from VLM
/// * `channels` - Available channels with their keywords
/// * `max_channels` - Maximum number of channels to return
/// * `min_confidence` - Minimum confidence threshold for matching
///
/// # Returns
/// A vector of matched channels, sorted by confidence descending
pub fn match_channels(
    tags: &[(String, f32)],
    channels: &[Channel],
    max_channels: usize,
    min_confidence: f32,
) -> Vec<ChannelMatch> {
    let mut matches: Vec<ChannelMatch> = Vec::new();

    for channel in channels {
        let (score, matched_keywords) = calculate_channel_score(tags, &channel.vlm_keywords);

        if score >= min_confidence && !matched_keywords.is_empty() {
            debug!(
                channel = %channel.name,
                score = score,
                matches = ?matched_keywords,
                "Channel matched"
            );

            matches.push(ChannelMatch {
                channel_id: channel.id,
                channel_name: channel.name.clone(),
                channel_slug: channel.slug.clone(),
                confidence: score,
                matched_keywords,
            });
        }
    }

    // Sort by confidence descending
    matches.sort_by(|a, b| {
        b.confidence
            .partial_cmp(&a.confidence)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    matches.truncate(max_channels);

    matches
}

/// Calculate match score between tags and channel keywords
fn calculate_channel_score(
    tags: &[(String, f32)],
    keywords: &[KeywordWeight],
) -> (f32, Vec<String>) {
    let mut total_score = 0.0f32;
    let mut matched_keywords: Vec<String> = Vec::new();
    let mut seen_keywords: std::collections::HashSet<String> = std::collections::HashSet::new();

    for (tag, tag_confidence) in tags {
        let tag_lower = tag.to_lowercase();

        for kw in keywords {
            let kw_lower = kw.keyword.to_lowercase();

            // Calculate match score
            let match_score = if tag_lower == kw_lower {
                // Exact match
                1.0
            } else if tag_lower.contains(&kw_lower) {
                // Tag contains keyword
                0.7
            } else if kw_lower.contains(&tag_lower) {
                // Keyword contains tag
                0.6
            } else {
                // No match
                0.0
            };

            if match_score > 0.0 {
                let weighted_score = match_score * kw.weight * tag_confidence;
                total_score += weighted_score;

                // Track unique matched keywords
                if !seen_keywords.contains(&kw.keyword) {
                    matched_keywords.push(kw.keyword.clone());
                    seen_keywords.insert(kw.keyword.clone());
                }
            }
        }
    }

    // Normalize score with diminishing returns
    let normalized = if matched_keywords.is_empty() || keywords.is_empty() {
        0.0
    } else {
        // Base score normalized by keyword count
        let keyword_count = keywords.len() as f32;
        let base_score = (total_score / keyword_count).min(1.0);

        // Bonus for multiple matches (up to 30%)
        let match_boost = (matched_keywords.len() as f32 * 0.1).min(0.3);

        (base_score + match_boost).min(1.0)
    };

    (normalized, matched_keywords)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_test_channel(name: &str, keywords: Vec<(&str, f32)>) -> Channel {
        Channel {
            id: Uuid::new_v4(),
            name: name.to_string(),
            slug: name.to_lowercase().replace(' ', "-"),
            vlm_keywords: keywords
                .into_iter()
                .map(|(k, w)| KeywordWeight {
                    keyword: k.to_string(),
                    weight: w,
                })
                .collect(),
        }
    }

    #[test]
    fn test_exact_match() {
        let channels = vec![create_test_channel(
            "Fashion",
            vec![("fashion", 1.0), ("style", 0.8)],
        )];

        let tags = vec![("fashion".to_string(), 0.9)];
        let matches = match_channels(&tags, &channels, 3, 0.25);

        assert_eq!(matches.len(), 1);
        assert_eq!(matches[0].channel_name, "Fashion");
        assert!(matches[0].confidence > 0.0);
    }

    #[test]
    fn test_partial_match() {
        let channels = vec![create_test_channel(
            "Fashion",
            vec![("fashion", 1.0), ("outfit", 0.9)],
        )];

        let tags = vec![("street fashion".to_string(), 0.9)];
        let matches = match_channels(&tags, &channels, 3, 0.25);

        assert_eq!(matches.len(), 1);
        assert!(matches[0].matched_keywords.contains(&"fashion".to_string()));
    }

    #[test]
    fn test_no_match_below_threshold() {
        let channels = vec![create_test_channel("Fashion", vec![("fashion", 1.0)])];

        let tags = vec![("nature".to_string(), 0.9)];
        let matches = match_channels(&tags, &channels, 3, 0.25);

        assert!(matches.is_empty());
    }

    #[test]
    fn test_multiple_channel_sorting() {
        let channels = vec![
            create_test_channel("Fashion", vec![("fashion", 1.0), ("style", 0.8)]),
            create_test_channel("Travel", vec![("travel", 1.0), ("vacation", 0.9)]),
        ];

        let tags = vec![
            ("fashion".to_string(), 0.9),
            ("style".to_string(), 0.8),
            ("travel".to_string(), 0.5), // Lower confidence
        ];

        let matches = match_channels(&tags, &channels, 3, 0.25);

        assert_eq!(matches.len(), 2);
        // Fashion should be first due to higher combined score
        assert_eq!(matches[0].channel_name, "Fashion");
    }

    #[test]
    fn test_max_channels_limit() {
        let channels = vec![
            create_test_channel("Fashion", vec![("fashion", 1.0)]),
            create_test_channel("Travel", vec![("travel", 1.0)]),
            create_test_channel("Fitness", vec![("fitness", 1.0)]),
            create_test_channel("Pets", vec![("pets", 1.0)]),
        ];

        let tags = vec![
            ("fashion".to_string(), 0.9),
            ("travel".to_string(), 0.8),
            ("fitness".to_string(), 0.7),
            ("pets".to_string(), 0.6),
        ];

        let matches = match_channels(&tags, &channels, 2, 0.25);

        assert_eq!(matches.len(), 2);
    }
}
