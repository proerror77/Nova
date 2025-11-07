# Spec 007 Phase 2: content-service Users Consolidation

**状态**: 规划中
**前置**: Phase 1 完成 (messaging-service)
**目标**: 移除 content-service.users 表，整合到 auth-service

---

## 1. 影响范围

### 1.1 数据库表（PostgreSQL）

| 表名 | user_id 字段 | FK 关系 | 清理策略 |
|------|-------------|---------|---------|
| `posts` | creator_id | users.id | orphan_cleaner: 删除软删除用户的 posts |
| `comments` | user_id | users.id | orphan_cleaner: 删除软删除用户的 comments |
| `likes` | user_id | users.id | orphan_cleaner: 删除软删除用户的 likes |
| `replies` | user_id | users.id | orphan_cleaner: 删除软删除用户的 replies |
| `bookmarks` | user_id | users.id | orphan_cleaner: 删除软删除用户的 bookmarks |
| `shares` | user_id | users.id | orphan_cleaner: 删除软删除用户的 shares |

### 1.2 ClickHouse 表

| 表名 | user_id 字段 | 说明 |
|------|-------------|------|
| `feed_candidates_followees` | user_id, author_id | 分析数据，不需要 orphan cleaner（30天自动过期）|
| `feed_candidates_affinity` | user_id, author_id | 分析数据，不需要 orphan cleaner |

**注意**: ClickHouse 表使用 String 类型 UUID，无 FK 约束。数据会通过 PARTITION BY 自动老化删除。

---

## 2. 任务分解

### T012: 移除数据库级 FK 约束
```sql
-- content_service 数据库
ALTER TABLE posts DROP CONSTRAINT IF EXISTS posts_user_id_fkey;
ALTER TABLE comments DROP CONSTRAINT IF EXISTS comments_user_id_fkey;
ALTER TABLE likes DROP CONSTRAINT IF EXISTS likes_user_id_fkey;
ALTER TABLE replies DROP CONSTRAINT IF EXISTS replies_user_id_fkey;
ALTER TABLE bookmarks DROP CONSTRAINT IF EXISTS bookmarks_user_id_fkey;
ALTER TABLE shares DROP CONSTRAINT IF EXISTS shares_user_id_fkey;
```

**验证**:
```sql
SELECT conname, conrelid::regclass
FROM pg_constraint
WHERE confrelid = 'users'::regclass;
-- 预期结果: 空（所有 FK 已移除）
```

---

### T013: 实现 content_cleaner 后台任务

**参考**: messaging-service/src/jobs/orphan_cleaner.rs

**实现要点**:
```rust
// backend/content-service/src/jobs/content_cleaner.rs

pub async fn start_content_cleaner(
    db: PgPool,
    auth_client: Arc<AuthClient>,
) {
    loop {
        // 1. 查询所有 user_id（从 posts, comments, likes, bookmarks, shares）
        let user_ids = collect_all_user_ids(&db).await;

        // 2. 批量验证（100个一批）
        let deleted_users = identify_deleted_users(
            &auth_client,
            &user_ids,
            BATCH_SIZE
        ).await;

        // 3. 删除软删除用户的内容
        for user_id in deleted_users {
            delete_user_content(&db, user_id).await;
        }

        tokio::time::sleep(Duration::from_secs(3600)).await;
    }
}

async fn collect_all_user_ids(db: &PgPool) -> Vec<Uuid> {
    // UNION 查询获取所有表的 user_id
    sqlx::query_scalar(
        "SELECT DISTINCT user_id FROM posts
         UNION
         SELECT DISTINCT user_id FROM comments
         UNION
         SELECT DISTINCT user_id FROM likes
         UNION
         SELECT DISTINCT user_id FROM bookmarks
         UNION
         SELECT DISTINCT user_id FROM shares"
    )
    .fetch_all(db)
    .await
    .unwrap_or_default()
}

async fn delete_user_content(db: &PgPool, user_id: Uuid) -> Result<()> {
    // 软删除用户的所有内容
    sqlx::query("UPDATE posts SET deleted_at = NOW() WHERE user_id = $1")
        .bind(user_id)
        .execute(db)
        .await?;

    sqlx::query("DELETE FROM comments WHERE user_id = $1")
        .bind(user_id)
        .execute(db)
        .await?;

    sqlx::query("DELETE FROM likes WHERE user_id = $1")
        .bind(user_id)
        .execute(db)
        .await?;

    sqlx::query("DELETE FROM bookmarks WHERE user_id = $1")
        .bind(user_id)
        .execute(db)
        .await?;

    sqlx::query("DELETE FROM shares WHERE user_id = $1")
        .bind(user_id)
        .execute(db)
        .await?;

    Ok(())
}
```

**配置**:
- 间隔: 1小时
- 批次大小: 100 users
- 保留期: 30天

---

### T014: 集成测试

**参考**: messaging-service/tests/batch_api_orphan_cleaner_test.rs

```rust
// backend/content-service/tests/content_cleaner_test.rs

#[tokio::test]
#[ignore]
async fn test_cleaner_deletes_user_posts() {
    // 1. 创建测试数据（posts, comments, likes）
    // 2. MockAuthClient 标记用户为已删除
    // 3. 运行 content_cleaner
    // 4. 验证用户内容被删除
}

#[tokio::test]
#[ignore]
async fn test_batch_api_n_plus_1_elimination() {
    // 验证 500 用户 → 5 批次 gRPC 调用
}
```

---

### T015: 监控指标

**新增 Prometheus 指标**:
```rust
// content-service/src/metrics.rs

lazy_static! {
    static ref CONTENT_CLEANER_DELETED_POSTS: IntCounter = register_int_counter!(
        "content_cleaner_deleted_posts_total",
        "Total posts deleted by content cleaner"
    ).unwrap();

    static ref CONTENT_CLEANER_DELETED_COMMENTS: IntCounter = register_int_counter!(
        "content_cleaner_deleted_comments_total",
        "Total comments deleted by content cleaner"
    ).unwrap();
}
```

**Grafana Dashboard**:
- Posts 删除速率
- Comments 删除速率
- batch API 调用延迟
- content_cleaner 执行周期

---

## 3. 验证清单

### 3.1 编译验证
- [ ] `cargo check --package content-service` 通过
- [ ] 集成测试编译: `cargo test --test content_cleaner_test --no-run`

### 3.2 功能验证
- [ ] content_cleaner 成功启动并运行
- [ ] batch API 调用正常（查看日志）
- [ ] 软删除用户的 posts/comments 被清理
- [ ] 正常用户的内容不受影响

### 3.3 性能验证
- [ ] 500 用户 → 5 批次 gRPC 调用（非 500 次）
- [ ] P99 延迟 < 100ms

---

## 4. 回滚计划

如果发现问题：

```bash
# 1. 回滚代码
git revert <commit-hash>

# 2. 恢复 FK 约束
psql -h content-db -U postgres -d content -f restore_fk.sql

# restore_fk.sql 内容：
ALTER TABLE posts ADD CONSTRAINT posts_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(id);
-- ... 其他表的 FK
```

---

## 5. 部署顺序

1. **Phase 2-1**: T012 (移除 FK) + T013 (content_cleaner)
2. **Phase 2-2**: T014 (集成测试)
3. **Phase 2-3**: T015 (监控指标)
4. **验证 1周**: 观察生产环境运行
5. **Phase 3 启动**: feed-service 整合

---

## 6. 风险评估

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 误删活跃用户内容 | 高 | 30天保留期 + 审计日志 |
| batch API 性能问题 | 中 | 分批处理（100个/批） |
| content_cleaner 失败 | 低 | 自动重试 + 告警 |

---

## 7. 依赖

- ✅ Phase 1 完成（messaging-service）
- ✅ auth-service gRPC API 稳定
- ✅ GrpcClientPool 已实现
- [ ] content-service PostgreSQL schema 稳定

---

## 8. 预计工时

- T012: 1小时（schema 修改 + 验证）
- T013: 4小时（content_cleaner 实现）
- T014: 3小时（集成测试）
- T015: 2小时（监控指标 + dashboard）
- **总计**: 10小时

---

## 9. 成功标准

- [ ] 所有 users FK 约束已移除
- [ ] content_cleaner 正常运行（1小时周期）
- [ ] 集成测试全部通过
- [ ] 生产环境运行 1 周无异常
- [ ] 监控指标正常
