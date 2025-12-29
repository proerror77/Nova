// ============================================
// Content Classifier Service (內容分類器)
// ============================================
//
// Automatically classifies posts into channels based on:
// 1. Keyword matching with channel topic_keywords
// 2. AI/LLM semantic understanding (optional)
// 3. Image analysis from Alice enhance response
//
// Used for:
// - Auto-suggesting channels during post creation
// - Backfilling channel associations for existing posts
// - Improving feed relevance by ensuring proper channel tagging

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use thiserror::Error;
use uuid::Uuid;

// ============================================
// Error Types
// ============================================

#[derive(Debug, Error)]
pub enum ClassifierError {
    #[error("Classification failed: {0}")]
    ClassificationFailed(String),
    #[error("No channels available for classification")]
    NoChannelsAvailable,
    #[error("Content too short for classification")]
    ContentTooShort,
}

pub type Result<T> = std::result::Result<T, ClassifierError>;

// ============================================
// Classification Result Types
// ============================================

/// A single channel classification result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChannelClassification {
    pub channel_id: Uuid,
    pub channel_name: String,
    pub channel_slug: Option<String>,
    /// Confidence score (0.0 - 1.0)
    pub confidence: f32,
    /// Keywords that matched
    pub matched_keywords: Vec<String>,
    /// Classification method used
    pub method: ClassificationMethod,
}

/// How the classification was determined
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum ClassificationMethod {
    /// Keyword matching with topic_keywords
    KeywordMatch,
    /// AI/LLM semantic understanding
    LlmSemantic,
    /// Alice image analysis
    ImageAnalysis,
    /// Combined score from multiple methods
    Hybrid,
}

/// Input for classification
#[derive(Debug, Clone)]
pub struct ClassificationInput {
    pub post_id: Uuid,
    pub content: String,
    /// Alice enhance response (hashtags, themes from image analysis)
    pub image_themes: Option<Vec<String>>,
    pub image_hashtags: Option<Vec<String>>,
}

/// Channel profile for matching
#[derive(Debug, Clone)]
pub struct ChannelProfile {
    pub id: Uuid,
    pub name: String,
    pub slug: Option<String>,
    pub topic_keywords: Vec<String>,
}

// ============================================
// Content Classifier
// ============================================

pub struct ContentClassifier {
    /// Minimum confidence threshold to include a channel
    min_confidence: f32,
    /// Maximum number of channels to return
    max_channels: usize,
    /// Minimum content length to attempt classification
    min_content_length: usize,
}

impl Default for ContentClassifier {
    fn default() -> Self {
        Self {
            min_confidence: 0.3,
            max_channels: 3,
            min_content_length: 10,
        }
    }
}

impl ContentClassifier {
    pub fn new(min_confidence: f32, max_channels: usize) -> Self {
        Self {
            min_confidence,
            max_channels,
            min_content_length: 10,
        }
    }

    /// Classify content into channels using keyword matching
    pub fn classify(
        &self,
        input: &ClassificationInput,
        channels: &[ChannelProfile],
    ) -> Result<Vec<ChannelClassification>> {
        if channels.is_empty() {
            return Err(ClassifierError::NoChannelsAvailable);
        }

        // Combine all text sources for matching
        let mut all_text = input.content.to_lowercase();

        // Add image themes and hashtags
        if let Some(themes) = &input.image_themes {
            all_text.push(' ');
            all_text.push_str(&themes.join(" ").to_lowercase());
        }
        if let Some(hashtags) = &input.image_hashtags {
            all_text.push(' ');
            // Remove # prefix from hashtags
            let clean_hashtags: Vec<String> = hashtags
                .iter()
                .map(|h| h.trim_start_matches('#').to_lowercase())
                .collect();
            all_text.push_str(&clean_hashtags.join(" "));
        }

        if all_text.len() < self.min_content_length {
            return Err(ClassifierError::ContentTooShort);
        }

        // Tokenize content into words
        let content_words: Vec<&str> = all_text
            .split(|c: char| !c.is_alphanumeric())
            .filter(|s| !s.is_empty() && s.len() > 2)
            .collect();

        // Score each channel
        let mut classifications: Vec<ChannelClassification> = Vec::new();

        for channel in channels {
            let (score, matched) = self.score_channel(&content_words, &all_text, channel);

            if score >= self.min_confidence && !matched.is_empty() {
                let method = if input.image_themes.is_some() || input.image_hashtags.is_some() {
                    ClassificationMethod::Hybrid
                } else {
                    ClassificationMethod::KeywordMatch
                };

                classifications.push(ChannelClassification {
                    channel_id: channel.id,
                    channel_name: channel.name.clone(),
                    channel_slug: channel.slug.clone(),
                    confidence: score,
                    matched_keywords: matched,
                    method,
                });
            }
        }

        // Sort by confidence descending (NaN values treated as equal)
        classifications.sort_by(|a, b| {
            b.confidence
                .partial_cmp(&a.confidence)
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        // Limit to max channels
        classifications.truncate(self.max_channels);

        Ok(classifications)
    }

    /// Score a channel based on keyword matches
    fn score_channel(
        &self,
        content_words: &[&str],
        full_text: &str,
        channel: &ChannelProfile,
    ) -> (f32, Vec<String>) {
        let mut matched_keywords = Vec::new();
        let mut total_weight = 0.0f32;

        for keyword in &channel.topic_keywords {
            let keyword_lower = keyword.to_lowercase();

            // Check for exact word match (higher weight)
            let exact_match = content_words.iter().any(|&w| w == keyword_lower);

            // Check for substring match (lower weight)
            let substring_match = !exact_match && full_text.contains(&keyword_lower);

            if exact_match {
                matched_keywords.push(keyword.clone());
                total_weight += 1.0;
            } else if substring_match {
                matched_keywords.push(keyword.clone());
                total_weight += 0.5;
            }
        }

        // Normalize score: more matches = higher confidence, but cap at 1.0
        // Use diminishing returns formula
        let keyword_count = channel.topic_keywords.len() as f32;
        let base_score = if keyword_count > 0.0 {
            (total_weight / keyword_count).min(1.0)
        } else {
            0.0
        };

        // Boost score based on number of matches (more matches = more confident)
        let match_boost = (matched_keywords.len() as f32 * 0.1).min(0.3);
        let final_score = (base_score + match_boost).min(1.0);

        (final_score, matched_keywords)
    }

    /// Suggest channels for a post with Alice enhancement data
    pub fn suggest_channels(
        &self,
        content: &str,
        alice_description: Option<&str>,
        alice_hashtags: Option<&[String]>,
        channels: &[ChannelProfile],
    ) -> Result<Vec<ChannelClassification>> {
        // Build classification input
        let mut combined_content = content.to_string();
        if let Some(desc) = alice_description {
            combined_content.push(' ');
            combined_content.push_str(desc);
        }

        let input = ClassificationInput {
            post_id: Uuid::nil(), // Not needed for suggestions
            content: combined_content,
            image_themes: None,
            image_hashtags: alice_hashtags.map(|h| h.to_vec()),
        };

        self.classify(&input, channels)
    }
}

// ============================================
// Tests
// ============================================

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_channels() -> Vec<ChannelProfile> {
        vec![
            ChannelProfile {
                id: Uuid::new_v4(),
                name: "Tech News".to_string(),
                slug: Some("tech".to_string()),
                topic_keywords: vec![
                    "technology".to_string(),
                    "tech".to_string(),
                    "software".to_string(),
                    "AI".to_string(),
                    "programming".to_string(),
                ],
            },
            ChannelProfile {
                id: Uuid::new_v4(),
                name: "Fashion".to_string(),
                slug: Some("fashion".to_string()),
                topic_keywords: vec![
                    "fashion".to_string(),
                    "style".to_string(),
                    "outfit".to_string(),
                    "clothes".to_string(),
                ],
            },
            ChannelProfile {
                id: Uuid::new_v4(),
                name: "Fitness".to_string(),
                slug: Some("fitness".to_string()),
                topic_keywords: vec![
                    "fitness".to_string(),
                    "workout".to_string(),
                    "gym".to_string(),
                    "exercise".to_string(),
                ],
            },
        ]
    }

    #[test]
    fn test_classify_tech_content() {
        let classifier = ContentClassifier::default();
        let channels = sample_channels();

        let input = ClassificationInput {
            post_id: Uuid::new_v4(),
            content: "Just learned about the new AI programming tools! The technology is amazing."
                .to_string(),
            image_themes: None,
            image_hashtags: None,
        };

        let results = classifier.classify(&input, &channels).unwrap();
        assert!(!results.is_empty());
        assert_eq!(results[0].channel_name, "Tech News");
        assert!(results[0].confidence > 0.3);
    }

    #[test]
    fn test_classify_with_hashtags() {
        let classifier = ContentClassifier::default();
        let channels = sample_channels();

        let input = ClassificationInput {
            post_id: Uuid::new_v4(),
            content: "Morning vibes".to_string(),
            image_themes: None,
            image_hashtags: Some(vec![
                "#fitness".to_string(),
                "#workout".to_string(),
                "#gym".to_string(),
            ]),
        };

        let results = classifier.classify(&input, &channels).unwrap();
        assert!(!results.is_empty());
        assert_eq!(results[0].channel_name, "Fitness");
    }

    #[test]
    fn test_max_channels_limit() {
        let classifier = ContentClassifier::new(0.1, 2);
        let channels = sample_channels();

        let input = ClassificationInput {
            post_id: Uuid::new_v4(),
            content: "Technology fashion fitness workout programming style gym".to_string(),
            image_themes: None,
            image_hashtags: None,
        };

        let results = classifier.classify(&input, &channels).unwrap();
        assert!(results.len() <= 2);
    }
}
