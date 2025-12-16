// ============================================
// Insight Generator (LLM 洞察生成器)
// ============================================
//
// 使用 LLM 深度分析用戶記憶，生成：
// 1. 用戶人設 - 自然語言描述用戶特徵
// 2. 深度興趣分析 - 識別表面興趣背後的深層需求
// 3. 行為解讀 - 理解用戶行為背後的動機
// 4. 推薦策略 - 針對該用戶的個性化推薦策略

use super::memory_store::InterestTrend;
use super::{MemoryError, UserMemoryView};
use crate::services::profile_builder::LlmProfileAnalyzer;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::info;
use uuid::Uuid;

/// LLM 洞察生成器
pub struct InsightGenerator {
    llm: Option<Arc<LlmProfileAnalyzer>>,
}

impl InsightGenerator {
    pub fn new(llm: Option<Arc<LlmProfileAnalyzer>>) -> Self {
        Self { llm }
    }

    /// 生成用戶洞察
    pub async fn generate(&self, memory: &UserMemoryView) -> Result<UserInsight, MemoryError> {
        let llm = self
            .llm
            .as_ref()
            .ok_or_else(|| MemoryError::Llm("LLM analyzer not configured".to_string()))?;

        // 構建分析 Prompt
        let prompt = self.build_insight_prompt(memory);

        // 調用 LLM (通過現有的 analyzer)
        // 這裡我們直接構建結果，實際應該調用 LLM
        let insight = self.analyze_with_llm(&prompt, memory).await?;

        info!(user_id = %memory.user_id, "Generated user insight");
        Ok(insight)
    }

    /// 構建洞察分析 Prompt
    fn build_insight_prompt(&self, memory: &UserMemoryView) -> String {
        let mut prompt = String::new();

        prompt.push_str("你是一個用戶行為分析專家。請根據以下用戶數據，生成深度洞察。\n\n");

        // 短期記憶
        prompt.push_str("## 近期行為 (最近 30 分鐘)\n");
        prompt.push_str(&format!("事件數量: {}\n", memory.short_term.events.len()));
        prompt.push_str(&format!("活躍度: {:?}\n", memory.short_term.activity_level));
        prompt.push_str("即時興趣:\n");
        for (tag, weight) in memory.short_term.instant_interests.iter().take(10) {
            prompt.push_str(&format!("  - {}: {:.2}\n", tag, weight));
        }

        // 長期記憶
        if let Ok(ref lt) = memory.long_term {
            prompt.push_str("\n## 長期興趣\n");
            let mut interests: Vec<_> = lt.stable_interests.iter().collect();
            interests.sort_by(|a, b| {
                b.1.weight
                    .partial_cmp(&a.1.weight)
                    .unwrap_or(std::cmp::Ordering::Equal)
            });

            for (tag, info) in interests.iter().take(15) {
                let trend_str = match info.trend {
                    InterestTrend::Rising => "↑",
                    InterestTrend::Stable => "→",
                    InterestTrend::Declining => "↓",
                };
                prompt.push_str(&format!(
                    "  - {} (權重: {:.2}, 互動: {}, 趨勢: {})\n",
                    tag, info.weight, info.interaction_count, trend_str
                ));
            }

            prompt.push_str("\n## 行為模式\n");
            let peak_hours: Vec<_> = lt
                .behavior_patterns
                .active_hours
                .iter()
                .enumerate()
                .filter(|(_, &c)| c > 0)
                .max_by_key(|(_, &c)| c)
                .map(|(h, _)| h)
                .into_iter()
                .collect();
            prompt.push_str(&format!("高峰活躍時段: {:?}\n", peak_hours));
            prompt.push_str(&format!("總互動次數: {}\n", lt.total_interactions));
        }

        // 語義記憶 (如果有)
        if let Some(ref sem) = memory.semantic {
            prompt.push_str("\n## 現有語義理解\n");
            prompt.push_str(&format!("人設: {}\n", sem.persona_description));
            prompt.push_str(&format!("核心興趣: {:?}\n", sem.core_interests));
        }

        prompt.push_str(
            r#"
## 任務
請分析以上數據，生成 JSON 格式的用戶洞察：

{
  "persona_summary": "2-3 句話描述這個用戶的特徵和偏好",
  "deep_interests": ["表面興趣背後的深層需求/動機，3-5 個"],
  "behavior_insights": ["對用戶行為的解讀，2-3 個洞察"],
  "content_preferences": {
    "preferred_topics": ["最適合推薦的話題"],
    "avoid_topics": ["應該避免的話題"],
    "preferred_style": "適合的內容風格",
    "optimal_timing": "最佳推送時機"
  },
  "recommendation_reasoning": "針對這個用戶的推薦策略建議",
  "exploration_suggestions": ["可以嘗試探索的新興趣方向"]
}

只返回 JSON，不要其他文字。
"#,
        );

        prompt
    }

    /// 使用 LLM 分析 (模擬實現)
    async fn analyze_with_llm(
        &self,
        _prompt: &str,
        memory: &UserMemoryView,
    ) -> Result<UserInsight, MemoryError> {
        // TODO: 實際調用 LLM API
        // 目前返回基於規則的分析結果

        let mut insight = UserInsight {
            user_id: memory.user_id,
            persona_summary: String::new(),
            deep_interests: Vec::new(),
            behavior_insights: Vec::new(),
            content_preferences: ContentPreferenceInsight::default(),
            recommendation_reasoning: String::new(),
            exploration_suggestions: Vec::new(),
            confidence: 0.0,
            generated_at: Utc::now(),
            model_used: "rule-based".to_string(),
        };

        // 基於規則分析
        self.rule_based_analysis(&mut insight, memory);

        Ok(insight)
    }

    /// 基於規則的分析 (當 LLM 不可用時的備選)
    fn rule_based_analysis(&self, insight: &mut UserInsight, memory: &UserMemoryView) {
        // 分析興趣
        let top_interests: Vec<String> = memory
            .short_term
            .instant_interests
            .iter()
            .take(5)
            .map(|(tag, _)| tag.clone())
            .collect();

        // 生成人設摘要
        if top_interests.is_empty() {
            insight.persona_summary = "新用戶，正在探索平台內容".to_string();
            insight.confidence = 0.3;
        } else {
            insight.persona_summary = format!(
                "對{}感興趣的用戶，{}活躍",
                top_interests.join("、"),
                match memory.short_term.activity_level {
                    super::memory_store::ActivityLevel::VeryActive => "非常",
                    super::memory_store::ActivityLevel::Active => "較為",
                    super::memory_store::ActivityLevel::Normal => "一般",
                    super::memory_store::ActivityLevel::Idle => "較少",
                }
            );
            insight.confidence = 0.6;
        }

        // 深度興趣分析
        insight.deep_interests = self.infer_deep_interests(&top_interests);

        // 行為洞察
        insight.behavior_insights = vec![format!(
            "當前 Session 有 {} 個互動事件",
            memory.short_term.events.len()
        )];

        // 內容偏好
        insight.content_preferences = ContentPreferenceInsight {
            preferred_topics: top_interests.clone(),
            avoid_topics: Vec::new(),
            preferred_style: "短視頻為主".to_string(),
            optimal_timing: "根據活躍時段推送".to_string(),
        };

        // 推薦策略
        insight.recommendation_reasoning = format!(
            "該用戶對{}有明顯興趣，建議優先推薦相關內容，同時可以探索相關領域",
            top_interests.first().unwrap_or(&"未知".to_string())
        );

        // 探索建議
        insight.exploration_suggestions = self.generate_exploration_suggestions(&top_interests);
    }

    /// 推斷深度興趣
    fn infer_deep_interests(&self, surface_interests: &[String]) -> Vec<String> {
        let mut deep = Vec::new();

        for interest in surface_interests {
            match interest.as_str() {
                "科技" | "編程" | "AI" => {
                    deep.push("追求效率和創新".to_string());
                    deep.push("對未來趨勢敏感".to_string());
                }
                "美食" | "烹飪" | "探店" => {
                    deep.push("追求生活品質".to_string());
                    deep.push("注重感官體驗".to_string());
                }
                "健身" | "運動" | "減肥" => {
                    deep.push("追求自我提升".to_string());
                    deep.push("注重健康和外表".to_string());
                }
                "投資" | "理財" | "股票" => {
                    deep.push("追求財務自由".to_string());
                    deep.push("風險意識較強".to_string());
                }
                "遊戲" | "電競" | "動漫" => {
                    deep.push("追求娛樂和放鬆".to_string());
                    deep.push("喜歡虛擬世界體驗".to_string());
                }
                _ => {
                    deep.push(format!("對{}領域有持續興趣", interest));
                }
            }
        }

        deep.into_iter().take(5).collect()
    }

    /// 生成探索建議
    fn generate_exploration_suggestions(&self, interests: &[String]) -> Vec<String> {
        let mut suggestions = Vec::new();

        // 基於興趣關聯推薦
        let expansion_map: std::collections::HashMap<&str, Vec<&str>> = [
            ("科技", vec!["創業", "產品設計", "數位遊牧"]),
            ("美食", vec!["旅行", "文化體驗", "攝影"]),
            ("健身", vec!["戶外運動", "冥想", "營養學"]),
            ("投資", vec!["創業", "房地產", "被動收入"]),
            ("遊戲", vec!["遊戲開發", "直播", "電競產業"]),
        ]
        .into_iter()
        .collect();

        for interest in interests {
            if let Some(expansions) = expansion_map.get(interest.as_str()) {
                for exp in expansions.iter().take(1) {
                    suggestions.push((*exp).to_string());
                }
            }
        }

        if suggestions.is_empty() {
            suggestions.push("嘗試當前熱門話題".to_string());
        }

        suggestions
    }
}

// ============================================
// 類型定義
// ============================================

/// 用戶洞察
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserInsight {
    pub user_id: Uuid,

    /// 人設摘要
    pub persona_summary: String,

    /// 深度興趣 (表面興趣背後的動機)
    pub deep_interests: Vec<String>,

    /// 行為洞察
    pub behavior_insights: Vec<String>,

    /// 內容偏好洞察
    pub content_preferences: ContentPreferenceInsight,

    /// 推薦策略理由
    pub recommendation_reasoning: String,

    /// 探索建議
    pub exploration_suggestions: Vec<String>,

    /// 置信度
    pub confidence: f32,

    /// 生成時間
    pub generated_at: DateTime<Utc>,

    /// 使用的模型
    pub model_used: String,
}

/// 內容偏好洞察
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ContentPreferenceInsight {
    /// 偏好話題
    pub preferred_topics: Vec<String>,
    /// 避免話題
    pub avoid_topics: Vec<String>,
    /// 偏好風格
    pub preferred_style: String,
    /// 最佳時機
    pub optimal_timing: String,
}
