# Auth-Service 提取计划 (Week 1-4)

## 当前状态分析

### user-service中的认证代码
- **handlers/auth.rs**: 988行 - 认证HTTP处理器（注册、登录、密码重置等）
- **handlers/oauth.rs**: 561行 - OAuth HTTP处理器（回调、令牌刷新等）
- **security/jwt.rs**: 466行 - JWT生成、验证、签名
- **services/oauth/**: 2,520行
  - apple.rs: 333行 - Apple OAuth集成
  - facebook.rs: 220行 - Facebook OAuth集成
  - google.rs: 201行 - Google OAuth集成
  - jwks_cache.rs: 333行 - JWKS缓存管理
  - pkce.rs: 238行 - PKCE实现
  - state_manager.rs: 281行 - OAuth状态管理
  - token_encryption.rs: 286行 - 令牌加密
  - token_refresh_job.rs: 460行 - 令牌刷新任务

**总计**: ~4,515行认证相关代码

### 相关的模型和数据库
- **db/oauth_repo.rs**: OAuth数据库操作
- **models/**: 用户、OAuth令牌、会话等模型
- **middleware/jwt_auth.rs**: JWT认证中间件
- **services/**: JWT密钥轮换等

## 分阶段提取计划

### Phase 1: 准备工作 (Day 1-2)
- [ ] 创建auth-service项目结构
- [ ] 定义proto文件（auth.proto）
- [ ] 分析user-service中的认证依赖关系

### Phase 2: 核心逻辑提取 (Day 3-7)
- [ ] 提取JWT核心逻辑（security/jwt.rs）
- [ ] 提取认证处理器（handlers/auth.rs）
- [ ] 提取OAuth处理器（handlers/oauth.rs）
- [ ] 提取OAuth服务（services/oauth/）

### Phase 3: 数据库和模型 (Day 8-10)
- [ ] 提取认证相关模型
- [ ] 提取OAuth数据库操作
- [ ] 建立数据库迁移脚本

### Phase 4: 集成和测试 (Day 11-15)
- [ ] 实现gRPC服务
- [ ] 测试OAuth流程（Google、Apple、Facebook）
- [ ] 测试JWT生成和验证
- [ ] 测试密码重置流程

### Phase 5: 迁移和兼容性 (Day 16-20)
- [ ] user-service改为调用auth-service
- [ ] 实现HTTP网关兼容层
- [ ] 测试端到端流程
- [ ] 性能优化和文档

## Proto 契约设计

```protobuf
syntax = "proto3";

package nova.auth.v1;

service AuthService {
  // 用户认证
  rpc Register(RegisterRequest) returns (AuthResponse);
  rpc Login(LoginRequest) returns (AuthResponse);
  rpc ValidateToken(ValidateTokenRequest) returns (ValidateTokenResponse);
  rpc RefreshToken(RefreshTokenRequest) returns (AuthResponse);
  rpc Logout(LogoutRequest) returns (LogoutResponse);
  
  // OAuth认证
  rpc StartOAuthFlow(StartOAuthFlowRequest) returns (StartOAuthFlowResponse);
  rpc CompleteOAuthFlow(CompleteOAuthFlowRequest) returns (AuthResponse);
  
  // 密码管理
  rpc RequestPasswordReset(RequestPasswordResetRequest) returns (RequestPasswordResetResponse);
  rpc ResetPassword(ResetPasswordRequest) returns (ResetPasswordResponse);
  
  // 会话管理
  rpc CreateSession(CreateSessionRequest) returns (SessionResponse);
  rpc GetSession(GetSessionRequest) returns (SessionResponse);
  rpc RevokeSession(RevokeSessionRequest) returns (RevokeSessionResponse);
}
```

## 关键架构决策

### 1. 令牌管理
- **JWT格式**: RS256签名，15分钟过期
- **刷新令牌**: 7天有效期，存储在Redis
- **签名密钥**: 定期轮换（每月），用JWKS公开

### 2. OAuth集成
- **支持**: Google、Apple、Facebook
- **PKCE**: 用于移动客户端安全性
- **状态管理**: Redis存储OAuth状态（5分钟过期）

### 3. 密码策略
- **最小长度**: 8字符
- **复杂度**: 至少包含大小写、数字、特殊字符
- **哈希**: Argon2id
- **重置**: 24小时有效期的安全令牌

### 4. 会话管理
- **存储**: Redis（支持Sentinel高可用）
- **超时**: 30天不活动自动失效
- **并发**: 支持多设备登录

## 风险和缓解

| 风险 | 影响 | 缓解 |
|-----|------|------|
| JWT密钥泄露 | 高 | 定期轮换，使用JWKS公开密钥 |
| 令牌刷新循环 | 中 | 设置合理的刷新间隔 |
| OAuth回调超时 | 中 | 增加超时时间，使用重试机制 |
| 数据库迁移 | 高 | 创建完整的迁移脚本和回滚计划 |

## 交付物

### Week 1-4结束时
1. ✅ auth-service完整代码（~4,500行）
2. ✅ auth.proto定义和生成的代码
3. ✅ 数据库迁移脚本
4. ✅ HTTP网关兼容层
5. ✅ 完整的单元和集成测试
6. ✅ API文档（OpenAPI）
7. ✅ 部署指南和运维手册

## 成功标准
- ✅ 所有认证流程（注册、登录、OAuth）正常工作
- ✅ JWT验证通过
- ✅ 密码重置功能完整
- ✅ 与现有user-service兼容
- ✅ 性能与原有实现相同或更优
- ✅ 零生产缺陷
