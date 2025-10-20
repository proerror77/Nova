# Job Worker 系统

后台任务系统,负责定时刷新 Redis 缓存,为高频读场景提供预计算数据。

## 架构概览

```
┌──────────────┐      ┌─────────────────┐      ┌──────────┐
│ ClickHouse   │─────▶│   Job Worker    │─────▶│  Redis   │
│ (事件数据)    │      │  (独立进程)      │      │ (缓存)    │
└──────────────┘      └─────────────────┘      └──────────┘
                             │
                             │ 定时调度
                             ▼
                      ┌─────────────┐
                      │  Jobs       │
                      │ - Trending  │
                      │ - Suggested │
                      └─────────────┘
```

## 功能特性

### 1. 热榜生成器 (Trending Generator)

- **刷新频率**: 每 60 秒
- **数据源**: ClickHouse `post_events` 表
- **时间窗口**: 最近 1 小时
- **算法**: engagement score = `views * 0.1 + likes * 2 + comments * 3 + shares * 5`
- **输出**: Top 50 热门帖子 → Redis `nova:cache:trending:1h`
- **TTL**: 90 秒 (1.5 倍刷新间隔)

### 2. 建议用户生成器 (Suggested Users Generator)

- **刷新频率**: 每 10 分钟
- **数据源**: ClickHouse `user_relationships` 表
- **算法**: 协同过滤 (二度好友推荐)
- **采样策略**: 每次处理 100 个活跃用户
- **输出**: 每用户 20 个推荐 → Redis `nova:cache:suggested_users:{user_id}`
- **TTL**: 20 分钟 (2 倍刷新间隔)

## 快速开始

### 本地开发

```bash
# 1. 启动依赖服务 (Redis + ClickHouse)
docker-compose up -d redis clickhouse

# 2. 配置环境变量
export REDIS_URL="redis://127.0.0.1:6379"
export CLICKHOUSE_URL="http://localhost:8123"

# 3. 运行 job worker
cargo run --bin job_worker

# 4. 查看日志
RUST_LOG=debug cargo run --bin job_worker
```

### 生产环境部署

```bash
# 1. 构建 Docker 镜像
./scripts/build_job_worker.sh v1.0.0

# 2. 部署到 Kubernetes
kubectl apply -f infra/k8s/job-worker-deployment.yaml

# 3. 查看状态
kubectl get pods -l app=job-worker -n nova
kubectl logs -f deployment/job-worker -n nova

# 4. 验证缓存
kubectl exec -it deployment/redis-master -n nova -- redis-cli
> GET nova:cache:trending:1h
> KEYS nova:cache:suggested_users:*
```

## 配置说明

所有配置通过环境变量传递:

| 环境变量                        | 默认值                          | 说明                    |
| ------------------------------- | ------------------------------- | ----------------------- |
| `REDIS_URL`                     | `redis://127.0.0.1:6379`        | Redis 连接 URL          |
| `CLICKHOUSE_URL`                | `http://localhost:8123`         | ClickHouse 连接 URL     |
| `JOB_TRENDING_INTERVAL_SEC`     | `60`                            | 热榜刷新间隔 (秒)       |
| `JOB_TRENDING_WINDOW_HOURS`     | `1`                             | 热榜时间窗口 (小时)     |
| `JOB_TRENDING_TOPK`             | `50`                            | 热榜 Top-K 数量         |
| `JOB_SUGGESTION_INTERVAL_SEC`   | `600`                           | 建议用户刷新间隔 (秒)   |
| `JOB_SUGGESTION_BATCH_SIZE`     | `100`                           | 每次处理的用户数        |
| `JOB_SUGGESTIONS_PER_USER`      | `20`                            | 每用户推荐数量          |
| `JOB_CH_TIMEOUT_MS`             | `30000`                         | ClickHouse 超时 (毫秒)  |
| `JOB_REDIS_POOL_SIZE`           | `10`                            | Redis 连接池大小        |
| `JOB_MAX_CONCURRENT`            | `4`                             | 最大并发 job 数量       |

## 监控与告警

### 关键指标

(TODO: 集成 Prometheus)

```rust
// Job 执行时长
job_refresh_duration_seconds{redis_key="nova:cache:trending:1h"}

// Job 执行次数 (成功/失败)
job_refresh_total{redis_key="nova:cache:trending:1h", status="success"}

// ClickHouse 查询耗时
clickhouse_query_duration_seconds{job="trending"}
```

### 日志示例

```json
{
  "timestamp": "2025-10-18T01:30:00Z",
  "level": "INFO",
  "correlation_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "redis_key": "nova:cache:trending:1h",
  "ttl_sec": 90,
  "elapsed_ms": 245,
  "message": "Cache refresh completed"
}
```

## 故障处理

### 常见问题

**Q1: Job 执行失败,但不中断**

✅ **正常行为**。所有 job 都有自动重试机制,失败后会在下一个周期重试,不会导致进程崩溃。

**Q2: ClickHouse 查询超时**

- 检查 `JOB_CH_TIMEOUT_MS` 配置 (默认 30s)
- 优化 SQL 查询,添加索引
- 调整 `window_hours` 减少数据量

**Q3: Redis 写入失败**

- 检查 Redis 连接状态
- 验证 Redis 内存是否足够 (`INFO memory`)
- 检查网络延迟

**Q4: 优雅关闭时间过长**

- 调整 K8s `terminationGracePeriodSeconds` (默认 60s)
- 减少 job 的执行间隔,让其更快完成

## 开发指南

### 添加新的 Job

1. 在 `src/jobs/` 创建新模块:

```rust
// src/jobs/my_new_job.rs
use super::{CacheRefreshJob, JobContext};
use async_trait::async_trait;

pub struct MyNewJob;

#[async_trait]
impl CacheRefreshJob for MyNewJob {
    async fn fetch_data(&self, ctx: &JobContext) -> Result<Vec<u8>> {
        // 1. 从 ClickHouse 查询数据
        // 2. 计算/转换
        // 3. 序列化为 JSON
        todo!()
    }

    fn redis_key(&self) -> &str {
        "nova:cache:my_new_job"
    }

    fn interval_sec(&self) -> u64 {
        300  // 5 分钟
    }
}
```

2. 在 `src/bin/job_worker.rs` 注册 job:

```rust
let my_job = Arc::new(MyNewJob::new());
let my_ctx = JobContext::new(redis_pool.clone(), ch_client.clone());
jobs.push((my_job as Arc<dyn CacheRefreshJob>, my_ctx));
```

3. 编写测试:

```bash
cargo test --test job_test
```

### 测试策略

```bash
# 单元测试
cargo test --lib jobs

# 集成测试 (需要 Redis 实例)
cargo test --test job_test -- --ignored

# 端到端测试
docker-compose up -d redis clickhouse
cargo run --bin job_worker &
sleep 70  # 等待一轮刷新
redis-cli GET nova:cache:trending:1h
```

## 性能优化

### ClickHouse 查询优化

- 使用物化视图预聚合
- 添加分区键和排序键
- 使用 `PREWHERE` 过滤
- 限制查询时间范围

### Redis 写入优化

- 使用 pipeline 批量写入 (suggested_users 已实现)
- 合理设置 TTL,避免缓存雪崩
- 使用 Redis Cluster 水平扩展

### 资源管理

- 控制并发数 (`JOB_MAX_CONCURRENT`)
- 调整连接池大小 (`JOB_REDIS_POOL_SIZE`)
- 监控内存使用,及时释放

## 安全考虑

- ✅ 独立的 Service Account
- ✅ 非 root 用户运行 (UID 1000)
- ✅ 资源限制 (CPU/Memory)
- ✅ 优雅关闭,避免数据丢失
- ⚠️ Secret 管理:生产环境应使用 external-secrets

## 相关资源

- [ClickHouse 文档](https://clickhouse.com/docs)
- [Redis 缓存策略](https://redis.io/docs/manual/eviction/)
- [Kubernetes Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
- [Tokio 异步运行时](https://tokio.rs/)

---

**维护者**: Backend Team
**最后更新**: 2025-10-18
