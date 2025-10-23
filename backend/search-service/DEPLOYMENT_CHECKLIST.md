# Search Service Deployment Checklist

## Prerequisites

### 1. Infrastructure

- [ ] PostgreSQL 数据库运行中
- [ ] Redis 服务器运行中（推荐版本 >= 6.0）
- [ ] 确认数据库连接权限
- [ ] 确认 Redis 连接权限

### 2. Environment Variables

- [ ] `DATABASE_URL` 已设置
- [ ] `REDIS_URL` 已设置（或使用默认值）
- [ ] `PORT` 已设置（可选，默认 8081）
- [ ] `RUST_LOG` 已设置（可选，用于日志级别）

## Deployment Steps

### 1. Database Migrations

```bash
# 应用全文搜索索引
psql $DATABASE_URL -f migrations/001_add_fulltext_index.sql
```

验证:
```sql
-- 检查索引是否创建
SELECT indexname, indexdef
FROM pg_indexes
WHERE indexname IN ('idx_posts_caption_fts', 'idx_posts_search_filter');
```

### 2. Build Application

```bash
# Development build
cargo build

# Production build (optimized)
cargo build --release
```

验证:
- [ ] 编译无错误
- [ ] 编译无警告（除了 workspace profile 警告）

### 3. Start Service

```bash
# Development mode
cargo run

# Production mode (使用发布版本)
./target/release/search-service
```

验证:
- [ ] 服务启动成功
- [ ] 日志显示 "Database connection established"
- [ ] 日志显示 "Redis connection established"
- [ ] 日志显示 "search-service listening on 0.0.0.0:8081"

### 4. Health Check

```bash
curl http://localhost:8081/health
```

期望响应: `OK` (HTTP 200)

### 5. Functional Testing

运行测试脚本:
```bash
./test-fulltext-cache.sh
```

或手动测试关键端点:
```bash
# 搜索帖子（全文搜索）
curl "http://localhost:8081/api/v1/search/posts?q=test"

# 清除缓存
curl -X POST http://localhost:8081/api/v1/search/clear-cache

# 再次搜索（验证缓存重建）
curl "http://localhost:8081/api/v1/search/posts?q=test"
```

### 6. Performance Verification

```bash
# 第一次请求（缓存未命中）
time curl -s "http://localhost:8081/api/v1/search/posts?q=photo" > /dev/null

# 第二次请求（缓存命中）
time curl -s "http://localhost:8081/api/v1/search/posts?q=photo" > /dev/null
```

期望：第二次请求显著快于第一次（至少 5-10 倍）

### 7. Log Monitoring

```bash
# 检查缓存行为
grep -E "Cache (hit|miss)" <log-file>

# 检查错误
grep -i error <log-file>

# 检查 Redis 连接
grep -i redis <log-file>
```

## Production Considerations

### Redis Configuration

推荐 Redis 配置（`redis.conf`）:

```conf
# 最大内存（根据实际情况调整）
maxmemory 256mb

# 内存淘汰策略（当达到 maxmemory 时）
maxmemory-policy allkeys-lru

# 持久化（可选，根据需求）
save 900 1
save 300 10
save 60 10000

# AOF 持久化（可选，更高数据安全性）
appendonly yes
```

### PostgreSQL Tuning

```sql
-- 检查 full-text search 配置
SHOW default_text_search_config;

-- 如果需要，设置为英语
-- ALTER DATABASE nova SET default_text_search_config = 'pg_catalog.english';
```

### Service Monitoring

建议监控指标:

1. **性能指标**
   - 搜索端点响应时间（p50, p95, p99）
   - 请求吞吐量（QPS）

2. **缓存指标**
   - 缓存命中率：`hits / (hits + misses)`
   - Redis 连接错误率
   - 缓存键数量

3. **数据库指标**
   - 全文搜索查询延迟
   - 数据库连接池使用率

4. **系统指标**
   - CPU 使用率
   - 内存使用率
   - 网络流量

### Alerting

建议设置告警:

- [ ] Redis 连接失败
- [ ] 数据库连接失败
- [ ] 搜索端点 p95 延迟 > 500ms
- [ ] 5xx 错误率 > 1%
- [ ] 缓存命中率 < 50%

## Rollback Plan

如果出现问题，回滚步骤:

1. **停止新版本服务**
   ```bash
   # 找到进程 ID
   ps aux | grep search-service

   # 停止服务
   kill <PID>
   ```

2. **启动旧版本**（如果有的话）
   ```bash
   # 使用旧版本二进制
   ./target/release/search-service.old
   ```

3. **数据库回滚**（如果需要）
   ```sql
   -- 删除全文搜索索引
   DROP INDEX IF EXISTS idx_posts_caption_fts;
   DROP INDEX IF EXISTS idx_posts_search_filter;
   ```

4. **清除 Redis 缓存**
   ```bash
   redis-cli FLUSHDB
   ```

## Post-Deployment Verification

- [ ] 健康检查端点返回 200 OK
- [ ] 所有搜索端点正常响应
- [ ] 缓存清除端点正常工作
- [ ] 日志无异常错误
- [ ] Redis 连接稳定
- [ ] 数据库连接稳定
- [ ] 缓存命中/未命中正常记录
- [ ] 性能符合预期

## Troubleshooting

### Redis 连接失败

症状: 日志显示 "Failed to connect to Redis"

解决方案:
1. 检查 Redis 是否运行: `redis-cli ping`
2. 检查 `REDIS_URL` 配置
3. 检查防火墙/网络配置
4. 服务会自动降级到数据库查询

### 全文搜索无结果

症状: 搜索返回空结果，但数据库有数据

解决方案:
1. 检查索引是否创建: `\d posts` in psql
2. 检查数据是否符合过滤条件（`soft_delete IS NULL`, `status = 'published'`）
3. 测试简单查询:
   ```sql
   SELECT * FROM posts
   WHERE to_tsvector('english', caption) @@ plainto_tsquery('english', 'test');
   ```

### 缓存未命中

症状: 所有请求都记录 "Cache miss"

解决方案:
1. 检查 Redis 是否正常: `redis-cli INFO`
2. 检查缓存是否被设置: `redis-cli KEYS "search:posts:*"`
3. 检查 TTL: `redis-cli TTL "search:posts:test"`

### 性能未提升

症状: 缓存命中后响应时间未显著改善

解决方案:
1. 检查 Redis 延迟: `redis-cli --latency`
2. 检查网络延迟（Redis 和服务是否在同一机器）
3. 检查序列化/反序列化开销（结果集是否过大）

## Success Criteria

部署成功的标志:

- ✅ 服务稳定运行 > 1 小时无崩溃
- ✅ 缓存命中率 > 60%（稳定状态）
- ✅ 搜索端点 p95 延迟 < 200ms（缓存命中）
- ✅ 搜索端点 p95 延迟 < 500ms（缓存未命中）
- ✅ 零 5xx 错误
- ✅ Redis 和 PostgreSQL 连接稳定

## Contact

如有问题，请查阅:
- `FULLTEXT_SEARCH_IMPLEMENTATION.md` - 详细实现文档
- `README.md` - 服务使用说明
- `IMPLEMENTATION_COMPLETE.md` - 完成总结
