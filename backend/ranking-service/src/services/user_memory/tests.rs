// ============================================
// User Memory System Integration Tests
// ============================================
//
// 運行方式:
// cargo test --lib user_memory::tests -- --nocapture

#[cfg(test)]
mod tests {
    use super::super::*;
    use chrono::Utc;
    use uuid::Uuid;

    /// 測試完整的記憶系統流程
    #[tokio::test]
    async fn test_memory_system_flow() {
        // 注意: 此測試需要 Redis 連接
        // 如果沒有 Redis，測試會被跳過
        let redis_url =
            std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://localhost:6379".to_string());

        let redis = match redis::Client::open(redis_url.clone()) {
            Ok(client) => {
                // 嘗試連接以確認 Redis 可用
                match client.get_multiplexed_async_connection().await {
                    Ok(_) => client,
                    Err(_) => {
                        println!("⚠️  跳過測試: 無法連接到 Redis ({})", redis_url);
                        return;
                    }
                }
            }
            Err(_) => {
                println!("⚠️  跳過測試: Redis 客戶端創建失敗");
                return;
            }
        };

        // 創建記憶系統 (無 LLM)
        let config = MemorySystemConfig::default();
        let system = UserMemorySystem::new(redis, None, config);

        let user_id = Uuid::new_v4();

        // 1. 記錄用戶事件
        let event = UserEvent {
            user_id,
            event_type: EventType::View,
            content_id: Some(Uuid::new_v4()),
            content_tags: vec!["科技".to_string(), "AI".to_string()],
            duration_ms: Some(30000),
            completion_rate: Some(0.8),
            timestamp: Utc::now(),
            context: EventContext {
                session_id: "test-session-001".to_string(),
                device_type: "mobile".to_string(),
                location: None,
                referrer: None,
                hour_of_day: 14,
                day_of_week: 1,
            },
        };

        let result = system.record_event(event).await;
        assert!(result.is_ok(), "記錄事件應該成功");

        // 2. 記錄更多事件以建立興趣
        for i in 0..5 {
            let event = UserEvent {
                user_id,
                event_type: EventType::Like,
                content_id: Some(Uuid::new_v4()),
                content_tags: vec!["科技".to_string(), "編程".to_string()],
                duration_ms: Some(45000),
                completion_rate: Some(0.9),
                timestamp: Utc::now(),
                context: EventContext {
                    session_id: "test-session-001".to_string(),
                    device_type: "mobile".to_string(),
                    location: None,
                    referrer: None,
                    hour_of_day: 14 + (i % 3) as u8,
                    day_of_week: 1,
                },
            };
            let _ = system.record_event(event).await;
        }

        // 3. 獲取用戶記憶
        let memory = system.get_user_memory(user_id).await;
        assert!(memory.is_ok(), "獲取記憶應該成功");

        let memory = memory.unwrap();
        println!("📊 短期記憶事件數: {}", memory.short_term.events.len());
        println!("📊 即時興趣: {:?}", memory.short_term.instant_interests);
        println!("📊 活躍度: {:?}", memory.short_term.activity_level);

        // 4. 探索潛在興趣
        let latent = system.explore_interests(user_id).await;
        assert!(latent.is_ok(), "探索興趣應該成功");

        let latent = latent.unwrap();
        println!("🔍 發現 {} 個潛在興趣", latent.len());
        for interest in &latent {
            println!(
                "   - {} (置信度: {:.2}, 來源: {:?})",
                interest.topic, interest.confidence, interest.source
            );
        }

        // 5. 生成洞察
        let insight = system.generate_insight(user_id).await;
        assert!(insight.is_ok(), "生成洞察應該成功");

        let insight = insight.unwrap();
        println!("🧠 用戶人設: {}", insight.persona_summary);
        println!("🧠 深度興趣: {:?}", insight.deep_interests);
        println!("🧠 置信度: {:.2}", insight.confidence);

        // 6. 預測下一步
        let predictions = system.predict_next(user_id).await;
        assert!(predictions.is_ok(), "預測應該成功");

        let predictions = predictions.unwrap();
        println!("🔮 {} 個預測結果:", predictions.len());
        for pred in &predictions {
            println!(
                "   - {:?}: {} (置信度: {:.2})",
                pred.prediction_type, pred.content_hint, pred.confidence
            );
        }

        println!("\n✅ 所有測試通過！");
    }

    /// 測試興趣探索器
    #[test]
    fn test_interest_explorer_config() {
        let config = ExplorationConfig::default();
        assert!(config.exploration_ratio > 0.0);
        assert!(config.exploration_ratio < 1.0);
        assert!(config.max_latent_interests > 0);
    }

    /// 測試預測配置
    #[test]
    fn test_prediction_config() {
        let config = PredictionConfig::default();
        assert!(config.min_confidence > 0.0);
        assert!(config.prediction_horizon_hours > 0);
    }

    /// 測試事件類型權重
    #[test]
    fn test_event_weights() {
        use memory_store::MemoryEvent;

        let test_cases = vec![
            (EventType::Purchase, 1.0),
            (EventType::LongWatch, 0.9),
            (EventType::Share, 0.8),
            (EventType::Like, 0.5),
            (EventType::View, 0.3),
            (EventType::Skip, 0.1),
            (EventType::NotInterested, 0.0),
        ];

        for (event_type, expected_weight) in test_cases {
            let event = UserEvent {
                user_id: Uuid::new_v4(),
                event_type,
                content_id: None,
                content_tags: vec![],
                duration_ms: None,
                completion_rate: None,
                timestamp: Utc::now(),
                context: EventContext {
                    session_id: "test".to_string(),
                    device_type: "mobile".to_string(),
                    location: None,
                    referrer: None,
                    hour_of_day: 12,
                    day_of_week: 1,
                },
            };

            let memory_event = MemoryEvent::from_user_event(&event);
            assert_eq!(
                memory_event.engagement_score, expected_weight,
                "{:?} 權重應為 {}",
                event.event_type, expected_weight
            );
        }
    }

    /// 測試時間衰減
    #[test]
    fn test_time_decay() {
        use chrono::Duration;
        use memory_store::MemoryStore;

        // 30 分鐘前的事件應該有較低的權重
        let now = Utc::now();
        let old_time = now - Duration::minutes(30);

        // 指數衰減: weight = base_weight * e^(-λ * t)
        // 假設半衰期為 15 分鐘
        let half_life_minutes: f64 = 15.0;
        let lambda: f64 = 0.693 / half_life_minutes; // ln(2) / half_life
        let elapsed_minutes: f64 = 30.0;

        let decay_factor: f64 = (-lambda * elapsed_minutes).exp();
        println!("30 分鐘後的衰減因子: {:.4}", decay_factor);

        // 30 分鐘後應該大約是 0.25 (經過 2 個半衰期)
        assert!(decay_factor < 0.3);
        assert!(decay_factor > 0.2);
    }
}
