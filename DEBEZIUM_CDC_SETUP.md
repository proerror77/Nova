# Debezium CDC Setup Guide

## Overview

配置 Debezium PostgreSQL 连接器实时捕获 PostgreSQL 数据变更，将其流入 Kafka，最后由 user-service 消费并写入 ClickHouse。

```
PostgreSQL → Debezium CDC → Kafka (cdc.posts, cdc.follows, etc.)
                                        ↓
                          user-service (CDC Consumer)
                                        ↓
                                  ClickHouse
                                        ↓
                            Feed Ranking Queries
```

---

## 部署步骤

### 1. 启动 Debezium 容器

```bash
docker-compose up -d debezium
```

**验证**：
```bash
curl -s http://localhost:8083/connector-plugins | jq '.[].class' | grep Postgres
```

应该返回：`"io.debezium.connector.postgresql.PostgresConnector"`

### 2. 创建 PostgreSQL 连接器

使用 REST API 创建连接器：

```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -d @backend/debezium-connector-config.json \
  http://localhost:8083/connectors
```

### 3. 验证连接器状态

```bash
# 检查所有连接器
curl -s http://localhost:8083/connectors | jq .

# 检查特定连接器状态
curl -s http://localhost:8083/connectors/postgres-cdc-connector/status | jq .
```

应该返回：
```json
{
  "connector": {
    "state": "RUNNING",
    "worker_id": "..."
  },
  "tasks": [
    {
      "id": 0,
      "state": "RUNNING",
      "worker_id": "..."
    }
  ]
}
```

### 4. 验证 Kafka 主题

```bash
docker-compose exec kafka kafka-topics --bootstrap-server localhost:9092 --list | grep cdc
```

应该看到：
```
cdc.comments
cdc.follows
cdc.likes
cdc.posts
```

### 5. 验证 user-service CDC 消费者

```bash
docker-compose logs user-service | grep "CDC consumer"
```

应该看到：
```
INFO: CDC consumer subscribed to topics: ["cdc.posts", "cdc.follows", "cdc.comments", "cdc.likes"]
INFO: Starting CDC consumer loop
```

---

## 自动部署脚本

如果想自动化整个过程，创建 `scripts/setup-cdc.sh`：

```bash
#!/bin/bash
set -e

echo "🚀 Starting Debezium CDC setup..."

# 1. Start Debezium
echo "1️⃣ Starting Debezium..."
docker-compose up -d debezium
sleep 5

# 2. Create PostgreSQL connector
echo "2️⃣ Creating PostgreSQL connector..."
curl -X POST \
  -H "Content-Type: application/json" \
  -d @backend/debezium-connector-config.json \
  http://localhost:8083/connectors

# 3. Wait for connector to start
echo "3️⃣ Waiting for connector to start..."
sleep 10

# 4. Verify
echo "4️⃣ Verifying connector status..."
curl -s http://localhost:8083/connectors/postgres-cdc-connector/status | jq .

echo "✅ Debezium CDC setup complete!"
```

---

## 故障排查

### 连接器状态为 FAILED

```bash
# 查看错误
curl -s http://localhost:8083/connectors/postgres-cdc-connector/status | jq '.tasks[0]'

# 查看 Debezium 日志
docker-compose logs debezium | grep -i "error\|exception"
```

**常见问题：**

1. **PostgreSQL 无法连接**
   ```
   ERROR: Cannot connect to host 'postgres' port 5432
   ```
   检查 PostgreSQL 是否运行：`docker-compose ps postgres`

2. **WAL 配置不正确**
   ```
   ERROR: Cannot decode plugin 'pgoutput'
   ```
   检查 PostgreSQL 配置：
   ```bash
   docker-compose exec postgres psql -U postgres -c "SHOW wal_level;"
   # 应该返回 'logical'
   ```

3. **逻辑复制插件缺失**
   ```
   ERROR: No such function 'pgoutput'
   ```
   PostgreSQL 需要编译时支持。debezium/postgres:15-alpine 已包含。

### user-service 消费者没有接收消息

```bash
# 检查 Kafka 主题中是否有消息
docker-compose exec kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic cdc.posts \
  --from-beginning \
  --timeout-ms 2000

# 检查 user-service 消费者组
docker-compose exec kafka kafka-consumer-groups \
  --bootstrap-server localhost:9092 \
  --group nova-cdc-consumer-v1 \
  --describe
```

---

## 关键配置解释

| 配置项 | 值 | 说明 |
|--------|-----|------|
| `database.server.name` | `nova-postgres` | 用于 LSN（日志序列号）跟踪 |
| `table.include.list` | `public.posts,public.follows,...` | 要监听的表 |
| `plugin.name` | `pgoutput` | PostgreSQL 内置 WAL 逻辑解码插件 |
| `topic.prefix` | `cdc` | Kafka 主题前缀（→ `cdc.posts` 等） |
| `publication.name` | `debezium_publication` | PostgreSQL 逻辑复制发布名称 |
| `slot.name` | `debezium_slot` | PostgreSQL 复制槽名称 |
| `transforms.route.replacement` | `$3` | 移除数据库和表名前缀，只保留表名 |

---

## 数据流验证

测试完整的 CDC 管道：

```bash
# 1. 在 PostgreSQL 中插入数据
docker-compose exec postgres psql -U postgres -d nova_auth -c \
  "INSERT INTO posts (id, author_id, content) VALUES ('550e8400-e29b-41d4-a716-446655440000', '550e8400-e29b-41d4-a716-446655440001', 'Test post');"

# 2. 检查 Kafka 中的消息
docker-compose exec kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic cdc.posts \
  --from-beginning \
  --max-messages 1

# 3. 检查 ClickHouse 中是否有数据
docker-compose exec clickhouse clickhouse-client \
  --user=default \
  --password=clickhouse \
  --query="SELECT COUNT(*) FROM nova_feed.posts_cdc"

# 4. 验证 feed ranking 可以查询
curl http://localhost:8085/api/v1/feed?offset=0&limit=20
```

---

## 生产部署考虑

1. **监控**
   - 监控 Debezium 连接器状态
   - 监控 Kafka lag
   - 监控 PostgreSQL 复制槽 (replication slots)

2. **灾难恢复**
   - 定期备份 PostgreSQL
   - 保留足够的 WAL 历史（`wal_keep_size`）
   - 定期检查复制槽占用磁盘空间

3. **性能**
   - 调整 `max.batch.size` 和 `max.queue.size`
   - 考虑分区策略
   - 监控 LSN lag

4. **安全**
   - 使用强密码（不要在生产中硬编码）
   - 限制 Debezium 用户权限（仅需 REPLICATION 权限）
   - 使用 SSL/TLS 加密连接

---

## 参考

- [Debezium PostgreSQL Connector](https://debezium.io/documentation/reference/stable/connectors/postgresql.html)
- [PostgreSQL Logical Replication](https://www.postgresql.org/docs/current/logical-replication.html)
- [PgOutput Plug-in](https://www.postgresql.org/docs/current/logical-replication-plugin-interface.html)
