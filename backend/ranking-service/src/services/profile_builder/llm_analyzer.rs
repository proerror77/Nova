// ============================================
// LLM Profile Analyzer (AI 用戶畫像分析器)
// ============================================
//
// Uses Large Language Models to:
// 1. Generate natural language user persona descriptions
// 2. Identify deep interest patterns and connections
// 3. Predict content preferences and engagement likelihood
// 4. Generate personalized content recommendations
// 5. Create user segment classifications
//
// Supports multiple LLM providers: Anthropic Claude, OpenAI, Local models

use super::{BehaviorPattern, InterestTag, ProfileBuilderError, Result, UserProfile};
use crate::config::LlmConfig;
use async_trait::async_trait;
use chrono::{DateTime, Utc};
use reqwest::Client as HttpClient;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::RwLock;
use tracing::{debug, error, info, warn};
use uuid::Uuid;

// ============================================
// Core Types
// ============================================

/// AI-generated user persona with insights
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserPersona {
    pub user_id: Uuid,
    /// Natural language description of the user
    pub description: String,
    /// Primary interest categories (high-level)
    pub primary_interests: Vec<String>,
    /// Content consumption patterns
    pub consumption_patterns: ConsumptionPatterns,
    /// Predicted preferences
    pub predicted_preferences: PredictedPreferences,
    /// User segment classification
    pub segment: UserSegment,
    /// Confidence score (0-1)
    pub confidence: f32,
    /// When this persona was generated
    pub generated_at: DateTime<Utc>,
    /// LLM model used
    pub model_used: String,
}

/// Content consumption patterns identified by AI
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConsumptionPatterns {
    /// Preferred content length category
    pub preferred_length: String,
    /// Peak activity description
    pub activity_pattern: String,
    /// Engagement style (e.g., "passive viewer", "active engager")
    pub engagement_style: String,
    /// Content discovery preference
    pub discovery_preference: String,
}

/// AI-predicted user preferences
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PredictedPreferences {
    /// Topics likely to engage the user
    pub likely_interests: Vec<String>,
    /// Topics to avoid
    pub disliked_topics: Vec<String>,
    /// Optimal posting time for content targeting this user
    pub optimal_delivery_hours: Vec<u8>,
    /// Preferred content format
    pub format_preferences: Vec<String>,
}

/// User segment classification
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum UserSegment {
    /// New users with limited data
    NewUser,
    /// Casual browser, low engagement
    CasualViewer,
    /// Regular user with consistent patterns
    RegularUser,
    /// Highly engaged power user
    PowerUser,
    /// Content creator who also consumes
    CreatorConsumer,
    /// Niche interest focused
    NicheEnthusiast,
    /// Trend follower
    TrendFollower,
    /// Deep diver on specific topics
    DeepDiver,
}

impl UserSegment {
    pub fn as_str(&self) -> &'static str {
        match self {
            UserSegment::NewUser => "new_user",
            UserSegment::CasualViewer => "casual_viewer",
            UserSegment::RegularUser => "regular_user",
            UserSegment::PowerUser => "power_user",
            UserSegment::CreatorConsumer => "creator_consumer",
            UserSegment::NicheEnthusiast => "niche_enthusiast",
            UserSegment::TrendFollower => "trend_follower",
            UserSegment::DeepDiver => "deep_diver",
        }
    }

    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "new_user" => UserSegment::NewUser,
            "casual_viewer" => UserSegment::CasualViewer,
            "regular_user" => UserSegment::RegularUser,
            "power_user" => UserSegment::PowerUser,
            "creator_consumer" => UserSegment::CreatorConsumer,
            "niche_enthusiast" => UserSegment::NicheEnthusiast,
            "trend_follower" => UserSegment::TrendFollower,
            "deep_diver" => UserSegment::DeepDiver,
            _ => UserSegment::RegularUser,
        }
    }
}

// ============================================
// LLM Provider Trait
// ============================================

#[async_trait]
pub trait LlmProvider: Send + Sync {
    /// Generate completion from prompt
    async fn complete(&self, prompt: &str, max_tokens: u32) -> Result<String>;

    /// Generate embeddings for text
    async fn embed(&self, text: &str) -> Result<Vec<f32>>;

    /// Get provider name
    fn name(&self) -> &str;
}

// ============================================
// Anthropic Claude Provider
// ============================================

pub struct AnthropicProvider {
    client: HttpClient,
    api_key: String,
    model: String,
}

impl AnthropicProvider {
    pub fn new(api_key: &str, model: &str) -> Self {
        let client = HttpClient::builder()
            .timeout(Duration::from_secs(60))
            .build()
            .expect("Failed to create HTTP client");

        Self {
            client,
            api_key: api_key.to_string(),
            model: model.to_string(),
        }
    }
}

#[derive(Serialize)]
struct AnthropicRequest {
    model: String,
    max_tokens: u32,
    messages: Vec<AnthropicMessage>,
}

#[derive(Serialize)]
struct AnthropicMessage {
    role: String,
    content: String,
}

#[derive(Deserialize)]
struct AnthropicResponse {
    content: Vec<AnthropicContent>,
}

#[derive(Deserialize)]
struct AnthropicContent {
    text: String,
}

#[async_trait]
impl LlmProvider for AnthropicProvider {
    async fn complete(&self, prompt: &str, max_tokens: u32) -> Result<String> {
        let request = AnthropicRequest {
            model: self.model.clone(),
            max_tokens,
            messages: vec![AnthropicMessage {
                role: "user".to_string(),
                content: prompt.to_string(),
            }],
        };

        let response = self
            .client
            .post("https://api.anthropic.com/v1/messages")
            .header("x-api-key", &self.api_key)
            .header("anthropic-version", "2023-06-01")
            .header("content-type", "application/json")
            .json(&request)
            .send()
            .await
            .map_err(|e| {
                ProfileBuilderError::DatabaseError(format!("Anthropic API error: {}", e))
            })?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(ProfileBuilderError::DatabaseError(format!(
                "Anthropic API error: {}",
                error_text
            )));
        }

        let result: AnthropicResponse = response
            .json()
            .await
            .map_err(|e| ProfileBuilderError::DatabaseError(format!("Parse error: {}", e)))?;

        Ok(result
            .content
            .first()
            .map(|c| c.text.clone())
            .unwrap_or_default())
    }

    async fn embed(&self, _text: &str) -> Result<Vec<f32>> {
        // Anthropic doesn't have embeddings API, use OpenAI for embeddings
        Err(ProfileBuilderError::DatabaseError(
            "Anthropic does not support embeddings".to_string(),
        ))
    }

    fn name(&self) -> &str {
        "anthropic"
    }
}

// ============================================
// OpenAI Provider
// ============================================

pub struct OpenAIProvider {
    client: HttpClient,
    api_key: String,
    model: String,
    embedding_model: String,
}

impl OpenAIProvider {
    pub fn new(api_key: &str, model: &str, embedding_model: &str) -> Self {
        let client = HttpClient::builder()
            .timeout(Duration::from_secs(60))
            .build()
            .expect("Failed to create HTTP client");

        Self {
            client,
            api_key: api_key.to_string(),
            model: model.to_string(),
            embedding_model: embedding_model.to_string(),
        }
    }
}

#[derive(Serialize)]
struct OpenAICompletionRequest {
    model: String,
    messages: Vec<OpenAIMessage>,
    max_tokens: u32,
    temperature: f32,
}

#[derive(Serialize)]
struct OpenAIMessage {
    role: String,
    content: String,
}

#[derive(Deserialize)]
struct OpenAICompletionResponse {
    choices: Vec<OpenAIChoice>,
}

#[derive(Deserialize)]
struct OpenAIChoice {
    message: OpenAIResponseMessage,
}

#[derive(Deserialize)]
struct OpenAIResponseMessage {
    content: String,
}

#[derive(Serialize)]
struct OpenAIEmbeddingRequest {
    model: String,
    input: String,
}

#[derive(Deserialize)]
struct OpenAIEmbeddingResponse {
    data: Vec<OpenAIEmbeddingData>,
}

#[derive(Deserialize)]
struct OpenAIEmbeddingData {
    embedding: Vec<f32>,
}

#[async_trait]
impl LlmProvider for OpenAIProvider {
    async fn complete(&self, prompt: &str, max_tokens: u32) -> Result<String> {
        let request = OpenAICompletionRequest {
            model: self.model.clone(),
            messages: vec![OpenAIMessage {
                role: "user".to_string(),
                content: prompt.to_string(),
            }],
            max_tokens,
            temperature: 0.3,
        };

        let response = self
            .client
            .post("https://api.openai.com/v1/chat/completions")
            .header("Authorization", format!("Bearer {}", self.api_key))
            .header("Content-Type", "application/json")
            .json(&request)
            .send()
            .await
            .map_err(|e| ProfileBuilderError::DatabaseError(format!("OpenAI API error: {}", e)))?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(ProfileBuilderError::DatabaseError(format!(
                "OpenAI API error: {}",
                error_text
            )));
        }

        let result: OpenAICompletionResponse = response
            .json()
            .await
            .map_err(|e| ProfileBuilderError::DatabaseError(format!("Parse error: {}", e)))?;

        Ok(result
            .choices
            .first()
            .map(|c| c.message.content.clone())
            .unwrap_or_default())
    }

    async fn embed(&self, text: &str) -> Result<Vec<f32>> {
        let request = OpenAIEmbeddingRequest {
            model: self.embedding_model.clone(),
            input: text.to_string(),
        };

        let response = self
            .client
            .post("https://api.openai.com/v1/embeddings")
            .header("Authorization", format!("Bearer {}", self.api_key))
            .header("Content-Type", "application/json")
            .json(&request)
            .send()
            .await
            .map_err(|e| ProfileBuilderError::DatabaseError(format!("OpenAI API error: {}", e)))?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(ProfileBuilderError::DatabaseError(format!(
                "OpenAI API error: {}",
                error_text
            )));
        }

        let result: OpenAIEmbeddingResponse = response
            .json()
            .await
            .map_err(|e| ProfileBuilderError::DatabaseError(format!("Parse error: {}", e)))?;

        Ok(result
            .data
            .first()
            .map(|d| d.embedding.clone())
            .unwrap_or_default())
    }

    fn name(&self) -> &str {
        "openai"
    }
}

// ============================================
// LLM Profile Analyzer
// ============================================

pub struct LlmProfileAnalyzer {
    provider: Arc<dyn LlmProvider>,
    config: LlmConfig,
    /// Cache for generated personas
    persona_cache: Arc<RwLock<HashMap<Uuid, UserPersona>>>,
    /// Cache TTL in seconds
    cache_ttl_secs: u64,
}

impl LlmProfileAnalyzer {
    /// Create a new LLM Profile Analyzer from config
    pub fn from_config(config: &LlmConfig) -> Option<Self> {
        if !config.enabled {
            info!("LLM Profile Analyzer is disabled");
            return None;
        }

        let provider: Arc<dyn LlmProvider> = match config.provider.as_str() {
            "anthropic" => Arc::new(AnthropicProvider::new(&config.api_key, &config.model)),
            "openai" => Arc::new(OpenAIProvider::new(
                &config.api_key,
                &config.model,
                &config.embedding_model,
            )),
            _ => {
                warn!(provider = %config.provider, "Unknown LLM provider, using Anthropic");
                Arc::new(AnthropicProvider::new(&config.api_key, &config.model))
            }
        };

        info!(
            provider = provider.name(),
            model = %config.model,
            "LLM Profile Analyzer initialized"
        );

        Some(Self {
            provider,
            config: config.clone(),
            persona_cache: Arc::new(RwLock::new(HashMap::new())),
            cache_ttl_secs: 3600, // 1 hour cache
        })
    }

    /// Analyze user profile and generate AI persona
    pub async fn analyze_profile(&self, profile: &UserProfile) -> Result<UserPersona> {
        // Check cache first
        {
            let cache = self.persona_cache.read().await;
            if let Some(cached) = cache.get(&profile.user_id) {
                let age = Utc::now() - cached.generated_at;
                if age.num_seconds() < self.cache_ttl_secs as i64 {
                    debug!(user_id = %profile.user_id, "Returning cached persona");
                    return Ok(cached.clone());
                }
            }
        }

        info!(user_id = %profile.user_id, "Generating AI persona");

        // Build analysis prompt
        let prompt = self.build_analysis_prompt(profile);

        // Call LLM
        let response = self
            .provider
            .complete(&prompt, self.config.max_tokens)
            .await?;

        // Parse response into UserPersona
        let persona = self.parse_persona_response(&response, profile)?;

        // Cache the result
        {
            let mut cache = self.persona_cache.write().await;
            cache.insert(profile.user_id, persona.clone());
        }

        Ok(persona)
    }

    /// Generate content recommendations based on persona
    pub async fn generate_recommendations(
        &self,
        persona: &UserPersona,
        available_topics: &[String],
        count: usize,
    ) -> Result<Vec<ContentRecommendation>> {
        let prompt = format!(
            r#"You are a content recommendation AI. Based on this user persona, recommend the most relevant content topics.

User Persona:
{}

Primary Interests: {}

Consumption Style: {}

Available Topics:
{}

Task: Select the top {} topics that would most engage this user. Return ONLY a JSON array of recommendations in this exact format:
[
  {{"topic": "topic_name", "relevance_score": 0.95, "reason": "brief reason"}},
  ...
]

Return ONLY valid JSON, no other text."#,
            persona.description,
            persona.primary_interests.join(", "),
            persona.consumption_patterns.engagement_style,
            available_topics.join("\n"),
            count
        );

        let response = self
            .provider
            .complete(&prompt, self.config.max_tokens)
            .await?;

        // Parse recommendations
        let recommendations: Vec<ContentRecommendation> =
            serde_json::from_str(&response).map_err(|e| {
                warn!(error = %e, response = %response, "Failed to parse recommendations");
                ProfileBuilderError::InvalidData(format!("Failed to parse recommendations: {}", e))
            })?;

        Ok(recommendations)
    }

    /// Generate user interest embedding for similarity matching
    pub async fn generate_interest_embedding(&self, profile: &UserProfile) -> Result<Vec<f32>> {
        // Create text representation of user interests
        let interest_text = profile
            .interests
            .iter()
            .map(|t| format!("{}: {:.2}", t.tag, t.weight))
            .collect::<Vec<_>>()
            .join(", ");

        self.provider.embed(&interest_text).await
    }

    /// Build the analysis prompt for LLM
    fn build_analysis_prompt(&self, profile: &UserProfile) -> String {
        let interests_str = profile
            .interests
            .iter()
            .take(20)
            .map(|t| format!("- {} (weight: {:.2})", t.tag, t.weight))
            .collect::<Vec<_>>()
            .join("\n");

        let behavior = &profile.behavior;
        let peak_hours = behavior
            .peak_hours
            .iter()
            .map(|h| format!("{}:00", h))
            .collect::<Vec<_>>()
            .join(", ");

        format!(
            r#"You are a user behavior analyst for a social media platform. Analyze this user's profile data and generate a comprehensive persona.

USER PROFILE DATA:

Interest Tags (with engagement weights):
{interests}

Behavior Patterns:
- Active Hours Bitmap: {active_hours:024b}
- Peak Activity Hours: {peak_hours}
- Average Session Length: {session_length:.1} minutes
- Preferred Video Length: {video_pref}
- Engagement Rate: {engagement_rate:.1}%

TASK: Generate a JSON response with the following structure:
{{
  "description": "A 2-3 sentence natural language description of this user's content consumption personality",
  "primary_interests": ["top 5 high-level interest categories"],
  "consumption_patterns": {{
    "preferred_length": "short/medium/long form content preference",
    "activity_pattern": "description of when and how often they use the platform",
    "engagement_style": "one of: passive_viewer, casual_liker, active_engager, social_sharer, deep_commenter",
    "discovery_preference": "how they find new content: trending, algorithmic, social, search"
  }},
  "predicted_preferences": {{
    "likely_interests": ["topics they would probably like but haven't engaged with yet"],
    "disliked_topics": ["topics to avoid based on skip/not-interested signals"],
    "optimal_delivery_hours": [array of 24h hour numbers when most receptive],
    "format_preferences": ["video", "image", "text", etc.]
  }},
  "segment": "one of: new_user, casual_viewer, regular_user, power_user, creator_consumer, niche_enthusiast, trend_follower, deep_diver",
  "confidence": 0.0-1.0 confidence in this analysis
}}

Return ONLY valid JSON, no other text."#,
            interests = interests_str,
            active_hours = behavior.active_hours_bitmap,
            peak_hours = peak_hours,
            session_length = behavior.avg_session_length / 60.0,
            video_pref = behavior.preferred_video_length.as_str(),
            engagement_rate = behavior.engagement_rate * 100.0,
        )
    }

    /// Parse LLM response into UserPersona
    fn parse_persona_response(&self, response: &str, profile: &UserProfile) -> Result<UserPersona> {
        // Try to extract JSON from response (handle markdown code blocks)
        let json_str = if response.contains("```json") {
            response
                .split("```json")
                .nth(1)
                .and_then(|s| s.split("```").next())
                .unwrap_or(response)
        } else if response.contains("```") {
            response.split("```").nth(1).unwrap_or(response)
        } else {
            response
        };

        #[derive(Deserialize)]
        struct LlmPersonaResponse {
            description: String,
            primary_interests: Vec<String>,
            consumption_patterns: ConsumptionPatterns,
            predicted_preferences: PredictedPreferences,
            segment: String,
            confidence: f32,
        }

        let parsed: LlmPersonaResponse = serde_json::from_str(json_str.trim()).map_err(|e| {
            error!(error = %e, response = %response, "Failed to parse LLM response");
            ProfileBuilderError::InvalidData(format!("Failed to parse LLM response: {}", e))
        })?;

        Ok(UserPersona {
            user_id: profile.user_id,
            description: parsed.description,
            primary_interests: parsed.primary_interests,
            consumption_patterns: parsed.consumption_patterns,
            predicted_preferences: parsed.predicted_preferences,
            segment: UserSegment::from_str(&parsed.segment),
            confidence: parsed.confidence,
            generated_at: Utc::now(),
            model_used: self.config.model.clone(),
        })
    }

    /// Clear persona cache for a user
    pub async fn invalidate_cache(&self, user_id: Uuid) {
        let mut cache = self.persona_cache.write().await;
        cache.remove(&user_id);
    }

    /// Clear all cached personas
    pub async fn clear_cache(&self) {
        let mut cache = self.persona_cache.write().await;
        cache.clear();
    }
}

// ============================================
// Supporting Types
// ============================================

/// Content recommendation from AI
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContentRecommendation {
    pub topic: String,
    pub relevance_score: f32,
    pub reason: String,
}

/// Extension trait for BehaviorPattern to get video length as string
trait VideoLengthExt {
    fn as_str(&self) -> &'static str;
}

impl VideoLengthExt for super::behavior_builder::VideoLengthPreference {
    fn as_str(&self) -> &'static str {
        match self {
            super::behavior_builder::VideoLengthPreference::VeryShort => "very_short (<15s)",
            super::behavior_builder::VideoLengthPreference::Short => "short (15-60s)",
            super::behavior_builder::VideoLengthPreference::Medium => "medium (1-3min)",
            super::behavior_builder::VideoLengthPreference::Long => "long (3-10min)",
            super::behavior_builder::VideoLengthPreference::VeryLong => "very_long (>10min)",
            super::behavior_builder::VideoLengthPreference::Mixed => "mixed (no clear preference)",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_user_segment_conversion() {
        assert!(matches!(
            UserSegment::from_str("power_user"),
            UserSegment::PowerUser
        ));
        assert!(matches!(
            UserSegment::from_str("CASUAL_VIEWER"),
            UserSegment::CasualViewer
        ));
        assert_eq!(UserSegment::DeepDiver.as_str(), "deep_diver");
    }
}
