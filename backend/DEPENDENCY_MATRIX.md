# Nova 服务依赖矩阵

**生成时间**: 2025-11-11
**验证脚本**: `backend/scripts/validate-boundaries-simple.sh`

---

## 数据库访问矩阵

### users 表访问统计

| 服务 | 查询次数 | 写操作 | 拥有权 | 状态 |
|------|---------|--------|-------|------|
| **user-service** | 18 | ✓ | ✅ 拥有者 | ✅ 正确 |
| auth-service | 24 | ✓ | ❌ | 🔴 违规 |
| messaging-service | 4 | ✓ | ❌ | 🔴 **BLOCKER** |
| search-service | 2 | - | ❌ | 🟡 应通过事件 |
| streaming-service | 2 | - | ❌ | 🟡 应通过 gRPC |
| graphql-gateway | 1 | - | ❌ | 🟡 应通过 gRPC |

**总计**: 6 个服务访问 users 表（应该只有 1 个）

---

### posts 表访问统计

| 服务 | 查询次数 | 写操作 | 拥有权 | 状态 |
|------|---------|--------|-------|------|
| **content-service** | 32 | ✓ | ✅ 拥有者 | ✅ 正确 |
| feed-service | 6 | - | ❌ | 🔴 违规 |
| search-service | 5 | - | ❌ | 🟡 应通过事件 |
| user-service | 1 | - | ❌ | 🟡 CDC 可接受 |

**总计**: 4 个服务访问 posts 表（应该只有 1 个）

---

## gRPC 调用矩阵

| 调用方 ↓ \ 被调用方 → | auth | user | content | feed | messaging | notification |
|---------------------|------|------|---------|------|-----------|-------------|
| **auth-service** | - | 0 | 0 | 0 | 0 | 0 |
| **user-service** | 12 | - | 26 | 0 | 0 | 0 |
| **content-service** | 19 | 0 | - | 0 | 0 | 0 |
| **feed-service** | 17 | 6 | 7 | - | 0 | 0 |
| **messaging-service** | 19 | 0 | 0 | 0 | - | 0 |
| **notification-service** | 0 | 0 | 0 | 0 | 0 | - |

### 循环依赖标记

- 🔴 **Chain 1**: `auth-service` ↔ `user-service` (auth 通过 DB 访问 users，user 通过 gRPC 调用 auth)
- 🔴 **Chain 2**: `content-service` ↔ `feed-service` (互相通过 gRPC 调用)
- 🔴 **Chain 3**: `user-service` → `content-service` → `auth-service` (传递依赖链)

---

## 服务依赖深度

```
Level 0 (无依赖):
  - events-service
  - cdn-service
  - media-service

Level 1 (依赖 Level 0):
  - auth-service → users (DB, 应该分离到 identity-service)

Level 2 (依赖 Level 1):
  - user-service → auth-service (12 次 gRPC)
  - content-service → auth-service (19 次 gRPC)
  - messaging-service → auth-service (19 次 gRPC)

Level 3 (依赖 Level 2):
  - feed-service → user (6), content (7), auth (17)
  - user-service → content-service (26 次 gRPC) ← 形成循环!

Level 4 (Gateway):
  - graphql-gateway → 所有服务
```

**最大依赖深度**: 4 层
**目标**: < 3 层

---

## 跨服务写操作 (BLOCKER)

### 1. messaging-service → users 表

**代码位置**:
```
messaging-service/src/services/conversation_service.rs:333
messaging-service/src/services/conversation_service.rs:344
```

**违规代码**:
```rust
sqlx::query("INSERT INTO users (id, username) VALUES ($1, $2) ON CONFLICT (id) DO NOTHING")
    .bind(user_id)
    .bind(username)
    .execute(&self.pool)
    .await?;
```

**风险**:
- 绕过 user-service 的业务逻辑
- 审计日志丢失
- 数据一致性风险

**修复方案**:
```rust
// ✅ 方案 1: gRPC 调用
let user = self.user_client
    .get_or_create_user(GetOrCreateUserRequest {
        id: user_id,
        username: username.clone(),
    })
    .await?;

// ✅ 方案 2: 发布事件
self.event_bus.publish(Event::UserSeenInMessage {
    user_id,
    username,
    timestamp: Utc::now(),
}).await?;
```

---

## GraphQL Gateway 架构问题

**当前依赖**:
```toml
[dependencies]
sqlx = { workspace = true, features = ["runtime-tokio", "postgres"] }
db-pool = { path = "../libs/db-pool" }
```

**问题**:
- Gateway 应该是无状态的 API 聚合层
- 不应该直接访问数据库
- 所有数据应该通过 gRPC 从后端服务获取

**修复方案**:
```toml
# 移除 sqlx 依赖
# 添加 gRPC 客户端
[dependencies]
grpc-clients = { path = "../libs/grpc-clients" }
```

---

## 服务边界评分

| 服务 | 数据所有权 | gRPC 使用 | 事件驱动 | 独立部署 | 总分 |
|------|-----------|----------|---------|---------|------|
| **user-service** | 🟡 (被 auth 访问) | ✅ | ❌ | ❌ | 5/10 |
| **auth-service** | 🔴 (访问 users) | ✅ | ❌ | ❌ | 4/10 |
| **content-service** | ✅ | ✅ | ❌ | ❌ | 6/10 |
| **feed-service** | 🔴 (访问 posts) | ✅ | ❌ | ❌ | 4/10 |
| **messaging-service** | 🔴 (写 users) | ✅ | ❌ | ❌ | 3/10 |
| **notification-service** | ✅ | ❌ | ✅ | ✅ | 8/10 |
| **search-service** | 🟡 (读多表) | ❌ | ✅ | ✅ | 7/10 |
| **media-service** | ✅ | ❌ | ✅ | ✅ | 9/10 |
| **events-service** | ✅ | ❌ | N/A | ✅ | 10/10 |
| **cdn-service** | ✅ | ❌ | N/A | ✅ | 10/10 |

**平均分**: 6.6/10
**目标**: 8/10

---

## 修复优先级

### P0 (本周必须修复)

1. ✅ **messaging-service 停止写 users 表**
   - 风险: 数据一致性破坏
   - 工作量: 2 小时
   - 影响: messaging-service 重新部署

2. ✅ **创建 identity-service**
   - 风险: auth-service 和 user-service 启动死锁
   - 工作量: 1 周
   - 影响: 需要数据迁移

3. ✅ **feed-service 停止直接查询 posts 表**
   - 风险: 数据不一致（gRPC 缓存 vs 直接 DB）
   - 工作量: 3 天
   - 影响: feed-service 性能可能下降（需要优化缓存）

### P1 (下周修复)

4. 🔲 **GraphQL Gateway 移除 sqlx 依赖**
   - 风险: 架构反模式
   - 工作量: 1 天
   - 影响: DataLoader 重构

5. 🔲 **search-service 和 streaming-service 改用 gRPC**
   - 风险: 中等（只读操作）
   - 工作量: 2 天
   - 影响: 性能可能略有下降

### P2 (1 个月内修复)

6. 🔲 **实施事件驱动架构**
   - 风险: 低（增量改进）
   - 工作量: 2 周
   - 影响: 系统整体架构升级

---

## 验证命令

### 手动验证

```bash
# 1. 检查 messaging-service 是否还在写 users 表
cd backend
grep -r "INSERT INTO users\|UPDATE users SET" messaging-service/src --include="*.rs"

# 预期: 无输出 (0 次)
# 当前: 2 次 (BLOCKER)

# 2. 检查 feed-service 是否还在读 posts 表
grep -r "FROM posts" feed-service/src --include="*.rs" | grep -v test

# 预期: 0 次
# 当前: 6 次

# 3. 检查 GraphQL Gateway 是否有 sqlx 依赖
grep sqlx graphql-gateway/Cargo.toml

# 预期: 无输出
# 当前: 有依赖
```

### 自动化验证

```bash
# 运行边界验证脚本
cd backend
./scripts/validate-boundaries-simple.sh

# 预期结果:
# ✅ ALL CHECKS PASSED

# 当前结果:
# ❌ FAILED: 1 blocker(s) found
```

---

## 重构进度跟踪

| 任务 | 负责人 | 开始日期 | 目标完成日期 | 状态 |
|------|-------|---------|------------|------|
| 修复 messaging-service 写 users | TBD | - | Week 1 | 🔴 待开始 |
| 创建 identity-service | TBD | - | Week 1 | 🔴 待开始 |
| feed-service 事件驱动 | TBD | - | Week 2 | 🔴 待开始 |
| GraphQL Gateway 重构 | TBD | - | Week 2 | 🔴 待开始 |
| 完整事件驱动架构 | TBD | - | Week 4 | 🔴 待开始 |

---

## 相关文档

- 📊 **完整分析报告**: `backend/DEPENDENCY_SCAN_REPORT.md`
- 📝 **审计报告**: `backend/SERVICE_DEPENDENCY_AUDIT.md`
- ✅ **验证脚本**: `backend/scripts/validate-boundaries-simple.sh`
- 📋 **数据所有权矩阵**: `backend/DATA_OWNERSHIP_MATRIX.md`
- 🔄 **事件驱动架构**: `backend/EVENT_DRIVEN_ARCHITECTURE.md`

---

**最后更新**: 2025-11-11
**下次验证**: 每次代码合并前自动运行
**责任人**: Backend Architecture Team
