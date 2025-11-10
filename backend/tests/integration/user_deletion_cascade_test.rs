//! 用户删除级联测试 - P1 级别
//!
//! 测试目标：验证用户软删除的完整性和级联行为
//! - 软删除用户 → 触发 Outbox 事件
//! - 级联软删除相关记录（messages, posts, comments, etc.）
//! - 验证 deleted_by 字段正确传播
//! - 验证级联深度（一层vs多层）
//!
//! Linus 哲学：
//! "Never break userspace - 软删除是唯一正确的删除方式"
//! "数据结构优先 - 级联关系应该由数据库触发器保证，而不是应用代码"

use crate::fixtures::test_env::TestEnvironment;
use chrono::Utc;
use sqlx::PgPool;
use uuid::Uuid;

/// 测试 1: 软删除用户触发 Outbox 事件
///
/// 场景：管理员软删除用户账号
/// 预期：
/// - user.deleted_at 设置为当前时间
/// - user.deleted_by 设置为操作者 ID
/// - outbox_events 表插入 UserDeleted 事件
/// - 事件 payload 包含完整的删除上下文
#[tokio::test]
async fn test_soft_delete_user_creates_outbox_event() {
    let env = TestEnvironment::new().await;
    let db = env.db();

    // 准备测试数据
    let user_id = Uuid::new_v4();
    let admin_id = Uuid::new_v4();

    // 1. 创建用户
    create_user(&db, user_id, "test@example.com").await;

    // 2. 软删除用户
    let deleted_at = Utc::now();
    sqlx::query(
        r#"
        UPDATE users
        SET deleted_at = $1, deleted_by = $2
        WHERE id = $3
        "#,
    )
    .bind(deleted_at)
    .bind(admin_id)
    .bind(user_id)
    .execute(&*db)
    .await
    .expect("软删除用户失败");

    // 验证：用户已软删除
    let (user_deleted_at, user_deleted_by): (Option<chrono::DateTime<Utc>>, Option<Uuid>) =
        sqlx::query_as("SELECT deleted_at, deleted_by FROM users WHERE id = $1")
            .bind(user_id)
            .fetch_one(&*db)
            .await
            .expect("查询用户失败");

    assert!(user_deleted_at.is_some(), "deleted_at 应该被设置");
    assert_eq!(user_deleted_by, Some(admin_id), "deleted_by 应该是管理员");

    // 验证：Outbox 事件已创建
    let event_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM outbox_events WHERE aggregate_id = $1 AND event_type = 'UserDeleted'",
    )
    .bind(user_id)
    .fetch_one(&*db)
    .await
    .expect("查询 Outbox 事件失败");

    assert_eq!(event_count, 1, "应该有一个 UserDeleted 事件");

    // 验证：事件 payload 包含完整信息
    let payload: serde_json::Value = sqlx::query_scalar(
        "SELECT payload FROM outbox_events WHERE aggregate_id = $1 AND event_type = 'UserDeleted'",
    )
    .bind(user_id)
    .fetch_one(&*db)
    .await
    .expect("查询事件 payload 失败");

    assert_eq!(
        payload["user_id"].as_str().unwrap(),
        user_id.to_string(),
        "payload 应该包含 user_id"
    );
    assert_eq!(
        payload["deleted_by"].as_str().unwrap(),
        admin_id.to_string(),
        "payload 应该包含 deleted_by"
    );
    assert!(
        payload["deleted_at"].is_string(),
        "payload 应该包含 deleted_at"
    );

    env.cleanup().await;
}

/// 测试 2: 级联软删除用户的消息、帖子、评论
///
/// 场景：用户有多条消息、帖子、评论，软删除用户应该级联删除所有相关内容
/// 预期：
/// - 所有 messages 记录的 deleted_at 被设置
/// - 所有 posts 记录的 deleted_at 被设置
/// - 所有 comments 记录的 deleted_at 被设置
/// - deleted_by 字段正确传播到所有记录
#[tokio::test]
async fn test_cascade_soft_delete_user_content() {
    let env = TestEnvironment::new().await;
    let db = env.db();

    let user_id = Uuid::new_v4();
    let admin_id = Uuid::new_v4();

    // 1. 创建用户
    create_user(&db, user_id, "user@example.com").await;

    // 2. 创建用户的内容
    let message_ids = create_messages(&db, user_id, 5).await;
    let post_ids = create_posts(&db, user_id, 3).await;
    let comment_ids = create_comments(&db, user_id, 4).await;

    // 3. 软删除用户（触发级联）
    let deleted_at = Utc::now();
    sqlx::query(
        r#"
        UPDATE users
        SET deleted_at = $1, deleted_by = $2
        WHERE id = $3
        "#,
    )
    .bind(deleted_at)
    .bind(admin_id)
    .bind(user_id)
    .execute(&*db)
    .await
    .expect("软删除用户失败");

    // 验证：所有消息已软删除
    for message_id in &message_ids {
        let (msg_deleted_at, msg_deleted_by): (Option<chrono::DateTime<Utc>>, Option<Uuid>) =
            sqlx::query_as("SELECT deleted_at, deleted_by FROM messages WHERE id = $1")
                .bind(message_id)
                .fetch_one(&*db)
                .await
                .expect("查询消息失败");

        assert!(
            msg_deleted_at.is_some(),
            "消息 {} 应该被软删除",
            message_id
        );
        assert_eq!(
            msg_deleted_by,
            Some(admin_id),
            "消息 {} 的 deleted_by 应该是管理员",
            message_id
        );
    }

    // 验证：所有帖子已软删除
    for post_id in &post_ids {
        let (post_deleted_at, post_deleted_by): (Option<chrono::DateTime<Utc>>, Option<Uuid>) =
            sqlx::query_as("SELECT deleted_at, deleted_by FROM posts WHERE id = $1")
                .bind(post_id)
                .fetch_one(&*db)
                .await
                .expect("查询帖子失败");

        assert!(
            post_deleted_at.is_some(),
            "帖子 {} 应该被软删除",
            post_id
        );
        assert_eq!(
            post_deleted_by,
            Some(admin_id),
            "帖子 {} 的 deleted_by 应该是管理员",
            post_id
        );
    }

    // 验证：所有评论已软删除
    for comment_id in &comment_ids {
        let (comment_deleted_at, comment_deleted_by): (
            Option<chrono::DateTime<Utc>>,
            Option<Uuid>,
        ) = sqlx::query_as("SELECT deleted_at, deleted_by FROM comments WHERE id = $1")
            .bind(comment_id)
            .fetch_one(&*db)
            .await
            .expect("查询评论失败");

        assert!(
            comment_deleted_at.is_some(),
            "评论 {} 应该被软删除",
            comment_id
        );
        assert_eq!(
            comment_deleted_by,
            Some(admin_id),
            "评论 {} 的 deleted_by 应该是管理员",
            comment_id
        );
    }

    env.cleanup().await;
}

/// 测试 3: 级联深度验证 - 多层关系的级联删除
///
/// 场景：用户 → 帖子 → 评论 → 点赞（三层级联）
/// 预期：
/// - 删除用户 → 软删除用户的帖子
/// - 软删除帖子 → 软删除帖子的评论
/// - 软删除评论 → 软删除评论的点赞
/// - 所有层级的 deleted_by 字段正确传播
#[tokio::test]
async fn test_cascade_depth_multi_level_relationships() {
    let env = TestEnvironment::new().await;
    let db = env.db();

    let user_id = Uuid::new_v4();
    let admin_id = Uuid::new_v4();

    // 1. 创建用户
    create_user(&db, user_id, "user@example.com").await;

    // 2. 创建帖子
    let post_id = Uuid::new_v4();
    sqlx::query(
        r#"
        INSERT INTO posts (id, user_id, content, created_at)
        VALUES ($1, $2, $3, $4)
        "#,
    )
    .bind(post_id)
    .bind(user_id)
    .bind("Test post")
    .bind(Utc::now())
    .execute(&*db)
    .await
    .expect("创建帖子失败");

    // 3. 创建评论
    let comment_id = Uuid::new_v4();
    sqlx::query(
        r#"
        INSERT INTO comments (id, post_id, user_id, content, created_at)
        VALUES ($1, $2, $3, $4, $5)
        "#,
    )
    .bind(comment_id)
    .bind(post_id)
    .bind(user_id)
    .bind("Test comment")
    .bind(Utc::now())
    .execute(&*db)
    .await
    .expect("创建评论失败");

    // 4. 创建点赞
    let like_id = Uuid::new_v4();
    sqlx::query(
        r#"
        INSERT INTO likes (id, comment_id, user_id, created_at)
        VALUES ($1, $2, $3, $4)
        "#,
    )
    .bind(like_id)
    .bind(comment_id)
    .bind(user_id)
    .bind(Utc::now())
    .execute(&*db)
    .await
    .expect("创建点赞失败");

    // 5. 软删除用户（触发级联）
    let deleted_at = Utc::now();
    sqlx::query(
        r#"
        UPDATE users
        SET deleted_at = $1, deleted_by = $2
        WHERE id = $3
        "#,
    )
    .bind(deleted_at)
    .bind(admin_id)
    .bind(user_id)
    .execute(&*db)
    .await
    .expect("软删除用户失败");

    // 验证：用户已软删除
    let user_deleted: Option<chrono::DateTime<Utc>> =
        sqlx::query_scalar("SELECT deleted_at FROM users WHERE id = $1")
            .bind(user_id)
            .fetch_one(&*db)
            .await
            .expect("查询用户失败");
    assert!(user_deleted.is_some(), "用户应该被软删除");

    // 验证：帖子已软删除（第一层级联）
    let post_deleted: Option<chrono::DateTime<Utc>> =
        sqlx::query_scalar("SELECT deleted_at FROM posts WHERE id = $1")
            .bind(post_id)
            .fetch_one(&*db)
            .await
            .expect("查询帖子失败");
    assert!(post_deleted.is_some(), "帖子应该被软删除（第一层级联）");

    // 验证：评论已软删除（第二层级联）
    let comment_deleted: Option<chrono::DateTime<Utc>> =
        sqlx::query_scalar("SELECT deleted_at FROM comments WHERE id = $1")
            .bind(comment_id)
            .fetch_one(&*db)
            .await
            .expect("查询评论失败");
    assert!(
        comment_deleted.is_some(),
        "评论应该被软删除（第二层级联）"
    );

    // 验证：点赞已软删除（第三层级联）
    let like_deleted: Option<chrono::DateTime<Utc>> =
        sqlx::query_scalar("SELECT deleted_at FROM likes WHERE id = $1")
            .bind(like_id)
            .fetch_one(&*db)
            .await
            .expect("查询点赞失败");
    assert!(
        like_deleted.is_some(),
        "点赞应该被软删除（第三层级联）"
    );

    // 验证：所有层级的 deleted_by 字段正确传播
    let post_deleted_by: Option<Uuid> =
        sqlx::query_scalar("SELECT deleted_by FROM posts WHERE id = $1")
            .bind(post_id)
            .fetch_one(&*db)
            .await
            .expect("查询帖子 deleted_by 失败");
    assert_eq!(
        post_deleted_by,
        Some(admin_id),
        "帖子的 deleted_by 应该是管理员"
    );

    let comment_deleted_by: Option<Uuid> =
        sqlx::query_scalar("SELECT deleted_by FROM comments WHERE id = $1")
            .bind(comment_id)
            .fetch_one(&*db)
            .await
            .expect("查询评论 deleted_by 失败");
    assert_eq!(
        comment_deleted_by,
        Some(admin_id),
        "评论的 deleted_by 应该是管理员"
    );

    let like_deleted_by: Option<Uuid> =
        sqlx::query_scalar("SELECT deleted_by FROM likes WHERE id = $1")
            .bind(like_id)
            .fetch_one(&*db)
            .await
            .expect("查询点赞 deleted_by 失败");
    assert_eq!(
        like_deleted_by,
        Some(admin_id),
        "点赞的 deleted_by 应该是管理员"
    );

    env.cleanup().await;
}

// ============================================
// Helper Functions（辅助函数）
// ============================================

/// 创建用户
async fn create_user(db: &PgPool, user_id: Uuid, email: &str) {
    sqlx::query(
        r#"
        INSERT INTO users (id, email, username, password_hash, created_at)
        VALUES ($1, $2, $3, $4, $5)
        "#,
    )
    .bind(user_id)
    .bind(email)
    .bind(email.split('@').next().unwrap_or("user"))
    .bind("hashed_password")
    .bind(Utc::now())
    .execute(db)
    .await
    .expect("创建用户失败");
}

/// 创建多条消息
async fn create_messages(db: &PgPool, sender_id: Uuid, count: usize) -> Vec<Uuid> {
    let mut message_ids = Vec::new();
    let conversation_id = Uuid::new_v4();

    for i in 0..count {
        let message_id = Uuid::new_v4();
        sqlx::query(
            r#"
            INSERT INTO messages (id, conversation_id, sender_id, content, created_at)
            VALUES ($1, $2, $3, $4, $5)
            "#,
        )
        .bind(message_id)
        .bind(conversation_id)
        .bind(sender_id)
        .bind(format!("Message {}", i))
        .bind(Utc::now())
        .execute(db)
        .await
        .expect("创建消息失败");

        message_ids.push(message_id);
    }

    message_ids
}

/// 创建多个帖子
async fn create_posts(db: &PgPool, user_id: Uuid, count: usize) -> Vec<Uuid> {
    let mut post_ids = Vec::new();

    for i in 0..count {
        let post_id = Uuid::new_v4();
        sqlx::query(
            r#"
            INSERT INTO posts (id, user_id, content, created_at)
            VALUES ($1, $2, $3, $4)
            "#,
        )
        .bind(post_id)
        .bind(user_id)
        .bind(format!("Post {}", i))
        .bind(Utc::now())
        .execute(db)
        .await
        .expect("创建帖子失败");

        post_ids.push(post_id);
    }

    post_ids
}

/// 创建多个评论
async fn create_comments(db: &PgPool, user_id: Uuid, count: usize) -> Vec<Uuid> {
    let mut comment_ids = Vec::new();
    let post_id = Uuid::new_v4();

    // 先创建一个帖子
    sqlx::query(
        r#"
        INSERT INTO posts (id, user_id, content, created_at)
        VALUES ($1, $2, $3, $4)
        "#,
    )
    .bind(post_id)
    .bind(user_id)
    .bind("Post for comments")
    .bind(Utc::now())
    .execute(db)
    .await
    .expect("创建帖子失败");

    for i in 0..count {
        let comment_id = Uuid::new_v4();
        sqlx::query(
            r#"
            INSERT INTO comments (id, post_id, user_id, content, created_at)
            VALUES ($1, $2, $3, $4, $5)
            "#,
        )
        .bind(comment_id)
        .bind(post_id)
        .bind(user_id)
        .bind(format!("Comment {}", i))
        .bind(Utc::now())
        .execute(db)
        .await
        .expect("创建评论失败");

        comment_ids.push(comment_id);
    }

    comment_ids
}
