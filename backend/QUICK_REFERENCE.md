# Nova 后端 - 快速参考指南

## 服务端口一览表

```
8080  → user-service      (认证、关系、Feed)
8081  → content-service   (发布、评论、故事)
8082  → media-service     (上传、视频、Reels)
8083  → auth-service      (待实现)
8085  → messaging-service (消息、通话、位置)
8086  → search-service    (搜索、建议)

9081  → content-service gRPC
9082  → media-service gRPC

5432  → PostgreSQL
6379  → Redis
8123  → ClickHouse
9092  → Kafka
8025  → MailHog Web UI
```

---

## API 速查表

### 认证相关
```bash
# 注册
POST /api/v1/auth/register
  { "email": "...", "username": "...", "password": "..." }

# 登录
POST /api/v1/auth/login
  { "email": "...", "password": "..." }
  → { "access_token": "...", "refresh_token": "..." }

# 刷新令牌
POST /api/v1/auth/refresh
  { "refresh_token": "..." }

# 启用2FA
POST /api/v1/auth/2fa/enable
POST /api/v1/auth/2fa/confirm
  { "totp_code": "..." }
```

### 用户关系
```bash
# 关注用户
POST /api/v1/users/{id}/follow

# 获取follower列表
GET /api/v1/users/{id}/followers

# 获取following列表
GET /api/v1/users/{id}/following

# 获取推荐用户
GET /api/v1/users/suggested
```

### 内容操作
```bash
# 创建发布
POST /api/v1/posts
  { "caption": "...", "images": [...] }

# 获取Feed
GET /api/v1/feed?limit=20&cursor=...

# 赞一条发布
POST /api/v1/posts/{id}/like

# 获取趋势
GET /api/v1/trending?type=posts|videos|users
```

### 消息相关
```bash
# 创建对话
POST /api/v1/conversations
  { "member_ids": [...], "kind": "direct|group" }

# 发送消息
POST /api/v1/conversations/{id}/messages
  { "content": "..." }

# 获取消息历史
GET /api/v1/conversations/{id}/messages?limit=50

# WebSocket实时消息
WebSocket /ws?conversation_id=...&user_id=...&token=...

# 群组通话
POST /api/v1/conversations/{id}/calls
  { "call_type": "group", "max_participants": 8 }

POST /api/v1/calls/{id}/join
  { "sdp": "..." }

GET /api/v1/calls/{id}/participants
```

### 搜索
```bash
# 统一搜索
GET /api/v1/search?q=...&types=user,post,hashtag

# 搜索建议
GET /api/v1/search/suggestions?prefix=...&type=user

# 热搜
GET /api/v1/search/trending?type=user
```

### 媒体上传
```bash
# 开始上传
POST /api/v1/uploads
  { "file_name": "...", "file_size": 1024000, "content_type": "video/mp4" }
  → { "upload_id": "...", "presigned_url": "..." }

# 上传进度
PATCH /api/v1/uploads/{id}/progress
  { "uploaded_size": 512000 }

# 完成上传
POST /api/v1/uploads/{id}/complete
  → { "video_id": "..." }
```

---

## 常用环境变量

```bash
# 基础配置
DATABASE_URL=postgresql://user:pass@localhost:5432/nova
REDIS_URL=redis://localhost:6379
CLICKHOUSE_URL=http://localhost:8123
KAFKA_BROKERS=localhost:9092

# JWT
JWT_PRIVATE_KEY_PEM="-----BEGIN PRIVATE KEY-----\n..."
JWT_PUBLIC_KEY_PEM="-----BEGIN PUBLIC KEY-----\n..."

# S3
AWS_S3_BUCKET=nova-media
AWS_S3_REGION=us-east-1
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...

# 邮件
SMTP_HOST=localhost
SMTP_PORT=1025
SMTP_USERNAME=...
SMTP_PASSWORD=...

# OAuth
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...

# APNs(iOS推送)
APNS_KEY_ID=...
APNS_TEAM_ID=...
APNS_PRIVATE_KEY_PATH=/path/to/key.p8

# Elasticsearch(可选)
ELASTICSEARCH_URL=http://localhost:9200
ELASTICSEARCH_POST_INDEX=nova_posts

# 日志
LOG_LEVEL=info
```

---

## 数据库常用查询

### PostgreSQL

```sql
-- 查看用户及最后登录时间
SELECT id, username, email, last_login_at FROM users ORDER BY last_login_at DESC LIMIT 10;

-- 查看活跃用户(过去7天)
SELECT DISTINCT user_id FROM posts WHERE created_at > NOW() - INTERVAL '7 days';

-- 查看Feed数据一致性(PostgreSQL vs ClickHouse)
SELECT COUNT(*) FROM posts WHERE soft_delete IS NULL;

-- 查看消息延迟
SELECT COUNT(*) FROM messages WHERE created_at > NOW() - INTERVAL '1 minute';

-- 看看Kafka CDC偏移量
SELECT * FROM pg_logical_slot_get_changes('replication_slot', NULL, NULL) LIMIT 10;
```

### ClickHouse

```sql
-- 查看Feed排序数据
SELECT user_id, post_id, engagement_score FROM feed_ranking_events ORDER BY created_at DESC LIMIT 100;

-- 检查数据延迟
SELECT COUNT(*) as event_count, MAX(created_at) as latest_event FROM feed_ranking_events;

-- 用户热门发布排序
SELECT post_id, user_id, engagement_score FROM feed_ranking_events 
WHERE user_id = 'user-uuid' ORDER BY engagement_score DESC LIMIT 10;
```

### Redis

```bash
# 查看缓存键
redis-cli KEYS 'feed:*'
redis-cli KEYS 'user:*'
redis-cli KEYS 'stream:*'

# 查看缓存大小
redis-cli INFO memory

# 清空所有缓存
redis-cli FLUSHALL
```

---

## 常见故障排查

### "Feed API 返回500"
```
症状: GET /api/v1/feed → 500 Internal Server Error
原因: ClickHouse连接失败
检查:
  1. ClickHouse是否运行: curl http://localhost:8123
  2. 检查日志: docker-compose logs clickhouse
  3. ClickHouse数据是否有: SELECT COUNT(*) FROM feed_ranking_events;

快速修复: 
  1. 重启ClickHouse: docker-compose restart clickhouse
  2. 或启用PostgreSQL后备排序(如已实现)
```

### "视频上传失败"
```
症状: POST /api/v1/uploads/*/complete → Failed
原因: S3连接或权限问题
检查:
  1. S3配置是否正确: echo $AWS_S3_BUCKET
  2. AWS凭证是否有效: aws s3 ls
  3. S3健康检查失败: docker-compose logs media-service

快速修复:
  1. 验证IAM权限包含s3:PutObject
  2. 检查S3桶存在且可访问
  3. 重启media-service
```

### "消息没有实时推送"
```
症状: 发送消息后WebSocket没有收到message.new事件
原因: WebSocket连接断开或消息队列堵塞
检查:
  1. WebSocket连接是否活跃: 检查客户端日志
  2. Redis在线状态: redis-cli GET "user:{id}:online"
  3. Kafka消息堆积: kafka-topics --describe --topic nova.events

快速修复:
  1. 重连WebSocket
  2. 检查messaging-service日志: docker-compose logs messaging-service
  3. 清空消息队列(仅开发): redis-cli FLUSHALL
```

### "ClickHouse数据过时"
```
症状: Feed排序不符合最新发布
原因: CDC Consumer落后或数据一致性问题
检查:
  1. 查看CDC延迟: SELECT MAX(created_at) FROM feed_ranking_events;
  2. 检查Kafka Consumer lag: kafka-consumer-groups --describe --group nova-cdc-consumer-v1

快速修复:
  1. 重启CDC Consumer: 重启user-service
  2. 触发全量重新同步(如有实现): curl -X POST /api/v1/admin/resync-clickhouse
```

---

## 性能调优建议

### 快速提升(1-2周)

| 问题 | 方案 | 效果 |
|------|------|------|
| Feed延迟 | 增加Redis缓存TTL | P99延迟 -30% |
| 搜索慢 | 添加PostgreSQL索引 | 搜索 -70% |
| WebSocket连接多 | 启用消息压缩 | 带宽 -50% |
| S3上传慢 | 使用多线程上传 | 速度 +3倍 |

### 中期改进(1-2月)

1. ClickHouse 副本 + 负载均衡
2. PostgreSQL 连接池优化
3. Redis 集群化
4. Kafka partition 增加
5. CDN 集成(直播/Reels)

### 长期规划(3-6月)

1. SFU 群组通话
2. 数据库分片
3. 多地域部署
4. 消息队列替换(Kafka → Pulsar)

---

## 开发工作流

### 启动本地环境
```bash
# 1. 克隆并进入目录
cd ~/Documents/nova

# 2. 启动Docker服务
docker-compose up -d

# 3. 检查服务健康
curl http://localhost:8080/api/v1/health
curl http://localhost:8081/api/v1/health
curl http://localhost:8085/api/v1/health

# 4. 运行Rust服务(开发模式)
cd backend/user-service
cargo watch -x run
```

### 构建与部署
```bash
# 构建Docker镜像
docker build -t nova-user-service:latest -f Dockerfile .

# 本地运行镜像
docker run -it --rm -p 8080:8080 nova-user-service:latest

# 推送到仓库
docker tag nova-user-service:latest myregistry/nova-user-service:latest
docker push myregistry/nova-user-service:latest

# Kubernetes部署
kubectl apply -f k8s/user-service-deployment.yaml
kubectl rollout status deployment/user-service
```

### 测试
```bash
# 单元测试
cargo test --lib

# 集成测试
cargo test --test '*'

# 性能测试
cargo bench

# 代码覆盖率
cargo tarpaulin --out Html
```

---

## 关键指标监控

### 需要告警的指标

```
1. ClickHouse查询延迟 > 1000ms
   → 作用: Feed排序性能监控

2. CDC消费延迟 > 30s
   → 作用: 数据一致性监控

3. WebSocket连接数突增 > 50% baseline
   → 作用: 服务容量监控

4. S3上传失败率 > 1%
   → 作用: 媒体服务健康度

5. PostgreSQL连接池使用率 > 80%
   → 作用: 数据库容量监控

6. Redis内存使用 > 70%
   → 作用: 缓存容量监控

7. Kafka Producer lag > 100k messages
   → 作用: 事件处理延迟

8. API P99延迟 > 500ms
   → 作用: 用户体验监控
```

---

## 文档导航

| 文档 | 用途 |
|------|------|
| **EXECUTIVE_SUMMARY.md** | 高管/决策者 - 1页总结 |
| **BACKEND_ARCHITECTURE_ANALYSIS.md** | 架构师/技术负责人 - 详细分析 |
| **QUICK_REFERENCE.md** | 开发者/运维 - 快速查询(本文件) |
| **GROUP_CALL_TEST_REPORT.md** | QA/测试 - 群组通话测试 |
| **LONG_TERM_SFU_PLAN.md** | 产品/架构 - SFU迁移规划 |
| **API_GATEWAY_CONFIG.md** | 运维 - 网关配置 |
| **ENCRYPTION_ARCHITECTURE.md** | 安全/运维 - 加密架构 |
| **WEBSOCKET_PROTOCOL_VERSIONING.md** | 前端/后端 - WebSocket协议版本 |

---

**最后更新**: 2025-10-29  
**版本**: 1.0
