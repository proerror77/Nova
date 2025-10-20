# Nova Infrastructure

实时热榜系统的基础设施配置与部署脚本。

## 目录结构

```
backend/infra/
├── debezium/                  # Debezium CDC 配置
│   ├── docker-compose.yml     # 本地开发环境（Postgres + Kafka + Debezium）
│   ├── postgres-connector.json # CDC 连接器配置
│   ├── init-postgres.sql      # PostgreSQL 初始化脚本（启用逻辑复制）
│   ├── Makefile               # 常用管理命令
│   ├── .env.example           # 环境变量模板
│   └── README.md              # 详细文档与故障排查
│
└── kafka/                     # Kafka Topics 配置
    └── topics-init.sh         # 初始化所有 CDC 和 Events topics
```

## 快速开始（5 分钟）

### 前置条件
- Docker Desktop 已安装并运行
- 可用端口：5432, 2181, 9092, 8083, 8080
- 至少 4GB 可用内存

### 一键启动

```bash
cd backend/infra/debezium

# 1. 启动所有服务
make start

# 2. 等待服务就绪（约 30 秒）
make health

# 3. 初始化 Kafka Topics
make topics

# 4. 部署 Debezium Connector
make deploy-connector

# 5. 测试 CDC 是否工作
make test-cdc
```

预期输出：
```json
{
  "id": 1,
  "username": "test_user_1697123456",
  "email": "test@example.com",
  "__op": "c",
  "__source_ts_ms": 1697123456789
}
```

### 访问服务

- **Kafka UI**: http://localhost:8080 （查看 Topics 和 Consumer Groups）
- **Debezium REST API**: http://localhost:8083 （管理 Connectors）
- **PostgreSQL**: `localhost:5432` （用户名/密码: postgres/postgres）

## 核心组件

### 1. Debezium CDC Connector

**功能**：捕获 PostgreSQL 表变更（INSERT/UPDATE/DELETE），实时发送到 Kafka

**监听的表**：
- `public.users`
- `public.posts`
- `public.follows`
- `public.comments`
- `public.likes`

**输出 Kafka Topics**：
- `cdc.users` (3 分区)
- `cdc.posts` (10 分区，高吞吐)
- `cdc.follows` (5 分区)
- `cdc.comments` (5 分区)
- `cdc.likes` (8 分区)

**关键配置**：
- 快照模式：`initial`（首次全量同步）
- 插件：`pgoutput`（PostgreSQL 原生逻辑复制）
- Tombstones：启用（用于软删除标记）
- 心跳：10 秒（防止 replication slot 超时）

### 2. Kafka Topics

**CDC Topics**：
- 日志压缩：`cleanup.policy=compact`（保留最新状态）
- 保留时间：7-30 天
- 压缩算法：Snappy

**Events Topic**：
- 分区数：开发环境 10 个，生产环境 300 个
- 保留时间：3 天
- 压缩算法：LZ4（更快）
- 用途：后续由 Events API 写入用户行为事件

### 3. PostgreSQL 逻辑复制

**配置**：
```sql
wal_level = logical
max_wal_senders = 10
max_replication_slots = 10
```

**Replication Slot**: `debezium_nova_slot`（持久化，Connector 重启不丢数据）

## 常用命令

```bash
# 服务管理
make start              # 启动所有服务
make stop               # 停止所有服务
make restart            # 重启所有服务
make status             # 查看服务状态
make logs               # 查看 Debezium 日志
make clean              # 清理所有容器和数据（危险操作！）

# Connector 管理
make deploy-connector   # 部署 CDC Connector
make delete-connector   # 删除 Connector
make health             # 健康检查

# 调试
make test-cdc           # 插入测试数据并验证 CDC
make consume-users      # 消费 cdc.users topic
make consume-posts      # 消费 cdc.posts topic
make psql               # 连接到 PostgreSQL
make kafka-ui           # 打开 Kafka UI
```

## 架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                        Application Layer                        │
│  (Go REST API, gRPC Events API, Flink Jobs)                     │
└───────────────┬─────────────────────────────────────────────────┘
                │
                ├─ Write ─────────┐
                │                 ▼
                │         ┌──────────────┐
                │         │ PostgreSQL   │
                │         │ (Source DB)  │
                │         └───────┬──────┘
                │                 │ WAL Streaming (pgoutput)
                │                 ▼
                │         ┌──────────────┐
                │         │  Debezium    │
                │         │  Connect     │
                │         └───────┬──────┘
                │                 │ Produce CDC Events
                │                 ▼
                └─ Produce ───▶ ┌──────────────┐
                                │    Kafka     │
                                │ (Message Bus)│
                                └───────┬──────┘
                                        │ Consume
                                        ▼
                                ┌──────────────┐
                                │ Flink Jobs   │
                                │ (CDC + Events│
                                │  Processing) │
                                └───────┬──────┘
                                        │ Write
                                        ▼
                        ┌───────────────┴───────────────┐
                        ▼                               ▼
                ┌──────────────┐              ┌──────────────┐
                │ ClickHouse   │              │    Redis     │
                │ (Analytics)  │              │ (Hot Ranking)│
                └──────────────┘              └──────────────┘
```

## 数据流示例

### 1. 用户发帖（CDC 捕获）

```
1. User POST /api/posts → Go API
2. Go API INSERT INTO posts → PostgreSQL
3. PostgreSQL WAL → Debezium Connector
4. Debezium → Kafka cdc.posts topic:
   {
     "id": 123,
     "user_id": 456,
     "content": "Hello World",
     "created_at": 1697123456789,
     "__op": "c",
     "__source_ts_ms": 1697123456789
   }
5. Flink CDC Job consumes → Write to ClickHouse posts table
6. Flink Aggregation Job → Update Redis hot ranking
```

### 2. 用户点赞（高频操作）

```
1. User POST /api/likes → Go API
2. Go API INSERT INTO likes → PostgreSQL
3. CDC → Kafka cdc.likes (8 partitions for high throughput)
4. Flink Job aggregates likes_count → Redis sorted set
```

## 监控指标

### 关键 Metrics

**Debezium**：
- `debezium.connector.task.state`（必须 = RUNNING）
- `debezium.connector.records.lag`（延迟记录数，应 < 1000）
- `debezium.connector.milliseconds.behind.source`（延迟时间，应 < 1000ms）

**Kafka**：
- `kafka.consumer.lag`（消费者延迟，应 < 10000）
- `kafka.topic.partitions`（分区数，确认是否需要扩容）
- `kafka.topic.bytes.in.per.sec`（写入速率）

**PostgreSQL**：
- `pg_replication_slots.restart_lsn`（WAL 位置，防止磁盘爆满）
- `pg_stat_replication.state`（复制状态，必须 = streaming）

### 健康检查脚本

```bash
#!/bin/bash
# health-check.sh

# 1. Debezium Connector
curl -s http://localhost:8083/connectors/nova-postgres-cdc-connector/status | \
  jq -e '.connector.state == "RUNNING" and .tasks[0].state == "RUNNING"'

# 2. Kafka Topics
docker exec nova-kafka kafka-topics.sh --bootstrap-server localhost:9092 --list | \
  grep -E '^(cdc\.users|cdc\.posts|events)$' | wc -l | grep -q 6

# 3. PostgreSQL Replication Slot
docker exec nova-postgres psql -U postgres -d nova -tAc \
  "SELECT active FROM pg_replication_slots WHERE slot_name = 'debezium_nova_slot';" | \
  grep -q 't'

echo "All checks passed!"
```

## 故障排查

### 常见问题

| 症状 | 原因 | 解决方案 |
|------|------|----------|
| Connector 状态 FAILED | PostgreSQL 未启用逻辑复制 | 检查 `SHOW wal_level;` 是否为 `logical` |
| Kafka Topic 无消息 | Connector 未运行或表无数据变更 | `make health` 检查状态，`make test-cdc` 插入测试数据 |
| Replication Slot 占用磁盘 | Connector 长时间离线，WAL 未清理 | 重启 Connector 或删除旧 slot |
| 消费延迟高 | Flink Job 处理能力不足 | 增加 Flink 并行度或 Kafka 分区数 |

详细排查步骤见：[backend/infra/debezium/README.md](/Users/proerror/Documents/nova/backend/infra/debezium/README.md)

## 生产环境部署

### 前置条件

1. **PostgreSQL 配置**：
   ```sql
   ALTER SYSTEM SET wal_level = 'logical';
   ALTER SYSTEM SET max_wal_senders = 20;
   ALTER SYSTEM SET max_replication_slots = 20;
   ALTER SYSTEM SET wal_keep_size = '1GB';
   SELECT pg_reload_conf();
   ```

2. **Kafka 集群**：
   - 至少 3 个 Broker（副本因子 = 3）
   - Zookeeper 3 节点集群
   - 推荐：AWS MSK 或 Confluent Cloud

3. **Debezium Connect**：
   - 部署在 Kubernetes 或 ECS
   - 至少 2 个实例（高可用）
   - 资源：2 vCPU, 4GB RAM per instance

### 部署步骤

```bash
# 1. 设置环境变量
export DB_HOST=prod-postgres.example.com
export DB_USER=debezium_user
export DB_PASSWORD=<secure_password>
export KAFKA_BROKER=kafka-prod-1:9092,kafka-prod-2:9092,kafka-prod-3:9092
export REPLICATION_FACTOR=3
export ENV=prod

# 2. 初始化 Topics（一次性）
cd backend/infra/kafka
./topics-init.sh

# 3. 部署 Connector（使用 Debezium 运维工具）
curl -X POST http://debezium-prod:8083/connectors \
  -H "Content-Type: application/json" \
  -d @postgres-connector.json
```

### 成本估算（AWS）

**月度成本**：约 $3,500

- **Debezium**: 3x m5.xlarge = $450/月
- **Kafka (MSK)**: 5x kafka.m5.2xlarge = $2,800/月
- **数据传输**: ~$200/月
- **存储 (EBS)**: ~$50/月

**优化建议**：
- 使用 Kafka Tiered Storage（降低 50% 存储成本）
- Spot Instances 用于 Debezium（降低 60% 计算成本）

## 下一步

1. **集成 Flink Jobs**：
   - 创建 Flink CDC 消费者（Flink SQL 或 DataStream API）
   - 实时写入 ClickHouse 和 Redis

2. **Events API**：
   - 实现高吞吐的事件写入 API（gRPC）
   - 直接写入 Kafka `events` topic

3. **监控告警**：
   - 接入 Prometheus + Grafana
   - 配置 PagerDuty 告警（Connector 失败、延迟 > 5s）

4. **灾难恢复演练**：
   - 测试 Connector 故障恢复
   - 测试 Kafka 分区重新平衡
   - 测试 PostgreSQL 主从切换

## 参考文档

- [Debezium 详细文档](/Users/proerror/Documents/nova/backend/infra/debezium/README.md)
- [Debezium 官方文档](https://debezium.io/documentation/)
- [Kafka 配置参考](https://kafka.apache.org/documentation/)
- [PostgreSQL 逻辑复制](https://www.postgresql.org/docs/current/logical-replication.html)
