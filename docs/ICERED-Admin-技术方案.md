# ICERED Admin 后台管理系统 - 技术方案

## 1. 项目概述

基于 Figma 生成的代码，为 Nova 社交平台构建完整的后台管理系统。

### 组成部分
- **admin-api**: Rust Axum 后端服务 (待开发)
- **admin-web**: React + shadcn/ui 前端应用 (Figma 已生成基础代码)

### MVP 范围 (用户确认)
1. ✅ Dashboard (首页概览) - Figma 已生成
2. ✅ 用户中心 - Figma 已生成
3. 🔨 内容 & 评论审核 - 待开发

### 认证方式 (用户确认)
- **独立 Admin 账户体系** (与普通用户分离)

### Figma 已生成代码分析

**技术栈：**
- React 18 + TypeScript
- Tailwind CSS
- shadcn/ui (Radix UI 基础组件)
- Recharts 图表
- Lucide 图标
- Vite 构建

**已完成组件：**
- `MainLayout.tsx` - 侧边栏 + 顶栏布局 (122行)
- `Dashboard.tsx` - 首页概览 (134行)
- `UserCenter.tsx` - 用户列表 + 详情 (286行)
- 50+ shadcn/ui 基础组件 (Button, Table, Card, etc.)

**待开发：**
- 登录页面
- API 调用层
- 内容审核页面
- 认证状态管理

---

## 2. 系统架构

```
┌─────────────────────────────────────────────────────────────────┐
│                        Load Balancer                             │
│                     (Nginx Ingress)                              │
└─────────────────────┬───────────────────────────────────────────┘
                      │
        ┌─────────────┴─────────────┐
        │                           │
        ▼                           ▼
┌───────────────┐           ┌───────────────┐
│  admin-web    │           │   admin-api   │
│  (React SPA)  │◄─────────►│ (Rust Axum)   │
│  Port: 3001   │   REST    │  Port: 8090   │
└───────────────┘           └───────┬───────┘
                                    │
                    ┌───────────────┼───────────────┐
                    │               │               │
                    ▼               ▼               ▼
            ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
            │ PostgreSQL  │ │   Redis     │ │  ClickHouse │
            │ (主数据库)   │ │ (缓存/会话) │ │ (分析数据)  │
            └─────────────┘ └─────────────┘ └─────────────┘
                    │
                    ▼
            ┌─────────────────────────────────────────┐
            │          Existing Services (gRPC)       │
            │  identity / content / social / trust    │
            └─────────────────────────────────────────┘
```

---

## 3. admin-api 服务设计

### 3.0 职责原则

admin-api 采用 **BFF（Backend for Frontend）模式**，作为聚合层而非业务层。

#### 核心原则

| 原则 | 说明 |
|------|------|
| **聚合不重复** | 聚合多个服务数据，不重复实现业务逻辑 |
| **调用不直连** | 写操作通过 gRPC 调用服务，不直接操作其他服务的表 |
| **只读可直查** | 复杂统计查询允许直接查数据库（只读） |
| **自有数据自管** | admin_users / audit_logs 等自有表直接管理 |

#### 数据所有权

| 数据 | 所有者 | admin-api 操作方式 |
|------|--------|-------------------|
| `admin_users` | admin-api | ✅ 直接读写 |
| `audit_logs` | admin-api | ✅ 直接读写 |
| `system_configs` | admin-api | ✅ 直接读写 |
| `users` | identity-service | ⚠️ 通过 gRPC |
| `posts/comments` | content-service | ⚠️ 通过 gRPC |
| `reports` | trust-safety | ⚠️ 通过 gRPC |

#### 操作路径示例

```
封禁用户:
  admin-api → identity-service.SuspendUser(user_id) → users 表

删除帖子:
  admin-api → content-service.RemovePost(post_id) → posts 表

Dashboard 统计（只读例外）:
  admin-api → 直接 SQL 查询 users/posts 表（只读聚合）
```

---

### 3.1 目录结构

```
backend/admin-api/
├── Cargo.toml
├── Dockerfile
├── build.rs                    # protobuf 代码生成
├── migrations/
│   ├── 001_admin_users.sql     # 管理员账户表
│   ├── 002_audit_logs.sql      # 操作审计日志
│   ├── 003_system_configs.sql  # 系统配置表
│   └── 004_feedback_tickets.sql # 反馈工单表
├── src/
│   ├── main.rs                 # 入口点
│   ├── lib.rs
│   ├── config.rs               # 配置管理
│   ├── error.rs                # 错误类型
│   ├── state.rs                # 应用状态
│   │
│   ├── middleware/
│   │   ├── mod.rs
│   │   ├── auth.rs             # JWT 验证
│   │   ├── admin_role.rs       # 角色权限检查
│   │   ├── audit.rs            # 审计日志记录
│   │   └── rate_limit.rs       # 速率限制
│   │
│   ├── handlers/               # HTTP 处理器 (按模块)
│   │   ├── mod.rs
│   │   ├── dashboard.rs        # 首页概览
│   │   ├── users.rs            # 用户中心
│   │   ├── content.rs          # 内容 & 评论
│   │   ├── identity.rs         # 身份 & 职业
│   │   ├── social.rs           # 社交 & 匹配
│   │   ├── ai.rs               # AI & Deepsearch
│   │   ├── operations.rs       # 运营 & 增长
│   │   ├── payments.rs         # 支付 & 会员
│   │   ├── feedback.rs         # 反馈 & 客服
│   │   ├── reports.rs          # 数据报表
│   │   └── settings.rs         # 系统设置
│   │
│   ├── services/               # 业务逻辑层
│   │   ├── mod.rs
│   │   ├── dashboard_service.rs
│   │   ├── user_service.rs
│   │   ├── content_service.rs
│   │   ├── moderation_service.rs
│   │   ├── analytics_service.rs
│   │   └── audit_service.rs
│   │
│   ├── db/                     # 数据访问层
│   │   ├── mod.rs
│   │   ├── admin_users.rs
│   │   ├── audit_logs.rs
│   │   ├── users.rs            # 查询主用户表
│   │   ├── content.rs
│   │   └── analytics.rs        # ClickHouse 查询
│   │
│   ├── grpc/                   # gRPC 客户端
│   │   ├── mod.rs
│   │   ├── identity_client.rs
│   │   ├── content_client.rs
│   │   ├── social_client.rs
│   │   └── trust_safety_client.rs
│   │
│   └── models/                 # 数据模型
│       ├── mod.rs
│       ├── admin.rs
│       ├── audit.rs
│       ├── dashboard.rs
│       └── common.rs
│
└── tests/
    └── integration/
```

### 3.2 API 端点设计

#### API 命名规范

| HTTP 方法 | 用途 | 示例 |
|-----------|------|------|
| `GET` | 查询数据 | `GET /users/:id` |
| `POST` | 创建资源 | `POST /users` |
| `POST /:id/action` | 状态变更/操作 | `POST /users/:id/suspend` |
| `PUT` | 完整更新 | `PUT /users/:id` |
| `PATCH` | 部分更新 | `PATCH /users/:id` |
| `DELETE` | 硬删除（慎用） | `DELETE /users/:id/permanent` |

**软删除/恢复统一使用 POST + action：**
```
POST /:resource/:id/remove   # 软删除（可恢复）
POST /:resource/:id/restore  # 恢复软删除
```

---

#### Dashboard (首页概览)
```
GET  /api/admin/v1/dashboard/overview      # 概览指标
GET  /api/admin/v1/dashboard/trends        # 7日趋势数据
GET  /api/admin/v1/dashboard/risk-monitor  # 风险监控数据
GET  /api/admin/v1/dashboard/alerts        # 系统告警
```

#### Users (用户中心)
```
GET    /api/admin/v1/users                      # 用户列表 (分页/搜索)
GET    /api/admin/v1/users/:id                  # 用户详情
GET    /api/admin/v1/users/:id/activities       # 用户活动记录
GET    /api/admin/v1/users/:id/reports          # 用户相关举报
POST   /api/admin/v1/users/:id/suspend          # 封禁用户
POST   /api/admin/v1/users/:id/unsuspend        # 解封用户
POST   /api/admin/v1/users/:id/warn             # 发送警告
POST   /api/admin/v1/users/:id/remove           # 软删除用户
POST   /api/admin/v1/users/:id/restore          # 恢复用户
```

#### Content (内容 & 评论)
```
GET    /api/admin/v1/content/posts              # 帖子列表
GET    /api/admin/v1/content/posts/:id          # 帖子详情
POST   /api/admin/v1/content/posts/:id/remove   # 删除帖子
POST   /api/admin/v1/content/posts/:id/restore  # 恢复帖子
GET    /api/admin/v1/content/comments           # 评论列表
POST   /api/admin/v1/content/comments/:id/remove
GET    /api/admin/v1/content/moderation-queue   # 待审核队列
POST   /api/admin/v1/content/moderation/:id/approve
POST   /api/admin/v1/content/moderation/:id/reject
```

#### Identity (身份 & 职业)
```
GET    /api/admin/v1/identity/verifications     # 认证申请列表
GET    /api/admin/v1/identity/verifications/:id
POST   /api/admin/v1/identity/verifications/:id/approve
POST   /api/admin/v1/identity/verifications/:id/reject
GET    /api/admin/v1/identity/professions       # 职业标签管理
POST   /api/admin/v1/identity/professions
PUT    /api/admin/v1/identity/professions/:id
DELETE /api/admin/v1/identity/professions/:id
```

#### Social (社交 & 匹配)
```
GET    /api/admin/v1/social/matches/stats       # 匹配统计
GET    /api/admin/v1/social/matches/config      # 匹配算法配置
PUT    /api/admin/v1/social/matches/config
GET    /api/admin/v1/social/reports             # 社交相关举报
GET    /api/admin/v1/social/blocked-pairs       # 互相拉黑的用户对
```

#### AI & Deepsearch
```
GET    /api/admin/v1/ai/config                  # AI 审核配置
PUT    /api/admin/v1/ai/config
GET    /api/admin/v1/ai/errors                  # AI 审核错误列表
POST   /api/admin/v1/ai/errors/:id/feedback     # 反馈纠正
GET    /api/admin/v1/ai/stats                   # AI 审核统计
GET    /api/admin/v1/search/config              # 搜索配置
PUT    /api/admin/v1/search/config
GET    /api/admin/v1/search/hot-keywords        # 热搜词管理
```

#### Operations (运营 & 增长)
```
GET    /api/admin/v1/operations/campaigns       # 活动列表
POST   /api/admin/v1/operations/campaigns
PUT    /api/admin/v1/operations/campaigns/:id
GET    /api/admin/v1/operations/push            # 推送管理
POST   /api/admin/v1/operations/push/send
GET    /api/admin/v1/operations/banners         # Banner 管理
POST   /api/admin/v1/operations/banners
GET    /api/admin/v1/operations/growth-metrics  # 增长指标
```

#### Payments (支付 & 会员)
```
GET    /api/admin/v1/payments/orders            # 订单列表
GET    /api/admin/v1/payments/orders/:id
POST   /api/admin/v1/payments/orders/:id/refund # 退款
GET    /api/admin/v1/payments/subscriptions     # 会员订阅
GET    /api/admin/v1/payments/revenue           # 收入统计
GET    /api/admin/v1/payments/plans             # 会员套餐管理
PUT    /api/admin/v1/payments/plans/:id
```

#### Feedback (反馈 & 客服)
```
GET    /api/admin/v1/feedback/tickets           # 工单列表
GET    /api/admin/v1/feedback/tickets/:id
PUT    /api/admin/v1/feedback/tickets/:id       # 更新工单状态
POST   /api/admin/v1/feedback/tickets/:id/reply # 回复工单
GET    /api/admin/v1/feedback/reports           # 用户举报
POST   /api/admin/v1/feedback/reports/:id/handle
GET    /api/admin/v1/feedback/suggestions       # 功能建议
```

#### Reports (数据报表)
```
GET    /api/admin/v1/reports/users              # 用户报表
GET    /api/admin/v1/reports/content            # 内容报表
GET    /api/admin/v1/reports/engagement         # 互动报表
GET    /api/admin/v1/reports/revenue            # 收入报表
POST   /api/admin/v1/reports/export             # 导出报表
GET    /api/admin/v1/reports/export/:id/status  # 导出状态
GET    /api/admin/v1/reports/export/:id/download
```

#### Settings (系统设置)
```
GET    /api/admin/v1/settings/general           # 通用设置
PUT    /api/admin/v1/settings/general
GET    /api/admin/v1/settings/admins            # 管理员列表
POST   /api/admin/v1/settings/admins            # 添加管理员
PUT    /api/admin/v1/settings/admins/:id        # 修改权限
DELETE /api/admin/v1/settings/admins/:id
GET    /api/admin/v1/settings/roles             # 角色管理
POST   /api/admin/v1/settings/roles
PUT    /api/admin/v1/settings/roles/:id
GET    /api/admin/v1/settings/audit-logs        # 审计日志
GET    /api/admin/v1/settings/feature-flags     # 功能开关
PUT    /api/admin/v1/settings/feature-flags/:key
```

### 3.3 数据库设计

#### admin_users (管理员账户 - 独立体系)
```sql
CREATE TABLE admin_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,  -- argon2 哈希
    role VARCHAR(50) NOT NULL DEFAULT 'viewer',  -- super_admin, admin, moderator, viewer
    permissions JSONB DEFAULT '[]',     -- 细粒度权限
    status VARCHAR(20) DEFAULT 'active',
    last_login_at TIMESTAMPTZ,
    login_attempts INT DEFAULT 0,       -- 登录失败次数（防暴力破解）
    locked_until TIMESTAMPTZ,           -- 账户锁定时间
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_admin_users_email ON admin_users(email);
CREATE INDEX idx_admin_users_role ON admin_users(role);
CREATE INDEX idx_admin_users_status ON admin_users(status);
```

#### audit_logs (审计日志)
```sql
CREATE TABLE audit_logs (
    id BIGSERIAL PRIMARY KEY,
    admin_id UUID REFERENCES admin_users(id),

    -- 分布式追踪
    request_id VARCHAR(36),             -- 单次请求 ID (UUID)
    trace_id VARCHAR(32),               -- OpenTelemetry trace ID
    span_id VARCHAR(16),                -- 当前 span ID

    -- 操作信息
    action VARCHAR(100) NOT NULL,       -- 'user.suspend', 'content.remove'
    resource_type VARCHAR(50),          -- 'user', 'post', 'comment'
    resource_id VARCHAR(255),
    old_value JSONB,
    new_value JSONB,

    -- 请求上下文
    ip_address INET,
    user_agent TEXT,
    duration_ms INT,                    -- 操作耗时
    error_message TEXT,                 -- 失败时的错误信息

    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_audit_logs_admin ON audit_logs(admin_id);
CREATE INDEX idx_audit_logs_action ON audit_logs(action);
CREATE INDEX idx_audit_logs_created ON audit_logs(created_at DESC);
CREATE INDEX idx_audit_logs_trace ON audit_logs(trace_id);
CREATE INDEX idx_audit_logs_request ON audit_logs(request_id);
CREATE INDEX idx_audit_logs_resource ON audit_logs(resource_type, resource_id);
```

**追踪字段说明：**
| 字段 | 格式 | 用途 |
|------|------|------|
| `request_id` | UUID | 关联同一 HTTP 请求的所有日志 |
| `trace_id` | 32 位 hex | 跨服务追踪（OpenTelemetry/Jaeger） |
| `span_id` | 16 位 hex | 当前操作在追踪链中的位置 |
| `duration_ms` | INT | 排查慢操作 |
| `error_message` | TEXT | 操作失败原因 |

#### 审计日志强制策略

**1. 必审操作清单**

| 级别 | 操作类型 | 示例 | 可跳过 |
|------|----------|------|--------|
| Critical | 用户封禁/删除 | `user.suspend`, `user.remove` | ❌ |
| Critical | 内容删除 | `post.remove`, `comment.remove` | ❌ |
| Critical | 权限变更 | `admin.role_change`, `admin.create` | ❌ |
| Critical | 系统配置 | `config.update` | ❌ |
| High | 数据导出 | `report.export` | ❌ |
| Medium | 数据查看 | `user.view_detail` | ✅ 可配置 |
| Low | 列表浏览 | `user.list`, `post.list` | ✅ 可配置 |

**2. 保留策略**

| 级别 | 保留时间 | 说明 |
|------|----------|------|
| Critical / High | 7 年 | 符合合规审计要求 |
| Medium | 1 年 | 常规操作追溯 |
| Low | 90 天 | 浏览记录 |

**3. 完整性保护**

```sql
-- 防篡改校验
ALTER TABLE audit_logs ADD COLUMN
    checksum VARCHAR(64);  -- SHA-256(id + admin_id + action + created_at + secret)

-- 禁止修改和删除
REVOKE UPDATE, DELETE ON audit_logs FROM admin_api_user;
```

**4. 代码级强制（中间件实现）**

```rust
// Critical/High 操作自动审计，业务代码无法跳过
pub async fn audit_middleware(req: Request, next: Next) -> Response {
    let response = next.run(req).await;

    if requires_audit(&req.uri().path()) {
        // 强制写入，失败则整个请求失败
        audit_service.log(...).await?;
    }

    response
}
```

---

#### system_configs (系统配置)
```sql
CREATE TABLE system_configs (
    key VARCHAR(255) PRIMARY KEY,
    value JSONB NOT NULL,
    description TEXT,
    updated_by UUID REFERENCES admin_users(id),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### 3.4 权限模型 (RBAC)

```rust
// 角色定义
enum AdminRole {
    SuperAdmin,  // 全部权限
    Admin,       // 除系统设置外全部权限
    Moderator,   // 内容审核、用户管理
    Operations,  // 运营相关
    Support,     // 客服相关
    Viewer,      // 只读
}

// 权限定义
enum Permission {
    // 用户管理
    UserView, UserEdit, UserSuspend, UserDelete,
    // 内容管理
    ContentView, ContentEdit, ContentRemove, ContentRestore,
    // 审核
    ModerationView, ModerationAction,
    // 运营
    CampaignView, CampaignEdit, PushSend,
    // 支付
    PaymentView, PaymentRefund,
    // 系统
    SettingsView, SettingsEdit, AdminManage,
    // 报表
    ReportView, ReportExport,
}
```

#### 权限模型演进策略

**演进路径**

```
阶段 1 (MVP)              阶段 2                    阶段 3
────────────────────────────────────────────────────────────────
RBAC 角色+接口级    →    RBAC + 资源级     →    Policy-based (ABAC)
────────────────────────────────────────────────────────────────
"Moderator 能删帖"       "Moderator 只能删        "Moderator 只能在
                          自己审核的帖子"          工作时间删除
                                                  低风险内容"
```

| 阶段 | 模型 | 触发条件 | 工具 |
|------|------|----------|------|
| 1. 接口级 | 角色 → 权限 → API | MVP | 代码硬编码 |
| 2. 资源级 | + 资源条件 | 多团队协作、细分职责 | 配置化规则 |
| 3. Policy | 策略引擎 | 复杂合规、动态策略 | Casbin / OPA |

**设计原则：保持可演进**

```rust
// 抽象权限检查接口，便于未来替换实现
#[async_trait]
pub trait PermissionChecker: Send + Sync {
    async fn check(
        &self,
        admin: &Admin,
        action: &str,
        resource: Option<&Resource>
    ) -> Result<bool>;
}

// 阶段 1：简单 RBAC 实现
pub struct RbacChecker { /* ... */ }

impl PermissionChecker for RbacChecker {
    async fn check(&self, admin: &Admin, action: &str, _: Option<&Resource>) -> Result<bool> {
        Ok(admin.permissions.contains(action))
    }
}

// 阶段 3：可无缝替换为策略引擎
pub struct CasbinChecker { enforcer: Enforcer }
```

**MVP 阶段不做过度设计**，但通过接口抽象保留演进空间。

---

### 3.5 ClickHouse 分析链路设计

#### 为什么需要 ClickHouse

| 场景 | PostgreSQL | ClickHouse |
|------|------------|------------|
| 单用户详情查询 | ✅ 毫秒级 | ❌ 不适合 |
| 7日 DAU 趋势 | ⚠️ 秒级（需聚合） | ✅ 毫秒级 |
| 全量用户漏斗分析 | ❌ 分钟级 | ✅ 秒级 |
| 实时 UV/PV 统计 | ❌ 高负载 | ✅ 专为 OLAP 设计 |

**原则**：PostgreSQL 做 OLTP，ClickHouse 做 OLAP。

#### 数据流架构

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         数据生产层                                       │
│  identity-service / content-service / social-service / payment-service │
└─────────────────────────┬───────────────────────────────────────────────┘
                          │ 写入
                          ▼
                  ┌───────────────┐
                  │  PostgreSQL   │
                  │  (主数据库)    │
                  └───────┬───────┘
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
        ▼                 ▼                 ▼
  ┌───────────┐    ┌───────────┐    ┌───────────┐
  │  方案 A   │    │  方案 B   │    │  方案 C   │
  │   CDC     │    │  定时批量  │    │  双写     │
  │ Debezium  │    │  ETL Job  │    │ (不推荐)  │
  └─────┬─────┘    └─────┬─────┘    └───────────┘
        │                │
        └────────┬───────┘
                 ▼
         ┌─────────────┐
         │ ClickHouse  │
         │ (分析数据)   │
         └──────┬──────┘
                │ 查询
                ▼
         ┌─────────────┐
         │  admin-api  │◄───── Dashboard / Reports
         └─────────────┘
```

#### 同步方案对比

| 方案 | 延迟 | 复杂度 | 一致性 | 推荐场景 |
|------|------|--------|--------|----------|
| **CDC (Debezium)** | ~秒级 | 高 | 最终一致 | 生产环境首选 |
| **定时批量 ETL** | 分钟~小时 | 低 | T+1 | MVP / 报表 |
| **双写** | 实时 | 中 | 需要事务 | ❌ 不推荐 |

**MVP 推荐**：定时批量 ETL（每 5 分钟 / 每小时增量同步）

#### 查询路由规则

```rust
// admin-api/src/services/analytics_service.rs

pub enum QueryTarget {
    PostgreSQL,  // OLTP 查询
    ClickHouse,  // OLAP 查询
}

impl AnalyticsService {
    /// 根据查询类型自动路由到合适的数据库
    pub fn route_query(query_type: &QueryType) -> QueryTarget {
        match query_type {
            // PostgreSQL: 单条/少量记录查询
            QueryType::UserDetail { .. } => QueryTarget::PostgreSQL,
            QueryType::PostDetail { .. } => QueryTarget::PostgreSQL,
            QueryType::RecentAuditLogs { limit } if *limit <= 100 => QueryTarget::PostgreSQL,

            // ClickHouse: 聚合/趋势/大数据量查询
            QueryType::DailyActiveUsers { .. } => QueryTarget::ClickHouse,
            QueryType::WeeklyTrends { .. } => QueryTarget::ClickHouse,
            QueryType::ContentStats { .. } => QueryTarget::ClickHouse,
            QueryType::UserGrowthFunnel { .. } => QueryTarget::ClickHouse,
            QueryType::RevenueReport { .. } => QueryTarget::ClickHouse,

            // 默认 PostgreSQL
            _ => QueryTarget::PostgreSQL,
        }
    }
}
```

#### ClickHouse 表设计

**1. 用户活跃事件表（核心表）**

```sql
-- 用户行为事件宽表
CREATE TABLE analytics.user_events
(
    event_date Date,
    event_time DateTime,
    user_id UUID,
    event_type LowCardinality(String),  -- 'login', 'post', 'like', 'match', etc.

    -- 用户维度（冗余存储，避免 JOIN）
    user_created_at DateTime,
    user_verified UInt8,
    user_gender LowCardinality(String),
    user_city LowCardinality(String),

    -- 事件属性
    target_type LowCardinality(String),  -- 'post', 'comment', 'user'
    target_id String,
    extra_data String,  -- JSON 格式扩展字段

    -- 设备信息
    platform LowCardinality(String),  -- 'ios', 'android', 'web'
    app_version String,
    device_model LowCardinality(String)
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_date)
ORDER BY (event_date, event_type, user_id, event_time)
TTL event_date + INTERVAL 2 YEAR;

-- 索引
CREATE INDEX idx_user ON analytics.user_events (user_id) TYPE bloom_filter GRANULARITY 4;
CREATE INDEX idx_event_type ON analytics.user_events (event_type) TYPE set(100) GRANULARITY 4;
```

**2. Dashboard 聚合物化视图**

```sql
-- 每日指标聚合（Dashboard 首页使用）
CREATE MATERIALIZED VIEW analytics.daily_metrics_mv
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(date)
ORDER BY (date, metric_type)
AS SELECT
    toDate(event_time) AS date,
    event_type AS metric_type,
    count() AS count,
    uniqExact(user_id) AS unique_users
FROM analytics.user_events
GROUP BY date, metric_type;

-- 查询示例：获取 7 日 DAU
SELECT date, unique_users
FROM analytics.daily_metrics_mv
WHERE metric_type = 'login'
  AND date >= today() - 7
ORDER BY date;
```

**3. 内容统计表**

```sql
CREATE TABLE analytics.content_stats
(
    stat_date Date,
    content_type LowCardinality(String),  -- 'post', 'comment'

    -- 计数指标
    total_count UInt64,
    new_count UInt64,
    removed_count UInt64,
    reported_count UInt64,

    -- AI 审核指标
    ai_approved UInt64,
    ai_rejected UInt64,
    ai_manual_review UInt64,

    updated_at DateTime DEFAULT now()
)
ENGINE = ReplacingMergeTree(updated_at)
PARTITION BY toYYYYMM(stat_date)
ORDER BY (stat_date, content_type);
```

#### ETL 同步脚本示例

```rust
// backend/admin-api/src/jobs/sync_clickhouse.rs

/// MVP 阶段：定时增量同步
pub async fn sync_user_events(
    pg_pool: &PgPool,
    ch_client: &ClickhouseClient,
    last_sync: DateTime<Utc>,
) -> Result<SyncStats> {
    // 1. 从 PostgreSQL 读取增量数据
    let events = sqlx::query_as!(
        UserEventRow,
        r#"
        SELECT
            u.id as user_id,
            u.created_at as user_created_at,
            u.verified as user_verified,
            al.action as event_type,
            al.created_at as event_time,
            al.resource_type as target_type,
            al.resource_id as target_id
        FROM audit_logs al
        JOIN users u ON al.user_id = u.id
        WHERE al.created_at > $1
        ORDER BY al.created_at
        LIMIT 10000
        "#,
        last_sync
    )
    .fetch_all(pg_pool)
    .await?;

    // 2. 批量写入 ClickHouse
    if !events.is_empty() {
        let insert = ch_client
            .insert("analytics.user_events")?
            .with_timeouts(...)
            .write(&events)
            .await?;
    }

    Ok(SyncStats {
        synced_count: events.len(),
        last_event_time: events.last().map(|e| e.event_time),
    })
}
```

#### 演进路径

```
阶段 1 (MVP)              阶段 2                    阶段 3
────────────────────────────────────────────────────────────────
定时 ETL (5分钟)    →    Debezium CDC      →    实时 + 流处理
────────────────────────────────────────────────────────────────
cron job / Tokio          Kafka Connect           Kafka Streams
手动触发同步              自动变更捕获             复杂事件处理
```

| 阶段 | 触发条件 | 改动范围 |
|------|----------|----------|
| MVP → CDC | Dashboard 数据延迟不可接受 | 部署 Debezium + Kafka |
| CDC → 流处理 | 需要实时告警/复杂计算 | 引入流处理框架 |

---

### 3.6 gRPC 调用可靠性策略

admin-api 的写操作通过 gRPC 调用业务服务。为避免写操作误重试导致重复执行，需要统一可靠性策略。

#### 超时与重试策略

| 类型 | 超时 | 重试 | 说明 |
|------|------|------|------|
| 读请求（查询类） | 1~3s | ✅ 可重试（最多 2 次） | 允许幂等重试 |
| 写请求（状态变更） | 3~5s | ❌ 默认不重试 | 防止重复封禁/下架 |
| 长任务（报表导出） | 5~10s | ❌ | 采用异步任务 + 轮询 |

**原则**：写请求不自动重试，除非业务服务明确支持幂等键。

#### 幂等性设计（高风险写操作）

```http
POST /api/admin/v1/users/{id}/suspend
Idempotency-Key: 2a1c4c2c-9a2d-4bb1-9f6e-3c0b2f9d8c7a
```

```rust
// gRPC metadata 携带幂等键
metadata.insert("x-request-id", request_id.parse()?);
metadata.insert("x-idempotency-key", idem_key.parse()?);
```

#### 熔断与降级

| 组件 | 策略 |
|------|------|
| gRPC client | 连接池 + 超时 + 熔断 |
| Dashboard | 缓存 30~120s（Redis） |
| 写操作 | 不缓存、不降级，必须可追责 |

---

### 3.7 只读直查边界与数据库权限

#### 只读直查允许范围

| 允许 ✅ | 禁止 ❌ |
|---------|---------|
| Dashboard 指标（DAU、新增） | 依赖业务表字段实现审核判断 |
| 报表类聚合统计 | SQL 直接修改业务表 |

#### 数据库账号隔离（强制）

| 账号 | 用途 | 权限 |
|------|------|------|
| `admin_api_user` | admin-api 运行 | admin 表读写 + 业务表只读 |
| `migration_user` | 执行 migrations | 可创建/变更 admin 表 |

```sql
-- 业务表只读
GRANT SELECT ON ALL TABLES IN SCHEMA public TO admin_api_user;

-- admin 自有表读写
GRANT SELECT, INSERT, UPDATE ON admin_users TO admin_api_user;
GRANT SELECT, INSERT ON audit_logs TO admin_api_user;

-- 禁止修改审计表
REVOKE UPDATE, DELETE ON audit_logs FROM admin_api_user;
```

---

### 3.8 统一错误码与响应结构

```json
{
  "code": "AUTH_INVALID",
  "message": "Invalid token",
  "request_id": "8d2a3e1a-2a2d-4e5c-9f39-4a2c1f9c7a11",
  "details": {}
}
```

#### 错误码规范

| 类别 | code 前缀 | 示例 |
|------|-----------|------|
| 认证/授权 | `AUTH_` / `PERM_` | `AUTH_INVALID`, `PERM_DENIED` |
| 参数错误 | `REQ_` | `REQ_INVALID_PARAM` |
| 资源不存在 | `NOT_FOUND_` | `NOT_FOUND_USER` |
| 并发/幂等 | `CONFLICT_` | `CONFLICT_IDEMPOTENCY` |
| 下游依赖 | `UPSTREAM_` | `UPSTREAM_TIMEOUT` |
| 系统错误 | `SYS_` | `SYS_INTERNAL` |

---

### 3.9 审计日志归档策略

#### 分区策略（按月）

```
audit_logs_2025_01, audit_logs_2025_02 ...
```

#### 归档策略

| 级别 | 在线保留 | 冷存储 |
|------|----------|--------|
| Critical/High | 1~2 年 | 7 年 |
| Medium | 6~12 个月 | 1 年 |
| Low | 90 天 | 可选 |

---

### 3.10 监控与告警

#### Prometheus 指标

admin-api 需要暴露以下核心指标：

```rust
// 请求指标
admin_api_http_requests_total{method, path, status}        // 请求总数
admin_api_http_request_duration_seconds{method, path}      // 请求延迟 (histogram)
admin_api_http_requests_in_flight                          // 并发请求数

// gRPC 客户端指标
admin_api_grpc_client_requests_total{service, method, status}
admin_api_grpc_client_duration_seconds{service, method}

// 认证指标
admin_api_auth_login_total{status}                         // 登录次数 (success/failed)
admin_api_auth_token_refresh_total{status}

// 业务指标
admin_api_audit_logs_total{action, level}                  // 审计日志写入
admin_api_user_actions_total{action}                       // 用户操作 (suspend/warn/etc)
```

#### Grafana Dashboard

| Dashboard | 面板 | 说明 |
|-----------|------|------|
| **Overview** | QPS / 延迟 P50/P95/P99 | 整体健康度 |
| **Auth** | 登录成功率 / 失败分布 | 安全监控 |
| **gRPC** | 各服务调用延迟 / 错误率 | 依赖健康度 |
| **Business** | 审核量 / 封禁量趋势 | 运营数据 |

#### 告警规则

| 告警名称 | 条件 | 级别 | 动作 |
|----------|------|------|------|
| `AdminApiHighErrorRate` | HTTP 5xx > 1% (5分钟) | Critical | PagerDuty |
| `AdminApiHighLatency` | P99 > 3s (5分钟) | Warning | Slack |
| `AdminLoginBruteForce` | 登录失败 > 20/分钟 | Critical | PagerDuty + 自动封 IP |
| `AdminGrpcServiceDown` | 某服务错误率 > 50% | Critical | PagerDuty |
| `AdminAuditLogWriteFail` | 审计写入失败 > 0 | Critical | PagerDuty |

#### 告警配置示例 (Prometheus AlertManager)

```yaml
groups:
- name: admin-api-alerts
  rules:
  - alert: AdminApiHighErrorRate
    expr: |
      sum(rate(admin_api_http_requests_total{status=~"5.."}[5m]))
      / sum(rate(admin_api_http_requests_total[5m])) > 0.01
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "Admin API 错误率过高"
      description: "5xx 错误率超过 1%，当前: {{ $value | humanizePercentage }}"

  - alert: AdminLoginBruteForce
    expr: |
      sum(rate(admin_api_auth_login_total{status="failed"}[1m])) > 0.33
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "疑似登录爆破攻击"
      description: "登录失败率过高: {{ $value | humanize }}/秒"
```

---

### 3.11 日志规范

#### 日志格式 (结构化 JSON)

```json
{
  "timestamp": "2025-01-15T10:30:00.123Z",
  "level": "INFO",
  "message": "User suspended",
  "service": "admin-api",
  "trace_id": "abc123def456",
  "span_id": "789xyz",
  "request_id": "req-uuid-here",
  "admin_id": "admin-uuid",
  "fields": {
    "target_user_id": "user-uuid",
    "action": "user.suspend",
    "duration_ms": 45
  }
}
```

#### 日志级别使用规范

| 级别 | 使用场景 | 示例 |
|------|----------|------|
| `ERROR` | 需要人工介入的错误 | gRPC 调用失败、审计写入失败 |
| `WARN` | 异常但可自动恢复 | 重试成功、缓存 miss |
| `INFO` | 关键业务事件 | 用户封禁、内容删除、登录 |
| `DEBUG` | 调试信息 | SQL 查询、请求详情 |

#### 日志收集架构

```
admin-api  ──► stdout (JSON) ──► Fluent Bit ──► Loki / Elasticsearch
                                     │
                                     └──► S3 (长期归档)
```

#### 敏感信息脱敏

```rust
// 禁止记录的字段
- password / password_hash
- totp_secret
- Authorization header 完整值
- 用户手机号完整 (仅记录 138****1234)
```

---

### 3.12 数据库迁移

#### 工具选择：sqlx-cli

与 Rust 生态一致，编译时校验 SQL。

```bash
# 安装
cargo install sqlx-cli --features postgres

# 创建迁移
sqlx migrate add create_admin_users

# 执行迁移
DATABASE_URL=postgres://... sqlx migrate run

# 回滚（需手动编写 down 文件）
sqlx migrate revert
```

#### 迁移文件命名

```
migrations/
├── 20250115_001_create_admin_users.sql
├── 20250115_002_create_audit_logs.sql
├── 20250116_001_add_totp_fields.sql
└── 20250120_001_add_audit_checksum.sql
```

#### 迁移最佳实践

| 原则 | 说明 |
|------|------|
| **向前兼容** | 新增列设置默认值，旧代码仍可运行 |
| **小步快跑** | 大变更拆分为多个小迁移 |
| **禁止删列** | 使用软弃用，观察 30 天后再删 |
| **必须可逆** | 每个 up 都要写 down |

#### CI 集成

```yaml
# GitHub Actions
- name: Check migrations
  run: |
    sqlx database create --database-url $TEST_DB_URL
    sqlx migrate run --database-url $TEST_DB_URL
    cargo sqlx prepare --check
```

---

### 3.13 测试策略

#### 测试金字塔

```
                    ┌─────────┐
                    │  E2E    │  5%   Playwright (关键流程)
                   ─┼─────────┼─
                  ┌─┴─────────┴─┐
                  │ Integration │  25%  API + DB 测试
                 ─┼─────────────┼─
               ┌──┴─────────────┴──┐
               │     Unit Tests    │  70%  纯逻辑测试
               └───────────────────┘
```

#### 测试类型与覆盖

| 类型 | 目标 | 工具 | 覆盖范围 |
|------|------|------|----------|
| **单元测试** | 业务逻辑 | `#[test]` | 权限检查、数据转换、工具函数 |
| **集成测试** | API + DB | `axum::test` + testcontainers | 完整 API 流程 |
| **E2E 测试** | 用户流程 | Playwright | 登录→封禁用户→查看审计 |

#### 关键测试场景 (MVP)

```rust
// tests/integration/auth_test.rs
#[tokio::test]
async fn test_login_success() { ... }

#[tokio::test]
async fn test_login_wrong_password() { ... }

#[tokio::test]
async fn test_login_account_locked_after_5_failures() { ... }

#[tokio::test]
async fn test_token_refresh() { ... }

// tests/integration/users_test.rs
#[tokio::test]
async fn test_suspend_user_creates_audit_log() { ... }

#[tokio::test]
async fn test_suspend_user_requires_permission() { ... }

#[tokio::test]
async fn test_suspend_already_suspended_user() { ... }
```

#### 测试数据管理

```rust
// 使用 testcontainers 启动临时 PostgreSQL
#[fixture]
async fn db() -> PgPool {
    let container = PostgresContainer::new();
    let pool = PgPool::connect(&container.url()).await?;
    sqlx::migrate!().run(&pool).await?;
    pool
}

// 每个测试独立事务，自动回滚
#[sqlx::test]
async fn test_xxx(pool: PgPool) { ... }
```

---

## 4. admin-web 前端设计

### 4.1 技术栈选择 (基于 Figma 生成代码)

```
框架:      React 18 + TypeScript
样式:      Tailwind CSS (Figma 已生成)
状态管理:  React useState / Zustand (简单场景直接用 hooks)
路由:      React Router v6 (或保持当前 state 切换方式)
请求:      Axios + React Query (TanStack Query)
图表:      Recharts (轻量，与 Tailwind 配合好)
构建:      Vite
UI 组件:   自定义组件 + Tailwind (Figma 已生成基础组件)
```

**注意**: Figma 已生成的代码使用纯 Tailwind CSS，无需引入 Ant Design

### 4.2 目录结构 (基于 Figma 生成代码)

```
admin-web/
├── package.json
├── vite.config.ts
├── tailwind.config.js
├── tsconfig.json
├── Dockerfile
├── nginx.conf                    # 生产环境 nginx 配置
│
├── public/
│   └── favicon.ico
│
├── src/
│   ├── main.tsx                  # 入口
│   ├── App.tsx                   # 根组件 (Figma 已生成)
│   │
│   ├── api/                      # API 层 (需新建)
│   │   ├── client.ts             # Axios 实例
│   │   ├── dashboard.ts
│   │   ├── users.ts
│   │   ├── content.ts
│   │   └── ...
│   │
│   ├── components/               # 组件 (Figma 已生成部分)
│   │   ├── layout/
│   │   │   └── MainLayout.tsx    # ✅ Figma 已生成
│   │   ├── charts/               # 图表组件 (需开发)
│   │   │   ├── AreaChart.tsx
│   │   │   └── StatCard.tsx
│   │   └── common/
│   │       ├── SearchInput.tsx
│   │       └── StatusBadge.tsx
│   │
│   ├── components/pages/         # 页面组件 (Figma 结构)
│   │   ├── Dashboard.tsx         # ✅ Figma 已生成
│   │   ├── UserCenter.tsx        # ✅ Figma 已生成
│   │   ├── ContentManage.tsx     # 待开发
│   │   ├── Verification.tsx      # 待开发
│   │   ├── SocialMatch.tsx       # 待开发
│   │   ├── AIDeepsearch.tsx      # 待开发
│   │   ├── Growth.tsx            # 待开发
│   │   ├── Finance.tsx           # 待开发
│   │   ├── Feedback.tsx          # 待开发
│   │   ├── Reports.tsx           # 待开发
│   │   └── System.tsx            # 待开发
│   │
│   ├── hooks/                    # 自定义 Hooks (需新建)
│   │   ├── useAuth.ts
│   │   ├── usePermission.ts
│   │   └── usePagination.ts
│   │
│   ├── stores/                   # 状态管理 (需新建)
│   │   └── authStore.ts
│   │
│   ├── utils/                    # 工具函数
│   │   ├── format.ts
│   │   └── request.ts
│   │
│   ├── types/                    # TypeScript 类型
│   │   ├── api.ts
│   │   └── user.ts
│   │
│   └── styles/
│       └── global.css            # Tailwind 入口
```

**Figma 已生成组件：**
- `MainLayout` - 主布局 (侧边栏 + 顶栏)
- `Dashboard` - 首页概览
- `UserCenter` - 用户中心
- 页面切换逻辑 (useState)

### 4.3 Tailwind 主题配置 (匹配设计稿)

```javascript
// tailwind.config.js
module.exports = {
  theme: {
    extend: {
      colors: {
        primary: {
          DEFAULT: '#E53935',       // 红色主色调
          hover: '#D32F2F',
          light: '#FFEBEE',
        },
        sidebar: {
          bg: '#1a1a1a',            // 侧边栏深色背景
          hover: '#2d2d2d',
          active: '#E53935',
        },
        risk: {
          high: '#E53935',
          medium: '#FB8C00',
          low: '#4CAF50',
        }
      },
      animation: {
        'fade-in': 'fadeIn 0.5s ease-out',
        'slide-up': 'slideUp 0.5s ease-out',
      }
    }
  }
}
```

**设计稿色彩提取：**
- 主色调: `#E53935` (红色)
- 侧边栏背景: `#1a1a1a` (深灰)
- 正向指标: `#4CAF50` (绿色)
- 负向指标: `#E53935` (红色)
- 风险高: `#E53935` / 中: `#FB8C00`

### 4.4 路由与权限感知 UI

#### 路由方案：React Router v6

后台系统需要支持深链、刷新保持状态、权限路由守卫，因此采用 **React Router v6**。

Figma 生成的 `useState` 页面切换需要重构为路由。

```tsx
// App.tsx 重构后
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';

function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route element={<ProtectedRoute />}>
          <Route element={<MainLayout />}>
            <Route path="/" element={<Navigate to="/dashboard" />} />
            <Route path="/dashboard" element={<Dashboard />} />
            <Route path="/users" element={<UserCenter />} />
            <Route path="/users/:id" element={<UserDetail />} />
            <Route path="/content" element={<ContentManage />} />
            {/* ... */}
          </Route>
        </Route>
      </Routes>
    </BrowserRouter>
  );
}
```

#### 权限感知 UI

权限控制分两层：
- **前端（显示级）**：无权限菜单不展示，按钮隐藏
- **后端（最终校验）**：接口必须校验并返回 `PERM_DENIED`

```ts
// hooks/usePermission.ts
export function usePermission() {
  const { permissions } = useAuth();

  const hasPermission = (required: string | string[]) => {
    const list = Array.isArray(required) ? required : [required];
    return list.some(p => permissions.includes(p));
  };

  return { hasPermission };
}

// 使用示例
const { hasPermission } = usePermission();
{hasPermission('UserSuspend') && <SuspendButton />}
```

#### 权限映射配置

```ts
// config/permissions.ts
export const menuPermissions: Record<string, string[]> = {
  "/dashboard": [],  // 所有人可见
  "/users": ["UserView"],
  "/content": ["ContentView"],
  "/settings": ["SettingsView"],
};

export const actionPermissions: Record<string, string[]> = {
  "user.suspend": ["UserSuspend"],
  "post.remove": ["ContentRemove"],
};
```

---

### 4.5 错误处理与用户反馈

#### 全局错误边界

```tsx
// components/ErrorBoundary.tsx
import { Component, ErrorInfo, ReactNode } from 'react';

interface Props {
  children: ReactNode;
  fallback?: ReactNode;
}

interface State {
  hasError: boolean;
  error?: Error;
}

export class ErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false };

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    // 上报错误到监控系统 (Sentry / 自建)
    console.error('Uncaught error:', error, errorInfo);
  }

  render() {
    if (this.state.hasError) {
      return this.props.fallback || <ErrorFallback error={this.state.error} />;
    }
    return this.props.children;
  }
}

// 错误回退页面
const ErrorFallback = ({ error }: { error?: Error }) => (
  <div className="min-h-screen flex items-center justify-center bg-slate-50">
    <div className="text-center">
      <h1 className="text-2xl font-bold text-slate-900">页面出错了</h1>
      <p className="text-slate-500 mt-2">{error?.message || '未知错误'}</p>
      <button
        onClick={() => window.location.reload()}
        className="mt-4 px-4 py-2 bg-primary text-white rounded"
      >
        刷新页面
      </button>
    </div>
  </div>
);
```

#### API 错误处理

```tsx
// api/client.ts - 响应拦截器增强
client.interceptors.response.use(
  (response) => response,
  (error) => {
    const { response } = error;

    // 统一错误处理
    if (response) {
      switch (response.status) {
        case 401:
          // Token 过期，尝试刷新
          return handleTokenRefresh(error);
        case 403:
          toast.error('权限不足，无法执行此操作');
          break;
        case 404:
          toast.error('请求的资源不存在');
          break;
        case 429:
          toast.error('请求过于频繁，请稍后再试');
          break;
        case 500:
          toast.error('服务器错误，请稍后重试');
          break;
        default:
          toast.error(response.data?.message || '操作失败');
      }
    } else {
      // 网络错误
      toast.error('网络连接失败，请检查网络');
    }

    return Promise.reject(error);
  }
);
```

#### Toast 通知系统

```tsx
// 使用 sonner (已在 Figma 依赖中)
import { toast } from 'sonner';

// 操作成功
toast.success('用户已封禁');

// 操作失败
toast.error('封禁失败：用户不存在');

// 需要确认的操作
toast.promise(suspendUser(userId), {
  loading: '正在封禁用户...',
  success: '用户已封禁',
  error: (err) => `封禁失败：${err.message}`,
});
```

#### 加载状态组件

```tsx
// components/common/LoadingState.tsx
export const TableSkeleton = ({ rows = 5 }: { rows?: number }) => (
  <div className="space-y-3">
    {Array.from({ length: rows }).map((_, i) => (
      <div key={i} className="h-12 bg-slate-200 rounded animate-pulse" />
    ))}
  </div>
);

export const PageLoading = () => (
  <div className="flex items-center justify-center h-64">
    <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary" />
  </div>
);

// 使用 React Query 的标准模式
function UserCenter() {
  const { data, isLoading, error, refetch } = useUsers(params);

  if (isLoading) return <TableSkeleton rows={10} />;

  if (error) {
    return (
      <div className="text-center py-12">
        <p className="text-red-500">加载失败：{error.message}</p>
        <button onClick={() => refetch()} className="mt-2 text-primary">
          点击重试
        </button>
      </div>
    );
  }

  return <UserTable data={data} />;
}
```

---

## 5. 部署架构

### 5.1 Docker Compose (本地开发)

```yaml
# docker-compose.admin.yml
services:
  admin-api:
    build:
      context: ./backend
      dockerfile: admin-api/Dockerfile
    ports:
      - "8090:8090"
    environment:
      DATABASE_URL: postgresql://postgres:postgres@postgres:5432/nova_auth
      REDIS_URL: redis://:redis123@redis:6379/6
      CLICKHOUSE_URL: http://clickhouse:8123
      JWT_PUBLIC_KEY_FILE: /app/certs/public_key.pem
      RUST_LOG: info,admin_api=debug
    volumes:
      - ./backend/keys:/app/certs:ro
    depends_on:
      - postgres
      - redis
      - clickhouse
    networks:
      - nova-network

  admin-web:
    build:
      context: ./admin-web
      dockerfile: Dockerfile
    ports:
      - "3001:80"
    environment:
      VITE_API_URL: http://localhost:8090
    depends_on:
      - admin-api
    networks:
      - nova-network
```

### 5.2 Kubernetes 部署

```
k8s/microservices/
├── admin-api-deployment.yaml
├── admin-api-service.yaml
├── admin-api-configmap.yaml
├── admin-api-secret.yaml
├── admin-api-serviceaccount.yaml
├── admin-web-deployment.yaml
├── admin-web-service.yaml
└── admin-ingress.yaml           # /admin/* 路由
```

### 5.3 Ingress 路由（单域名 + 安全加固）

```yaml
# admin-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: admin-ingress
  annotations:
    # 安全加固
    nginx.ingress.kubernetes.io/configuration-snippet: |
      # 防止 path traversal 攻击
      if ($request_uri ~* "\.\.") { return 403; }
      # 安全响应头
      add_header X-Frame-Options "SAMEORIGIN" always;
      add_header X-Content-Type-Options "nosniff" always;
      add_header X-XSS-Protection "1; mode=block" always;
    # 速率限制
    nginx.ingress.kubernetes.io/limit-rps: "20"
    nginx.ingress.kubernetes.io/limit-connections: "10"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - admin.nova.app
    secretName: admin-tls
  rules:
  - host: admin.nova.app
    http:
      paths:
      # API 路由 - 前缀匹配（后端路由已包含 /api/admin/v1 前缀）
      - path: /api/admin/v1
        pathType: Prefix
        backend:
          service:
            name: admin-api
            port:
              number: 8090
      # 前端静态资源
      - path: /
        pathType: Prefix
        backend:
          service:
            name: admin-web
            port:
              number: 80
```

**前端 API 配置：**
```typescript
// .env.production
VITE_API_URL=/api/admin/v1

// api/client.ts - 方便后续迁移到双域名
const API_BASE = import.meta.env.VITE_API_URL || '/api/admin/v1';
```

**后续迁移到双域名**：只需改 `VITE_API_URL=https://admin-api.nova.app` 并添加 CORS 中间件

### 5.4 外网访问安全策略

#### 防护分层

| 层级 | 组件 | 目标 |
|------|------|------|
| L7 边界 | WAF / Ingress | 拦截扫描、注入、爆破，限速 |
| 网关层 | Nginx | 路由、额外鉴权、日志 |
| 应用层 | admin-api | RBAC、审计、幂等、业务校验 |

#### 最小安全基线（上线必须满足）

| 项目 | 说明 |
|------|------|
| HTTPS 强制 | TLS 终止于 Ingress |
| 登录爆破防护 | 失败 5 次锁定 15 分钟 |
| WAF/限流 | Ingress 限流 + WAF 规则 |
| 强审计 | Critical/High 操作不可跳过 |
| 2FA（建议） | TOTP（外网强烈建议） |

#### 域名策略建议

| 方案 | 配置 | 适用场景 |
|------|------|----------|
| 单域名 | `admin.nova.app` + path 分流 | MVP / 内网 |
| 双域名 | `admin.nova.app` + `admin-api.nova.app` | 生产 / 外网 |

双域名优点：
- WAF 规则可分别配置
- CORS 更清晰
- API 可做严格访问控制（只接受 JSON）

---

### 5.5 CI/CD 配置

#### GitHub Actions Workflow

```yaml
# .github/workflows/admin-api.yml
name: Admin API CI/CD

on:
  push:
    branches: [main, develop]
    paths:
      - 'backend/admin-api/**'
  pull_request:
    branches: [main]
    paths:
      - 'backend/admin-api/**'

env:
  CARGO_TERM_COLOR: always
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}/admin-api

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: admin_test
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432

    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - uses: Swatinem/rust-cache@v2

      - name: Run migrations
        run: |
          cargo install sqlx-cli --no-default-features --features postgres
          sqlx migrate run
        working-directory: backend/admin-api
        env:
          DATABASE_URL: postgres://postgres:postgres@localhost:5432/admin_test

      - name: Run tests
        run: cargo test --workspace
        working-directory: backend/admin-api
        env:
          DATABASE_URL: postgres://postgres:postgres@localhost:5432/admin_test

      - name: Clippy
        run: cargo clippy -- -D warnings
        working-directory: backend/admin-api

  build:
    needs: test
    runs-on: ubuntu-latest
    if: github.event_name == 'push'

    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: ./backend
          file: ./backend/admin-api/Dockerfile
          push: true
          tags: |
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max

  deploy-staging:
    needs: build
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/develop'
    environment: staging

    steps:
      - name: Deploy to staging
        run: |
          kubectl set image deployment/admin-api \
            admin-api=${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
        env:
          KUBECONFIG: ${{ secrets.KUBECONFIG_STAGING }}

  deploy-production:
    needs: build
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    environment: production

    steps:
      - name: Deploy to production
        run: |
          kubectl set image deployment/admin-api \
            admin-api=${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
        env:
          KUBECONFIG: ${{ secrets.KUBECONFIG_PROD }}
```

#### 前端 CI/CD

```yaml
# .github/workflows/admin-web.yml
name: Admin Web CI/CD

on:
  push:
    branches: [main, develop]
    paths:
      - 'admin-web/**'

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v2
        with:
          version: 8

      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'pnpm'
          cache-dependency-path: admin-web/pnpm-lock.yaml

      - name: Install dependencies
        run: pnpm install
        working-directory: admin-web

      - name: Type check
        run: pnpm tsc --noEmit
        working-directory: admin-web

      - name: Build
        run: pnpm build
        working-directory: admin-web
        env:
          VITE_API_URL: /api/admin/v1

      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          context: ./admin-web
          push: true
          tags: ${{ env.REGISTRY }}/admin-web:${{ github.sha }}
```

---

### 5.6 多环境配置

#### 环境划分

| 环境 | 用途 | 数据 | 域名 |
|------|------|------|------|
| **local** | 本地开发 | Mock/本地 DB | localhost:3001 |
| **staging** | 测试验收 | 测试数据 | admin-staging.nova.app |
| **production** | 正式环境 | 生产数据 | admin.nova.app |

#### 后端配置管理

```rust
// backend/admin-api/src/config.rs
use config::{Config, Environment, File};

#[derive(Debug, Deserialize)]
pub struct Settings {
    pub database_url: String,
    pub redis_url: String,
    pub clickhouse_url: String,
    pub jwt_secret: String,
    pub jwt_expiry_hours: i64,
    pub environment: String,  // local, staging, production
}

impl Settings {
    pub fn new() -> Result<Self, config::ConfigError> {
        let env = std::env::var("RUN_ENV").unwrap_or_else(|_| "local".into());

        Config::builder()
            // 1. 默认配置
            .add_source(File::with_name("config/default"))
            // 2. 环境特定配置
            .add_source(File::with_name(&format!("config/{}", env)).required(false))
            // 3. 环境变量覆盖 (ADMIN_API_ 前缀)
            .add_source(Environment::with_prefix("ADMIN_API").separator("__"))
            .build()?
            .try_deserialize()
    }
}
```

#### 配置文件结构

```
backend/admin-api/config/
├── default.toml          # 默认值
├── local.toml            # 本地开发
├── staging.toml          # 测试环境
└── production.toml       # 生产环境 (仅结构，敏感值用环境变量)
```

```toml
# config/default.toml
jwt_expiry_hours = 2
log_level = "info"

# config/local.toml
database_url = "postgres://postgres:postgres@localhost:5432/admin_dev"
redis_url = "redis://localhost:6379/0"
log_level = "debug"

# config/production.toml (敏感值通过环境变量注入)
# database_url = "${ADMIN_API__DATABASE_URL}"
log_level = "info"
```

#### 前端环境配置

```bash
# admin-web/.env.local
VITE_API_URL=http://localhost:8090/api/admin/v1
VITE_ENV=local

# admin-web/.env.staging
VITE_API_URL=https://admin-staging.nova.app/api/admin/v1
VITE_ENV=staging

# admin-web/.env.production
VITE_API_URL=/api/admin/v1
VITE_ENV=production
```

```typescript
// 前端使用
const isDev = import.meta.env.VITE_ENV === 'local';
const apiUrl = import.meta.env.VITE_API_URL;
```

#### K8s ConfigMap 示例

```yaml
# k8s/microservices/admin-api-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: admin-api-config
  namespace: nova
data:
  RUN_ENV: "production"
  ADMIN_API__LOG_LEVEL: "info"
  ADMIN_API__JWT_EXPIRY_HOURS: "2"
---
apiVersion: v1
kind: Secret
metadata:
  name: admin-api-secrets
  namespace: nova
type: Opaque
stringData:
  ADMIN_API__DATABASE_URL: "postgres://..."
  ADMIN_API__REDIS_URL: "redis://..."
  ADMIN_API__JWT_SECRET: "..."
```

---

## 6. 认证方案

### 方案：独立 Admin 账户体系

```
┌─────────────┐                    ┌─────────────┐
│  admin-web  │  POST /auth/login  │  admin-api  │
│  (登录表单)  │ ─────────────────► │             │
└─────────────┘                    └──────┬──────┘
                                          │
                                          ▼
                                 ┌─────────────────┐
                                 │   admin_users   │
                                 │  (验证密码)      │
                                 └────────┬────────┘
                                          │
                                          ▼
                                 ┌─────────────────┐
                                 │  签发 JWT Token │
                                 │  (admin-api 自签)│
                                 └─────────────────┘
```

**认证 API：**
```
POST   /api/admin/v1/auth/login           # 登录
POST   /api/admin/v1/auth/logout          # 登出
POST   /api/admin/v1/auth/refresh         # 刷新 Token
POST   /api/admin/v1/auth/forgot-password # 忘记密码
POST   /api/admin/v1/auth/reset-password  # 重置密码
GET    /api/admin/v1/auth/me              # 获取当前用户信息
```

**安全措施：**
- 密码使用 argon2 哈希
- 登录失败 5 次后锁定账户 15 分钟
- JWT 有效期 2 小时，Refresh Token 7 天
- 支持后续扩展 2FA

### 6.1 Token 存储策略

#### 方案 A（推荐）：HttpOnly Cookie

| Token | 存储位置 | 说明 |
|-------|----------|------|
| Access Token | 内存 | 刷新页面丢失，需 refresh 换取 |
| Refresh Token | HttpOnly Cookie | SameSite=Strict |

优点：降低 XSS 窃取风险

需要：
- refresh 接口
- CSRF 防护（Double Submit Cookie）

#### 方案 B：localStorage

若采用此方案，必须增加：
- 严格 CSP（Content-Security-Policy）
- 依赖锁定（避免供应链注入）
- 禁止内联脚本

**MVP 建议**：优先方案 A；若受限则方案 B + 严格 CSP。

### 6.2 忘记密码流程（可选）

```
用户提交邮箱 → admin-api 生成 reset_token (Redis TTL 15分钟)
            → 发送邮件 → 用户点击链接 → 重置密码
            → 作废所有 session/refresh token
```

| 组件 | 说明 |
|------|------|
| 邮件服务 | SMTP / SendGrid |
| reset_token | Redis TTL 15 分钟 |
| 安全 | 限速 + 不泄露邮箱是否存在 |

**MVP 替代方案**：SuperAdmin 在后台手动重置密码。

### 6.3 2FA 扩展设计（建议）

外网后台建议启用 2FA。

#### 数据模型扩展

```sql
ALTER TABLE admin_users ADD COLUMN
    totp_enabled BOOLEAN DEFAULT FALSE,
    totp_secret VARCHAR(255),           -- 加密存储
    backup_codes JSONB DEFAULT '[]';    -- 哈希存储
```

#### 登录流程

1. 校验密码
2. 若启用 2FA → 要求 TOTP code
3. 通过后签发 token

**MVP**：可延后，外网部署时优先实现。

---

## 7. 实施计划

### Phase 1: 基础框架 (Week 1)
- [ ] 创建 admin-api 项目骨架
- [ ] 实现认证中间件 (JWT + 角色)
- [ ] 创建 admin_users / audit_logs 数据库表
- [ ] 实现审计日志中间件
- [ ] 创建 admin-web 项目骨架
- [ ] 实现登录页面和基础布局

### Phase 2: 核心功能 (Week 2-3)
- [ ] Dashboard 首页概览
- [ ] 用户中心 (列表、详情、封禁)
- [ ] 内容 & 评论 (审核队列)
- [ ] 反馈 & 客服 (工单系统)

### Phase 3: 扩展功能 (Week 4-5)
- [ ] 身份 & 职业认证
- [ ] 社交 & 匹配配置
- [ ] AI & Deepsearch 配置
- [ ] 数据报表

### Phase 4: 运营功能 (Week 6)
- [ ] 运营 & 增长
- [ ] 支付 & 会员
- [ ] 系统设置

### Phase 5: 部署上线 (Week 7)
- [ ] K8s manifests
- [ ] CI/CD workflow
- [ ] 文档完善

---

## 8. 关键文件参考

**Rust 服务模板：**
- `/backend/content-service/src/main.rs` - 服务启动模板
- `/backend/content-service/src/middleware/` - 中间件模式
- `/backend/identity-service/src/config.rs` - 配置管理
- `/backend/libs/crypto-core/src/jwt.rs` - JWT 处理

**K8s 部署模板：**
- `/k8s/microservices/content-service-deployment.yaml`
- `/k8s/microservices/ingress.yaml`

**Nginx 配置：**
- `/backend/nginx/nginx.conf` - API 路由模式

---

## 9. 已确认决策

| 决策项 | 确认结果 |
|--------|----------|
| MVP 范围 | Dashboard + 用户中心 + 内容审核 |
| 认证方式 | 独立 Admin 账户体系 |
| 前端技术栈 | React + shadcn/ui + Tailwind (Figma 已生成) |
| Figma 代码位置 | `/Users/icered/Downloads/Icered Admin Panel Prototype` |

## 10. Figma 代码重构清单

Figma 生成的代码需要以下改造才能用于生产：

### 10.1 类型安全

| 文件 | 问题 | 修复 |
|------|------|------|
| `UserCenter.tsx:24` | `useState<any>` | 定义 `User` 接口 |
| `Dashboard.tsx:16` | `StatCard` props 用 `any` | 定义 `StatCardProps` 接口 |
| 全局 | 无 API 响应类型 | 创建 `types/api.ts` |

```typescript
// types/user.ts
interface User {
  id: string;
  name: string;
  phone: string;
  status: 'active' | 'warning' | 'banned';
  verified: boolean;
  date: string;
  avatar?: string;
}

// types/api.ts
interface PaginatedResponse<T> {
  data: T[];
  total: number;
  page: number;
  pageSize: number;
}
```

### 10.2 组件拆分

```
components/
├── common/
│   ├── StatusBadge.tsx      # 从 UserCenter 提取
│   ├── StatCard.tsx         # 从 Dashboard 提取
│   └── SearchInput.tsx      # 复用搜索框
├── user/
│   ├── UserTable.tsx        # 用户列表表格
│   ├── UserDetail.tsx       # 用户详情卡片
│   └── UserRiskCard.tsx     # 风险记录卡片
└── dashboard/
    ├── TrendChart.tsx       # 趋势图表
    └── RiskMonitor.tsx      # 风险监控面板
```

### 10.3 API 集成

```typescript
// api/client.ts
import axios from 'axios';

const client = axios.create({
  baseURL: import.meta.env.VITE_API_URL || '/api/admin/v1',
  timeout: 10000,
});

// 请求拦截器 - 添加 JWT
client.interceptors.request.use((config) => {
  const token = localStorage.getItem('admin_token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// 响应拦截器 - 处理 401
client.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      localStorage.removeItem('admin_token');
      window.location.href = '/login';
    }
    return Promise.reject(error);
  }
);

export default client;
```

### 10.4 状态管理 (React Query)

```typescript
// hooks/useUsers.ts
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { getUsers, suspendUser } from '../api/users';

export function useUsers(params: UserQueryParams) {
  return useQuery({
    queryKey: ['users', params],
    queryFn: () => getUsers(params),
  });
}

export function useSuspendUser() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: suspendUser,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['users'] });
    },
  });
}
```

### 10.5 加载与错误状态

```typescript
// 每个数据页面需要添加
function UserCenter() {
  const { data, isLoading, error } = useUsers(queryParams);

  if (isLoading) return <TableSkeleton rows={5} />;
  if (error) return <ErrorAlert message={error.message} />;

  return <UserTable data={data} />;
}
```

### 10.6 重构优先级

| 优先级 | 任务 | 原因 |
|--------|------|------|
| P0 | 添加登录页面 | 无法访问系统 |
| P0 | API client + 拦截器 | 所有功能依赖 |
| P0 | 类型定义 | 避免运行时错误 |
| P1 | Dashboard API 集成 | MVP 核心页面 |
| P1 | UserCenter API 集成 | MVP 核心页面 |
| P1 | 加载/错误状态 | 用户体验 |
| P2 | 组件拆分 | 代码可维护性 |
| P2 | 内容审核页面 | MVP 第三个功能 |

---

## 11. 下一步行动

准备开始实施后，按以下顺序执行：

1. **复制 Figma 代码到项目**
   ```bash
   cp -r "/Users/icered/Downloads/Icered Admin Panel Prototype" ./admin-web
   ```

2. **创建 admin-api 项目骨架**
   - 参考 content-service 结构
   - 实现 JWT 认证中间件
   - 创建 admin_users 数据库表

3. **前端集成 API**
   - 添加 Axios + React Query
   - 创建登录页面
   - 实现认证状态管理

4. **开发内容审核页面**
   - 待审核队列
   - 审批/拒绝操作
