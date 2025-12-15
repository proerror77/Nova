// ============================================
// Predictive Engine (預測引擎)
// ============================================
//
// 基於用戶記憶預測未來需求：
// 1. 興趣預測 - 預測用戶接下來會對什麼感興趣
// 2. 時機預測 - 預測最佳推送時機
// 3. 內容偏好 - 預測用戶喜歡的內容類型
// 4. 行為預測 - 預測用戶下一步行為
//
// 結合規則引擎 + LLM 進行多維度預測

use super::memory_store::{LongTermMemory, MemoryStore, ShortTermMemory, InterestTrend};
use super::{MemoryError, PredictionConfig};
use crate::services::profile_builder::LlmProfileAnalyzer;
use chrono::{DateTime, Timelike, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{debug, info, warn};
use uuid::Uuid;

/// 預測引擎
pub struct PredictiveEngine {
    memory_store: Arc<MemoryStore>,
    llm: Option<Arc<LlmProfileAnalyzer>>,
    config: PredictionConfig,
    /// 預測緩存
    prediction_cache: RwLock<HashMap<Uuid, CachedPrediction>>,
}

impl PredictiveEngine {
    pub fn new(
        memory_store: Arc<MemoryStore>,
        llm: Option<Arc<LlmProfileAnalyzer>>,
        config: PredictionConfig,
    ) -> Self {
        Self {
            memory_store,
            llm,
            config,
            prediction_cache: RwLock::new(HashMap::new()),
        }
    }

    /// 生成用戶預測
    pub async fn predict(&self, user_id: Uuid) -> Result<Vec<Prediction>, MemoryError> {
        // 檢查緩存
        if let Some(cached) = self.get_cached_prediction(user_id).await {
            if !cached.is_expired() {
                return Ok(cached.predictions);
            }
        }

        // 獲取記憶數據
        let short_term = self.memory_store.get_short_term(user_id).await?;
        let long_term = self.memory_store.get_long_term(user_id).await?;

        let mut predictions = Vec::new();

        // 1. 興趣預測
        predictions.extend(self.predict_interests(&short_term, &long_term));

        // 2. 時機預測
        predictions.extend(self.predict_optimal_time(&long_term));

        // 3. 內容類型預測
        predictions.extend(self.predict_content_type(&short_term, &long_term));

        // 4. 行為預測
        predictions.extend(self.predict_behavior(&short_term, &long_term));

        // 5. LLM 增強預測 (如果啟用)
        if self.config.use_llm_enhancement {
            if let Ok(llm_predictions) = self.llm_enhanced_prediction(&short_term, &long_term).await {
                predictions.extend(llm_predictions);
            }
        }

        // 過濾低置信度預測
        predictions.retain(|p| p.confidence >= self.config.min_confidence);

        // 排序
        predictions.sort_by(|a, b| {
            b.confidence.partial_cmp(&a.confidence).unwrap_or(std::cmp::Ordering::Equal)
        });

        // 緩存結果
        self.cache_prediction(user_id, predictions.clone()).await;

        Ok(predictions)
    }

    /// 更新預測 (當有新事件時調用)
    pub async fn update_predictions(&self, user_id: Uuid) -> Result<(), MemoryError> {
        // 清除緩存，強制下次重新計算
        let mut cache = self.prediction_cache.write().await;
        cache.remove(&user_id);
        Ok(())
    }

    /// 預測興趣
    fn predict_interests(
        &self,
        short_term: &ShortTermMemory,
        long_term: &LongTermMemory,
    ) -> Vec<Prediction> {
        let mut predictions = Vec::new();

        // 基於上升趨勢的興趣預測
        for (tag, info) in &long_term.stable_interests {
            if matches!(info.trend, InterestTrend::Rising) {
                predictions.push(Prediction {
                    prediction_type: PredictionType::NextInterest,
                    content_hint: tag.clone(),
                    confidence: 0.7 + (info.weight * 0.2),
                    reasoning: format!("「{}」興趣持續上升，權重 {:.2}", tag, info.weight),
                    time_horizon: TimeHorizon::ShortTerm,
                    predicted_at: Utc::now(),
                });
            }
        }

        // 基於即時興趣的短期預測
        for (tag, weight) in short_term.instant_interests.iter().take(3) {
            if *weight > 0.5 {
                predictions.push(Prediction {
                    prediction_type: PredictionType::NextInterest,
                    content_hint: tag.clone(),
                    confidence: *weight,
                    reasoning: format!("當前 Session 對「{}」表現出強烈興趣", tag),
                    time_horizon: TimeHorizon::Immediate,
                    predicted_at: Utc::now(),
                });
            }
        }

        // 基於週期性行為的預測
        let current_hour = Utc::now().hour() as usize;
        let hourly_interest = self.get_hourly_interest_pattern(long_term, current_hour);
        for (tag, confidence) in hourly_interest {
            predictions.push(Prediction {
                prediction_type: PredictionType::NextInterest,
                content_hint: tag,
                confidence,
                reasoning: format!("用戶在此時段 ({:02}:00) 通常對此類內容感興趣", current_hour),
                time_horizon: TimeHorizon::ShortTerm,
                predicted_at: Utc::now(),
            });
        }

        predictions
    }

    /// 預測最佳推送時機
    fn predict_optimal_time(&self, long_term: &LongTermMemory) -> Vec<Prediction> {
        let mut predictions = Vec::new();
        let patterns = &long_term.behavior_patterns;

        // 找出活躍高峰時段
        let peak_hours: Vec<(usize, u32)> = patterns.active_hours
            .iter()
            .enumerate()
            .filter(|(_, &count)| count > 0)
            .map(|(hour, &count)| (hour, count))
            .collect();

        if peak_hours.is_empty() {
            return predictions;
        }

        // 找出最活躍的時段
        let max_count = peak_hours.iter().map(|(_, c)| *c).max().unwrap_or(1);

        for (hour, count) in peak_hours {
            let relative_activity = count as f32 / max_count as f32;
            if relative_activity > 0.5 {
                predictions.push(Prediction {
                    prediction_type: PredictionType::OptimalTime,
                    content_hint: format!("{:02}:00", hour),
                    confidence: 0.5 + (relative_activity * 0.4),
                    reasoning: format!(
                        "用戶在 {:02}:00 時段活躍度高 (相對活躍度: {:.0}%)",
                        hour, relative_activity * 100.0
                    ),
                    time_horizon: TimeHorizon::Daily,
                    predicted_at: Utc::now(),
                });
            }
        }

        // 基於當前時間推薦
        let current_hour = Utc::now().hour() as usize;
        let current_activity = patterns.active_hours.get(current_hour).copied().unwrap_or(0);

        if current_activity > 0 {
            predictions.push(Prediction {
                prediction_type: PredictionType::OptimalTime,
                content_hint: "現在".to_string(),
                confidence: 0.6 + (current_activity as f32 / max_count as f32 * 0.3),
                reasoning: "用戶當前時段通常較活躍".to_string(),
                time_horizon: TimeHorizon::Immediate,
                predicted_at: Utc::now(),
            });
        }

        predictions
    }

    /// 預測內容類型偏好
    fn predict_content_type(
        &self,
        _short_term: &ShortTermMemory,
        long_term: &LongTermMemory,
    ) -> Vec<Prediction> {
        let mut predictions = Vec::new();
        let prefs = &long_term.content_preferences;

        // 時長偏好 (基於 preferred_duration_range)
        let (min_dur, max_dur) = prefs.preferred_duration_range;
        let duration_hint = if max_dur > 60 {
            ("長視頻", format!("用戶偏好 {}-{} 秒的較長內容", min_dur, max_dur))
        } else if max_dur > 30 {
            ("中等長度", format!("用戶偏好 {}-{} 秒的中等長度內容", min_dur, max_dur))
        } else {
            ("短視頻", format!("用戶偏好 {}-{} 秒的短內容", min_dur, max_dur))
        };

        predictions.push(Prediction {
            prediction_type: PredictionType::ContentPreference,
            content_hint: duration_hint.0.to_string(),
            confidence: 0.7,
            reasoning: duration_hint.1,
            time_horizon: TimeHorizon::Persistent,
            predicted_at: Utc::now(),
        });

        // 完播率閾值偏好
        if prefs.completion_threshold > 0.7 {
            predictions.push(Prediction {
                prediction_type: PredictionType::ContentPreference,
                content_hint: "高質量內容".to_string(),
                confidence: 0.75,
                reasoning: format!(
                    "用戶完播率閾值 {:.0}%，偏好深度觀看",
                    prefs.completion_threshold * 100.0
                ),
                time_horizon: TimeHorizon::Persistent,
                predicted_at: Utc::now(),
            });
        }

        // 偏好的內容類型
        for content_type in &prefs.preferred_content_types {
            predictions.push(Prediction {
                prediction_type: PredictionType::ContentPreference,
                content_hint: format!("{}類型內容", content_type),
                confidence: 0.65,
                reasoning: format!("經常觀看{}類型的內容", content_type),
                time_horizon: TimeHorizon::Persistent,
                predicted_at: Utc::now(),
            });
        }

        predictions
    }

    /// 預測用戶行為
    fn predict_behavior(
        &self,
        short_term: &ShortTermMemory,
        long_term: &LongTermMemory,
    ) -> Vec<Prediction> {
        let mut predictions = Vec::new();

        // 基於活躍度預測
        match short_term.activity_level {
            super::memory_store::ActivityLevel::VeryActive => {
                predictions.push(Prediction {
                    prediction_type: PredictionType::Behavior,
                    content_hint: "長時間瀏覽".to_string(),
                    confidence: 0.8,
                    reasoning: "用戶當前非常活躍，可能會長時間停留".to_string(),
                    time_horizon: TimeHorizon::Immediate,
                    predicted_at: Utc::now(),
                });
            }
            super::memory_store::ActivityLevel::Active => {
                predictions.push(Prediction {
                    prediction_type: PredictionType::Behavior,
                    content_hint: "正常瀏覽".to_string(),
                    confidence: 0.7,
                    reasoning: "用戶當前活躍度正常".to_string(),
                    time_horizon: TimeHorizon::Immediate,
                    predicted_at: Utc::now(),
                });
            }
            super::memory_store::ActivityLevel::Idle => {
                predictions.push(Prediction {
                    prediction_type: PredictionType::Behavior,
                    content_hint: "可能離開".to_string(),
                    confidence: 0.6,
                    reasoning: "用戶活躍度下降，可能即將離開".to_string(),
                    time_horizon: TimeHorizon::Immediate,
                    predicted_at: Utc::now(),
                });
            }
            _ => {}
        }

        // 基於互動模式預測
        let recent_events = &short_term.events;
        let like_count = recent_events.iter().filter(|e| e.event_type == "like").count();
        let comment_count = recent_events.iter().filter(|e| e.event_type == "comment").count();

        if like_count > 3 {
            predictions.push(Prediction {
                prediction_type: PredictionType::Behavior,
                content_hint: "可能會點讚".to_string(),
                confidence: 0.65,
                reasoning: format!("本 Session 已點讚 {} 次，互動意願較高", like_count),
                time_horizon: TimeHorizon::Immediate,
                predicted_at: Utc::now(),
            });
        }

        if comment_count > 1 {
            predictions.push(Prediction {
                prediction_type: PredictionType::Behavior,
                content_hint: "可能會評論".to_string(),
                confidence: 0.6,
                reasoning: format!("本 Session 已評論 {} 次，表達意願較強", comment_count),
                time_horizon: TimeHorizon::Immediate,
                predicted_at: Utc::now(),
            });
        }

        predictions
    }

    /// LLM 增強預測
    async fn llm_enhanced_prediction(
        &self,
        short_term: &ShortTermMemory,
        long_term: &LongTermMemory,
    ) -> Result<Vec<Prediction>, MemoryError> {
        let _llm = self.llm.as_ref().ok_or_else(|| {
            MemoryError::Llm("LLM not configured".to_string())
        })?;

        // TODO: 實際調用 LLM 進行深度預測
        // 目前返回基於規則的增強預測

        let mut predictions = Vec::new();

        // 綜合分析：結合興趣趨勢和行為模式
        let rising_interests: Vec<_> = long_term.stable_interests
            .iter()
            .filter(|(_, info)| matches!(info.trend, InterestTrend::Rising))
            .map(|(tag, _)| tag.clone())
            .collect();

        if !rising_interests.is_empty() {
            // 預測興趣演化方向
            let evolution_prediction = self.predict_interest_evolution(&rising_interests);
            if let Some(pred) = evolution_prediction {
                predictions.push(pred);
            }
        }

        // 分析用戶生命週期階段
        let lifecycle_prediction = self.predict_user_lifecycle(long_term);
        if let Some(pred) = lifecycle_prediction {
            predictions.push(pred);
        }

        Ok(predictions)
    }

    /// 預測興趣演化
    fn predict_interest_evolution(&self, rising_interests: &[String]) -> Option<Prediction> {
        // 興趣演化映射 (從 A 到 B 的可能演化路徑)
        let evolution_paths: HashMap<&str, Vec<&str>> = [
            ("科技", vec!["AI", "創業", "投資"]),
            ("健身", vec!["營養", "健康生活", "運動裝備"]),
            ("美食", vec!["烹飪", "食材", "餐廳評測"]),
            ("遊戲", vec!["電競", "遊戲開發", "直播"]),
            ("旅行", vec!["攝影", "戶外運動", "文化探索"]),
            ("投資", vec!["創業", "房地產", "財務自由"]),
            ("編程", vec!["開源", "職涯發展", "技術管理"]),
        ].into_iter().collect();

        for interest in rising_interests {
            if let Some(evolutions) = evolution_paths.get(interest.as_str()) {
                if let Some(next) = evolutions.first() {
                    return Some(Prediction {
                        prediction_type: PredictionType::InterestEvolution,
                        content_hint: (*next).to_string(),
                        confidence: 0.55,
                        reasoning: format!(
                            "基於「{}」興趣上升趨勢，預測可能對「{}」產生興趣",
                            interest, next
                        ),
                        time_horizon: TimeHorizon::MediumTerm,
                        predicted_at: Utc::now(),
                    });
                }
            }
        }

        None
    }

    /// 預測用戶生命週期
    fn predict_user_lifecycle(&self, long_term: &LongTermMemory) -> Option<Prediction> {
        let total = long_term.total_interactions;
        let interest_count = long_term.stable_interests.len();

        let (stage, hint, reasoning) = if total < 50 {
            (
                "新用戶探索期",
                "多樣化推薦",
                "用戶處於探索期，應提供多樣化內容幫助發現興趣",
            )
        } else if total < 200 && interest_count < 5 {
            (
                "興趣形成期",
                "深化當前興趣",
                "用戶正在形成穩定興趣，應深化現有興趣點",
            )
        } else if total < 500 {
            (
                "穩定使用期",
                "平衡深度與廣度",
                "用戶使用穩定，建議平衡推薦已有興趣和新領域探索",
            )
        } else {
            (
                "忠實用戶期",
                "個性化深度服務",
                "高度活躍的忠實用戶，提供深度個性化服務",
            )
        };

        Some(Prediction {
            prediction_type: PredictionType::UserLifecycle,
            content_hint: format!("{}: {}", stage, hint),
            confidence: 0.7,
            reasoning: reasoning.to_string(),
            time_horizon: TimeHorizon::Persistent,
            predicted_at: Utc::now(),
        })
    }

    /// 獲取特定時段的興趣模式
    fn get_hourly_interest_pattern(
        &self,
        long_term: &LongTermMemory,
        _hour: usize,
    ) -> Vec<(String, f32)> {
        // 基於時段的興趣權重調整
        // TODO: 實現更精細的時段興趣分析

        let mut hourly_interests = Vec::new();

        // 取權重最高的幾個興趣
        let mut sorted_interests: Vec<_> = long_term.stable_interests
            .iter()
            .filter(|(_, info)| info.weight > 0.3)
            .collect();

        sorted_interests.sort_by(|a, b| {
            b.1.weight.partial_cmp(&a.1.weight).unwrap_or(std::cmp::Ordering::Equal)
        });

        for (tag, info) in sorted_interests.into_iter().take(3) {
            hourly_interests.push((tag.clone(), info.weight * 0.6)); // 降低置信度
        }

        hourly_interests
    }

    /// 獲取緩存的預測
    async fn get_cached_prediction(&self, user_id: Uuid) -> Option<CachedPrediction> {
        let cache = self.prediction_cache.read().await;
        cache.get(&user_id).cloned()
    }

    /// 緩存預測結果
    async fn cache_prediction(&self, user_id: Uuid, predictions: Vec<Prediction>) {
        let mut cache = self.prediction_cache.write().await;
        cache.insert(user_id, CachedPrediction {
            predictions,
            cached_at: Utc::now(),
            ttl_seconds: 300, // 5 分鐘緩存
        });

        // 清理過期緩存
        cache.retain(|_, v| !v.is_expired());
    }
}

// ============================================
// 類型定義
// ============================================

/// 預測結果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Prediction {
    /// 預測類型
    pub prediction_type: PredictionType,
    /// 內容提示
    pub content_hint: String,
    /// 置信度 (0-1)
    pub confidence: f32,
    /// 預測理由
    pub reasoning: String,
    /// 時間範圍
    pub time_horizon: TimeHorizon,
    /// 預測時間
    pub predicted_at: DateTime<Utc>,
}

/// 預測類型
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum PredictionType {
    /// 下一個興趣
    NextInterest,
    /// 最佳推送時機
    OptimalTime,
    /// 內容偏好
    ContentPreference,
    /// 用戶行為
    Behavior,
    /// 興趣演化
    InterestEvolution,
    /// 用戶生命週期
    UserLifecycle,
}

/// 時間範圍
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum TimeHorizon {
    /// 立即 (當前 Session)
    Immediate,
    /// 短期 (今天)
    ShortTerm,
    /// 每日 (固定時段)
    Daily,
    /// 中期 (本週)
    MediumTerm,
    /// 持久 (長期特徵)
    Persistent,
}

/// 緩存的預測
#[derive(Debug, Clone)]
struct CachedPrediction {
    predictions: Vec<Prediction>,
    cached_at: DateTime<Utc>,
    ttl_seconds: i64,
}

impl CachedPrediction {
    fn is_expired(&self) -> bool {
        let elapsed = Utc::now().signed_duration_since(self.cached_at);
        elapsed.num_seconds() > self.ttl_seconds
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_prediction_type_serialization() {
        let pred = Prediction {
            prediction_type: PredictionType::NextInterest,
            content_hint: "科技".to_string(),
            confidence: 0.8,
            reasoning: "測試".to_string(),
            time_horizon: TimeHorizon::ShortTerm,
            predicted_at: Utc::now(),
        };

        let json = serde_json::to_string(&pred).unwrap();
        assert!(json.contains("NextInterest"));
    }

    #[test]
    fn test_cached_prediction_expiry() {
        let cached = CachedPrediction {
            predictions: vec![],
            cached_at: Utc::now() - chrono::Duration::seconds(400),
            ttl_seconds: 300,
        };
        assert!(cached.is_expired());

        let fresh = CachedPrediction {
            predictions: vec![],
            cached_at: Utc::now(),
            ttl_seconds: 300,
        };
        assert!(!fresh.is_expired());
    }
}
