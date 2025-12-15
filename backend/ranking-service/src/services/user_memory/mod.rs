// ============================================
// User Memory System (用戶記憶系統)
// ============================================
//
// 一個深度理解用戶的記憶系統，結合 LLM 實現：
// 1. 多層記憶架構 - 短期/長期/語義記憶
// 2. 興趣探索 - 主動發現用戶潛在興趣
// 3. 行為預測 - 預測用戶下一步需求
// 4. 投其所好 - 精準個性化推薦
//
// 架構圖:
// ┌─────────────────────────────────────────────────────────────┐
// │                   User Memory System                        │
// ├─────────────────────────────────────────────────────────────┤
// │                                                              │
// │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
// │  │ Short-Term  │  │ Long-Term   │  │  Semantic   │         │
// │  │   Memory    │  │   Memory    │  │   Memory    │         │
// │  │ (Session級) │  │ (持久化)   │  │ (LLM總結)  │         │
// │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘         │
// │         │                │                │                 │
// │         └────────────────┼────────────────┘                 │
// │                          ↓                                   │
// │              ┌───────────────────────┐                      │
// │              │   Memory Consolidator │ ← 記憶整合器         │
// │              └───────────┬───────────┘                      │
// │                          ↓                                   │
// │  ┌───────────────────────────────────────────────────────┐  │
// │  │                Interest Explorer                       │  │
// │  │  • 興趣邊界探索 (Exploration)                         │  │
// │  │  • 潛在興趣預測 (Latent Interest)                     │  │
// │  │  • 興趣演化追蹤 (Interest Evolution)                  │  │
// │  └───────────────────────┬───────────────────────────────┘  │
// │                          ↓                                   │
// │  ┌───────────────────────────────────────────────────────┐  │
// │  │              Insight Generator (LLM)                   │  │
// │  │  • 用戶人設生成                                        │  │
// │  │  • 深度興趣分析                                        │  │
// │  │  • 行為模式識別                                        │  │
// │  └───────────────────────┬───────────────────────────────┘  │
// │                          ↓                                   │
// │  ┌───────────────────────────────────────────────────────┐  │
// │  │              Predictive Engine                         │  │
// │  │  • 下一個興趣預測                                      │  │
// │  │  • 最佳推送時機                                        │  │
// │  │  • 內容偏好預測                                        │  │
// │  └───────────────────────────────────────────────────────┘  │
// │                                                              │
// └─────────────────────────────────────────────────────────────┘

pub mod insight_generator;
pub mod interest_explorer;
pub mod memory_store;
pub mod predictive_engine;

pub use insight_generator::{InsightGenerator, UserInsight};
pub use interest_explorer::{InterestExplorer, ExplorationResult, LatentInterest};
pub use memory_store::{
    MemoryStore, ShortTermMemory, LongTermMemory, SemanticMemory,
    MemoryEvent, MemoryConfig,
};
pub use predictive_engine::{PredictiveEngine, Prediction, PredictionType};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;
use uuid::Uuid;

use super::profile_builder::LlmProfileAnalyzer;

/// 用戶記憶系統 - 整合所有記憶和預測能力
pub struct UserMemorySystem {
    /// 記憶存儲
    memory_store: Arc<MemoryStore>,
    /// 興趣探索器
    interest_explorer: Arc<InterestExplorer>,
    /// LLM 洞察生成器
    insight_generator: Arc<InsightGenerator>,
    /// 預測引擎
    predictive_engine: Arc<PredictiveEngine>,
}

impl UserMemorySystem {
    /// 創建新的用戶記憶系統
    pub fn new(
        redis: redis::Client,
        llm_analyzer: Option<Arc<LlmProfileAnalyzer>>,
        config: MemorySystemConfig,
    ) -> Self {
        let memory_store = Arc::new(MemoryStore::new(redis, config.memory.clone()));
        let interest_explorer = Arc::new(InterestExplorer::new(config.exploration.clone()));
        let insight_generator = Arc::new(InsightGenerator::new(llm_analyzer.clone()));
        let predictive_engine = Arc::new(PredictiveEngine::new(
            memory_store.clone(),
            llm_analyzer,
            config.prediction.clone(),
        ));

        Self {
            memory_store,
            interest_explorer,
            insight_generator,
            predictive_engine,
        }
    }

    /// 記錄用戶事件 - 更新所有相關記憶
    pub async fn record_event(&self, event: UserEvent) -> Result<(), MemoryError> {
        let user_id = event.user_id;

        // 1. 更新短期記憶
        self.memory_store.add_to_short_term(user_id, &event).await?;

        // 2. 評估是否需要更新長期記憶
        if self.should_consolidate(&event) {
            self.memory_store.consolidate_to_long_term(user_id).await?;
        }

        // 3. 更新興趣探索器
        self.interest_explorer.update_from_event(&event).await;

        // 4. 觸發預測更新 (非同步)
        let predictive = self.predictive_engine.clone();
        tokio::spawn(async move {
            let _ = predictive.update_predictions(user_id).await;
        });

        Ok(())
    }

    /// 獲取用戶的完整記憶視圖
    pub async fn get_user_memory(&self, user_id: Uuid) -> Result<UserMemoryView, MemoryError> {
        let short_term = self.memory_store.get_short_term(user_id).await?;

        // 長期記憶可能不存在 (新用戶)
        let long_term = self.memory_store.get_long_term(user_id).await
            .map_err(|e| e.to_string());

        let semantic = self.memory_store.get_semantic(user_id).await?;

        Ok(UserMemoryView {
            user_id,
            short_term,
            long_term,
            semantic,
            retrieved_at: Utc::now(),
        })
    }

    /// 探索用戶潛在興趣
    pub async fn explore_interests(&self, user_id: Uuid) -> Result<Vec<LatentInterest>, MemoryError> {
        let memory = self.get_user_memory(user_id).await?;
        let exploration = self.interest_explorer.explore(&memory).await?;
        Ok(exploration.latent_interests)
    }

    /// 生成用戶洞察 (使用 LLM)
    pub async fn generate_insight(&self, user_id: Uuid) -> Result<UserInsight, MemoryError> {
        let memory = self.get_user_memory(user_id).await?;
        self.insight_generator.generate(&memory).await
    }

    /// 預測用戶下一步需求
    pub async fn predict_next(&self, user_id: Uuid) -> Result<Vec<Prediction>, MemoryError> {
        self.predictive_engine.predict(user_id).await
    }

    /// 獲取個性化推薦建議
    pub async fn get_personalized_suggestions(
        &self,
        user_id: Uuid,
        context: RecommendationContext,
    ) -> Result<PersonalizedSuggestions, MemoryError> {
        // 1. 獲取記憶
        let memory = self.get_user_memory(user_id).await?;

        // 2. 獲取預測
        let predictions = self.predict_next(user_id).await?;

        // 3. 獲取探索建議
        let explorations = self.explore_interests(user_id).await?;

        // 4. 生成洞察
        let insight = self.generate_insight(user_id).await.ok();

        // 5. 整合所有信息生成建議
        Ok(PersonalizedSuggestions {
            user_id,
            // 主要推薦 (基於預測)
            primary_recommendations: predictions
                .iter()
                .filter(|p| p.confidence > 0.7)
                .map(|p| p.content_hint.clone())
                .collect(),
            // 探索推薦 (發現新興趣)
            exploration_recommendations: explorations
                .iter()
                .take(3)
                .map(|e| e.topic.clone())
                .collect(),
            // 推薦理由
            reasoning: insight.map(|i| i.recommendation_reasoning),
            // 最佳推送時機
            optimal_time: predictions
                .iter()
                .find(|p| matches!(p.prediction_type, PredictionType::OptimalTime))
                .map(|p| p.content_hint.clone()),
            // 上下文
            context,
            generated_at: Utc::now(),
        })
    }

    /// 判斷是否應該整合記憶
    fn should_consolidate(&self, event: &UserEvent) -> bool {
        // 重要事件立即整合
        matches!(
            event.event_type,
            EventType::Purchase | EventType::Subscribe | EventType::LongWatch
        )
    }
}

// ============================================
// 核心類型定義
// ============================================

/// 記憶系統配置
#[derive(Debug, Clone)]
pub struct MemorySystemConfig {
    pub memory: MemoryConfig,
    pub exploration: ExplorationConfig,
    pub prediction: PredictionConfig,
}

impl Default for MemorySystemConfig {
    fn default() -> Self {
        Self {
            memory: MemoryConfig::default(),
            exploration: ExplorationConfig::default(),
            prediction: PredictionConfig::default(),
        }
    }
}

/// 探索配置
#[derive(Debug, Clone)]
pub struct ExplorationConfig {
    /// 探索比例 (0.0 - 1.0)
    pub exploration_ratio: f32,
    /// 最大探索興趣數
    pub max_latent_interests: usize,
    /// 興趣相似度閾值
    pub similarity_threshold: f32,
}

impl Default for ExplorationConfig {
    fn default() -> Self {
        Self {
            exploration_ratio: 0.15,
            max_latent_interests: 10,
            similarity_threshold: 0.6,
        }
    }
}

/// 預測配置
#[derive(Debug, Clone)]
pub struct PredictionConfig {
    /// 預測時間範圍 (小時)
    pub prediction_horizon_hours: u32,
    /// 最小置信度
    pub min_confidence: f32,
    /// 是否使用 LLM 增強
    pub use_llm_enhancement: bool,
}

impl Default for PredictionConfig {
    fn default() -> Self {
        Self {
            prediction_horizon_hours: 24,
            min_confidence: 0.5,
            use_llm_enhancement: true,
        }
    }
}

/// 用戶事件
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserEvent {
    pub user_id: Uuid,
    pub event_type: EventType,
    pub content_id: Option<Uuid>,
    pub content_tags: Vec<String>,
    pub duration_ms: Option<u64>,
    pub completion_rate: Option<f32>,
    pub timestamp: DateTime<Utc>,
    pub context: EventContext,
}

/// 事件類型
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum EventType {
    /// 瀏覽
    View,
    /// 完整觀看
    LongWatch,
    /// 點讚
    Like,
    /// 評論
    Comment,
    /// 分享
    Share,
    /// 收藏
    Save,
    /// 跳過
    Skip,
    /// 不感興趣
    NotInterested,
    /// 搜索
    Search,
    /// 關注
    Follow,
    /// 購買
    Purchase,
    /// 訂閱
    Subscribe,
}

/// 事件上下文
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventContext {
    pub session_id: String,
    pub device_type: String,
    pub location: Option<String>,
    pub referrer: Option<String>,
    pub hour_of_day: u8,
    pub day_of_week: u8,
}

/// 用戶記憶視圖
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserMemoryView {
    pub user_id: Uuid,
    pub short_term: ShortTermMemory,
    /// 長期記憶 (新用戶可能沒有)
    pub long_term: Result<LongTermMemory, String>,
    pub semantic: Option<SemanticMemory>,
    pub retrieved_at: DateTime<Utc>,
}

/// 推薦上下文
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecommendationContext {
    pub session_id: String,
    pub current_time: DateTime<Utc>,
    pub device_type: String,
    pub available_content_count: usize,
}

/// 個性化建議
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PersonalizedSuggestions {
    pub user_id: Uuid,
    /// 主要推薦內容提示
    pub primary_recommendations: Vec<String>,
    /// 探索性推薦
    pub exploration_recommendations: Vec<String>,
    /// 推薦理由
    pub reasoning: Option<String>,
    /// 最佳推送時機
    pub optimal_time: Option<String>,
    /// 上下文
    pub context: RecommendationContext,
    /// 生成時間
    pub generated_at: DateTime<Utc>,
}

/// 記憶系統錯誤
#[derive(Debug, thiserror::Error)]
pub enum MemoryError {
    #[error("Redis error: {0}")]
    Redis(String),
    #[error("Serialization error: {0}")]
    Serialization(String),
    #[error("LLM error: {0}")]
    Llm(String),
    #[error("Not found: {0}")]
    NotFound(String),
}

impl From<redis::RedisError> for MemoryError {
    fn from(e: redis::RedisError) -> Self {
        MemoryError::Redis(e.to_string())
    }
}
