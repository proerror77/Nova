# Nova Staging Runbook

> 目的：一次性梳理 staging 部署所需的镜像、环境变量、监控/告警、外部依赖与冒烟测试。所有信息均以当前仓库状态（`backend/` 下的新微服务拆分）为准。

---

## 1. Service Matrix

| Service | Dockerfile | 推荐镜像标签* | 默认端口 | Health / Ready | Metrics | 关键依赖 |
|---------|-----------|---------------|----------|----------------|---------|----------|
| auth-service | `backend/auth-service/Dockerfile` | `ghcr.io/nova/auth-service:staging-<git-sha>` | `SERVER_PORT` (建议 8084) | `GET /health`, `GET /readiness` | _缺失_（需补 Prometheus 暴露） | PostgreSQL（认证库）、Redis、Kafka（事件，可选） |
| user-service | `backend/user-service/Dockerfile` | `ghcr.io/nova/user-service:staging-<git-sha>` | 8080 | `GET /api/v1/health`, `/ready`, `/live` | `/metrics` (Prometheus) | PostgreSQL（核心用户）、Redis Sentinel、Kafka、ClickHouse、Neo4j、S3 |
| content-service | `backend/content-service/Dockerfile` | `ghcr.io/nova/content-service:staging-<git-sha>` | 8081 | `GET /api/v1/health`, `/ready`, `/live` | `/metrics` | PostgreSQL（内容）、Redis Sentinel、Kafka、ClickHouse |
| media-service | `backend/media-service/Dockerfile` | `ghcr.io/nova/media-service:staging-<git-sha>` | HTTP 8082 / gRPC 9082 | `GET /api/v1/health`, `/ready`, `/live` | _缺失_（中间件已计数但未暴露接口） | PostgreSQL（媒体）、Redis、Kafka、S3/CloudFront、ClickHouse(可选) |
| messaging-service | `backend/messaging-service/Dockerfile` | `ghcr.io/nova/messaging-service:staging-<git-sha>` | `PORT` (默认 3000) | `GET /health` | `GET /metrics`（JSON，占位需换 Prom 格式） | PostgreSQL（消息）、Redis Sentinel、Kafka、S3(语音)、APNs/FCM、TURN |
| notification-service | `backend/notification-service/Dockerfile` | `ghcr.io/nova/notification-service:staging-<git-sha>` | `APP_PORT` (默认 8086) | `GET /health` | `/metrics`（Prometheus） | PostgreSQL（通知）、Redis、Kafka、APNs/FCM |
| feed-service | `backend/feed-service/Dockerfile` | `ghcr.io/nova/feed-service:staging-<git-sha>` | `APP_PORT` (默认 8000) | `GET /health` | _缺失_（需新增 `/metrics`） | PostgreSQL（推荐）、Kafka、Redis、Neo4j(可选)、ONNX 模型存储 |
| streaming-service | `backend/streaming-service/Dockerfile` | `ghcr.io/nova/streaming-service:staging-<git-sha>` | 8088 (HTTP) / 7001 (RTMP) | `GET /health`, `/ready` | `/metrics` | Redis、Kafka、S3、Media CDN、TURN |

_\*镜像推荐：构建完成后以 `staging-<git-short-sha>` 打标签，并在部署前推送到共享 registry。_

---

## 2. 环境变量 / Secrets 总览

> 建议将以下变量集中写入 `k8s/infrastructure/base/configmap.yaml` 与 `secrets.yaml`，再通过 overlay 在 dev/staging/prod 之间覆写差异。详细字段定义可参考对应服务的 `config/*.rs`。

### 通用（所有服务）
- `APP_ENV`：`development|staging|production`
- `DATABASE_URL` / `DATABASE_MAX_CONNECTIONS`
- `REDIS_URL` + `REDIS_SENTINEL_ENDPOINTS` / `REDIS_SENTINEL_MASTER`（使用 Sentinel 时）
- `KAFKA_BROKERS`
- `JWT_PUBLIC_KEY_FILE` / `JWT_PRIVATE_KEY_FILE` 或各自的 `*_PEM`

### auth-service
- `SERVER_HOST`, `SERVER_PORT`
- `JWT_PRIVATE_KEY_PEM`, `JWT_PUBLIC_KEY_PEM`
- OAuth：`GOOGLE_CLIENT_ID`、`APPLE_TEAM_ID`...（见 `backend/auth-service/src/config.rs`）
- 可选：`KAFKA_BROKERS`（发布 auth-events）

### user-service
见 `backend/user-service/src/config/mod.rs`
- 数据存取：`DATABASE_URL`, `CLICKHOUSE_URL`, `NEO4J_URI`
- Redis Sentinel：`REDIS_SENTINEL_ENDPOINTS`, `REDIS_SENTINEL_MASTER_NAME`, `REDIS_POOL_SIZE`
- S3：`S3_BUCKET_NAME`, `S3_REGION`, `CLOUDFRONT_URL`, AWS 凭证
- Rate limit：`RATE_LIMIT_MAX_REQUESTS`, `RATE_LIMIT_WINDOW_SECS`
- Kafka：`KAFKA_EVENTS_TOPIC`, `KAFKA_RETRY_*`

### content-service
- `CONTENT_SERVICE_HOST|PORT`
- `REDIS_SENTINEL_ENDPOINTS`（新增）
- `KAFKA_EVENTS_TOPIC`
- `CLICKHOUSE_URL`
- `S3_MEDIA_BUCKET`（若需要访问媒体）

### media-service
- `MEDIA_SERVICE_HOST|PORT`
- `DB_URL_MEDIA`, `AWS_*`（上传 / 转码）
- `TRANSCODE_QUEUE` Kafka topic
- `CLOUDFRONT_URL`, `UPLOAD_MAX_MB`

### messaging-service
- `MESSAGE_ENCRYPTION_MASTER_KEY`（32 字节 base64）
- `RTC_STUN_URLS`, `RTC_TURN_URLS`, `RTC_TURN_USERNAME`, `RTC_TURN_PASSWORD`
- `FCM_API_KEY`, `APNS_*`
- `S3_BUCKET`, `AWS_REGION`
- `REDIS_SENTINEL_ENDPOINTS`（用于分布式 Signal）

### feed-service
- `COLLAB_MODEL_PATH`, `CONTENT_MODEL_PATH`, `ONNX_MODEL_PATH`
- `NEO4J_ENABLED`, `NEO4J_URI`
- `USER_SERVICE_GRPC_URL`（下游 gRPC）
- `KAFKA_BOOTSTRAP_SERVERS`

### notification-service
- `SNS_TOPIC_ARN` 或 FCM / APNs 设置
- `NOTIFICATION_WORKER_CONCURRENCY`
- `RATE_LIMIT_MAX_NOTIFICATIONS`

### streaming-service
- `RTMP_INGEST_HOST`
- `KAFKA_STREAM_TOPIC`
- `REDIS_URL`
- `S3_STREAM_SEGMENT_BUCKET`
- `TURN_URLS`

---

## 3. 外部依赖与容量建议

| 组件 | 用途 | Staging 规格建议 | 备注 |
|------|------|-----------------|------|
| PostgreSQL | 核心数据 (多 schema) | 4 vCPU / 16 GiB，`max_connections=150` | 建议按服务拆库；启用 WAL + 备份 |
| Redis Sentinel | 缓存 / 会话 | 3 × 1 GiB (master+2 replica)，Sentinel quorum 3 | 确认 `REDIS_SENTINEL_ENDPOINTS` 配置一致 |
| Kafka / Redpanda | 事件 / CDC | 3 节点，`message.max.bytes=5MB` | 预建 topics: `events`, `social.events`, `media.transcode`, `auth-events` |
| ClickHouse | 分析 | 2 节点 replica，`max_memory_usage=4GiB` | `user-service` + `content-service` 健康检查需一致 |
| Neo4j | 社交图 | 单节点 4 GiB 内存 | 若关闭，则 `graph.enabled=false` |
| S3 / MinIO | 媒体 / 备份 | 1 TB bucket + 100GB CDN 缓存 | 配置 CORS & Lifecycle |
| TURN (coturn) | WebRTC | 2 副本，UDP 3478 | Messaging / Streaming 共用 |
| Prometheus + Grafana | 监控 | 8 GiB | 抓取间隔 15s，告警规则绑定 Slack/Email |

---

## 4. 数据库 Schema & 迁移计划

1. **核心表归属**  
   - 用户 / 关系：保留在 user-service（PostgreSQL `nova_core`）
   - 认证 / OAuth：迁移至 auth-service (`nova_auth`)
   - 内容 / 媒体：迁移至 content-service、media-service
   - 消息 / 通知：迁移至 messaging-service、notification-service
2. **迁移执行顺序**  
   1. 在新库创建空 schema（参考 `backend/migrations` 目录分段名单）  
   2. 启用 Debezium / CDC，将旧库增量同步至各服务对应库  
   3. 切换 API Gateway 流量至新服务  
   4. 观察 24 小时后冻结旧表，仅保留只读访问  
3. **Runbook / Rollback**  
   - Runbook: `k8s/docs/DEPLOYMENT_CHECKLIST.md` + 本文件的服务矩阵  
   - 如需回滚：  
     1. 将各 Deployment 的镜像回滚到上一个 tag (`kubectl rollout undo deployment/<svc>`)  
     2. 将 API Gateway (Ingress) 指回 user-service monolith  
     3. 停止 CDC，确认旧表写入正常  
4. **文档引用**  
   - 更新 `backend/MIGRATION_CLEANUP_STATUS.md` 的未勾选项时，引用本 Runbook 作为 Cutover & Rollback 说明。

---

## 5. 监控与告警基线

- **Prometheus 抓取**：所有核心服务（auth/user/content/media/feed/messaging/notification/streaming）均提供 `/metrics`。  
- **核心告警**：
  1. `HighErrorRate`：5 分钟内 `http_requests_total{status="5xx"}` > 1%  
  2. `RedisSentinelFailover`：`redis_master_switch_total` 监测主从切换  
  3. `KafkaConsumerLag`：`kafka_consumergroup_lag` 超阈值  
  4. `JWTKeyReloadFailure`：启动阶段日志中如出现 `Failed to initialize JWT keys` 立即告警
- **集中日志**：建议将各服务的 `stdout` 推送至 Loki / ELK，标签包含 `service`, `namespace`, `commit`.

---

## 6. 冒烟测试流程

> 全量通过需约 45 分钟，可并行执行。

1. **部署验证**
   ```bash
   kubectl -n nova get pods
   kubectl -n nova wait --for=condition=ready pod -l app.kubernetes.io/part-of=nova --timeout=300s
   ```
2. **健康检查**
   ```bash
   for svc in auth user content media messaging feed notification streaming; do
     kubectl -n nova port-forward svc/$svc 18080 &
     sleep 2
     curl -fsS http://127.0.0.1:18080/health || exit 1
   done
   ```
3. **Redis Sentinel 主备切换**
   ```bash
   kubectl -n infra exec -it redis-sentinel-0 -- redis-cli SENTINEL failover nova-master
   # 30s 内确认新的 master 被发现，业务无 5xx 日志
   ```
4. **Kafka 连通性**
   ```bash
   kubectl -n infra exec -it kafka-0 -- \
     kafka-topics.sh --describe --topic social.events --bootstrap-server kafka:9092
   ```
5. **跨服务 E2E**
   - 注册 → 登录（auth-service），拿到 JWT  
   - 调用 user-service `/api/v1/users/me`（验证 JWT 统一加载）  
   - 发帖（content-service）→ 拉取推荐（feed-service）  
   - 发送消息（messaging-service WebSocket + REST）  
   - 触发通知（notification-service）  
   - 上传媒体并查询转码状态（media-service）  
   - 触发 streaming `start_stream` → `get_stream_status`
6. **故障注入**
   - 手动暂停 ClickHouse (`kubectl scale statefulset clickhouse --replicas=0`)：确认 user/content 服务 readiness 失败但不会返回 5xx  
   - 断开 Kafka broker：确认 `messaging-service` circuit breaker 告警

> CI 連動：`.github/workflows/staging-smoke.yml` 會在手動觸發、排程或部署成功後執行以上流程，需在儲存庫 Secrets 設定 `STAGING_KUBE_CONFIG`（base64 編碼 kubeconfig），並可透過 workflow_dispatch 的 `namespace` 參數覆寫目標命名空間。

---

## 7. 待办 / 风险提示

- [x] 为 auth/media/feed 添加 Prometheus exporter  
- [x] messaging-service `/metrics` 输出 Prometheus 格式  
- [ ] 更新 `k8s/infrastructure/base` 中缺失的 Deployment（auth/feed/notification/streaming）  
- [ ] 将 `REDIS_SENTINEL_ENDPOINTS` 宣告同步到所有 ConfigMap  
- [x] 编写自动化 smoke test（`scripts/smoke-staging.sh` 已提供，可整合至 CI）

---

**最后更新**：2025-10-30  
**联系人**：Platform Infra @ Nova
