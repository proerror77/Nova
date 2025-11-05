# Nova 项目安全审计 - 快速参考

## 关键发现 (按严重程度排序)

### 🔴 CRITICAL (立即修复)

#### 1. gRPC 无认证通信 (CVSS 9.8)
- **文件**: `/backend/libs/grpc-clients/src/lib.rs` (L92-127)
- **问题**: 所有服务间通信使用 `http://` 无加密，无 mTLS，无令牌认证
- **影响**: MITM 可拦截/修改任何服务间请求，伪造用户身份
- **修复时间**: 1-2 周
- **修复方案**: 启用 mTLS 或服务令牌认证

#### 2. 令牌吊销失败安全 (CVSS 8.2)
- **文件**: `/backend/libs/actix-middleware/src/jwt_auth.rs` (L302-304)
- **问题**: Redis 失败时返回 `Ok(false)` → 吊销的令牌被认为有效
- **影响**: 已吊销的令牌（注销、密码变更后）仍可使用
- **修复时间**: 2-3 天
- **修复方案**: 将错误转换为拒绝请求

---

### 🟠 HIGH (1-4 周内修复)

#### 3. 缺少 NBF 声明 (CVSS 7.2)
- **文件**: `/backend/libs/crypto-core/src/jwt.rs` (L56-71)
- **问题**: JWT 结构无 `nbf` (not before) 字段
- **影响**: 无法实现令牌定时发放、时间窗口保护
- **修复时间**: 1 周
- **修复方案**: 添加 `pub nbf: Option<i64>` 到 Claims 结构

#### 4. 缺少显式 IDOR 检查 (CVSS 7.1)
- **文件**: `/backend/user-service/src/handlers/users.rs` (L204-268)
- **问题**: 更新端点未显式验证用户是否拥有资源
- **影响**: 用户可能修改他人的个人资料
- **修复时间**: 3-5 天
- **修复方案**: 在所有更新/删除端点添加所有权检查

#### 5. 缺少 JTI 和密钥轮换 (CVSS 7.0)
- **文件**: `/backend/libs/crypto-core/src/jwt.rs`
- **问题**: 无 JWT ID (JTI)，无密钥版本控制
- **影响**: 无法精细化令牌吊销，密钥泄露难以处理
- **修复时间**: 2 周
- **修复方案**: 添加 `jti` 和 `kid` 字段

#### 6. 缺少服务认证框架 (CVSS 7.0)
- **文件**: `/backend/feed-service/src/handlers/recommendation.rs` (注释)
- **问题**: 无方式验证哪个服务在发起请求
- **影响**: 恶意服务可冒充其他服务
- **修复时间**: 2-3 周
- **修复方案**: 实现服务令牌或 mTLS 客户端证书

---

### 🟡 MEDIUM (2-4 周内修复)

#### 7. 缺少 IAT 验证 (CVSS 5.5)
- **文件**: `/backend/libs/crypto-core/src/jwt.rs` (L356-361)
- **问题**: JWT 未验证 `iat` (issued at) 声明
- **影响**: 理论上令牌可伪造未来发行时间
- **修复时间**: 1 天
- **修复方案**: 设置 `validation.validate_iat = true`

#### 8. 日志泄露敏感信息 (CVSS 5.3)
- **文件**: `/backend/auth-service/src/grpc/mod.rs`
- **问题**: 登录失败日志包含 `user_id` 和 `email`
- **影响**: 用户枚举攻击，隐私泄露
- **修复时间**: 2-3 天
- **修复方案**: 脱敏用户标识信息

#### 9. 授权框架未充分使用 (CVSS 5.5)
- **文件**: `/backend/libs/crypto-core/src/authorization.rs`
- **问题**: 定义了 `AuthContext` 但大多数端点未使用
- **影响**: 权限检查不一致，容易遗漏
- **修复时间**: 1-2 周
- **修复方案**: 在所有端点中强制使用 AuthContext

---

## 快速修复清单

```
[ 第 1 天 ] 
□ 修复令牌吊销 Redis 失败 (2-3h)
□ 添加 iat 验证 (1h)
□ 脱敏敏感日志 (2h)

[ 第 1 周 ]
□ 启用 gRPC mTLS (2-3d)
□ 添加 IDOR 检查 (2-3d)
□ 添加 nbf 字段 (1d)

[ 第 2-4 周 ]
□ 实现 JTI/密钥轮换 (2w)
□ 服务认证框架 (2-3w)
□ 统一使用 AuthContext (1w)
```

---

## 文件修复优先级

### P0 (今天修复)
```
/backend/libs/actix-middleware/src/token_revocation.rs
→ 修改第 303-304 行的错误处理
```

### P1 (本周修复)
```
/backend/libs/crypto-core/src/jwt.rs
→ 第 356-361 行：添加 validate_iat
→ 第 56-71 行：添加 nbf 字段

/backend/user-service/src/handlers/users.rs
→ 第 204-268 行：添加显式所有权检查
```

### P2 (2 周内)
```
/backend/libs/grpc-clients/src/lib.rs
/backend/libs/grpc-clients/src/config.rs
→ 启用 mTLS 配置
```

---

## 测试验证清单

- [ ] 新增单元测试验证 iat 检查
- [ ] 新增集成测试验证 nbf 声明
- [ ] 新增 IDOR 漏洞测试用例
- [ ] 验证 Redis 故障时请求被拒
- [ ] 验证 gRPC 连接需要 mTLS
- [ ] 验证日志无敏感信息

---

## 参考资源

- **OWASP JWT Best Practices**: https://cheatsheetseries.owasp.org/cheatsheets/JSON_Web_Token_for_Java_Cheat_Sheet.html
- **JWT RFC 7519**: https://tools.ietf.org/html/rfc7519
- **gRPC Security**: https://grpc.io/docs/guides/auth/
- **mTLS Setup**: https://grpc.io/docs/guides/performance-best-practices/

---

## 总体安全评分

```
┌─────────────────────┬────┐
│ JWT 实现             │ 8/10 │
│ 密码安全             │ 9/10 │
│ 令牌吊销             │ 6/10 │
│ 跨服务认证           │ 2/10 │
│ IDOR 防护            │ 5/10 │
│ 敏感数据处理         │ 6/10 │
├─────────────────────┼────┤
│ 整体评分             │ 5.3/10 │
│ CVSS 基础评分        │ 7.8   │
│ 生产就绪             │ ❌    │
└─────────────────────┴────┘
```

需要立即修复 P0 项后才能考虑上线。

