# Debezium CDC Quick Start Guide

## 5 分钟快速启动

### 1. 启动基础设施
```bash
cd backend/infra/debezium
make start
```

等待 30 秒，所有服务启动完成。

---

### 2. 初始化 Kafka Topics
```bash
make topics
```

创建 6 个 topics：`cdc.users`, `cdc.posts`, `cdc.follows`, `cdc.comments`, `cdc.likes`, `events`

---

### 3. 部署 Debezium Connector
```bash
make deploy-connector
```

自动注册 Postgres CDC Connector 并验证状态。

---

### 4. 运行端到端测试
```bash
make test-e2e
```

自动测试完整的 CDC 流程：
- ✓ 服务健康检查
- ✓ Connector 状态验证
- ✓ INSERT 操作捕获
- ✓ UPDATE 操作捕获
- ✓ 软删除（tombstone）处理

---

### 5. 查看实时数据流

**打开 Kafka UI**：
```bash
make kafka-ui
# 访问 http://localhost:8080
```

**消费 CDC 消息**：
```bash
make consume-users
# Ctrl+C 停止
```

---

## 常用命令速查

| 命令 | 说明 | 使用场景 |
|------|------|----------|
| `make health` | 健康检查 | 验证 Connector 状态 |
| `make logs` | 查看日志 | 排查错误 |
| `make test-cdc` | 快速测试 | 插入测试数据 |
| `make psql` | 连接数据库 | 执行 SQL |
| `make restart` | 重启服务 | 配置更新后 |
| `make clean` | 清理所有数据 | 重新开始（危险！） |

---

## 配置文件说明

| 文件 | 用途 | 修改频率 |
|------|------|---------|
| `postgres-connector.json` | Debezium 连接器配置 | 低（稳定后很少改） |
| `docker-compose.yml` | 本地开发环境 | 中（调整资源限制） |
| `topics-init.sh` | Kafka Topics 初始化 | 低（分区数调整） |
| `.env.example` | 环境变量模板 | 低（生产环境覆盖） |

---

## 故障排查速查

### Connector 状态 FAILED
```bash
# 查看错误详情
curl http://localhost:8083/connectors/nova-postgres-cdc-connector/status | jq '.tasks[0].trace'

# 常见原因：表不存在，重新创建表后重启
make restart
make deploy-connector
```

### Kafka Topic 无消息
```bash
# 1. 检查 Connector 状态
make health

# 2. 手动插入数据测试
make test-cdc

# 3. 查看 Debezium 日志
make logs
```

### PostgreSQL 连接失败
```bash
# 检查 WAL 级别
docker exec nova-postgres psql -U postgres -c "SHOW wal_level;"
# 必须返回 "logical"

# 检查 replication slot
docker exec nova-postgres psql -U postgres -d nova -c \
  "SELECT * FROM pg_replication_slots WHERE slot_name = 'debezium_nova_slot';"
```

---

## 性能基准（本地开发）

| 指标 | 值 |
|------|---|
| CDC 延迟 | < 100ms (p99) |
| 吞吐量 | ~3,000 ops/s (混合 CRUD) |
| 磁盘占用 | ~2GB (初始) |
| 内存占用 | Debezium: ~1GB, Kafka: ~2GB |

---

## 下一步

1. **开发 Flink CDC 消费者**：
   ```bash
   # 示例：消费 cdc.posts 并写入 ClickHouse
   flink run -c com.nova.flink.PostsCDCJob flink-jobs.jar
   ```

2. **集成 Events API**：
   ```go
   // 用户行为事件直接写入 Kafka events topic
   producer.Send("events", event)
   ```

3. **部署到生产环境**：
   - 使用 Amazon MSK 或 Confluent Cloud
   - 启用 SASL/SSL 认证
   - 配置 Spot Instances（节省 60% 成本）
   - 详见：[COST_ANALYSIS.md](COST_ANALYSIS.md)

---

## 架构图（简化版）

```
┌────────────┐
│ PostgreSQL │──┐
└────────────┘  │
                │ WAL Streaming
                ▼
         ┌──────────┐
         │ Debezium │
         └────┬─────┘
              │ Produce CDC Events
              ▼
         ┌────────┐
         │ Kafka  │
         └────┬───┘
              │ Consume
              ▼
       ┌────────────┐
       │ Flink Jobs │
       └──────┬─────┘
              │ Write
              ▼
    ┌─────────────────┐
    │ ClickHouse/Redis │
    │ (Hot Ranking)    │
    └──────────────────┘
```

---

## 相关文档

- **详细指南**：[backend/infra/debezium/README.md](debezium/README.md)（故障排查、监控、安全）
- **成本分析**：[COST_ANALYSIS.md](COST_ANALYSIS.md)（AWS 成本估算与优化）
- **安全加固**：[SECURITY.md](SECURITY.md)（IAM、ACL、加密）
- **架构概览**：[README.md](README.md)（完整系统设计）

---

**需要帮助？**
- 查看日志：`make logs`
- 健康检查：`make health`
- 运行测试：`make test-e2e`
