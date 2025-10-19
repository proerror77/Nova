# Debezium CDC Infrastructure for Nova

## 架构概览

```
PostgreSQL (logical replication enabled)
   ↓ (WAL streaming via pgoutput plugin)
Debezium Connect (captures INSERT/UPDATE/DELETE)
   ↓ (produces messages to)
Kafka Topics (cdc.users, cdc.posts, cdc.follows, cdc.comments, cdc.likes)
   ↓ (consumed by)
Flink Jobs (real-time processing) → ClickHouse/Redis
```

## 快速启动（本地开发）

### 1. 启动基础设施

```bash
cd backend/infra/debezium
docker-compose up -d
```

等待所有服务健康：
```bash
# 检查所有容器状态
docker-compose ps

# 等待 Debezium Connect 就绪（约30秒）
until curl -f http://localhost:8083/; do sleep 2; done
```

### 2. 初始化 Kafka Topics

```bash
cd ../kafka
chmod +x topics-init.sh

# 开发环境
./topics-init.sh

# 生产环境
ENV=prod REPLICATION_FACTOR=3 KAFKA_BROKER=kafka-prod:9092 ./topics-init.sh
```

### 3. 部署 Debezium Connector

```bash
cd ../debezium

# 注册 Postgres CDC Connector
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @postgres-connector.json

# 验证 Connector 状态
curl http://localhost:8083/connectors/nova-postgres-cdc-connector/status | jq
```

预期输出：
```json
{
  "name": "nova-postgres-cdc-connector",
  "connector": {
    "state": "RUNNING",
    "worker_id": "debezium:8083"
  },
  "tasks": [
    {
      "id": 0,
      "state": "RUNNING",
      "worker_id": "debezium:8083"
    }
  ]
}
```

### 4. 验证 CDC 工作

插入测试数据到 PostgreSQL：
```bash
docker exec -it nova-postgres psql -U postgres -d nova -c \
  "INSERT INTO users (username, email) VALUES ('test_user', 'test@example.com') RETURNING id;"
```

消费 Kafka 消息验证：
```bash
docker exec -it nova-kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:29092 \
  --topic cdc.users \
  --from-beginning \
  --max-messages 1
```

预期输出（JSON 格式）：
```json
{
  "id": 123,
  "username": "test_user",
  "email": "test@example.com",
  "created_at": 1697123456789,
  "__op": "c",
  "__source_ts_ms": 1697123456789,
  "__source_db": "nova",
  "__source_table": "users"
}
```

## 监控与管理

### Kafka UI
访问 http://localhost:8080 查看：
- Topics 消息流量
- Consumer Group Lag
- Debezium Connector 状态

### 健康检查命令

```bash
# 1. Debezium Connect 健康
curl http://localhost:8083/ | jq

# 2. 列出所有 Connectors
curl http://localhost:8083/connectors | jq

# 3. 查看 Connector 详细配置
curl http://localhost:8083/connectors/nova-postgres-cdc-connector | jq

# 4. 查看 Connector 任务状态
curl http://localhost:8083/connectors/nova-postgres-cdc-connector/status | jq

# 5. 查看 Kafka Topics
docker exec nova-kafka kafka-topics.sh --bootstrap-server localhost:9092 --list

# 6. 查看 Topic 详细信息
docker exec nova-kafka kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --describe \
  --topic cdc.posts

# 7. 检查 PostgreSQL 复制槽
docker exec nova-postgres psql -U postgres -d nova -c \
  "SELECT slot_name, plugin, slot_type, active FROM pg_replication_slots;"
```

### 查看 CDC 日志

```bash
# Debezium Connect 日志
docker logs -f nova-debezium

# 过滤错误日志
docker logs nova-debezium 2>&1 | grep -i error

# 查看 Kafka 日志
docker logs -f nova-kafka
```

## 故障排查

### 问题 1: Connector 状态为 FAILED

**症状**：
```bash
curl http://localhost:8083/connectors/nova-postgres-cdc-connector/status
# "state": "FAILED"
```

**排查步骤**：
```bash
# 1. 查看详细错误
curl http://localhost:8083/connectors/nova-postgres-cdc-connector/status | jq '.tasks[0].trace'

# 2. 常见原因：
# - PostgreSQL 未启用 logical replication
docker exec nova-postgres psql -U postgres -c "SHOW wal_level;"
# 预期: logical

# - 表不存在
docker exec nova-postgres psql -U postgres -d nova -c "\dt public.*"

# 3. 重启 Connector
curl -X POST http://localhost:8083/connectors/nova-postgres-cdc-connector/restart
```

### 问题 2: Kafka Topic 未收到消息

**排查步骤**：
```bash
# 1. 检查 Connector 是否在运行
curl http://localhost:8083/connectors/nova-postgres-cdc-connector/status | jq '.connector.state'

# 2. 检查 PostgreSQL 是否有数据变更
docker exec nova-postgres psql -U postgres -d nova -c \
  "SELECT COUNT(*) FROM users;"

# 3. 检查 Debezium 是否在读取 WAL
docker exec nova-postgres psql -U postgres -d nova -c \
  "SELECT * FROM pg_replication_slots WHERE slot_name = 'debezium_nova_slot';"

# 4. 手动消费 Topic（从最早偏移量）
docker exec nova-kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic cdc.users \
  --from-beginning
```

### 问题 3: Replication Slot 占用过多磁盘空间

**症状**：
```bash
docker exec nova-postgres psql -U postgres -d nova -c \
  "SELECT slot_name, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS lag
   FROM pg_replication_slots;"
# lag > 10GB
```

**解决方案**：
```bash
# 1. 检查 Connector 是否在运行
curl http://localhost:8083/connectors/nova-postgres-cdc-connector/status

# 2. 如果 Connector 停止且不再需要，删除 slot
docker exec nova-postgres psql -U postgres -d nova -c \
  "SELECT pg_drop_replication_slot('debezium_nova_slot');"

# 3. 如果需要保留但想清理 WAL，重启 Connector
curl -X POST http://localhost:8083/connectors/nova-postgres-cdc-connector/restart
```

### 问题 4: Snapshot 阶段过长（大表初始同步）

**症状**：
初次启动 Connector 时，`cdc.posts` 表数据量大（数百万行），Snapshot 需要几小时

**优化方案**：

1. **使用增量 Snapshot（Debezium 2.3+）**：
```json
{
  "snapshot.mode": "initial",
  "snapshot.fetch.size": "10240",
  "snapshot.max.threads": "4",
  "incremental.snapshot.chunk.size": "2048"
}
```

2. **仅捕获增量（跳过历史数据）**：
```json
{
  "snapshot.mode": "schema_only"
}
```

3. **并行 Snapshot（手动分区）**：
```bash
# 创建多个 Connector，每个监听不同 ID 范围
# Connector 1: WHERE id BETWEEN 0 AND 1000000
# Connector 2: WHERE id BETWEEN 1000001 AND 2000000
```

## 配置调优

### 生产环境建议

**1. Debezium Connector 配置**：
```json
{
  "tasks.max": "3",
  "max.batch.size": "4096",
  "max.queue.size": "16384",
  "poll.interval.ms": "100",
  "heartbeat.interval.ms": "5000",
  "slot.drop.on.stop": "false"
}
```

**2. Kafka Topics 配置**：
```bash
# 高吞吐表（posts, likes）
--config retention.ms=2592000000  # 30 天
--config segment.ms=3600000        # 1 小时滚动
--config min.insync.replicas=2     # 至少 2 个副本确认

# 低吞吐表（users, follows）
--config retention.ms=604800000    # 7 天
--config cleanup.policy=compact    # 日志压缩
```

**3. PostgreSQL WAL 配置**：
```bash
# postgresql.conf
wal_level = logical
max_wal_senders = 20
max_replication_slots = 20
wal_keep_size = 1GB  # PostgreSQL 13+
```

### 成本优化

**1. Kafka 存储成本**：
```bash
# 使用 Tiered Storage（Kafka 3.6+）
--config remote.storage.enable=true
--config local.retention.ms=86400000  # 本地只保留 1 天
--config retention.ms=2592000000      # 远程保留 30 天
```

**2. Debezium 资源限制**：
```yaml
# docker-compose.yml
debezium:
  deploy:
    resources:
      limits:
        cpus: '2'
        memory: 2G
      reservations:
        cpus: '1'
        memory: 1G
```

## 数据一致性保证

### Exactly-Once 语义

Debezium 提供 **At-Least-Once** 保证，需在下游（Flink）实现去重：

**Flink 去重示例**（基于主键）：
```java
StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
env.enableCheckpointing(10000); // 10s checkpoint

DataStream<RowData> deduplicated = cdcStream
    .keyBy(row -> row.getField("id"))
    .process(new DeduplicateFunction()); // 保留最新 ts_ms 的记录
```

### Tombstone 处理（软删除）

当表有 `deleted_at` 字段时：
```json
{
  "id": 123,
  "username": "deleted_user",
  "deleted_at": "2024-10-18T10:00:00Z",
  "__op": "u"
}
```

紧接着 Debezium 会发送 Tombstone（用于 Kafka Compaction）：
```json
{
  "id": 123,
  "value": null
}
```

**Flink 处理逻辑**：
```java
if (record.getString("deleted_at") != null) {
    // 软删除：更新 ClickHouse 状态为 deleted
    clickhouseWriter.markAsDeleted(record.getLong("id"));
}
```

## 迁移与升级

### Connector 版本升级

```bash
# 1. 暂停 Connector
curl -X PUT http://localhost:8083/connectors/nova-postgres-cdc-connector/pause

# 2. 备份当前偏移量
docker exec nova-kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic debezium_offsets \
  --from-beginning > offsets-backup.json

# 3. 更新 Debezium 镜像版本
# 编辑 docker-compose.yml: debezium/connect:2.5

# 4. 重启
docker-compose up -d debezium

# 5. 恢复 Connector
curl -X PUT http://localhost:8083/connectors/nova-postgres-cdc-connector/resume
```

### 灾难恢复

**场景**：Debezium 宕机 2 小时，PostgreSQL 删除了 replication slot

**恢复步骤**：
```bash
# 1. 重新创建 Connector（会自动创建新 slot）
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @postgres-connector.json

# 2. 选择 Snapshot 模式
# Option A: 重新全量同步（数据量小）
"snapshot.mode": "initial"

# Option B: 仅同步增量（接受数据丢失）
"snapshot.mode": "schema_only"

# Option C: 从 Kafka 偏移量恢复（推荐）
"snapshot.mode": "recovery"
```

## 安全最佳实践

### 1. 最小权限原则

```sql
-- 创建只读 CDC 用户
CREATE USER debezium_user WITH PASSWORD 'secure_password' REPLICATION;

-- 仅授权需要的表
GRANT SELECT ON public.users TO debezium_user;
GRANT SELECT ON public.posts TO debezium_user;
GRANT SELECT ON public.follows TO debezium_user;
GRANT SELECT ON public.comments TO debezium_user;
GRANT SELECT ON public.likes TO debezium_user;

-- 允许创建 publication
GRANT CREATE ON DATABASE nova TO debezium_user;
```

### 2. 网络隔离

生产环境建议：
- Debezium Connect 运行在独立 VPC
- PostgreSQL 仅对 Debezium 开放 5432 端口
- Kafka 使用 SASL/SSL 加密传输

### 3. 敏感数据脱敏

对于 `users.email` 等 PII 数据：
```json
{
  "transforms": "maskEmail",
  "transforms.maskEmail.type": "org.apache.kafka.connect.transforms.MaskField$Value",
  "transforms.maskEmail.fields": "email",
  "transforms.maskEmail.replacement": "***@***.com"
}
```

或在 Flink 中处理：
```java
String maskedEmail = email.replaceAll("(^[^@]{3})[^@]+(@.*)", "$1***$2");
```

## 性能基准

### 本地开发环境

- **硬件**: M1 Mac, 16GB RAM
- **吞吐量**:
  - 单表 INSERT: ~5000 rows/s
  - 混合 CRUD: ~3000 ops/s
  - Kafka 消费延迟: <100ms (p99)

### 生产环境预估（AWS）

- **配置**:
  - Debezium: 3x m5.xlarge (4 vCPU, 16GB)
  - Kafka: 5x m5.2xlarge (8 vCPU, 32GB)
  - PostgreSQL: db.r6g.4xlarge (16 vCPU, 128GB)

- **吞吐量**:
  - CDC 捕获: ~50,000 changes/s
  - Kafka 写入: ~100MB/s
  - 端到端延迟: <500ms (p99)

- **成本**: 约 $3,500/月（不含存储和数据传输）

## 参考资料

- [Debezium PostgreSQL Connector 官方文档](https://debezium.io/documentation/reference/2.4/connectors/postgresql.html)
- [Kafka Topic 配置最佳实践](https://kafka.apache.org/documentation/#topicconfigs)
- [PostgreSQL 逻辑复制详解](https://www.postgresql.org/docs/current/logical-replication.html)
- [Flink CDC Connectors](https://github.com/ververica/flink-cdc-connectors)

## 联系与支持

遇到问题？
1. 检查本文档的"故障排查"章节
2. 查看 Debezium 日志: `docker logs nova-debezium`
3. 提交 Issue 到项目仓库，附带完整日志和配置
