# Search Service

基础搜索服务，提供用户、帖子和话题标签的搜索功能。

## 特性

- **用户搜索**: 在 username 和 email 字段搜索
- **帖子搜索**: 优先使用 Elasticsearch 多字段检索（若未配置则回退到 PostgreSQL 全文搜索）
- **话题标签搜索**: 从帖子 caption 中提取并搜索话题标签
- **Redis 缓存**: 搜索结果缓存 24 小时，显著提升响应速度
- **相关性排序**: 帖子搜索按相关性（ts_rank）和时间排序
- **Kafka 事件同步**: 自动消费 `nova.message.events`（event_type: message.persisted/message.deleted），并兼容 `message_persisted`/`message_deleted`
- Axum web 框架
- 健康检查端点

## 运行

### 环境变量

```bash
DATABASE_URL=postgresql://user:password@localhost:5432/nova
REDIS_URL=redis://127.0.0.1:6379  # 可选，默认 redis://127.0.0.1:6379
ELASTICSEARCH_URL=http://localhost:9200        # 可选，启用 Elasticsearch 作为搜索后端
ELASTICSEARCH_POST_INDEX=nova_posts            # 可选，默认 nova_posts
ELASTICSEARCH_MESSAGE_INDEX=nova_messages      # 可选，默认 nova_messages
KAFKA_BROKERS=localhost:9092                   # 可选，启用 Kafka 消费 message 事件
KAFKA_MESSAGE_EVENTS_TOPIC=nova.message.events
KAFKA_MESSAGE_PERSISTED_TOPIC=message_persisted
KAFKA_MESSAGE_DELETED_TOPIC=message_deleted
KAFKA_SEARCH_GROUP_ID=nova-search-service
PORT=8081  # 可选，默认 8081
```

### 启动服务

```bash
# 确保 PostgreSQL 和 Redis 运行中
cd backend/search-service

# 应用数据库迁移（添加全文搜索索引）
psql $DATABASE_URL -f migrations/001_add_fulltext_index.sql

# 启动服务
cargo run
```

## API 端点

### 健康检查

```bash
GET /health
```

响应: `"OK"`

### 搜索用户

```bash
GET /api/v1/search/users?q=test&limit=20
```

**参数**:
- `q`: 搜索查询（必填，默认为空字符串）
- `limit`: 返回结果数量（可选，默认 20）

**响应示例**:
```json
{
  "query": "test",
  "results": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "username": "testuser",
      "email": "test@example.com",
      "created_at": "2025-01-15T10:30:00Z"
    }
  ],
  "count": 1
}
```

### 搜索帖子

```bash
GET /api/v1/search/posts?q=sunset&limit=20
```

**参数**:
- `q`: 搜索查询（必填，默认为空字符串）
- `limit`: 返回结果数量（可选，默认 20）

**响应示例**:
```json
{
  "query": "sunset",
  "results": [
    {
      "id": "660e8400-e29b-41d4-a716-446655440000",
      "user_id": "550e8400-e29b-41d4-a716-446655440000",
      "caption": "Beautiful sunset at the beach #sunset #nature",
      "created_at": "2025-01-20T18:45:00Z"
    }
  ],
  "count": 1
}
```

### 搜索话题标签

```bash
GET /api/v1/search/hashtags?q=tech&limit=20
```

**参数**:
- `q`: 搜索查询（必填，默认为空字符串）
- `limit`: 返回结果数量（可选，默认 20）

**响应示例**:
```json
{
  "query": "tech",
  "results": [
    {
      "tag": "technology",
      "count": 5
    },
    {
      "tag": "tech",
      "count": 3
    }
  ],
  "count": 2
}
```

**注意**: 话题标签按使用次数降序排序。

### 清除搜索缓存

```bash
POST /api/v1/search/clear-cache
```

清除所有 Redis 中缓存的搜索结果。

```bash
curl -X POST http://localhost:8081/api/v1/search/clear-cache
```

**响应示例**:
```json
{
  "message": "Search cache cleared",
  "deleted_count": 42
}
```

### 重新索引帖子（Elasticsearch）

```bash
curl -X POST http://localhost:8081/api/v1/search/posts/reindex \
     -H "Content-Type: application/json" \
     -d '{"batch_size": 500, "offset": 0}'
```

**响应示例**:

```json
{
  "message": "Reindex completed",
  "indexed_count": 500,
  "batch_size": 500,
  "offset": 0
}
```

## 测试

### 使用测试脚本

完整的测试套件：

```bash
./test-fulltext-cache.sh
```

### 使用 curl 测试

```bash
# 健康检查
curl http://localhost:8081/health

# 搜索用户
curl "http://localhost:8081/api/v1/search/users?q=test"

# 搜索帖子（全文搜索 + 缓存）
curl "http://localhost:8081/api/v1/search/posts?q=sunset"

# 搜索话题标签
curl "http://localhost:8081/api/v1/search/hashtags?q=tech"

# 清除缓存
curl -X POST http://localhost:8081/api/v1/search/clear-cache
```

## 架构

- **Web 框架**: Axum 0.7
- **数据库**: PostgreSQL (通过 SQLx)
- **缓存**: Redis (通过 redis-rs)
- **异步运行时**: Tokio
- **搜索方式**: PostgreSQL 全文搜索（tsvector/tsquery）

## 限制和未来改进

当前实现已支持全文搜索和 Redis 缓存。未来改进方向：

1. ✅ **全文搜索**: 已实现 PostgreSQL tsvector/tsquery
2. ✅ **搜索排名**: 已按相关性（ts_rank）排序
3. ✅ **缓存**: 已实现 Redis 缓存（24 小时 TTL）
4. **自动缓存失效**: 帖子更新/删除时自动清除相关缓存
5. **多语言支持**: 支持英语以外的全文搜索配置
6. **话题标签表**: 创建独立的 hashtags 表用于高效查询和统计
7. **分页**: 添加 cursor-based 分页支持
8. **查询规范化**: 缓存前规范化查询（小写、trim）
9. **Elasticsearch**: 若配置 `ELASTICSEARCH_URL` 即启用；否则回退 PostgreSQL 全文搜索

详细实现文档：[FULLTEXT_SEARCH_IMPLEMENTATION.md](./FULLTEXT_SEARCH_IMPLEMENTATION.md)

## 数据库查询逻辑

### 用户搜索
- 在 `username` 和 `email` 字段使用 ILIKE
- 过滤条件: `deleted_at IS NULL` 和 `is_active = true`
- 按创建时间倒序排列

### 帖子搜索
- 使用 PostgreSQL 全文搜索（`to_tsvector` 和 `plainto_tsquery`）
- 按相关性排序（`ts_rank`），然后按创建时间排序
- 过滤条件: `soft_delete IS NULL` 和 `status = 'published'`
- Redis 缓存：缓存键 `search:posts:{query}`，TTL 24 小时

### 话题标签搜索
- 从帖子的 `caption` 中提取以 `#` 开头的词
- 在内存中统计每个标签的出现次数
- 按出现次数倒序排列
