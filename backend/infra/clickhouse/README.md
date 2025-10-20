# ClickHouse Analytics Infrastructure

**Version**: 1.0.0
**Status**: Production Ready
**Purpose**: Real-time event analytics and feed ranking for Nova Social Platform

---

## 📋 Overview

这是 Nova 平台的 ClickHouse OLAP 数据仓库配置，用于：

- **实时事件追踪**：用户行为数据（浏览、点赞、评论、分享）
- **Feed 排序**：基于用户偏好和内容质量的个性化推荐
- **数据同步**：通过 Kafka CDC 从 PostgreSQL 同步维度数据
- **性能优化**：P95 查询延迟 < 800ms（50 条候选帖子）

---

## 🏗️ Architecture

```
PostgreSQL (OLTP)          Kafka (Event Stream)
      |                           |
      |-- CDC (Debezium)          |-- Events Producer
      |                           |
      v                           v
   [Kafka Topics]          [Kafka Topics]
      |                           |
      +----------> ClickHouse <---+
                       |
                       v
          [Materialized Views] → [Aggregation Tables]
                       |
                       v
               [Feed Ranking Queries]
                       |
                       v
                  Rust Backend
```

### Data Flow

1. **OLTP → CDC → Kafka**
   - PostgreSQL 表（posts, follows, likes, comments）通过 Debezium CDC 同步到 Kafka
   - Kafka topics: `postgres.public.posts`, `postgres.public.follows`, etc.

2. **Event Producers → Kafka**
   - 用户行为事件（impression, view, like, comment, share）由 Rust 后端发送到 Kafka
   - Kafka topic: `events`

3. **Kafka → ClickHouse**
   - Kafka Engine 表实时消费 Kafka 数据
   - Materialized Views 将数据转换并聚合到目标表

4. **ClickHouse → Backend**
   - Rust 后端通过 HTTP/Native 协议查询 ClickHouse
   - 获取 Feed 排序所需的指标和亲和度数据

---

## 📁 File Structure

```
backend/infra/clickhouse/
├── schema.sql                  # 核心表定义（events, posts, follows, metrics）
├── kafka-engines.sql          # Kafka Engine 表配置（消费者设置）
├── materialized-views.sql     # 物化视图（实时聚合 + CDC 同步）
├── init.sh                    # 初始化脚本（幂等，可重复执行）
├── docker-compose.yml         # 本地开发环境（ClickHouse + Kafka + Zookeeper）
├── config.xml                 # ClickHouse 服务器配置
├── users.xml                  # 用户权限配置
├── queries/
│   ├── feed-ranking.sql       # Feed 排序查询模板（6 种场景）
│   └── test-data.sql          # 测试数据生成脚本
└── README.md                  # 本文档
```

---

## 🚀 Quick Start

### 1. 本地开发环境启动

```bash
# 进入 ClickHouse 目录
cd backend/infra/clickhouse

# 启动所有服务（ClickHouse + Kafka + Zookeeper）
docker-compose up -d

# 检查服务状态
docker-compose ps

# 查看 ClickHouse 日志
docker-compose logs -f clickhouse
```

**服务端口**：
- ClickHouse HTTP: `http://localhost:8123`
- ClickHouse Native: `localhost:9000`
- Kafka: `localhost:9092`
- Kafka UI: `http://localhost:8081`
- Zookeeper: `localhost:2181`

### 2. 初始化数据库

```bash
# 自动创建所有表、Kafka Engine、物化视图
./init.sh

# 或者手动执行（如果在容器内）
docker exec -it nova-clickhouse bash
clickhouse-client --multiquery < /schema.sql
clickhouse-client --multiquery < /kafka-engines.sql
clickhouse-client --multiquery < /materialized-views.sql
```

**验证初始化**：
```sql
-- 连接 ClickHouse
clickhouse-client

-- 查看所有表
SHOW TABLES FROM nova_analytics;

-- 查看物化视图
SELECT name, engine FROM system.tables
WHERE database = 'nova_analytics' AND name LIKE 'mv_%';

-- 查看 Kafka 消费者状态
SELECT * FROM system.kafka_consumers;
```

### 3. 加载测试数据

```bash
# 加载示例数据（用户、帖子、关注、事件）
clickhouse-client --multiquery < queries/test-data.sql

# 验证数据
clickhouse-client --query "SELECT count(*) FROM nova_analytics.events"
clickhouse-client --query "SELECT count(*) FROM nova_analytics.posts FINAL"
```

### 4. 测试 Feed 查询

```bash
# 打开 ClickHouse 客户端
clickhouse-client

# 执行个性化 Feed 查询（Bob 的 Feed）
USE nova_analytics;

SELECT
  p.id AS post_id,
  p.caption,
  sum(pm.likes_count) AS likes,
  sum(pm.comments_count) AS comments
FROM posts AS p FINAL
INNER JOIN follows AS f FINAL
  ON f.following_id = p.user_id
  AND f.follower_id = '22222222-2222-2222-2222-222222222222'
LEFT JOIN post_metrics_1h AS pm
  ON pm.post_id = p.id
WHERE p.status = 'published' AND p.__deleted = 0
GROUP BY p.id, p.caption
ORDER BY p.created_at DESC
LIMIT 10;
```

---

## 📊 Table Schemas

### 核心表

| 表名 | 引擎 | 用途 | 保留期 |
|------|------|------|--------|
| `events` | MergeTree | 原始事件数据 | 90 天 |
| `posts` | ReplacingMergeTree | 帖子维度表（CDC） | 永久 |
| `follows` | ReplacingMergeTree | 关注关系（CDC） | 永久 |
| `likes` | ReplacingMergeTree | 点赞记录（CDC） | 永久 |
| `comments` | ReplacingMergeTree | 评论数据（CDC） | 永久 |
| `post_metrics_1h` | SummingMergeTree | 小时级聚合指标 | 30 天 |
| `user_author_affinity` | ReplacingMergeTree | 用户-作者亲和度 | 90 天 |
| `hot_posts` | ReplacingMergeTree | 热门帖子缓存 | 2 天 |

### Kafka Engine 表

| 表名 | Topic | 消费组 | 格式 |
|------|-------|--------|------|
| `events_kafka` | `events` | `clickhouse-consumer-events` | JSONEachRow |
| `posts_kafka` | `postgres.public.posts` | `clickhouse-consumer-posts-cdc` | JSONEachRow |
| `follows_kafka` | `postgres.public.follows` | `clickhouse-consumer-follows-cdc` | JSONEachRow |
| `likes_kafka` | `postgres.public.likes` | `clickhouse-consumer-likes-cdc` | JSONEachRow |
| `comments_kafka` | `postgres.public.comments` | `clickhouse-consumer-comments-cdc` | JSONEachRow |

### 物化视图

| 视图名 | 源表 | 目标表 | 作用 |
|--------|------|--------|------|
| `mv_events_ingest` | `events_kafka` | `events` | 事件流消费 |
| `mv_post_metrics_1h` | `events` | `post_metrics_1h` | 小时聚合 |
| `mv_user_author_affinity` | `events` | `user_author_affinity` | 亲和度计算 |
| `mv_posts_cdc` | `posts_kafka` | `posts` | CDC 同步 |
| `mv_follows_cdc` | `follows_kafka` | `follows` | CDC 同步 |
| `mv_likes_cdc` | `likes_kafka` | `likes` | CDC 同步 |
| `mv_comments_cdc` | `comments_kafka` | `comments` | CDC 同步 |

---

## 🔍 Query Templates

### 1. 个性化 Feed（关注用户）

```sql
-- 参数化查询（Rust 后端使用）
-- {user_id}: 当前用户 UUID
-- {limit}: 返回数量（默认 50）
-- {lookback_hours}: 时间窗口（默认 72 小时）

SELECT
  p.id AS post_id,
  p.user_id AS author_id,
  p.caption,
  p.created_at,
  sum(pm.likes_count) AS likes,
  sum(pm.comments_count) AS comments,
  sum(pm.shares_count) AS shares,

  -- 综合得分（新鲜度 30% + 互动 40% + 亲和度 30%）
  round(
    0.30 * exp(-0.10 * dateDiff('hour', p.created_at, now())) +
    0.40 * log1p(sum(pm.likes_count) + 2*sum(pm.comments_count) + 3*sum(pm.shares_count)) / greatest(sum(pm.impressions_count), 1) +
    0.30 * coalesce(ua.interaction_count / 100.0, 0.01),
    4
  ) AS score
FROM posts AS p FINAL
INNER JOIN follows AS f FINAL
  ON f.following_id = p.user_id
  AND f.follower_id = {user_id:UUID}
  AND f.__deleted = 0
LEFT JOIN post_metrics_1h AS pm
  ON pm.post_id = p.id
  AND pm.metric_hour >= toStartOfHour(now()) - INTERVAL 24 HOUR
LEFT JOIN user_author_affinity AS ua
  ON ua.user_id = {user_id:UUID}
  AND ua.author_id = p.user_id
PREWHERE
  p.status = 'published'
  AND p.soft_delete IS NULL
  AND p.__deleted = 0
  AND p.created_at >= now() - INTERVAL {lookback_hours:UInt16} HOUR
GROUP BY p.id, p.user_id, p.caption, p.created_at, ua.interaction_count
ORDER BY score DESC
LIMIT {limit:UInt16};
```

### 2. 发现页（热门内容）

```sql
-- 使用预计算的热门帖子表
SELECT
  post_id,
  author_id,
  score,
  likes,
  comments,
  shares
FROM hot_posts
WHERE collected_at = (SELECT max(collected_at) FROM hot_posts)
ORDER BY score DESC
LIMIT 50;
```

### 3. 作者主页

```sql
-- 查看特定作者的所有帖子
SELECT
  p.id AS post_id,
  p.caption,
  p.created_at,
  sum(pm.likes_count) AS likes,
  sum(pm.comments_count) AS comments
FROM posts AS p FINAL
LEFT JOIN post_metrics_1h AS pm
  ON pm.post_id = p.id
PREWHERE
  p.user_id = {author_id:UUID}
  AND p.status = 'published'
  AND p.__deleted = 0
GROUP BY p.id, p.caption, p.created_at
ORDER BY p.created_at DESC
LIMIT 50;
```

更多查询模板详见 `queries/feed-ranking.sql`。

---

## ⚙️ Configuration

### 环境变量

**Docker Compose (`.env` 文件)**:
```bash
CLICKHOUSE_DB=nova_analytics
CLICKHOUSE_USER=default
CLICKHOUSE_PASSWORD=  # 留空表示无密码（开发环境）

KAFKA_BROKER=kafka:9092
KAFKA_GROUP_PREFIX=clickhouse-consumer
```

**生产环境**:
```bash
export CLICKHOUSE_HOST=clickhouse.prod.example.com
export CLICKHOUSE_PORT=9000
export CLICKHOUSE_PASSWORD=your_secure_password
export KAFKA_BROKER=kafka1.prod:9093,kafka2.prod:9093,kafka3.prod:9093
export KAFKA_GROUP_PREFIX=clickhouse-prod
```

### 性能调优

**ClickHouse 配置 (`config.xml`)**:
```xml
<!-- 最大内存限制（生产环境建议 16GB+） -->
<max_server_memory_usage>17179869184</max_server_memory_usage>

<!-- 最大并发查询数（根据 CPU 核心数调整） -->
<max_concurrent_queries>200</max_concurrent_queries>

<!-- 后台合并线程（SSD 建议 32+） -->
<background_pool_size>32</background_pool_size>
```

**Kafka Engine 调优**:
```sql
-- 高吞吐场景（增加消费者数量，匹配 Kafka 分区数）
kafka_num_consumers = 4  -- 如果 topic 有 4 个分区

-- 低延迟场景（减小批次大小）
kafka_max_block_size = 262144  -- 256KB

-- 严格一致性（禁止跳过错误消息）
kafka_skip_broken_messages = 0
```

---

## 🧪 Testing

### 单元测试（ClickHouse 内置）

```sql
-- 测试事件消费速率
SELECT
  toStartOfMinute(created_at) AS minute,
  count(*) AS events_ingested,
  count() / 60 AS events_per_second
FROM events
WHERE created_at >= now() - INTERVAL 1 HOUR
GROUP BY minute
ORDER BY minute DESC;

-- 测试物化视图延迟
SELECT
  name,
  total_rows,
  formatReadableSize(total_bytes) AS size,
  max(last_exception_time) AS last_error
FROM system.tables
WHERE database = 'nova_analytics' AND name LIKE 'mv_%'
GROUP BY name, total_rows, total_bytes;

-- 测试查询性能（带 EXPLAIN）
EXPLAIN
SELECT * FROM posts FINAL WHERE user_id = '...' LIMIT 10;
```

### 集成测试（Kafka 数据流）

```bash
# 1. 启动 Kafka 生产者
docker exec -it nova-kafka bash

# 2. 发送测试事件
kafka-console-producer.sh \
  --topic events \
  --bootstrap-server localhost:9092

# 粘贴 JSON 数据：
{"event_id":"123e4567-e89b-12d3-a456-426614174000","user_id":"223e4567-e89b-12d3-a456-426614174000","post_id":"323e4567-e89b-12d3-a456-426614174000","event_type":"view","author_id":"423e4567-e89b-12d3-a456-426614174000","dwell_ms":5000,"created_at":"2025-10-18 10:00:00"}

# 3. 验证 ClickHouse 接收
clickhouse-client --query "SELECT * FROM nova_analytics.events WHERE event_id = '123e4567-e89b-12d3-a456-426614174000'"
```

### 负载测试

```bash
# 使用 clickhouse-benchmark 工具
echo "SELECT * FROM nova_analytics.posts FINAL WHERE status = 'published' LIMIT 50" | \
  clickhouse-benchmark \
    --host=localhost \
    --port=9000 \
    --concurrency=10 \
    --iterations=1000

# 期望结果：
# - P95 < 800ms
# - P99 < 1500ms
# - QPS > 100
```

---

## 📈 Monitoring

### 关键指标

**系统级**:
```sql
-- 表大小统计
SELECT
  table,
  formatReadableSize(sum(bytes)) AS size,
  sum(rows) AS rows,
  count() AS partitions
FROM system.parts
WHERE database = 'nova_analytics' AND active
GROUP BY table
ORDER BY sum(bytes) DESC;

-- 分区数量（过多会影响性能）
SELECT
  table,
  count(DISTINCT partition) AS partition_count,
  min(partition) AS oldest_partition,
  max(partition) AS newest_partition
FROM system.parts
WHERE database = 'nova_analytics' AND active
GROUP BY table;
```

**查询性能**:
```sql
-- 慢查询（P95 > 1s）
SELECT
  query_duration_ms,
  query,
  read_rows,
  formatReadableSize(read_bytes) AS read_size,
  event_time
FROM system.query_log
WHERE event_date = today()
  AND type = 'QueryFinish'
  AND query_duration_ms > 1000
  AND query NOT LIKE '%system.%'
ORDER BY query_duration_ms DESC
LIMIT 20;
```

**Kafka 消费**:
```sql
-- 消费者状态检查
SELECT
  table,
  consumer_number,
  assignments.topic_name,
  assignments.partition_id,
  assignments.current_offset,
  exceptions.time AS last_error_time,
  exceptions.text AS last_error
FROM system.kafka_consumers
WHERE database = 'nova_analytics';
```

### Grafana Dashboard

推荐监控指标（使用 Prometheus + ClickHouse Exporter）:

1. **事件摄入速率**：`events_per_second`
2. **查询 P95 延迟**：`query_duration_p95_ms`
3. **Kafka 消费延迟**：`kafka_consumer_lag`
4. **表大小增长**：`table_bytes_growth_per_hour`
5. **磁盘使用率**：`disk_usage_percent`
6. **CPU/内存使用**：`cpu_percent`, `memory_usage_bytes`

---

## 🔧 Troubleshooting

### 问题 1: Kafka 消费停滞

**症状**：`system.kafka_consumers` 显示 offset 不增加

**排查步骤**：
```bash
# 1. 检查 Kafka broker 连接
docker exec -it nova-kafka kafka-broker-api-versions.sh --bootstrap-server localhost:9092

# 2. 检查 topic 是否存在
docker exec -it nova-kafka kafka-topics.sh --list --bootstrap-server localhost:9092

# 3. 查看消费者组状态
docker exec -it nova-kafka kafka-consumer-groups.sh \
  --describe \
  --group clickhouse-consumer-events \
  --bootstrap-server localhost:9092

# 4. 重置 ClickHouse Kafka offset（谨慎操作！）
clickhouse-client --query "DROP TABLE nova_analytics.events_kafka"
clickhouse-client --multiquery < kafka-engines.sql
```

### 问题 2: 查询性能慢

**症状**：Feed 查询 P95 > 2s

**优化方案**：
```sql
-- 1. 检查是否使用了 FINAL（强制去重，很慢）
-- 解决：定期执行 OPTIMIZE TABLE 预合并数据
OPTIMIZE TABLE posts FINAL;
OPTIMIZE TABLE follows FINAL;

-- 2. 检查 ORDER BY 是否利用了主键索引
-- 解决：确保查询的 ORDER BY 与表的 ORDER BY 一致

-- 3. 检查是否扫描了过多数据
-- 解决：使用 PREWHERE 过滤（比 WHERE 更高效）
SELECT * FROM posts
PREWHERE status = 'published' AND created_at >= now() - INTERVAL 72 HOUR
WHERE user_id IN (SELECT following_id FROM follows WHERE follower_id = '...');

-- 4. 检查 JOIN 是否产生了笛卡尔积
-- 解决：确保 JOIN 条件包含高选择性字段（如 UUID）
```

### 问题 3: 磁盘空间不足

**症状**：`Disk is almost full` 错误

**解决方案**：
```sql
-- 1. 手动清理过期分区（TTL 未自动触发）
ALTER TABLE events DROP PARTITION '202509';  -- 删除 2025 年 9 月数据

-- 2. 强制执行 TTL 合并
OPTIMIZE TABLE events FINAL;

-- 3. 检查哪些表占用空间最多
SELECT
  table,
  formatReadableSize(sum(bytes)) AS size,
  sum(rows) AS rows
FROM system.parts
WHERE database = 'nova_analytics' AND active
GROUP BY table
ORDER BY sum(bytes) DESC;

-- 4. 压缩历史数据（降低存储成本）
ALTER TABLE events MODIFY SETTING storage_policy = 'cold_storage';
```

### 问题 4: 物化视图数据不一致

**症状**：`post_metrics_1h` 的数据与 `events` 不匹配

**原因**：
- 物化视图只处理创建后的新数据
- 历史数据需要手动回填

**解决方案**：
```sql
-- 回填历史数据（一次性操作）
INSERT INTO post_metrics_1h
SELECT
  post_id,
  author_id,
  toStartOfHour(created_at) AS metric_hour,
  sumIf(1, event_type = 'like') AS likes_count,
  sumIf(1, event_type = 'comment') AS comments_count,
  sumIf(1, event_type = 'share') AS shares_count,
  sumIf(1, event_type = 'impression') AS impressions_count,
  sumIf(1, event_type = 'view') AS views_count,
  avgIf(dwell_ms, event_type IN ('view', 'impression') AND dwell_ms IS NOT NULL) AS avg_dwell_ms,
  uniqState(user_id) AS unique_viewers,
  now() AS updated_at
FROM events
WHERE post_id IS NOT NULL
  AND author_id IS NOT NULL
  AND created_at >= '2025-01-01' AND created_at < now()
GROUP BY post_id, author_id, metric_hour;
```

---

## 🚀 Production Deployment

### 部署清单

- [ ] 修改 `KAFKA_BROKER` 为生产 Kafka 集群地址
- [ ] 设置强密码（`CLICKHOUSE_PASSWORD`）
- [ ] 配置生产级资源限制（`config.xml` 中的内存/CPU）
- [ ] 启用 TLS 加密（Kafka 和 ClickHouse）
- [ ] 配置 ACL 权限控制（限制用户访问）
- [ ] 设置 Kafka topic 分区数（建议 8-16 分区）
- [ ] 配置监控告警（Grafana + Prometheus）
- [ ] 测试灾难恢复流程（备份 + 恢复）
- [ ] 设置自动备份策略（每日全量 + 小时增量）
- [ ] 压力测试（10K events/s + 100 QPS 查询）

### Kubernetes 部署（可选）

```yaml
# clickhouse-statefulset.yaml（示例）
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: clickhouse
spec:
  serviceName: clickhouse
  replicas: 3  # 高可用集群
  selector:
    matchLabels:
      app: clickhouse
  template:
    metadata:
      labels:
        app: clickhouse
    spec:
      containers:
      - name: clickhouse
        image: clickhouse/clickhouse-server:23.8
        ports:
        - containerPort: 9000
          name: native
        - containerPort: 8123
          name: http
        volumeMounts:
        - name: clickhouse-data
          mountPath: /var/lib/clickhouse
        env:
        - name: CLICKHOUSE_PASSWORD
          valueFrom:
            secretKeyRef:
              name: clickhouse-secret
              key: password
  volumeClaimTemplates:
  - metadata:
      name: clickhouse-data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 500Gi  # SSD 推荐
```

---

## 📚 References

- [ClickHouse Official Documentation](https://clickhouse.com/docs/)
- [Kafka Engine Documentation](https://clickhouse.com/docs/en/engines/table-engines/integrations/kafka)
- [Materialized Views Guide](https://clickhouse.com/docs/en/guides/developer/cascading-materialized-views)
- [ReplacingMergeTree](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replacingmergetree)
- [SummingMergeTree](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/summingmergetree)
- [Query Optimization](https://clickhouse.com/docs/en/guides/developer/optimize-query-performance)

---

## 📝 Changelog

### v1.0.0 (2025-10-18)

- 初始版本发布
- 支持 7 张核心表（events, posts, follows, likes, comments, metrics, affinity）
- 5 个 Kafka Engine 表（事件流 + CDC 同步）
- 7 个物化视图（实时聚合 + 维度同步）
- 6 个查询模板（个性化 Feed、发现页、作者主页、批量指标、亲和度、热榜）
- Docker Compose 开发环境
- 完整的测试数据和验证脚本

---

## 🤝 Contributing

如果你发现 bug 或有改进建议：

1. Fork 本仓库
2. 创建功能分支 (`git checkout -b feature/optimization`)
3. 提交更改 (`git commit -m 'Optimize feed ranking query'`)
4. 推送到分支 (`git push origin feature/optimization`)
5. 创建 Pull Request

---

## 📄 License

MIT License - 详见 LICENSE 文件

---

**维护者**: Nova Backend Team
**最后更新**: 2025-10-18
**状态**: 生产就绪 ✅
