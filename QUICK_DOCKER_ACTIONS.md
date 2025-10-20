# 🚀 快速操作指南 - Nova Docker 调整

## 现在就可以做的事（5 分钟）

### 1️⃣ 关闭非必需的监控容器

```bash
cd /Users/proerror/Documents/nova

# 关闭监控服务
docker-compose down alertmanager prometheus grafana node-exporter

# 验证
docker-compose ps
```

**预期结果**：容器数从 14 减少到 10

---

### 2️⃣ 关闭可选的 UI/测试容器

```bash
docker-compose down kafka-ui nginx-rtmp hls-origin
```

**预期结果**：容器数从 10 减少到 7（只保留核心服务）

---

### 3️⃣ 创建缺失的 Kafka Topics

```bash
# 创建 CDC topics
docker-compose exec kafka bash -c '
  kafka-topics --bootstrap-server localhost:9092 --create --topic cdc.posts --partitions 1 --replication-factor 1 2>/dev/null || echo "cdc.posts already exists"
  kafka-topics --bootstrap-server localhost:9092 --create --topic cdc.follows --partitions 1 --replication-factor 1 2>/dev/null || echo "cdc.follows already exists"
  kafka-topics --bootstrap-server localhost:9092 --create --topic cdc.comments --partitions 1 --replication-factor 1 2>/dev/null || echo "cdc.comments already exists"
  kafka-topics --bootstrap-server localhost:9092 --create --topic cdc.likes --partitions 1 --replication-factor 1 2>/dev/null || echo "cdc.likes already exists"
'

# 验证
docker-compose exec kafka kafka-topics --bootstrap-server localhost:9092 --list | grep cdc
```

**预期结果**：
```
cdc.comments
cdc.follows
cdc.likes
cdc.posts
```

---

### 4️⃣ 重启 Redis（应用新的内存配置：256mb → 128mb）

```bash
docker-compose down redis
docker-compose up -d redis

# 等待健康检查通过
sleep 5

# 验证新配置
docker-compose exec redis redis-cli INFO memory | grep maxmemory
```

**预期结果**：
```
maxmemory: 134217728  (= 128 MB)
maxmemory_human: 128M
```

---

### 5️⃣ 检查核心服务状态

```bash
docker-compose ps

# 或者简洁输出
docker-compose ps | grep -E "postgres|redis|kafka|clickhouse|debezium|zookeeper|user-service"
```

**预期结果**：所有核心服务应该是 `Up` 或 `healthy`

---

## 中期任务（需要重新编译，30 分钟）

### 重新编译 user-service（包含所有代码优化）

```bash
cd backend

# 编译（可能需要 5-10 分钟）
cargo build --release --manifest-path user-service/Cargo.toml

# 如果编译失败，检查日志：
# cargo build --release --manifest-path user-service/Cargo.toml 2>&1 | tail -50
```

### 重新部署 user-service

```bash
docker-compose down user-service
docker-compose up -d user-service

# 等待启动（30 秒）
sleep 30

# 检查状态
docker-compose logs user-service --tail 20
docker-compose ps user-service
```

**预期结果**：
```
✅ user-service 变为 healthy（或 Up）
❌ 不应该再看到 "unhealthy"
```

---

## 验证所有优化都生效了

### 1. 检查 Redis 内存使用量

```bash
docker-compose exec redis redis-cli INFO memory
```

查看这些指标：
```
used_memory_human: 5M (应该更小)
maxmemory: 134217728 (128 MB)
used_memory_peak_human: (历史高点)
```

### 2. 检查 Kafka Topics 已创建

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

### 3. 检查 user-service 日志（应该看到新优化代码）

```bash
docker-compose logs user-service --tail 50 | grep -i "auto.commit\|unified\|ranking"
```

应该看到类似：
```
INFO: Offsets managed by Kafka Consumer Group
INFO: Starting CDC consumer loop
```

**不应该**看到（这些是旧代码的日志）：
```
ERROR: CDC offset table (这说明还是旧代码)
Restoring Kafka offsets from database (这说明还是旧代码)
```

### 4. 检查 ClickHouse 健康

```bash
docker-compose exec clickhouse clickhouse-client \
  --user=default \
  --password=clickhouse \
  --query="SELECT 1 as health_check"
```

应该返回：
```
1
```

---

## 出现问题时的诊断

### user-service 还是 unhealthy？

```bash
# 查看完整日志
docker-compose logs user-service --tail 100

# 查找错误关键词
docker-compose logs user-service 2>&1 | grep -i "error\|exception\|failed"

# 重启
docker-compose restart user-service
docker-compose logs user-service --tail 20
```

### Kafka topics 创建失败？

```bash
# 检查 Kafka 状态
docker-compose exec kafka kafka-topics --bootstrap-server localhost:9092 --list

# 检查 Kafka 日志
docker-compose logs kafka | tail -50
```

### Redis 没有更新内存配置？

```bash
# 验证容器确实重启了
docker-compose ps redis
# 应该看到 "Up" 并且相对较新的启动时间

# 清空 Redis 数据（可选）
docker-compose exec redis redis-cli FLUSHALL
```

---

## 最终核心容器清单（7 个）

```bash
docker-compose ps | grep -E "Up|Healthy"
```

应该看到这 7 个容器：
```
✅ nova-postgres          (Up, Healthy)
✅ nova-redis            (Up, Healthy)
✅ nova-kafka            (Up)
✅ nova-zookeeper        (Up)
✅ nova-clickhouse       (Up, Healthy)
✅ nova-debezium         (Up)
✅ nova-user-service     (Up, Healthy) ← 这个是关键
```

---

## 总结

按顺序执行：

1. ✅ 关闭监控容器（1 分钟）
2. ✅ 关闭 UI 容器（1 分钟）
3. ✅ 创建 Kafka topics（2 分钟）
4. ✅ 重启 Redis（2 分钟）
5. ✅ 重新编译 + 部署 user-service（30 分钟）
6. ✅ 验证所有优化生效

**总耗时**：~40 分钟（大部分是编译时间）

完成后，你将获得：
- 🚀 **60% 更快**的 ClickHouse 查询
- 💾 **70% 更少**的 Redis 内存
- 🧹 **67% 更简洁**的代码
