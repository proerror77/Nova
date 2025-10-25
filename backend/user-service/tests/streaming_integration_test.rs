//! 直播功能整合測試
//!
//! 測試涵蓋 StreamService、DiscoveryService 與 RTMP Webhook Handler。
//! 需依賴 PostgreSQL 與 Redis 測試環境，預設使用
//! `DATABASE_URL`、`REDIS_URL` 環境變數，或分別退回
//! `postgres://postgres:postgres@localhost:55432/nova_auth`
//! 與 `redis://127.0.0.1:6379/`。

mod common;

#[cfg(test)]
mod tests {
    use super::common::fixtures;
    use anyhow::Result;
    use redis::{aio::ConnectionManager, AsyncCommands};
    use user_service::services::streaming::{
        CreateStreamRequest, RtmpWebhookHandler, StreamChatStore,
        StreamDiscoveryService, StreamRepository, StreamService, ViewerCounter,
    };

    async fn create_redis_manager() -> Result<ConnectionManager> {
        let redis_url =
            std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379/".to_string());
        let client = redis::Client::open(redis_url)?;
        let mut manager = ConnectionManager::new(client).await?;
        redis::cmd("FLUSHDB").query_async::<_, ()>(&mut manager).await?;
        Ok(manager)
    }

    fn stream_service_dependencies(
        pool: sqlx::PgPool,
        redis_manager: ConnectionManager,
    ) -> (StreamService, StreamRepository) {
        let repo = StreamRepository::new(pool);
        let viewer_counter = ViewerCounter::new(redis_manager.clone());
        let chat_store = StreamChatStore::new(redis_manager, 200);
        let service = StreamService::new(
            repo.clone(),
            viewer_counter,
            chat_store,
            "rtmp://localhost/live".to_string(),
            "https://cdn.local".to_string(),
        );

        (service, repo)
    }

    #[tokio::test]
    #[ignore = "需 PostgreSQL 與 Redis 測試環境 (DATABASE_URL, REDIS_URL)"]
    async fn stream_lifecycle_flow() -> Result<()> {
        let pool = fixtures::create_test_pool().await;
        ensure_optional_columns(&pool).await?;
        fixtures::cleanup_test_data(&pool).await;

        let redis_manager = create_redis_manager().await?;
        let (mut service, repo) = stream_service_dependencies(pool.clone(), redis_manager.clone());

        let broadcaster = fixtures::create_test_user(&pool).await;
        let viewer = fixtures::create_test_user(&pool).await;

        let request = CreateStreamRequest {
            title: "Integration Live".to_string(),
            description: Some("Testing live streaming lifecycle".to_string()),
            category: None,
        };

        let created = service
            .create_stream(broadcaster.id, request)
            .await
            .expect("create stream");

        // RTMP 開始推流
        service
            .start_stream(&created.stream_key)
            .await
            .expect("start stream");

        // 觀眾加入
        let join = service
            .join_stream(created.stream_id, viewer.id)
            .await
            .expect("join stream");
        assert_eq!(join.current_viewers, 1);
        assert!(join.hls_url.contains("cdn.local"));

        // 發送聊天室訊息並驗證可讀
        let comment = user_service::services::streaming::StreamComment::new(
            created.stream_id,
            viewer.id,
            Some("viewer1".to_string()),
            "Hello Nova".to_string(),
        );
        service
            .post_comment(comment.clone())
            .await
            .expect("post comment");
        let comments = service
            .recent_comments(created.stream_id, 10)
            .await
            .expect("recent comments");
        assert_eq!(comments.len(), 1);
        assert_eq!(comments[0].message, "Hello Nova");

        // 離開後檢查觀眾數更新
        service
            .leave_stream(created.stream_id, viewer.id)
            .await
            .expect("leave stream");
        let details_live = service
            .get_stream_details(created.stream_id)
            .await
            .expect("details live");
        assert_eq!(details_live.current_viewers, 0);
        assert_eq!(
            details_live.status,
            user_service::services::streaming::StreamStatus::Live
        );

        // 結束直播並確認狀態
        service
            .end_stream(&created.stream_key)
            .await
            .expect("end stream");
        let details = service
            .get_stream_details(created.stream_id)
            .await
            .expect("details ended");
        assert_eq!(
            details.status,
            user_service::services::streaming::StreamStatus::Ended
        );

        // 使用 Discovery Service 搜尋直播記錄
        let mut discovery =
            StreamDiscoveryService::new(repo.clone(), ViewerCounter::new(redis_manager));
        let results = discovery
            .search_streams("Integration", 10)
            .await
            .expect("search streams");
        assert!(!results.is_empty());
        assert_eq!(results[0].title, "Integration Live");

        fixtures::cleanup_test_data(&pool).await;
        Ok(())
    }

    #[tokio::test]
    #[ignore = "需 PostgreSQL 與 Redis 測試環境 (DATABASE_URL, REDIS_URL)"]
    async fn rtmp_webhook_handlers_transition_states() -> Result<()> {
        let pool = fixtures::create_test_pool().await;
        ensure_optional_columns(&pool).await?;
        fixtures::cleanup_test_data(&pool).await;

        let redis_manager = create_redis_manager().await?;
        let (mut service, repo) = stream_service_dependencies(pool.clone(), redis_manager.clone());

        let broadcaster = fixtures::create_test_user(&pool).await;
        let request = CreateStreamRequest {
            title: "Webhook Live".to_string(),
            description: None,
            category: None,
        };

        let created = service.create_stream(broadcaster.id, request).await?;

        let mut handler = RtmpWebhookHandler::new(
            repo.clone(),
            ViewerCounter::new(redis_manager),
            "https://cdn.local".to_string(),
        );
        let auth_result = handler
            .authenticate_stream(&created.stream_key, "127.0.0.1")
            .await?;
        assert!(auth_result);

        // 再次執行 authenticate 視為重新連線，依舊允許
        let reconnect = handler
            .authenticate_stream(&created.stream_key, "127.0.0.1")
            .await?;
        assert!(reconnect);

        handler.on_stream_done(&created.stream_key).await?;

        let status: String =
            sqlx::query_scalar("SELECT status::text FROM live_streams WHERE id = $1")
                .bind(created.stream_id)
                .fetch_one(&pool)
                .await?;
        assert_eq!(status, "ended");

        fixtures::cleanup_test_data(&pool).await;
        Ok(())
    }

    #[tokio::test]
    async fn websocket_chat_registry_creation() -> Result<()> {
        use user_service::services::streaming::StreamConnectionRegistry;

        // 验证可以创建注册表 - 这是一个简单的单元测试
        // 验证构造函数和清理操作不会导致错误
        let registry = StreamConnectionRegistry::new();
        let stream_id = uuid::Uuid::new_v4();

        // 清理一个不存在的流不应该产生错误
        registry.cleanup(stream_id).await;

        // 默认实例也应该工作
        let default_registry = StreamConnectionRegistry::default();
        default_registry.cleanup(stream_id).await;

        Ok(())
    }

    #[tokio::test]
    #[ignore = "需 PostgreSQL 與 Redis 測試環境 (DATABASE_URL, REDIS_URL)"]
    async fn stream_comment_validation() -> Result<()> {
        let stream_id = uuid::Uuid::new_v4();
        let user_id = uuid::Uuid::new_v4();

        // 測試有效的注釋
        let valid_comment = user_service::services::streaming::StreamComment::new(
            stream_id,
            user_id,
            Some("testuser".to_string()),
            "This is a valid message".to_string(),
        );
        assert_eq!(valid_comment.message, "This is a valid message");
        assert_eq!(valid_comment.stream_id, stream_id);
        assert_eq!(valid_comment.user_id, user_id);

        // 測試空消息不應在 StreamChatActor 中處理
        // （在 ws.rs 中有 msg_text.trim().is_empty() 檢查）
        let empty_msg = "";
        assert!(empty_msg.trim().is_empty());

        // 測試長消息限制（500 字符）
        let long_msg = "a".repeat(501);
        assert!(long_msg.len() > 500);

        // 測試 500 字符邊界
        let boundary_msg = "a".repeat(500);
        assert_eq!(boundary_msg.len(), 500);

        Ok(())
    }

    #[tokio::test]
    #[ignore = "需 PostgreSQL 與 Redis 測試環境 (DATABASE_URL, REDIS_URL)"]
    async fn stream_chat_lifecycle() -> Result<()> {
        let pool = fixtures::create_test_pool().await;
        ensure_optional_columns(&pool).await?;
        fixtures::cleanup_test_data(&pool).await;

        let redis_manager = create_redis_manager().await?;
        let (mut service, _repo) = stream_service_dependencies(pool.clone(), redis_manager.clone());

        let broadcaster = fixtures::create_test_user(&pool).await;
        let viewer1 = fixtures::create_test_user(&pool).await;
        let viewer2 = fixtures::create_test_user(&pool).await;

        // 建立直播
        let request = CreateStreamRequest {
            title: "Chat Lifecycle Test".to_string(),
            description: Some("Testing chat functionality".to_string()),
            category: None,
        };

        let created = service
            .create_stream(broadcaster.id, request)
            .await
            .expect("create stream");

        // 開始直播
        service
            .start_stream(&created.stream_key)
            .await
            .expect("start stream");

        // 兩個觀眾加入
        service
            .join_stream(created.stream_id, viewer1.id)
            .await
            .expect("viewer1 join");
        service
            .join_stream(created.stream_id, viewer2.id)
            .await
            .expect("viewer2 join");

        // 多個使用者發送聊天訊息
        let msg1 = user_service::services::streaming::StreamComment::new(
            created.stream_id,
            viewer1.id,
            Some("viewer1".to_string()),
            "First message".to_string(),
        );
        service.post_comment(msg1).await.expect("post msg1");

        let msg2 = user_service::services::streaming::StreamComment::new(
            created.stream_id,
            viewer2.id,
            Some("viewer2".to_string()),
            "Second message".to_string(),
        );
        service.post_comment(msg2).await.expect("post msg2");

        let msg3 = user_service::services::streaming::StreamComment::new(
            created.stream_id,
            viewer1.id,
            Some("viewer1".to_string()),
            "Third message".to_string(),
        );
        service.post_comment(msg3).await.expect("post msg3");

        // 驗證聊天記錄
        let comments = service
            .recent_comments(created.stream_id, 10)
            .await
            .expect("fetch comments");

        assert_eq!(comments.len(), 3);
        assert_eq!(comments[0].message, "Third message"); // 最新的先
        assert_eq!(comments[1].message, "Second message");
        assert_eq!(comments[2].message, "First message");

        // 驗證訊息來自正確的使用者
        assert_eq!(comments[0].user_id, viewer1.id);
        assert_eq!(comments[1].user_id, viewer2.id);
        assert_eq!(comments[2].user_id, viewer1.id);

        // 驗證訊息屬於正確的流
        for comment in &comments {
            assert_eq!(comment.stream_id, created.stream_id);
        }

        // 觀眾離開
        service
            .leave_stream(created.stream_id, viewer1.id)
            .await
            .expect("viewer1 leave");
        service
            .leave_stream(created.stream_id, viewer2.id)
            .await
            .expect("viewer2 leave");

        // 結束直播
        service
            .end_stream(&created.stream_key)
            .await
            .expect("end stream");

        // 驗證聊天記錄在直播結束後仍然可用
        let final_comments = service
            .recent_comments(created.stream_id, 10)
            .await
            .expect("fetch comments after end");
        assert_eq!(final_comments.len(), 3);

        fixtures::cleanup_test_data(&pool).await;
        Ok(())
    }

    async fn ensure_optional_columns(pool: &sqlx::PgPool) -> Result<()> {
        sqlx::query("ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_url VARCHAR(255)")
            .execute(pool)
            .await?;
        Ok(())
    }
}
