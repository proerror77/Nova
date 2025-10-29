# auth-service 方向决策文档

**日期**: 2025-10-29
**优先级**: P0 架构决策
**需要做出**: 本周（2025-10-31 前）

---

## 当前状况

### 现有架构

```
API 请求
    ↓
API 网关 (Nginx)
    ↓
user-service (包含 JWT 验证)
    ↓ gRPC
其他微服务
```

### auth-service 现状

- **完整度**: 40% 骨架实现
- **文件**: `/backend/auth-service/`
- **状态**: 未实际使用，所有认证都由 user-service 处理
- **维护负担**: 高（死代码，需要同步 Cargo 版本）
- **架构一致性**: 低（虚假模块化）

**具体问题**:

```rust
// auth-service 中的典型实现
pub async fn verify_token(token: &str) -> Result<TokenClaims> {
    // TODO: 实现 JWT 验证
    Ok(TokenClaims::default()) // 硬编码返回，未实际验证
}
```

---

## 三个选项对比

### 🔴 Option 1: 删除 auth-service

#### 架构图

```
用户请求
    ↓
API 网关
    ↓
user-service (认证 + JWT 验证)
    ↓ gRPC
content-service  media-service  messaging-service  ...
```

#### 优点

✅ **立即见效**:
- 代码库变清晰（删除 ~500 行死代码）
- 不需要同步版本升级
- 无维护负担

✅ **成熟的方案**:
- 已经在生产运行
- user-service 已验证可靠
- 其他服务通过 gRPC 验证成功

✅ **最简设计**:
- 认证职责单一明确
- 发送方明确（来自 user-service JWT）
- 降低系统复杂度

#### 缺点

❌ **限制扩展性**:
- 无法支持第三方认证提供商
- user-service 负载增加时难以扩展
- 如果 user-service 宕机，所有服务认证失败

❌ **无法分离关注点**:
- 认证和用户管理耦合
- 用户服务 scaling 必须扩展认证能力

#### 工期

**0 天** - 仅需代码清理

#### 推荐指数

⭐⭐⭐⭐ (4/5)

---

### 🟡 Option 2: 补全 auth-service

#### 架构图

```
用户请求
    ↓
API 网关 (Nginx)
    ├─ POST /auth/login  →  auth-service
    ├─ POST /auth/token  →  auth-service
    └─ (其他请求)        →  user-service / content-service...
    ↓
用户微服务框架
```

#### 优点

✅ **完全分离认证**:
- user-service 只管理用户数据
- auth-service 专注认证逻辑
- 符合微服务原则

✅ **支持多认证方式**:
- JWT + OAuth2 + OIDC
- 第三方认证提供商
- 硬件密钥支持

✅ **独立扩展**:
- 认证服务独立 scaling
- user-service 性能不受影响
- 支持多数据中心

✅ **符合行业标准**:
- Okta, Auth0, Keycloak 都采用此模式
- 便于未来与第三方 IdP 集成

#### 缺点

❌ **复杂度增加**:
- 需要重新设计所有服务的认证流程
- 引入新的故障点
- 所有现有代码需要更改

❌ **维护成本高**:
- 新增 2-3 个 service-to-service 调用链
- 网络延迟增加 (50-100ms)
- 更多的监控和告警规则

❌ **破坏现有架构**:
- 需要重新设计 gRPC 认证
- 迁移所有现有通信
- 风险高，易出现认证漏洞

#### 工期

**3-5 天** - 完整实现
**5-7 天** - 包括迁移和测试
**1-2 周** - 生产验证

#### 推荐指数

⭐⭐ (2/5)

---

### 🟢 Option 3: 改造为轻量级 token-service（推荐）

#### 架构图

```
user-service (认证入口)
    ↓ (登录成功)
token-service (专用 token 生成器)
    ↓ (返回 JWT)
其他微服务 (验证 JWT，无需 token-service)
```

#### 优点

✅ **分离关注点**:
- user-service: 用户管理 + 认证逻辑
- token-service: JWT 生成 + token 轮换
- 各司其职，易于维护

✅ **低复杂度迁移**:
- 现有认证流程不变
- 仅提取 token 生成逻辑
- 1-2 天完成

✅ **支持扩展**:
- token-service 可独立部署多份
- JWT 无状态，天然支持分布式
- 便于集成第三方认证（未来）

✅ **最小化风险**:
- 现有 user-service 认证不变
- 其他服务 JWT 验证不变
- 平滑的渐进式迁移

#### 缺点

❌ **无法实现完全独立**:
- 仍然依赖 user-service 的登录逻辑
- 认证和用户管理仍耦合

❌ **单一责任不够彻底**:
- 不符合严格的微服务定义
- 但符合实践中的平衡点

#### 工期

**1-2 天** - 提取 token 生成逻辑
**1 天** - 集成和测试
**2 小时** - 部署

#### 推荐指数

⭐⭐⭐⭐⭐ (5/5) **强烈推荐**

---

## 推荐方案：Option 3 (轻量级 token-service)

### 为什么选择 Option 3？

1. **成本-收益最优**: 1-2 天工作，收益是代码清理 + 架构改进

2. **平衡微服务和实用性**:
   - 认证职责清晰
   - 不过度工程化
   - 符合现有架构

3. **支持未来扩展**:
   - 如果需要，可升级为完整 auth-service
   - 如果不需要，token-service 可保持精简

4. **最小化风险**:
   - 现有系统无需改动
   - 逐步迁移，易于回滚
   - 完全向后兼容

### 实施计划（Option 3）

#### Phase 1: 设计 (2 小时)

定义 token-service 接口：

```rust
// token-service/src/lib.rs

pub struct TokenService {
    secret_key: String,
    token_ttl: Duration,
    refresh_ttl: Duration,
}

impl TokenService {
    /// 生成访问令牌和刷新令牌
    pub fn generate_tokens(
        &self,
        user_id: Uuid,
        email: &str,
    ) -> Result<TokenPair> {
        // JWT 生成逻辑
    }

    /// 刷新访问令牌
    pub fn refresh_access_token(
        &self,
        refresh_token: &str,
    ) -> Result<String> {
        // 验证刷新令牌，生成新的访问令牌
    }
}

pub struct TokenPair {
    pub access_token: String,  // JWT，短有效期（15 min）
    pub refresh_token: String, // JWT，长有效期（30 day）
    pub expires_in: i64,      // 秒
}
```

#### Phase 2: 提取代码 (4 小时)

从 user-service 中提取：

```
user-service/handlers/auth.rs → token-service/src/handlers.rs
user-service/models/token.rs  → token-service/src/models.rs
user-service/jwt.rs           → token-service/src/jwt.rs
```

#### Phase 3: 创建服务 (4 小时)

```rust
// token-service/src/main.rs
#[tokio::main]
async fn main() {
    let app = Router::new()
        .route("/api/v1/tokens", post(generate_tokens))
        .route("/api/v1/tokens/refresh", post(refresh_tokens));

    axum::serve(listener, app).await
}

async fn generate_tokens(
    State(service): State<TokenService>,
    Json(req): Json<GenerateTokenRequest>,
) -> Json<TokenPair> {
    service.generate_tokens(req.user_id, req.email)
}
```

#### Phase 4: 集成 (4 小时)

```rust
// user-service 调用 token-service
let token_pair = http_client
    .post("http://token-service:8000/api/v1/tokens")
    .json(&GenerateTokenRequest { user_id, email })
    .send()
    .await?;
```

#### Phase 5: 测试与部署 (4 小时)

- 单元测试
- 集成测试
- 金丝雀部署

**总计**: 1-2 天

---

## 决策矩阵

| 维度 | Option 1 (删除) | Option 2 (完整) | Option 3 (轻量) |
|------|----------|------------|-----------|
| 实施成本 | 0 天 | 1-2 周 | 1-2 天 |
| 架构质量 | 3/5 | 5/5 | 4.5/5 |
| 运维复杂度 | 1/5 | 4/5 | 2/5 |
| 扩展灵活性 | 2/5 | 5/5 | 4/5 |
| 风险等级 | 低 | 高 | 低 |
| **总体评分** | **3/5** | **2/5** | **⭐5/5** |

---

## 最终建议

### 🎯 立即行动（本周）

**如果选择 Option 3:**
1. ✅ 删除当前 auth-service 骨架代码
2. 📋 创建新的轻量级 token-service
3. 🔄 逐步迁移 user-service 认证逻辑
4. ✨ 1-2 周内完全替换

**Timeline**:
- Day 1: 设计 + 实施
- Day 2: 集成 + 测试
- Day 3: 部署验证

---

## 如果选择 Option 1（删除）

**立即行动**:
```bash
# 删除 auth-service 目录
rm -rf /backend/auth-service/

# 更新 Cargo.toml（移除依赖）
# 更新文档（移除 auth-service 参考）
```

**工期**: 4 小时

---

## 投票与决策

### 需要确认

- [ ] 架构师同意（推荐 Option 3）
- [ ] 产品经理确认（认证需求）
- [ ] 运维确认（部署支持）

### 沟通给团队

```
🎯 需要决策：auth-service 方向

现状：auth-service 是 40% 完整的骨架，未实际使用

选项：
1️⃣  删除（0 天）- 最简单
2️⃣  补全（1-2 周）- 最完美
3️⃣  轻量化（1-2 天）- 推荐 ⭐

建议：Option 3（token-service）
原因：
  ✅ 最小工作量
  ✅ 最大收益
  ✅ 最低风险
  ✅ 支持未来扩展

请在 2025-10-31 前投票。
```

---

## 相关文档

- `COMPREHENSIVE_BACKEND_REVIEW.md` - 全面审查（auth-service 40% 完整）
- `backend/BACKEND_ARCHITECTURE_ANALYSIS.md` - 架构分析
- `CRITICAL_FIXES_SUMMARY.md` - 关键修复清单

---

## 历史决策记录

| 日期 | 选项 | 投票者 | 决策 |
|------|------|--------|------|
| 2025-10-29 | 待选择 | 待定 | ⏳ 待决策 |

---

**决策状态**: 🚨 **待定（需在本周五前确认）**

**后续行动**: 一旦决策确定，立即分配给开发者执行

May the Force be with you.
