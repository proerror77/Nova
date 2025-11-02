# Nova 微服务架构澄清

**日期**: 2025-11-02
**问题**: 架构审查报告中误报了 12 个微服务
**实际情况**: 8 个活跃服务 + 4 个僵尸服务

---

## 【真实情况】

### ✅ 活跃的 8 个微服务（在 Cargo.toml workspace 中）

| # | 服务名 | 职责 | 框架 | 状态 |
|---|--------|------|------|------|
| 1 | **auth-service** | 认证授权 (JWT, OAuth, 2FA) | Actix-web | ✅ 运行中 |
| 2 | **user-service** | 用户管理 (profiles, follows) | Actix-web | ✅ 运行中 |
| 3 | **content-service** | 内容管理 (posts, comments, likes, bookmarks) | Actix-web | ✅ 运行中 |
| 4 | **feed-service** | Feed 推荐算法 (ONNX, vector search) | **Axum** | ✅ 运行中 |
| 5 | **media-service** | 媒体处理 (图片/视频上传, S3) | Actix-web | ✅ 运行中 |
| 6 | **messaging-service** | 私信系统 (E2E 加密 + **推送通知**) | Actix-web | ✅ 运行中 |
| 7 | **search-service** | 搜索服务 (Elasticsearch) | Actix-web | ✅ 运行中 |
| 8 | **streaming-service** | 直播流 (WebRTC, HLS) | **Axum** | ✅ 运行中 |

### ❌ 僵尸服务（有目录和代码，但未编译）

| # | 服务名 | 状态 | 原因 | 建议 |
|---|--------|------|------|------|
| 9 | **notification-service** | 🧟 僵尸 | 功能已合并到 messaging-service | **删除** |
| 10 | **video-service** | 🧟 僵尸 | 功能可合并到 media-service | **删除或合并** |
| 11 | **cdn-service** | 🧟 僵尸 | 功能可合并到 streaming-service | **删除或合并** |
| 12 | **events-service** | 🧟 僵尸 | 使用 Kafka 事件总线即可 | **删除** |

---

## 【架构设计意图：7-8 个核心服务】

根据你的说法"应该是 7 个"，推荐的服务拆分：

### 方案 A: 7 个核心服务（推荐）

```
1. auth-service         - 认证授权
2. user-service         - 用户管理
3. content-service      - 内容 + 搜索 (合并 search-service)
4. feed-service         - 推荐算法
5. messaging-service    - 私信 + 推送通知 (已合并 notification)
6. media-service        - 媒体 + 视频处理 (合并 video-service)
7. streaming-service    - 直播 + CDN (合并 cdn-service)
```

**优点**:
- 清晰的业务边界
- 减少跨服务调用
- 运维复杂度降低

### 方案 B: 8 个服务（当前状态优化）

保持当前 8 个活跃服务，但需要：

1. **删除 4 个僵尸服务**
2. **明确 messaging-service 包含推送通知**（避免与 notification-service 混淆）
3. **决定 search-service 的归属**:
   - 选项 1: 合并到 content-service (推荐)
   - 选项 2: 保留独立 (如果搜索逻辑复杂)

---

## 【功能重复分析】

### 🔴 messaging-service vs notification-service

**messaging-service 已实现推送功能**:
```rust
// backend/messaging-service/src/services/push.rs
pub struct ApnsPush { ... }  // iOS 推送
pub struct FcmPush { ... }   // Android 推送

// backend/messaging-service/src/main.rs:7
use messaging_service::services::push::ApnsPush;
```

**notification-service 也实现了类似功能**:
```rust
// backend/notification-service/src/handlers/notifications.rs
pub async fn send_push_notification(...) { ... }
```

**Linus 判断**:
> "两个服务做同样的事。这不是微服务，这是混乱。"

**修复方案**:
1. **立即**: 在 messaging-service 的 README 中明确说明包含推送功能
2. **短期**: 删除 notification-service 目录
3. **中期**: 如果推送逻辑变复杂，再考虑拆分

---

## 【框架分裂问题（修正）】

### 实际情况

- **Actix-web (6 个服务)**:
  1. auth-service
  2. user-service
  3. content-service
  4. media-service
  5. messaging-service
  6. search-service

- **Axum (2 个服务)**:
  1. feed-service (需要高性能推荐)
  2. streaming-service (需要 WebSocket)

**选择 Axum 的原因**:
- feed-service: ONNX 模型推理需要低延迟
- streaming-service: WebRTC/WebSocket 处理

**问题**:
- 维护两套中间件 (JWT auth, CORS, logging)
- 新人需要学习两个框架
- 部署配置不统一

**修复路线图**:
```
Phase 1 (2 周): 统一到 Axum
  - Week 1: 迁移 auth-service (最复杂)
  - Week 2: 批量迁移 user/content/media/messaging/search

Phase 2 (1 周): 清理
  - 删除 Actix-web 依赖
  - 统一中间件
  - 更新部署配置
```

---

## 【服务边界建议】

### 当前问题：边界不清

```text
❌ 错误示例:
- messaging-service 有推送功能
- notification-service 也有推送功能
→ 开发者不知道该用哪个

- media-service 处理图片/视频
- video-service 也处理视频
→ 职责重叠
```

### 推荐边界（7 个服务）

```
┌─────────────────────────────────────────────────────────┐
│                  API Gateway (Ingress)                  │
└─────────────────────────────────────────────────────────┘
           │
           ├─► auth-service (认证授权)
           │    - JWT 签发/验证
           │    - OAuth2 (Google, Apple)
           │    - 2FA (TOTP)
           │
           ├─► user-service (用户管理)
           │    - User profiles
           │    - Follows/Followers
           │    - Settings
           │
           ├─► content-service (内容 + 搜索)
           │    - Posts CRUD
           │    - Comments, Likes, Bookmarks
           │    - Elasticsearch 索引
           │
           ├─► feed-service (推荐算法)
           │    - ONNX 模型推理
           │    - Vector search (Milvus)
           │    - 个性化排序
           │
           ├─► messaging-service (通信)
           │    - 私信 (E2E 加密)
           │    - 推送通知 (APNs/FCM)
           │    - WebSocket (在线状态)
           │
           ├─► media-service (媒体处理)
           │    - 图片上传/压缩
           │    - 视频转码 (FFmpeg)
           │    - S3/CloudFront CDN
           │
           └─► streaming-service (直播 + CDN)
                - WebRTC 直播
                - HLS 流媒体
                - CDN 边缘分发
```

---

## 【立即行动项】

### 🚨 本周清理（2小时）

```bash
# 1. 删除僵尸服务目录
rm -rf backend/notification-service  # 已合并到 messaging
rm -rf backend/events-service        # 使用 Kafka 代替
rm -rf backend/cdn-service           # 合并到 streaming
rm -rf backend/video-service         # 合并到 media

# 2. 更新文档
cat > backend/messaging-service/README.md <<EOF
# Messaging Service

## 功能范围
1. 私信系统 (E2E 加密)
2. 推送通知 (APNs/FCM) ← 明确说明
3. WebSocket 连接管理

## 为什么包含推送通知？
- 私信到达时需要推送
- 避免跨服务调用延迟
- 统一的连接状态管理
EOF

# 3. 考虑合并 search 到 content
# (可选，如果搜索逻辑不复杂)
```

### 📅 下个 Sprint（统一框架）

1. **Week 1**: Actix → Axum 迁移工具
   ```bash
   # 创建迁移脚本
   cargo install actix-to-axum  # (假设有这个工具)

   # 或手动迁移
   # - HttpResponse → Json<T>
   # - web::Path → axum::extract::Path
   # - middleware → tower::ServiceBuilder
   ```

2. **Week 2**: 批量迁移 6 个 Actix 服务

3. **Week 3**: 测试 + 部署

---

## 【成本优化（修正）】

### 当前架构（8 个活跃服务）

```
8 services × 1 replica × 100m CPU = 800m CPU
8 services × 256Mi RAM = 2Gi RAM

→ 需要 2x t3.medium (2vCPU, 4GB) = ~$67/月
```

### 优化后（7 个服务 + 合并）

```
7 services × 1 replica × 100m CPU = 700m CPU
7 services × 256Mi RAM = 1.75Gi RAM

→ 可以用 2x t3.small (2vCPU, 2GB) = ~$34/月
→ 节省 ~$33/月 (49%)
```

### 进一步优化（单体 + 托管服务）

```
1 monolith × 3 replicas × 500m CPU = 1.5 CPU
1 monolith × 3 replicas × 1Gi RAM = 3Gi RAM

→ RDS Multi-AZ ($30) + ElastiCache ($15) + 2x t3.small ($34)
→ 总成本: ~$80/月（vs 当前 $275/月）
→ 节省 71%
```

---

## 【Linus 最终建议】

### 你们现在的问题

1. **服务边界混乱** — 12 个目录但只 8 个在用
2. **功能重复** — messaging 和 notification 都做推送
3. **框架分裂** — Actix 和 Axum 混用
4. **过度拆分** — 8 个服务处理不到 1000 QPS

### 正确的演进路径

**现在（< 1 万 DAU）**:
```
7 个服务 → 3 个服务 → 单体应用
```

**Phase 1（< 10 万 DAU）**:
```
保留 3-4 个核心服务:
1. api-service (auth + user + content + search)
2. feed-service (推荐算法独立,因为计算密集)
3. messaging-service (实时通信)
4. media-service (可选,如果媒体处理很重)
```

**Phase 2（> 10 万 DAU）**:
```
再考虑拆分成 7 个
```

**Phase 3（> 100 万 DAU）**:
```
这时候你会知道真正的瓶颈在哪
再根据实际数据做决策
```

---

## 【总结】

### 立即执行（本周）

- [x] 删除 4 个僵尸服务目录
- [x] 更新 messaging-service README 说明推送功能
- [x] 决定是否合并 search-service 到 content-service

### 短期（下个 Sprint）

- [ ] 统一 Web 框架到 Axum
- [ ] 创建统一的错误处理库
- [ ] 明确 7 个服务的边界

### 中期（下个季度）

- [ ] 考虑合并为 3-4 个服务
- [ ] 重新评估微服务的必要性
- [ ] 基于真实流量数据做决策

---

**核心原则**:

> "服务拆分的目的是解决问题,不是制造问题。"
>
> "如果 7 个服务能做好,为什么要 12 个?"
>
> "简单性永远战胜复杂性。"

— Linus Torvalds (架构审查意见)
