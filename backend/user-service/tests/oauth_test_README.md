# OAuth2 Integration Tests (AUTH-3001)

## 概述

本测试套件完整覆盖 OAuth2 认证流程，包括 Google、Apple、Facebook 三种提供者的集成测试。

## 测试覆盖

### 1. 新用户注册流程 (Happy Path)
- `test_oauth_google_new_user_registration` - Google OAuth 新用户注册
- `test_oauth_apple_new_user_registration` - Apple OAuth 新用户注册
- `test_oauth_facebook_new_user_registration` - Facebook OAuth 新用户注册

**验证点**:
- OAuth 连接创建成功
- 用户自动创建并验证邮箱
- 提供者用户 ID 正确存储
- 令牌安全哈希存储

### 2. 现有用户登录
- `test_oauth_existing_user_login` - 已注册用户通过 OAuth 登录
- `test_oauth_token_refresh` - OAuth 令牌刷新机制

**验证点**:
- 现有连接查找成功
- 用户信息正确返回
- 令牌更新机制
- 时间戳更新

### 3. 账户链接 (Account Linking)
- `test_link_multiple_oauth_providers` - 链接多个 OAuth 提供者
- `test_login_with_any_linked_provider` - 使用任意已链接提供者登录

**验证点**:
- 单用户支持多个 OAuth 连接
- 所有连接指向同一用户
- 提供者独立性验证

### 4. 账户解绑
- `test_unlink_oauth_provider` - 解绑 OAuth 提供者
- `test_prevent_unlink_last_oauth_provider` - 防止解绑最后一个认证方式

**验证点**:
- 解绑操作成功执行
- 业务逻辑验证（至少保留一种登录方式）
- 连接删除确认

### 5. 错误处理
- `test_oauth_invalid_authorization_code` - 无效授权码
- `test_oauth_state_parameter_tampering` - state 参数篡改
- `test_oauth_provider_error_response` - 提供者错误响应
- `test_oauth_network_error` - 网络错误处理
- `test_oauth_duplicate_provider_connection` - 重复连接检测

**验证点**:
- 所有错误场景正确处理
- 错误信息清晰准确
- 安全机制有效

### 6. 数据安全验证
- `test_oauth_connection_stores_tokens_securely` - 令牌安全存储
- `test_oauth_connection_email_validation` - 邮箱验证

**验证点**:
- 令牌使用 SHA256 哈希存储
- 不存储明文令牌
- 数据验证机制

## 运行测试

### 前置条件

1. **启动测试数据库**:
```bash
# 使用 Docker 启动 PostgreSQL
docker run --name nova-test-db \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=nova_test \
  -p 5432:5432 \
  -d postgres:14
```

2. **设置环境变量**:
```bash
export DATABASE_URL="postgres://postgres:postgres@localhost:5432/nova_test"
```

3. **运行数据库迁移**:
```bash
cd /Users/proerror/Documents/nova/backend
sqlx migrate run --database-url "$DATABASE_URL"
```

### 运行所有 OAuth 测试

```bash
cd /Users/proerror/Documents/nova/backend
cargo test --test oauth_test
```

### 运行特定测试

```bash
# 运行新用户注册测试
cargo test --test oauth_test test_oauth_google_new_user_registration

# 运行账户链接测试
cargo test --test oauth_test test_link_multiple_oauth_providers

# 运行错误处理测试
cargo test --test oauth_test test_oauth_invalid_authorization_code
```

### 显示测试输出

```bash
cargo test --test oauth_test -- --nocapture
```

## 测试结构

```
tests/
├── oauth_test.rs              # 主测试文件
└── common/
    ├── mod.rs                 # 公共模块
    └── fixtures.rs            # 测试辅助函数
```

### 关键辅助函数

**fixtures.rs 中的 OAuth 辅助函数**:
- `create_test_oauth_connection()` - 创建测试 OAuth 连接
- `find_oauth_connection()` - 查找 OAuth 连接
- `count_user_oauth_connections()` - 统计用户连接数

## Mock 策略

本测试使用 `mockall` 库模拟 OAuth 提供者行为:

```rust
mock! {
    pub OAuthProvider {}

    #[async_trait::async_trait]
    impl OAuthProvider for OAuthProvider {
        fn get_authorization_url(&self, state: &str) -> Result<String, OAuthError>;
        async fn exchange_code(&self, code: &str, redirect_uri: &str) -> Result<OAuthUserInfo, OAuthError>;
        fn verify_state(&self, state: &str) -> Result<(), OAuthError>;
        fn provider_name(&self) -> &str;
    }
}
```

**优势**:
- 无需真实 OAuth 提供者
- 测试快速可靠
- 可模拟各种错误场景
- 不受外部 API 限制

## 代码覆盖率目标

### 当前覆盖模块

| 模块 | 目标覆盖率 | 说明 |
|-----|-----------|------|
| `oauth_repo.rs` | 90%+ | OAuth 数据库操作 |
| `oauth/mod.rs` | 85%+ | OAuth 核心逻辑 |
| `oauth/google.rs` | 75%+ | Google 提供者 |
| `oauth/apple.rs` | 75%+ | Apple 提供者 |
| `oauth/facebook.rs` | 75%+ | Facebook 提供者 |
| `handlers/oauth.rs` | 80%+ | OAuth HTTP 处理器 |

### 生成覆盖率报告

使用 `tarpaulin` 生成覆盖率报告:

```bash
# 安装 tarpaulin
cargo install cargo-tarpaulin

# 生成 HTML 覆盖率报告
cargo tarpaulin --test oauth_test --out Html --output-dir coverage/
```

## 测试数据清理

每个测试都包含清理步骤:

```rust
cleanup(&pool).await;
```

`cleanup()` 函数会删除所有测试数据，确保测试隔离性。

## 故障排查

### 数据库连接失败

**错误**: `password authentication failed for user "postgres"`

**解决**:
```bash
# 检查数据库是否运行
docker ps | grep postgres

# 验证连接字符串
psql "postgres://postgres:postgres@localhost:5432/nova_test"
```

### 迁移失败

**错误**: `no migrations found`

**解决**:
```bash
# 确认迁移目录
ls -la migrations/

# 手动运行迁移
sqlx migrate run
```

### 测试超时

**解决**:
```bash
# 增加测试超时时间
cargo test --test oauth_test -- --test-threads=1
```

## CI/CD 集成

### GitHub Actions 示例

```yaml
name: OAuth Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:14
        env:
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: nova_test
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432

    steps:
      - uses: actions/checkout@v3

      - name: Run OAuth tests
        env:
          DATABASE_URL: postgres://postgres:postgres@localhost:5432/nova_test
        run: |
          cargo test --test oauth_test
```

## 贡献指南

### 添加新测试

1. 在 `tests/oauth_test.rs` 中添加新测试函数
2. 遵循命名约定: `test_oauth_<scenario>_<expected_result>`
3. 包含清晰的文档注释
4. 添加适当的断言
5. 确保清理测试数据

### 测试最佳实践

- **独立性**: 每个测试应独立运行
- **幂等性**: 测试可重复执行
- **清晰性**: 测试意图一目了然
- **快速性**: 避免不必要的延迟
- **完整性**: 覆盖正常和异常路径

## 相关文档

- [OAuth2 规范](../docs/specs/oauth2-integration.md)
- [数据库 Schema](../migrations/)
- [API 文档](../docs/api/)

## 测试统计

- **总测试数**: 16
- **Happy Path 测试**: 6
- **错误处理测试**: 5
- **业务逻辑测试**: 5
- **平均执行时间**: < 200ms (不含数据库启动)

## 下一步

- [ ] 添加 OAuth 令牌过期测试
- [ ] 添加并发登录测试
- [ ] 添加 OAuth scope 验证测试
- [ ] 集成端到端测试
