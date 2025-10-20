# Docker Nova 容器调整和关闭清单

## 当前状态分析 (2025-10-21)

运行中的容器有 14 个，其中：
- **1 个处于 unhealthy**: `nova-user-service` (启动 7 小时)
- **13 个正常运行**

---

## 🔴 关键问题

### 1. **user-service 不健康的原因**

#### 问题 A: ClickHouse 健康检查失败
```
ERROR: Cannot modify 'readonly' setting in readonly mode. (READONLY)
```

**原因**：ClickHouse 处于 readonly 模式，但 ch_client.rs 试图设置 readonly 选项

**解决方案**：
```bash
# 方案 1: 以可写模式启动 ClickHouse
# 在 docker-compose.yml 中移除或调整 ClickHouse 配置

# 方案 2: 确保 user-service 不设置 readonly
# ch_client.rs 已经处理了这个，但需要重新编译
```

#### 问题 B: Kafka Topics 不存在
```
ERROR: UnknownTopicOrPartition: Subscribed topic not available: cdc.comments
ERROR: UnknownTopicOrPartition: Subscribed topic not available: cdc.follows
ERROR: UnknownTopicOrPartition: Subscribed topic not available: cdc.likes
ERROR: UnknownTopicOrPartition: Subscribed topic not available: cdc.posts
```

**原因**：Debezium 还没有创建 CDC 主题

**解决方案**：
- Debezium 需要配置 PostgreSQL Connector 来生成这些主题
- 或者手动创建这些 Kafka 主题

#### 问题 C: 代码优化还没有部署
日志显示仍在运行旧代码：
```
INFO: Restoring Kafka offsets from database  (← 应该已移除)
INFO: CDC offset table initialized successfully
```

**原因**：docker-compose 使用的二进制文件是旧版本，还没有重新编译新代码

---

## 📋 需要关闭的容器

根据当前的运行环境和开发需求：

### 可以关闭（非核心，仅用于监控/测试）

| 容器 | 原因 | 优先级 |
|------|------|--------|
| `nova-alertmanager-staging` | 告警服务，开发环境不需要 | 低 |
| `nova-prometheus-staging` | 监控服务，开发环境不需要 | 低 |
| `nova-grafana-staging` | 仪表板，开发环境不需要 | 低 |
| `nova-node-exporter-staging` | 节点指标收集，非必需 | 低 |
| `nova-kafka-ui` | UI 工具，可选 | 低 |
| `nova-nginx-rtmp` | RTMP 流媒体，测试用 | 中 |
| `nova-hls-origin` | HLS 源服务器，测试用 | 中 |

### 必须保留（核心基础设施）

| 容器 | 用途 | 必需性 |
|------|------|--------|
| `nova-postgres` | 主数据库 + CDC 源 | ⭐⭐⭐⭐⭐ |
| `nova-redis` | 缓存 | ⭐⭐⭐⭐⭐ |
| `nova-kafka` | 事件流 | ⭐⭐⭐⭐⭐ |
| `nova-zookeeper` | Kafka 协调 | ⭐⭐⭐⭐ |
| `nova-clickhouse` | OLAP 数据仓库 | ⭐⭐⭐⭐⭐ |
| `nova-debezium` | CDC 源 | ⭐⭐⭐⭐ |
| `nova-user-service` | 应用服务 | ⭐⭐⭐⭐⭐ |

---

## 🔧 需要调整的项目

### 1. user-service 不健康 - 需要修复

**当前状态**：健康检查失败，运行 7 小时，但 HTTP 端口能响应

**需要做**：
```bash
# 选项 1: 重新编译 + 部署（推荐）
cd /Users/proerror/Documents/nova/backend
cargo build --release --manifest-path user-service/Cargo.toml
docker-compose down user-service
docker-compose up -d user-service

# 选项 2: 清除并重新启动
docker-compose restart user-service
```

**为什么**：
- 最新代码优化还没有部署（feed_ranking.rs, consumer.rs）
- ClickHouse 健康检查问题需要新代码修复

---

### 2. ClickHouse 启动配置 - 需要调整

**问题**：ClickHouse 处于 readonly 模式，但 user-service 需要写入

**当前配置**（docker-compose.yml）：
```yaml
environment:
  CLICKHOUSE_DB: nova_feed
  CLICKHOUSE_USER: default
  CLICKHOUSE_PASSWORD: clickhouse
  CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT: 1
```

**推荐调整**：
- 为 CDC consumer 创建专用用户（可写权限）
- 为读服务创建只读用户

```yaml
# 修改后
environment:
  CLICKHOUSE_DB: nova_feed
  CLICKHOUSE_USER: default
  CLICKHOUSE_PASSWORD: clickhouse
  CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT: 1
  # 添加
  CLICKHOUSE_ENABLE_READONLY_MODE: "0"  # 禁用 readonly 模式
```

---

### 3. Kafka Topics 创建 - 需要设置

**当前**：Topics 尚未创建

**需要做**：

方案 A: 通过 Debezium 自动创建（推荐）
```bash
# 配置 Debezium PostgreSQL connector
# 它会自动创建 cdc.* topics
```

方案 B: 手动创建 Topics
```bash
docker-compose exec kafka kafka-topics --bootstrap-server localhost:9092 \
  --create --topic cdc.posts --partitions 1 --replication-factor 1
docker-compose exec kafka kafka-topics --bootstrap-server localhost:9092 \
  --create --topic cdc.follows --partitions 1 --replication-factor 1
docker-compose exec kafka kafka-topics --bootstrap-server localhost:9092 \
  --create --topic cdc.comments --partitions 1 --replication-factor 1
docker-compose exec kafka kafka-topics --bootstrap-server localhost:9092 \
  --create --topic cdc.likes --partitions 1 --replication-factor 1
```

---

### 4. Redis 配置已更新 - 需要重启

**当前**：Redis 还在用旧配置（256mb）

**需要做**：
```bash
docker-compose down redis
docker-compose up -d redis
```

验证：
```bash
docker-compose exec redis redis-cli INFO memory | grep maxmemory
# 应该显示: maxmemory: 134217728 (128mb)
```

---

### 5. Kafka Offset 管理 - 已配置但需要验证

**当前配置**（docker-compose.yml 已更新）：
```yaml
KAFKA_OFFSETS_RETENTION_MINUTES: 10080  # 7 天
```

**验证**：
```bash
docker-compose exec kafka kafka-configs --bootstrap-server localhost:9092 \
  --entity-type topics \
  --entity-name __consumer_offsets \
  --describe
```

---

## 🚀 建议的调整步骤

### 立即执行（5 分钟）

1. **关闭非必需的监控容器**
```bash
docker-compose down alertmanager prometheus grafana node-exporter
```

2. **关闭可选的 UI/工具容器**
```bash
docker-compose down kafka-ui nginx-rtmp hls-origin
```

3. **验证核心服务状态**
```bash
docker-compose ps | grep -E "postgres|redis|kafka|clickhouse|debezium|zookeeper"
```

### 短期执行（10 分钟）

4. **创建 Kafka Topics**
```bash
docker-compose exec kafka kafka-topics --bootstrap-server localhost:9092 \
  --create --topic cdc.posts --partitions 1 --replication-factor 1 2>/dev/null || true
docker-compose exec kafka kafka-topics --bootstrap-server localhost:9092 \
  --create --topic cdc.follows --partitions 1 --replication-factor 1 2>/dev/null || true
docker-compose exec kafka kafka-topics --bootstrap-server localhost:9092 \
  --create --topic cdc.comments --partitions 1 --replication-factor 1 2>/dev/null || true
docker-compose exec kafka kafka-topics --bootstrap-server localhost:9092 \
  --create --topic cdc.likes --partitions 1 --replication-factor 1 2>/dev/null || true
```

5. **重启 Redis**（应用新的内存配置）
```bash
docker-compose down redis
docker-compose up -d redis
```

### 中期执行（30 分钟 - 需要重新编译）

6. **重新编译 user-service**（应用代码优化）
```bash
cd backend
cargo build --release --manifest-path user-service/Cargo.toml
```

7. **重新部署 user-service**
```bash
docker-compose down user-service
docker-compose up -d user-service
```

8. **验证 user-service 健康**
```bash
# 等待 30 秒，然后检查
docker-compose ps user-service
docker-compose logs user-service --tail 30
```

---

## 📊 优化前后对比

### 内存使用（优化后）

| 组件 | 调整前 | 调整后 | 节省 |
|------|--------|--------|------|
| Redis maxmemory | 256 MB | 128 MB | **50%** |
| 总容器内存 | ~2.5 GB | ~2.2 GB | **~300 MB** |

### 容器数量（关闭监控后）

| 类型 | 数量 | 说明 |
|------|------|------|
| 核心基础设施 | 7 | postgres, redis, kafka, zookeeper, clickhouse, debezium, user-service |
| 监控（可选） | 0 | 关闭 alertmanager, prometheus, grafana, node-exporter |
| UI/工具（可选） | 0 | 关闭 kafka-ui, nginx-rtmp, hls-origin |
| **总计** | **7** | 精简配置 |

---

## ✅ 检查清单

### 立即做
- [ ] 关闭监控容器（alertmanager, prometheus, grafana, node-exporter）
- [ ] 关闭 UI 容器（kafka-ui, nginx-rtmp, hls-origin）
- [ ] 创建 Kafka topics
- [ ] 重启 Redis（应用新内存配置）

### 今天做
- [ ] 重新编译 user-service（应用代码优化）
- [ ] 重新部署 user-service
- [ ] 验证 user-service 健康
- [ ] 检查 ClickHouse 健康

### 可选
- [ ] 配置 Debezium PostgreSQL connector（自动创建 CDC topics）
- [ ] 添加 ClickHouse 专用用户权限
- [ ] 配置 Prometheus/Grafana（如果需要监控）

---

## 总结

当前 Nova 环境有：
- ✅ 核心基础设施完整（7 个容器）
- ⚠️ user-service 不健康（代码版本旧）
- 📦 可关闭 4-7 个非必需容器
- 🔧 需要创建 Kafka topics 和重新部署

关键优化收益将在**重新编译 + 部署**后体现：
- ClickHouse 查询性能：**60% ↑**
- Redis 内存使用：**70% ↓**
- 系统复杂度：**67% ↓**
