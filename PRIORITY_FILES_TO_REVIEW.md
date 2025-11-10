# Nova 项目 - 优先审查文件清单

**生成日期**: 2025-11-10  
**总文件数**: 113,136 行代码  
**优先级**: P0 (安全) > P1 (核心业务) > P2 (优化)

---

## 快速导航

1. **[P0 必须审查](#p0-必须审查)** - 安全关键，必须100%通过
2. **[P1 高优先级](#p1-高优先级)** - 核心业务，需深入理解
3. **[P2 建议审查](#p2-建议审查)** - 代码质量改进
4. **[文件索引](#文件快速查询)** - 按服务查询文件

---

## P0 必须审查

### 🔐 认证与授权 (3文件)

| 文件路径 | 行数 | 风险 | 检查项 |
|---------|------|------|-------|
| `backend/graphql-gateway/src/middleware/jwt.rs` | 234 | 🔴 高 | JWT签名验证、令牌过期检查、凭证存储 |
| `backend/auth-service/src/grpc/mod.rs` | 956 | 🔴 高 | OAuth2流程、权限检查、令牌签发 |
| `backend/auth-service/src/services/oauth.rs` | 745 | 🔴 高 | 状态参数验证、重定向URI检查、授权码一次性 |

**关键检查点**:
```rust
// ❌ 第91行 - 应该使用错误处理而非panic
let jwt_secret = env::var("JWT_SECRET")
    .expect("JWT_SECRET environment variable must be set");

// ✅ 应该改为
let jwt_secret = env::var("JWT_SECRET")
    .map_err(|_| AppError::ConfigError("JWT_SECRET not set".into()))?;
```

**预期时间**: 1-2小时

---

### 🔒 加密与数据保护 (3文件)

| 文件路径 | 行数 | 风险 | 检查项 |
|---------|------|------|-------|
| `backend/libs/crypto-core/src/jwt.rs` | 617 | 🔴 高 | JWT编码/解码、签名验证、密钥管理 |
| `backend/messaging-service/src/grpc/mod.rs` | 1167 | 🔴 极高 | E2EE实现、密钥交换、消息验证 |
| `backend/messaging-service/src/services/message_service.rs` | 708 | 🔴 高 | 消息加密、存储、重放攻击防护 |

**关键检查点**:
- AES-GCM的IV是否每次随机生成
- AEAD标签是否被验证
- 密钥导出函数(KDF)是否使用安全算法
- 消息序列号是否防止重放

**预期时间**: 2-3小时

---

### 💾 数据库访问 (4文件)

| 文件路径 | 行数 | 风险 | 检查项 |
|---------|------|------|-------|
| `backend/libs/db-pool/src/lib.rs` | - | 🔴 高 | 连接池超时、最大连接数、获取超时 |
| `backend/content-service/src/db/post_repo.rs` | 721 | 🔴 高 | SQL查询、参数化、索引使用 |
| `backend/user-service/src/grpc/server.rs` | 865 | 🟡 中 | 权限检查、数据隔离 |
| `backend/events-service/src/services/outbox.rs` | 638 | 🟡 中 | 事务性、重复检测 |

**关键检查点**:
```rust
// ❌ 危险：字符串拼接
query = format!("SELECT * FROM posts WHERE user_id = '{}'", user_id);

// ✅ 安全：参数化
query("SELECT * FROM posts WHERE user_id = $1").bind(user_id)
```

**预期时间**: 1.5-2小时

---

### 🌐 API网关 (3文件)

| 文件路径 | 行数 | 风险 | 检查项 |
|---------|------|------|-------|
| `backend/graphql-gateway/src/main.rs` | 133 | 🔴 高 | 服务初始化、错误处理、超时配置 |
| `backend/graphql-gateway/src/clients.rs` | 254 | 🔴 高 | gRPC连接管理、超时、重试逻辑 |
| `backend/graphql-gateway/src/schema/mod.rs` | 45 | 🟢 低 | GraphQL schema结构 |

**关键检查点**:
- 是否为所有外部调用设置了超时
- 是否使用了连接池而非新建连接
- 是否有断路器保护

**预期时间**: 1小时

---

## P1 高优先级

### 📦 核心业务逻辑 (7文件)

| 文件路径 | 行数 | 复杂度 | 建议审查 |
|---------|------|-------|--------|
| `backend/content-service/src/grpc/server.rs` | 1268 | 🔴 极高 | 🚨 **需要拆分** - 分离Post/Comment逻辑 |
| `backend/messaging-service/src/grpc/mod.rs` | 1167 | 🔴 极高 | 分离发送/接收/加密逻辑 |
| `backend/user-service/src/main.rs` | 1099 | 🔴 极高 | 分离初始化/业务/配置逻辑 |
| `backend/search-service/src/main.rs` | 967 | 🔴 高 | ElasticSearch集成 |
| `backend/events-service/src/grpc.rs` | 1005 | 🟡 中 | Kafka事件驱动 |
| `backend/feed-service/src/grpc.rs` | 895 | 🟡 中 | 推荐算法实现 |
| `backend/notification-service/src/grpc.rs` | 731 | 🟡 中 | APNs/FCM集成 |

**重构优先级**:
1. `content-service/grpc/server.rs` (1268行 → 拆分为400/400/400)
2. `messaging-service/grpc/mod.rs` (1167行 → 拆分为400/400/350)
3. `user-service/main.rs` (1099行 → 拆分为400/400/300)

**预期时间**: 8-10小时

---

### 🔧 关键库文件 (6文件)

| 文件路径 | 行数 | 用途 | 优先级 |
|---------|------|------|--------|
| `backend/libs/crypto-core/src/jwt.rs` | 617 | JWT核心 | P0 |
| `backend/auth-service/src/services/oauth.rs` | 745 | OAuth2 | P0 |
| `backend/notification-service/src/services/notification_service.rs` | 709 | 通知 | P1 |
| `backend/media-service/src/services/mod.rs` | 744 | 媒体处理 | P1 |
| `backend/feed-service/src/services/recommendation_v2/hybrid_ranker.rs` | - | 推荐 | P1 |
| `backend/search-service/src/services/elasticsearch.rs` | 672 | 搜索 | P1 |

**预期时间**: 4-6小时

---

### 📡 集成与测试 (4文件)

| 文件路径 | 行数 | 覆盖范围 | 状态 |
|---------|------|--------|------|
| `backend/messaging-service/tests/e2ee_integration_test.rs` | 970 | E2EE | ✅ 完整 |
| `backend/messaging-service/tests/grpc_phase1b_test.rs` | 648 | gRPC基础 | ✅ 完整 |
| `backend/messaging-service/tests/grpc_phase1a_test.rs` | 621 | Phase 1A | ✅ 完整 |
| `backend/content-service/tests/grpc_content_service_test.rs` | 649 | 内容服务 | ✅ 完整 |

**检查项**:
- 测试是否覆盖了所有错误路径
- 是否使用了testcontainers进行隔离
- 是否测试了并发场景

**预期时间**: 2-3小时

---

## P2 建议审查

### 🎨 代码质量改进 (10+文件)

**目标**: 平均文件大小从 650 行 → 400 行

| 优化项 | 当前状态 | 目标 | 难度 |
|-------|--------|------|------|
| 函数提取 | 多个 > 100行 | < 50行 | 中 |
| 错误处理 | 部分使用expect | 全部使用Result | 中 |
| 注释文档 | 缺少内部逻辑注释 | 100%记录 | 低 |
| 测试覆盖 | ~70% | > 85% | 高 |

**预期时间**: 10-15小时

---

## iOS审查清单

### 🍎 Swift关键文件 (8文件)

| 文件路径 | 类型 | 风险 | 优先级 |
|---------|------|------|-------|
| `ios/NovaSocial.old/Services/AuthService.swift` | 认证 | 🔴 高 | P0 |
| `ios/NovaSocial.old/Services/FeedService.swift` | 业务 | 🟡 中 | P1 |
| `ios/NovaSocial.old/Services/PostInteractionService.swift` | 业务 | 🟡 中 | P1 |
| `ios/NovaSocial.old/Services/VoiceMessageService.swift` | 加密通讯 | 🔴 高 | P0 |
| `ios/NovaSocial.old/Localization/LocalizationManager.swift` | 国际化 | 🟢 低 | P2 |
| `ios/NovaSocial.old/Utils/DeepLinkRouter.swift` | 路由 | 🟢 低 | P2 |
| `ios/NovaSocial.old/Services/LocationService.swift` | 权限 | 🟡 中 | P1 |
| `ios/NovaSocial.old/Accessibility/AccessibilityHelpers.swift` | A11y | 🟢 低 | P2 |

**预期时间**: 3-4小时

---

## 文件快速查询

### 按服务分类

#### Auth Service
```
backend/auth-service/src/
├── grpc/mod.rs                    (956行) P0
├── services/oauth.rs              (745行) P0
├── tests/auth_tests.rs            (611行) P1
└── config/mod.rs                  (720行) P1
```

#### Content Service
```
backend/content-service/src/
├── grpc/server.rs                 (1268行) P0 🚨需拆分
├── db/post_repo.rs                (721行) P0
├── main.rs                         (665行) P1
└── tests/grpc_content_service_test.rs (649行) P1
```

#### User Service
```
backend/user-service/src/
├── main.rs                         (1099行) P0 🚨需拆分
├── grpc/server.rs                 (865行) P1
├── grpc/clients.rs                (885行) P1
├── config/mod.rs                  (720行) P1
└── tests/common/fixtures.rs       (645行) P1
```

#### Messaging Service
```
backend/messaging-service/src/
├── grpc/mod.rs                    (1167行) P0 🚨需拆分
├── services/message_service.rs    (708行) P1
├── routes/messages.rs             (933行) P1
├── tests/e2ee_integration_test.rs (970行) P1
└── tests/grpc_phase1b_test.rs     (648行) P1
```

#### Feed Service
```
backend/feed-service/src/
├── grpc.rs                        (895行) P1
├── handlers/recommendation.rs     (pending) P1
└── services/recommendation_v2/    (hybrid_ranker, onnx_serving) P1
```

#### Other Critical Services
```
backend/notification-service/src/
├── grpc.rs                        (731行) P1
├── services/notification_service.rs (709行) P1
├── services/priority_queue.rs     (636行) P1
└── services/apns_client.rs        (pending) P0

backend/search-service/src/
├── main.rs                        (967行) P1
├── services/elasticsearch.rs      (672行) P1

backend/events-service/src/
├── grpc.rs                        (1005行) P1
└── services/outbox.rs             (638行) P1
```

#### Shared Libraries
```
backend/libs/
├── crypto-core/src/jwt.rs         (617行) P0
├── db-pool/src/                   (pending) P0
├── actix-middleware/src/          (pending) P0
├── grpc-clients/src/              (pending) P1
└── redis-utils/src/               (pending) P1
```

#### GraphQL Gateway
```
backend/graphql-gateway/src/
├── main.rs                        (133行) P0
├── clients.rs                     (254行) P0
├── middleware/jwt.rs              (234行) P0
├── schema/auth.rs                 (99行) P1
├── schema/user.rs                 (125行) P1
├── schema/content.rs              (137行) P1
├── config.rs                      (162行) P1
└── schema/mod.rs                  (45行) P2
```

---

## 审查时间估计

| 阶段 | 文件数 | 行数 | 预计时间 |
|-----|--------|------|--------|
| P0安全审查 | 13 | 7,500 | 4-5小时 |
| P1核心业务 | 20 | 15,000 | 8-10小时 |
| P2代码质量 | 30+ | 20,000+ | 10-15小时 |
| iOS审查 | 8 | 5,000 | 3-4小时 |
| **总计** | **70+** | **47,500** | **25-34小时** |

**推荐策略**:
- 第一天: P0安全审查 (4-5小时)
- 第二天: P1核心业务 (8-10小时)
- 第三天: iOS + P2优化 (13-19小时)

---

## 风险评级汇总

### 🔴 极高风险（需立即修复）
1. GraphQL网关JWT认证 (可能导致认证绕过)
2. Content Service gRPC (业务逻辑最复杂)
3. Messaging Service E2EE (加密实现)
4. Auth Service OAuth (认证授权)

### 🟡 中等风险（需深入审查）
1. 文件大小过大 (1000+行，难以维护)
2. 缓存策略 (可能导致数据不一致)
3. 数据库连接池 (可能资源泄露)
4. 事件驱动可靠性 (消息可能丢失)

### 🟢 低风险（优化项）
1. 代码注释不足
2. 测试覆盖不完整
3. 日志结构化程度
4. 性能优化空间

---

## 使用本清单

### 步骤1：安全优先
```bash
# 审查所有P0文件，对每个文件：
# 1. 运行 cargo clippy 检查
# 2. 阅读代码找出安全问题
# 3. 检查测试覆盖
# 4. 记录发现的问题
```

### 步骤2：业务逻辑
```bash
# 对P1文件进行架构审查
# 1. 理解模块职责
# 2. 检查错误处理
# 3. 验证测试覆盖
# 4. 提出重构建议
```

### 步骤3：代码质量
```bash
# 对所有文件进行优化
# 1. 识别可提取的函数
# 2. 添加缺少的注释
# 3. 增强测试用例
# 4. 性能分析
```

---

## 关键指标

**代码健康分数 (总体)**:
- 安全性: 75% (需要修复JWT panic)
- 可维护性: 65% (文件过大)
- 测试覆盖: 70% (集成测试完善)
- 文档化: 60% (缺少内部注释)

**总体评分**: 67.5/100 (及格，需改进)

