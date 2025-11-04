# Test Fixtures

## 用途

Fixtures 包含测试环境初始化 SQL 脚本,在 Docker 容器启动时自动执行。

## 文件清单

### 1. `postgres-init.sql`

**用途**: 初始化 PostgreSQL 表结构,启用 CDC

**关键内容**:
```sql
-- 启用逻辑复制
ALTER SYSTEM SET wal_level = logical;

-- 创建帖子表
CREATE TABLE IF NOT EXISTS posts (
    id VARCHAR(50) PRIMARY KEY,
    author_id VARCHAR(50) NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 创建索引
CREATE INDEX idx_posts_author ON posts(author_id);
CREATE INDEX idx_posts_created ON posts(created_at DESC);

-- CDC 配置 (for Debezium)
ALTER TABLE posts REPLICA IDENTITY FULL;
```

### 2. `clickhouse-init.sql`

**用途**: 初始化 ClickHouse 表结构

**关键内容**:
```sql
-- 创建数据库
CREATE DATABASE IF NOT EXISTS nova_test;

-- Events 表 (事件流)
CREATE TABLE IF NOT EXISTS nova_test.events (
    event_id String,
    event_type String,
    user_id String,
    post_id String,
    timestamp DateTime64(3),
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
ORDER BY (event_id, timestamp)
SETTINGS index_granularity = 8192;

-- 去重引擎 (防止重复事件)
CREATE TABLE IF NOT EXISTS nova_test.events_dedup (
    event_id String,
    event_type String,
    user_id String,
    post_id String,
    timestamp DateTime64(3)
) ENGINE = ReplacingMergeTree()
ORDER BY event_id;

-- Posts 表 (CDC 同步)
CREATE TABLE IF NOT EXISTS nova_test.posts (
    id String,
    author_id String,
    content String,
    created_at DateTime
) ENGINE = MergeTree()
ORDER BY (id, created_at)
SETTINGS index_granularity = 8192;

-- Feed 物化视图
CREATE TABLE IF NOT EXISTS nova_test.feed_materialized (
    user_id String,
    post_id String,
    author_id String,
    score Float64,
    rank Int32,
    updated_at DateTime DEFAULT now()
) ENGINE = MergeTree()
ORDER BY (user_id, rank)
SETTINGS index_granularity = 8192;

-- CDC 镜像 (供 ClickHouse 推荐/Feed 查询使用)
CREATE TABLE IF NOT EXISTS nova_test.posts_cdc (
    id String,
    user_id String,
    content String,
    media_url Nullable(String),
    created_at DateTime,
    cdc_timestamp UInt64,
    is_deleted UInt8
) ENGINE = ReplacingMergeTree(cdc_timestamp)
ORDER BY id;

CREATE TABLE IF NOT EXISTS nova_test.comments_cdc (
    id String,
    post_id String,
    user_id String,
    content String,
    created_at DateTime,
    cdc_timestamp UInt64,
    is_deleted UInt8
) ENGINE = ReplacingMergeTree(cdc_timestamp)
ORDER BY id;

CREATE TABLE IF NOT EXISTS nova_test.likes_cdc (
    user_id String,
    post_id String,
    created_at DateTime,
    cdc_timestamp UInt64,
    is_deleted UInt8
) ENGINE = ReplacingMergeTree(cdc_timestamp)
ORDER BY (user_id, post_id);

-- 聚合视图(实时计算 Feed 排序所需信号)
CREATE VIEW IF NOT EXISTS nova_test.post_metrics_1h AS
SELECT * FROM post_metrics_1h; -- 详见 backend/clickhouse/init-db.sql

CREATE VIEW IF NOT EXISTS nova_test.user_author_90d AS
SELECT * FROM user_author_90d; -- 详见 backend/clickhouse/init-db.sql
```

## 实现原则

### Linus 风格

> "Keep it simple. Make it work."

- ❌ 不要创建复杂的 schema 迁移系统
- ❌ 不要定义完整的业务逻辑约束
- ✅ 只创建测试需要的最小结构
- ✅ 优先可读性,不是"最优性能"

### 数据隔离

每个测试应该:
1. 使用唯一 ID 前缀 (如 `test-dedup-001`, `evt-latency-001`)
2. 在 `cleanup()` 中删除自己的数据
3. 不依赖其他测试的数据

### 版本控制

如果 schema 需要变更:
1. 直接修改 `*-init.sql` 文件
2. 重建容器: `docker-compose down -v && docker-compose up -d`
3. 不需要迁移脚本 (测试环境每次重建)

## 扩展指南

### 添加新表

1. 在对应的 `*-init.sql` 文件中添加 `CREATE TABLE`
2. 重启服务: `docker-compose restart <service>`
3. 更新 Test Harness 客户端方法

### 添加初始数据

**不要**在 fixtures 中添加固定测试数据,应该在测试代码中动态生成:

```rust
// ❌ 坏: 依赖 fixture 中的固定数据
let feed = api.get_feed("user-1", 50).await;

// ✅ 好: 测试自己创建数据
let user_id = "user-test-dedup";
ch.execute("INSERT INTO feed_materialized ...").await;
let feed = api.get_feed(user_id, 50).await;
```

原因:
- 测试隔离: 固定数据可能被其他测试修改
- 可读性: 在测试代码中看到数据创建逻辑更清晰
- 灵活性: 每个测试可以创建自己需要的数据

## Linus 会说什么?

> "Don't over-design. The fixtures should be dumb and simple."

Fixtures 就是"把服务跑起来",不是构建完美的测试框架。

如果发现测试需要复杂的数据准备,问自己:
1. 这个测试是不是测太多东西了?
2. 能不能拆成两个更简单的测试?
3. 数据结构是不是设计得太复杂了?

好品味 > 完整性。
