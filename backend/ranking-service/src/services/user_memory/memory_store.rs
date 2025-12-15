// ============================================
// Memory Store (記憶存儲)
// ============================================
//
// 三層記憶架構:
// 1. Short-Term Memory (短期記憶) - Session 級別，快速訪問
// 2. Long-Term Memory (長期記憶) - 持久化，重要模式
// 3. Semantic Memory (語義記憶) - LLM 總結的高層理解

use super::{MemoryError, UserEvent, EventType};
use chrono::{DateTime, Duration, Timelike, Utc};
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tracing::{debug, info, warn};
use uuid::Uuid;

/// 記憶配置
#[derive(Debug, Clone)]
pub struct MemoryConfig {
    /// 短期記憶保留時間 (秒)
    pub short_term_ttl_secs: u64,
    /// 短期記憶最大事件數
    pub short_term_max_events: usize,
    /// 長期記憶保留時間 (天)
    pub long_term_ttl_days: u32,
    /// 整合閾值 (多少事件觸發整合)
    pub consolidation_threshold: usize,
    /// 語義記憶更新間隔 (小時)
    pub semantic_update_interval_hours: u32,
}

impl Default for MemoryConfig {
    fn default() -> Self {
        Self {
            short_term_ttl_secs: 1800, // 30 分鐘
            short_term_max_events: 100,
            long_term_ttl_days: 90,
            consolidation_threshold: 20,
            semantic_update_interval_hours: 24,
        }
    }
}

/// 記憶存儲
pub struct MemoryStore {
    redis: redis::Client,
    config: MemoryConfig,
}

impl MemoryStore {
    pub fn new(redis: redis::Client, config: MemoryConfig) -> Self {
        Self { redis, config }
    }

    // ============================================
    // 短期記憶 (Short-Term Memory)
    // ============================================

    /// 添加事件到短期記憶
    pub async fn add_to_short_term(&self, user_id: Uuid, event: &UserEvent) -> Result<(), MemoryError> {
        let mut conn = self.redis.get_multiplexed_async_connection().await?;
        let key = self.short_term_key(user_id);

        // 創建記憶事件
        let memory_event = MemoryEvent::from_user_event(event);
        let event_json = serde_json::to_string(&memory_event)
            .map_err(|e| MemoryError::Serialization(e.to_string()))?;

        // 添加到列表頭部
        let _: () = conn.lpush(&key, &event_json).await?;

        // 限制列表長度
        let _: () = conn.ltrim(&key, 0, self.config.short_term_max_events as isize - 1).await?;

        // 設置 TTL
        let _: () = conn.expire(&key, self.config.short_term_ttl_secs as i64).await?;

        debug!(user_id = %user_id, event_type = ?event.event_type, "Added to short-term memory");
        Ok(())
    }

    /// 獲取短期記憶
    pub async fn get_short_term(&self, user_id: Uuid) -> Result<ShortTermMemory, MemoryError> {
        let mut conn = self.redis.get_multiplexed_async_connection().await?;
        let key = self.short_term_key(user_id);

        let events_json: Vec<String> = conn.lrange(&key, 0, -1).await?;

        let events: Vec<MemoryEvent> = events_json
            .iter()
            .filter_map(|json| serde_json::from_str(json).ok())
            .collect();

        // 計算即時興趣
        let instant_interests = self.compute_instant_interests(&events);

        // 計算活躍度
        let activity_level = self.compute_activity_level(&events);

        // 當前 Session 信息
        let current_session = events.first().map(|e| e.session_id.clone());

        Ok(ShortTermMemory {
            user_id,
            events,
            instant_interests,
            activity_level,
            current_session,
            last_updated: Utc::now(),
        })
    }

    // ============================================
    // 長期記憶 (Long-Term Memory)
    // ============================================

    /// 整合短期記憶到長期記憶
    pub async fn consolidate_to_long_term(&self, user_id: Uuid) -> Result<(), MemoryError> {
        let short_term = self.get_short_term(user_id).await?;
        let mut long_term = self.get_long_term(user_id).await.unwrap_or_else(|_| {
            LongTermMemory::new(user_id)
        });

        // 整合興趣
        for (tag, weight) in &short_term.instant_interests {
            long_term.update_interest(tag, *weight);
        }

        // 更新行為模式
        long_term.update_behavior_patterns(&short_term.events);

        // 更新統計
        long_term.total_interactions += short_term.events.len() as u64;
        long_term.last_consolidated = Utc::now();

        // 保存
        self.save_long_term(&long_term).await?;

        info!(user_id = %user_id, "Consolidated short-term to long-term memory");
        Ok(())
    }

    /// 獲取長期記憶
    pub async fn get_long_term(&self, user_id: Uuid) -> Result<LongTermMemory, MemoryError> {
        let mut conn = self.redis.get_multiplexed_async_connection().await?;
        let key = self.long_term_key(user_id);

        let json: Option<String> = conn.get(&key).await?;

        match json {
            Some(data) => serde_json::from_str(&data)
                .map_err(|e| MemoryError::Serialization(e.to_string())),
            None => Err(MemoryError::NotFound(format!("Long-term memory not found for user {}", user_id))),
        }
    }

    /// 保存長期記憶
    async fn save_long_term(&self, memory: &LongTermMemory) -> Result<(), MemoryError> {
        let mut conn = self.redis.get_multiplexed_async_connection().await?;
        let key = self.long_term_key(memory.user_id);

        let json = serde_json::to_string(memory)
            .map_err(|e| MemoryError::Serialization(e.to_string()))?;

        let ttl_secs = self.config.long_term_ttl_days as i64 * 86400;
        let _: () = conn.set_ex(&key, &json, ttl_secs as u64).await?;

        Ok(())
    }

    // ============================================
    // 語義記憶 (Semantic Memory)
    // ============================================

    /// 獲取語義記憶
    pub async fn get_semantic(&self, user_id: Uuid) -> Result<Option<SemanticMemory>, MemoryError> {
        let mut conn = self.redis.get_multiplexed_async_connection().await?;
        let key = self.semantic_key(user_id);

        let json: Option<String> = conn.get(&key).await?;

        match json {
            Some(data) => {
                let memory: SemanticMemory = serde_json::from_str(&data)
                    .map_err(|e| MemoryError::Serialization(e.to_string()))?;
                Ok(Some(memory))
            }
            None => Ok(None),
        }
    }

    /// 保存語義記憶 (由 LLM 生成)
    pub async fn save_semantic(&self, memory: &SemanticMemory) -> Result<(), MemoryError> {
        let mut conn = self.redis.get_multiplexed_async_connection().await?;
        let key = self.semantic_key(memory.user_id);

        let json = serde_json::to_string(memory)
            .map_err(|e| MemoryError::Serialization(e.to_string()))?;

        let ttl_secs = self.config.long_term_ttl_days as i64 * 86400;
        let _: () = conn.set_ex(&key, &json, ttl_secs as u64).await?;

        Ok(())
    }

    // ============================================
    // 輔助方法
    // ============================================

    fn short_term_key(&self, user_id: Uuid) -> String {
        format!("mem:st:{}", user_id)
    }

    fn long_term_key(&self, user_id: Uuid) -> String {
        format!("mem:lt:{}", user_id)
    }

    fn semantic_key(&self, user_id: Uuid) -> String {
        format!("mem:sem:{}", user_id)
    }

    /// 計算即時興趣
    fn compute_instant_interests(&self, events: &[MemoryEvent]) -> HashMap<String, f32> {
        let mut interests: HashMap<String, f32> = HashMap::new();
        let now = Utc::now();

        for event in events {
            // 時間衰減 (指數衰減)
            let age_minutes = (now - event.timestamp).num_minutes() as f32;
            let decay = (-age_minutes / 30.0).exp(); // 30分鐘半衰期

            // 事件權重
            let event_weight = event.weight();

            // 更新興趣
            for tag in &event.tags {
                *interests.entry(tag.clone()).or_insert(0.0) += event_weight * decay;
            }
        }

        // 歸一化
        let max_weight = interests.values().cloned().fold(0.0f32, f32::max);
        if max_weight > 0.0 {
            for weight in interests.values_mut() {
                *weight /= max_weight;
            }
        }

        interests
    }

    /// 計算活躍度
    fn compute_activity_level(&self, events: &[MemoryEvent]) -> ActivityLevel {
        let event_count = events.len();
        let now = Utc::now();

        // 最近 5 分鐘的事件數
        let recent_count = events
            .iter()
            .filter(|e| (now - e.timestamp).num_minutes() < 5)
            .count();

        if recent_count > 10 {
            ActivityLevel::VeryActive
        } else if recent_count > 5 {
            ActivityLevel::Active
        } else if event_count > 0 {
            ActivityLevel::Normal
        } else {
            ActivityLevel::Idle
        }
    }
}

// ============================================
// 記憶類型定義
// ============================================

/// 記憶事件 (標準化的事件格式)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryEvent {
    pub event_id: String,
    pub event_type: String,
    pub content_id: Option<Uuid>,
    pub tags: Vec<String>,
    pub engagement_score: f32,
    pub session_id: String,
    pub timestamp: DateTime<Utc>,
}

impl MemoryEvent {
    pub fn from_user_event(event: &UserEvent) -> Self {
        let engagement_score = match event.event_type {
            EventType::Purchase | EventType::Subscribe => 1.0,
            EventType::LongWatch => 0.9,
            EventType::Share => 0.8,
            EventType::Comment => 0.7,
            EventType::Save => 0.6,
            EventType::Like => 0.5,
            EventType::Follow => 0.5,
            EventType::View => 0.3,
            EventType::Search => 0.4,
            EventType::Skip => 0.1,
            EventType::NotInterested => 0.0,
        };

        Self {
            event_id: Uuid::new_v4().to_string(),
            event_type: format!("{:?}", event.event_type),
            content_id: event.content_id,
            tags: event.content_tags.clone(),
            engagement_score,
            session_id: event.context.session_id.clone(),
            timestamp: event.timestamp,
        }
    }

    /// 獲取事件權重
    pub fn weight(&self) -> f32 {
        self.engagement_score
    }
}

/// 短期記憶
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ShortTermMemory {
    pub user_id: Uuid,
    /// 最近的事件序列
    pub events: Vec<MemoryEvent>,
    /// 即時興趣 (tag -> weight)
    pub instant_interests: HashMap<String, f32>,
    /// 當前活躍度
    pub activity_level: ActivityLevel,
    /// 當前 Session ID
    pub current_session: Option<String>,
    /// 最後更新時間
    pub last_updated: DateTime<Utc>,
}

/// 活躍度級別
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ActivityLevel {
    Idle,
    Normal,
    Active,
    VeryActive,
}

/// 長期記憶
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LongTermMemory {
    pub user_id: Uuid,

    /// 穩定興趣 (tag -> interest info)
    pub stable_interests: HashMap<String, InterestInfo>,

    /// 行為模式
    pub behavior_patterns: BehaviorPatterns,

    /// 內容偏好
    pub content_preferences: ContentPreferences,

    /// 總互動次數
    pub total_interactions: u64,

    /// 創建時間
    pub created_at: DateTime<Utc>,

    /// 最後整合時間
    pub last_consolidated: DateTime<Utc>,
}

impl LongTermMemory {
    pub fn new(user_id: Uuid) -> Self {
        let now = Utc::now();
        Self {
            user_id,
            stable_interests: HashMap::new(),
            behavior_patterns: BehaviorPatterns::default(),
            content_preferences: ContentPreferences::default(),
            total_interactions: 0,
            created_at: now,
            last_consolidated: now,
        }
    }

    /// 更新興趣
    pub fn update_interest(&mut self, tag: &str, weight: f32) {
        let info = self.stable_interests
            .entry(tag.to_string())
            .or_insert_with(|| InterestInfo::new(tag));

        // 指數移動平均更新
        let alpha = 0.3;
        info.weight = info.weight * (1.0 - alpha) + weight * alpha;
        info.interaction_count += 1;
        info.last_interaction = Utc::now();

        // 更新趨勢
        info.update_trend(weight);
    }

    /// 更新行為模式
    pub fn update_behavior_patterns(&mut self, events: &[MemoryEvent]) {
        for event in events {
            let hour = event.timestamp.hour() as u8;
            self.behavior_patterns.active_hours[hour as usize] += 1;
        }
    }
}

/// 興趣信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InterestInfo {
    pub tag: String,
    pub weight: f32,
    pub interaction_count: u64,
    pub last_interaction: DateTime<Utc>,
    /// 興趣趨勢: 上升/下降/穩定
    pub trend: InterestTrend,
    /// 歷史權重 (用於趨勢計算)
    pub weight_history: Vec<f32>,
}

impl InterestInfo {
    pub fn new(tag: &str) -> Self {
        Self {
            tag: tag.to_string(),
            weight: 0.0,
            interaction_count: 0,
            last_interaction: Utc::now(),
            trend: InterestTrend::Stable,
            weight_history: Vec::new(),
        }
    }

    pub fn update_trend(&mut self, new_weight: f32) {
        self.weight_history.push(new_weight);
        if self.weight_history.len() > 10 {
            self.weight_history.remove(0);
        }

        if self.weight_history.len() >= 3 {
            let recent_avg: f32 = self.weight_history.iter().rev().take(3).sum::<f32>() / 3.0;
            let older_avg: f32 = self.weight_history.iter().take(3).sum::<f32>() / 3.0;

            self.trend = if recent_avg > older_avg * 1.2 {
                InterestTrend::Rising
            } else if recent_avg < older_avg * 0.8 {
                InterestTrend::Declining
            } else {
                InterestTrend::Stable
            };
        }
    }
}

/// 興趣趨勢
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum InterestTrend {
    Rising,
    Stable,
    Declining,
}

/// 行為模式
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BehaviorPatterns {
    /// 每小時活躍度 (24 小時)
    pub active_hours: [u32; 24],
    /// 每週活躍度 (7 天)
    pub active_days: [u32; 7],
    /// 平均 Session 時長 (秒)
    pub avg_session_duration: f64,
    /// 平均每日互動數
    pub avg_daily_interactions: f64,
}

impl Default for BehaviorPatterns {
    fn default() -> Self {
        Self {
            active_hours: [0; 24],
            active_days: [0; 7],
            avg_session_duration: 0.0,
            avg_daily_interactions: 0.0,
        }
    }
}

/// 內容偏好
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContentPreferences {
    /// 偏好內容長度 (秒)
    pub preferred_duration_range: (u32, u32),
    /// 偏好內容類型
    pub preferred_content_types: Vec<String>,
    /// 厭惡的標籤
    pub disliked_tags: Vec<String>,
    /// 完播率閾值
    pub completion_threshold: f32,
}

impl Default for ContentPreferences {
    fn default() -> Self {
        Self {
            preferred_duration_range: (15, 60),
            preferred_content_types: vec!["video".to_string()],
            disliked_tags: Vec::new(),
            completion_threshold: 0.7,
        }
    }
}

/// 語義記憶 (LLM 生成的高層理解)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SemanticMemory {
    pub user_id: Uuid,

    /// 用戶人設描述
    pub persona_description: String,

    /// 核心興趣主題
    pub core_interests: Vec<String>,

    /// 潛在興趣 (尚未明確但可能感興趣)
    pub latent_interests: Vec<String>,

    /// 內容消費風格
    pub consumption_style: String,

    /// 決策模式
    pub decision_pattern: String,

    /// 推薦策略建議
    pub recommendation_strategy: String,

    /// LLM 模型
    pub model_used: String,

    /// 生成時間
    pub generated_at: DateTime<Utc>,

    /// 基於的數據量
    pub based_on_interactions: u64,
}

impl SemanticMemory {
    pub fn new(user_id: Uuid) -> Self {
        Self {
            user_id,
            persona_description: String::new(),
            core_interests: Vec::new(),
            latent_interests: Vec::new(),
            consumption_style: String::new(),
            decision_pattern: String::new(),
            recommendation_strategy: String::new(),
            model_used: String::new(),
            generated_at: Utc::now(),
            based_on_interactions: 0,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_memory_event_weight() {
        // Test engagement scores
        assert!(MemoryEvent {
            event_id: "1".to_string(),
            event_type: "Purchase".to_string(),
            content_id: None,
            tags: vec![],
            engagement_score: 1.0,
            session_id: "s1".to_string(),
            timestamp: Utc::now(),
        }.weight() == 1.0);
    }
}
