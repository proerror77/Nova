use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Candidate {
    pub post_id: String,
    pub recall_source: RecallSource,
    pub recall_weight: f32,
    pub timestamp: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum RecallSource {
    Graph,        // 基於關注的召回
    Trending,     // 熱門召回
    Personalized, // 個性化召回
}

impl RecallSource {
    pub fn as_str(&self) -> &'static str {
        match self {
            RecallSource::Graph => "graph",
            RecallSource::Trending => "trending",
            RecallSource::Personalized => "personalized",
        }
    }
}

#[derive(Debug, Clone)]
pub struct RankedPost {
    pub post_id: String,
    pub score: f32,
    pub recall_source: RecallSource,
    pub features: PostFeatures,
}

#[derive(Debug, Clone, Default)]
pub struct PostFeatures {
    pub engagement_score: f32,
    pub recency_score: f32,
    pub author_quality_score: f32,
    pub content_quality_score: f32,
    pub author_id: Option<Uuid>, // For diversity layer author tracking
}

#[derive(Debug, Clone)]
#[derive(Default)]
pub struct RecallStats {
    pub graph_recall_count: i32,
    pub trending_recall_count: i32,
    pub personalized_recall_count: i32,
    pub total_candidates: i32,
    pub final_count: i32,
}

