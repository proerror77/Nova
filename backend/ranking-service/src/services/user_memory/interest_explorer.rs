// ============================================
// Interest Explorer (興趣探索器)
// ============================================
//
// 主動探索用戶潛在興趣：
// 1. 興趣邊界擴展 - 從已知興趣推斷相關興趣
// 2. 潛在興趣發現 - 識別用戶可能感興趣但未接觸的領域
// 3. 興趣演化追蹤 - 追蹤興趣的變化趨勢
// 4. 探索/利用平衡 - Exploration vs Exploitation

use super::memory_store::InterestTrend;
use super::{ExplorationConfig, MemoryError, UserEvent, UserMemoryView};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use tokio::sync::RwLock;

/// 興趣探索器
pub struct InterestExplorer {
    config: ExplorationConfig,
    /// 興趣關聯圖 (tag -> 相關 tags)
    interest_graph: RwLock<HashMap<String, Vec<RelatedInterest>>>,
    /// 全局熱門興趣
    trending_interests: RwLock<Vec<TrendingInterest>>,
}

impl InterestExplorer {
    pub fn new(config: ExplorationConfig) -> Self {
        Self {
            config,
            interest_graph: RwLock::new(Self::build_default_interest_graph()),
            trending_interests: RwLock::new(Vec::new()),
        }
    }

    /// 探索用戶潛在興趣
    pub async fn explore(&self, memory: &UserMemoryView) -> Result<ExplorationResult, MemoryError> {
        let mut latent_interests = Vec::new();
        let mut exploration_reasons = Vec::new();

        // 1. 從已知興趣擴展
        let expanded = self.expand_from_known_interests(memory).await;
        latent_interests.extend(expanded.clone());
        if !expanded.is_empty() {
            exploration_reasons.push("基於已知興趣的關聯擴展".to_string());
        }

        // 2. 從興趣趨勢推斷
        let trending = self.infer_from_trends(memory).await;
        latent_interests.extend(trending.clone());
        if !trending.is_empty() {
            exploration_reasons.push("基於興趣上升趨勢的推斷".to_string());
        }

        // 3. 從行為模式推斷
        let behavioral = self.infer_from_behavior(memory).await;
        latent_interests.extend(behavioral.clone());
        if !behavioral.is_empty() {
            exploration_reasons.push("基於行為模式的推斷".to_string());
        }

        // 4. 加入全局熱門 (冷啟動 / 探索)
        let global = self.add_global_exploration(memory).await;
        latent_interests.extend(global.clone());
        if !global.is_empty() {
            exploration_reasons.push("全局熱門探索".to_string());
        }

        // 去重並排序
        latent_interests = self.deduplicate_and_rank(latent_interests, memory);

        // 限制數量
        latent_interests.truncate(self.config.max_latent_interests);

        // 計算探索分數
        let exploration_score = self.calculate_exploration_score(memory);

        Ok(ExplorationResult {
            latent_interests,
            exploration_score,
            exploration_reasons,
            explored_at: Utc::now(),
        })
    }

    /// 從事件更新興趣圖
    pub async fn update_from_event(&self, event: &UserEvent) {
        // 更新興趣共現關係
        if event.content_tags.len() >= 2 {
            let mut graph = self.interest_graph.write().await;

            for i in 0..event.content_tags.len() {
                for j in (i + 1)..event.content_tags.len() {
                    let tag_a = &event.content_tags[i];
                    let tag_b = &event.content_tags[j];

                    // A -> B
                    Self::update_relation(&mut graph, tag_a, tag_b);
                    // B -> A
                    Self::update_relation(&mut graph, tag_b, tag_a);
                }
            }
        }
    }

    /// 從已知興趣擴展
    async fn expand_from_known_interests(&self, memory: &UserMemoryView) -> Vec<LatentInterest> {
        let mut latent = Vec::new();
        let graph = self.interest_graph.read().await;

        // 獲取用戶已知興趣
        let known_interests: HashSet<String> = if let Ok(ref lt) = memory.long_term {
            lt.stable_interests.keys().cloned().collect()
        } else {
            memory
                .short_term
                .instant_interests
                .keys()
                .cloned()
                .collect()
        };

        // 從每個已知興趣擴展
        for known in &known_interests {
            if let Some(related) = graph.get(known) {
                for rel in related {
                    // 跳過已知興趣
                    if known_interests.contains(&rel.tag) {
                        continue;
                    }

                    // 檢查相似度閾值
                    if rel.strength >= self.config.similarity_threshold {
                        latent.push(LatentInterest {
                            topic: rel.tag.clone(),
                            confidence: rel.strength,
                            source: InterestSource::Expansion,
                            reason: format!("與「{}」高度相關", known),
                            discovered_at: Utc::now(),
                        });
                    }
                }
            }
        }

        latent
    }

    /// 從興趣趨勢推斷
    async fn infer_from_trends(&self, memory: &UserMemoryView) -> Vec<LatentInterest> {
        let mut latent = Vec::new();

        if let Ok(ref lt) = memory.long_term {
            // 找出上升趨勢的興趣
            let rising: Vec<_> = lt
                .stable_interests
                .iter()
                .filter(|(_, info)| matches!(info.trend, InterestTrend::Rising))
                .collect();

            let graph = self.interest_graph.read().await;

            // 對於每個上升興趣，推薦其相關興趣
            for (tag, info) in rising {
                if let Some(related) = graph.get(tag) {
                    for rel in related.iter().take(2) {
                        // 只取前兩個相關
                        if !lt.stable_interests.contains_key(&rel.tag) {
                            latent.push(LatentInterest {
                                topic: rel.tag.clone(),
                                confidence: rel.strength * 0.8, // 稍微降低置信度
                                source: InterestSource::TrendBased,
                                reason: format!("「{}」興趣正在上升，可能對此也感興趣", tag),
                                discovered_at: Utc::now(),
                            });
                        }
                    }
                }
            }
        }

        latent
    }

    /// 從行為模式推斷
    async fn infer_from_behavior(&self, memory: &UserMemoryView) -> Vec<LatentInterest> {
        let mut latent = Vec::new();

        if let Ok(ref lt) = memory.long_term {
            let patterns = &lt.behavior_patterns;

            // 根據活躍時段推斷
            let peak_hours: Vec<usize> = patterns
                .active_hours
                .iter()
                .enumerate()
                .filter(|(_, &count)| count > 0)
                .max_by_key(|(_, &count)| count)
                .map(|(hour, _)| hour)
                .into_iter()
                .collect();

            // 早起用戶 -> 可能對健康/效率內容感興趣
            if peak_hours.iter().any(|&h| h >= 5 && h <= 7) {
                latent.push(LatentInterest {
                    topic: "早起習慣".to_string(),
                    confidence: 0.6,
                    source: InterestSource::BehaviorBased,
                    reason: "經常早起活躍，可能對早起/健康內容感興趣".to_string(),
                    discovered_at: Utc::now(),
                });
            }

            // 夜貓子 -> 可能對娛樂/深度內容感興趣
            if peak_hours.iter().any(|&h| h >= 23 || h <= 2) {
                latent.push(LatentInterest {
                    topic: "深夜娛樂".to_string(),
                    confidence: 0.6,
                    source: InterestSource::BehaviorBased,
                    reason: "經常深夜活躍，可能對深度/娛樂內容感興趣".to_string(),
                    discovered_at: Utc::now(),
                });
            }
        }

        latent
    }

    /// 添加全局探索
    async fn add_global_exploration(&self, memory: &UserMemoryView) -> Vec<LatentInterest> {
        let mut latent = Vec::new();
        let trending = self.trending_interests.read().await;

        // 獲取用戶已知興趣
        let known: HashSet<String> = if let Ok(ref lt) = memory.long_term {
            lt.stable_interests.keys().cloned().collect()
        } else {
            HashSet::new()
        };

        // 計算需要多少全局探索
        let exploration_count = if known.len() < 5 {
            3 // 新用戶多探索
        } else {
            1 // 老用戶少探索
        };

        for trend in trending.iter().take(exploration_count) {
            if !known.contains(&trend.topic) {
                latent.push(LatentInterest {
                    topic: trend.topic.clone(),
                    confidence: 0.5, // 探索性較低置信度
                    source: InterestSource::GlobalTrending,
                    reason: format!("全球熱門：{}", trend.reason),
                    discovered_at: Utc::now(),
                });
            }
        }

        latent
    }

    /// 去重並排序
    fn deduplicate_and_rank(
        &self,
        interests: Vec<LatentInterest>,
        memory: &UserMemoryView,
    ) -> Vec<LatentInterest> {
        let mut seen = HashSet::new();
        let mut unique: Vec<LatentInterest> = interests
            .into_iter()
            .filter(|i| seen.insert(i.topic.clone()))
            .collect();

        // 按置信度排序
        unique.sort_by(|a, b| {
            b.confidence
                .partial_cmp(&a.confidence)
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        unique
    }

    /// 計算探索分數 (決定應該探索多少)
    fn calculate_exploration_score(&self, memory: &UserMemoryView) -> f32 {
        let mut score = self.config.exploration_ratio;

        // 新用戶增加探索
        if let Ok(ref lt) = memory.long_term {
            if lt.total_interactions < 100 {
                score += 0.1;
            }
            if lt.stable_interests.len() < 5 {
                score += 0.1;
            }
        } else {
            // 沒有長期記憶的用戶，大幅增加探索
            score += 0.2;
        }

        // 限制在合理範圍
        score.min(0.5).max(0.05)
    }

    /// 更新興趣關聯
    fn update_relation(graph: &mut HashMap<String, Vec<RelatedInterest>>, from: &str, to: &str) {
        let relations = graph.entry(from.to_string()).or_insert_with(Vec::new);

        if let Some(rel) = relations.iter_mut().find(|r| r.tag == to) {
            // 增強現有關係
            rel.co_occurrence_count += 1;
            rel.strength = (rel.strength + 0.1).min(1.0);
        } else {
            // 添加新關係
            relations.push(RelatedInterest {
                tag: to.to_string(),
                strength: 0.5,
                co_occurrence_count: 1,
            });
        }

        // 限制關係數量
        if relations.len() > 50 {
            relations.sort_by(|a, b| {
                b.strength
                    .partial_cmp(&a.strength)
                    .unwrap_or(std::cmp::Ordering::Equal)
            });
            relations.truncate(50);
        }
    }

    /// 構建默認興趣圖
    fn build_default_interest_graph() -> HashMap<String, Vec<RelatedInterest>> {
        let mut graph = HashMap::new();

        // 預定義一些常見興趣關聯
        let relations = vec![
            ("科技", vec!["編程", "AI", "數碼產品", "創業"]),
            ("編程", vec!["科技", "AI", "開源", "職涯"]),
            ("美食", vec!["旅行", "生活", "烹飪", "探店"]),
            ("旅行", vec!["美食", "攝影", "文化", "冒險"]),
            ("健身", vec!["運動", "健康", "減肥", "生活方式"]),
            ("遊戲", vec!["電競", "動漫", "科技", "娛樂"]),
            ("音樂", vec!["演唱會", "樂器", "藝術", "娛樂"]),
            ("時尚", vec!["美妝", "穿搭", "生活方式", "購物"]),
            ("投資", vec!["理財", "股票", "加密貨幣", "經濟"]),
            ("育兒", vec!["教育", "家庭", "親子", "健康"]),
        ];

        for (main, related) in relations {
            let related_interests: Vec<RelatedInterest> = related
                .iter()
                .map(|&tag| RelatedInterest {
                    tag: tag.to_string(),
                    strength: 0.7,
                    co_occurrence_count: 100,
                })
                .collect();
            graph.insert(main.to_string(), related_interests);
        }

        graph
    }

    /// 更新全局熱門興趣 (應由外部定期調用)
    pub async fn update_trending(&self, trending: Vec<TrendingInterest>) {
        let mut current = self.trending_interests.write().await;
        *current = trending;
    }
}

// ============================================
// 類型定義
// ============================================

/// 探索結果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExplorationResult {
    /// 發現的潛在興趣
    pub latent_interests: Vec<LatentInterest>,
    /// 探索分數 (0-1，越高表示越應該探索)
    pub exploration_score: f32,
    /// 探索原因
    pub exploration_reasons: Vec<String>,
    /// 探索時間
    pub explored_at: DateTime<Utc>,
}

/// 潛在興趣
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LatentInterest {
    /// 興趣主題
    pub topic: String,
    /// 置信度 (0-1)
    pub confidence: f32,
    /// 來源
    pub source: InterestSource,
    /// 發現原因
    pub reason: String,
    /// 發現時間
    pub discovered_at: DateTime<Utc>,
}

/// 興趣來源
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum InterestSource {
    /// 從已知興趣擴展
    Expansion,
    /// 基於趨勢推斷
    TrendBased,
    /// 基於行為推斷
    BehaviorBased,
    /// 全局熱門
    GlobalTrending,
    /// LLM 推斷
    LlmInferred,
}

/// 相關興趣
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RelatedInterest {
    pub tag: String,
    pub strength: f32,
    pub co_occurrence_count: u32,
}

/// 熱門興趣
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrendingInterest {
    pub topic: String,
    pub heat_score: f32,
    pub reason: String,
}
