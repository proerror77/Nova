//! Tag generation from VLM analysis results
use crate::providers::ImageAnalysisResult;
#[cfg(test)]
use crate::providers::Label;
use std::collections::HashMap;

/// Generated tag with metadata
#[derive(Debug, Clone)]
pub struct GeneratedTag {
    /// Normalized tag text
    pub tag: String,
    /// Confidence score (0.0 - 1.0)
    pub confidence: f32,
    /// Source of the tag
    pub source: TagSource,
}

/// Source of a generated tag
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TagSource {
    /// From label detection
    Label,
    /// From object detection
    Object,
    /// From web entity detection
    WebEntity,
    /// From best guess labels
    BestGuess,
}

impl TagSource {
    pub fn as_str(&self) -> &'static str {
        match self {
            TagSource::Label => "label",
            TagSource::Object => "object",
            TagSource::WebEntity => "web_entity",
            TagSource::BestGuess => "best_guess",
        }
    }
}

/// Tags that are too generic to be useful
const TAG_BLOCKLIST: &[&str] = &[
    // Generic image terms
    "image",
    "photo",
    "picture",
    "screenshot",
    "snapshot",
    "photography",
    "photograph",
    // Generic person terms
    "person",
    "people",
    "human",
    "man",
    "woman",
    "adult",
    "child",
    "face",
    // Time/location terms
    "day",
    "night",
    "indoor",
    "outdoor",
    "daytime",
    // Generic descriptors
    "close-up",
    "closeup",
    "background",
    "foreground",
    "vertical",
    "horizontal",
];

/// Generate normalized tags from VLM analysis result
///
/// # Arguments
/// * `result` - The VLM analysis result
/// * `max_tags` - Maximum number of tags to return
/// * `min_confidence` - Minimum confidence threshold
///
/// # Returns
/// A vector of generated tags, sorted by confidence descending
pub fn generate_tags(
    result: &ImageAnalysisResult,
    max_tags: usize,
    min_confidence: f32,
) -> Vec<GeneratedTag> {
    let mut tag_map: HashMap<String, GeneratedTag> = HashMap::new();

    // Process labels (highest priority, weight 1.0)
    for label in &result.labels {
        if label.confidence < min_confidence {
            continue;
        }
        let normalized = normalize_tag(&label.name);
        if is_valid_tag(&normalized) {
            let entry = tag_map.entry(normalized.clone()).or_insert(GeneratedTag {
                tag: normalized,
                confidence: 0.0,
                source: TagSource::Label,
            });
            // Keep highest confidence
            entry.confidence = entry.confidence.max(label.confidence);
        }
    }

    // Process objects (weight 0.9)
    for obj in &result.objects {
        if obj.confidence < min_confidence {
            continue;
        }
        let normalized = normalize_tag(&obj.name);
        if is_valid_tag(&normalized) && !tag_map.contains_key(&normalized) {
            tag_map.insert(
                normalized.clone(),
                GeneratedTag {
                    tag: normalized,
                    confidence: obj.confidence * 0.9,
                    source: TagSource::Object,
                },
            );
        }
    }

    // Process web entities (weight 0.8)
    for entity in &result.web_entities {
        if entity.confidence < min_confidence {
            continue;
        }
        let normalized = normalize_tag(&entity.name);
        if is_valid_tag(&normalized) && !tag_map.contains_key(&normalized) {
            tag_map.insert(
                normalized.clone(),
                GeneratedTag {
                    tag: normalized,
                    confidence: entity.confidence * 0.8,
                    source: TagSource::WebEntity,
                },
            );
        }
    }

    // Process best guess labels (fixed confidence 0.7)
    for label in &result.best_guess_labels {
        let normalized = normalize_tag(label);
        if is_valid_tag(&normalized) && !tag_map.contains_key(&normalized) {
            tag_map.insert(
                normalized.clone(),
                GeneratedTag {
                    tag: normalized,
                    confidence: 0.7,
                    source: TagSource::BestGuess,
                },
            );
        }
    }

    // Sort by confidence and take top N
    let mut tags: Vec<GeneratedTag> = tag_map.into_values().collect();
    tags.sort_by(|a, b| {
        b.confidence
            .partial_cmp(&a.confidence)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    tags.truncate(max_tags);

    tags
}

/// Normalize a tag string
fn normalize_tag(tag: &str) -> String {
    tag.to_lowercase()
        .trim()
        .replace(['_', '-'], " ")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

/// Check if a tag is valid (not blocked and has valid length)
fn is_valid_tag(tag: &str) -> bool {
    // Check length constraints
    if tag.len() < 2 || tag.len() > 50 {
        return false;
    }

    // Check blocklist
    if TAG_BLOCKLIST.contains(&tag) {
        return false;
    }

    // Check for purely numeric tags
    if tag.chars().all(|c| c.is_numeric() || c.is_whitespace()) {
        return false;
    }

    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_normalize_tag() {
        assert_eq!(normalize_tag("Hello World"), "hello world");
        assert_eq!(normalize_tag("street_style"), "street style");
        assert_eq!(normalize_tag("  spaced  out  "), "spaced out");
    }

    #[test]
    fn test_is_valid_tag() {
        assert!(is_valid_tag("fashion"));
        assert!(is_valid_tag("street style"));
        assert!(!is_valid_tag("a")); // too short
        assert!(!is_valid_tag("image")); // blocklisted
        assert!(!is_valid_tag("123")); // purely numeric
    }

    #[test]
    fn test_generate_tags_empty() {
        let result = ImageAnalysisResult {
            labels: vec![],
            objects: vec![],
            web_entities: vec![],
            best_guess_labels: vec![],
        };
        let tags = generate_tags(&result, 10, 0.3);
        assert!(tags.is_empty());
    }

    #[test]
    fn test_generate_tags_filters_low_confidence() {
        let result = ImageAnalysisResult {
            labels: vec![
                Label {
                    name: "fashion".to_string(),
                    confidence: 0.9,
                    mid: None,
                },
                Label {
                    name: "style".to_string(),
                    confidence: 0.2, // Below threshold
                    mid: None,
                },
            ],
            objects: vec![],
            web_entities: vec![],
            best_guess_labels: vec![],
        };
        let tags = generate_tags(&result, 10, 0.3);
        assert_eq!(tags.len(), 1);
        assert_eq!(tags[0].tag, "fashion");
    }

    #[test]
    fn test_generate_tags_deduplicates() {
        let result = ImageAnalysisResult {
            labels: vec![Label {
                name: "Fashion".to_string(),
                confidence: 0.9,
                mid: None,
            }],
            objects: vec![Label {
                name: "fashion".to_string(), // Same, different case
                confidence: 0.8,
                mid: None,
            }],
            web_entities: vec![],
            best_guess_labels: vec![],
        };
        let tags = generate_tags(&result, 10, 0.3);
        assert_eq!(tags.len(), 1);
        assert_eq!(tags[0].confidence, 0.9); // Should keep higher confidence
    }
}
