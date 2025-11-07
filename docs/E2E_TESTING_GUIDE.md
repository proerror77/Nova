# End-to-End Testing Guide

完整的端到端测试指南，包括 seed data 初始化和真实服务测试。

## 目录
- [概述](#概述)
- [架构](#架构)
- [Seed Data](#seed-data)
- [运行 E2E 测试](#运行-e2e-测试)
- [测试场景](#测试场景)
- [故障排查](#故障排查)

---

## 概述

E2E 测试验证整个系统的集成：
- **真实服务调用**：不使用 mock，直接调用部署的服务
- **真实数据**：使用 seed data 初始化的测试用户和内容
- **跨服务流程**：验证 auth → user → content → messaging 的完整链路

### 为什么需要 E2E 测试？

| 测试类型 | 单元测试 | 集成测试 | E2E 测试 |
|---------|---------|---------|---------|
| **范围** | 单个函数 | 单个服务 | 全系统 |
| **数据** | Mock | Mock/真实 DB | 真实 DB + Seed |
| **网络** | 无 | localhost | 真实 gRPC/HTTP |
| **发现的问题** | 逻辑错误 | 接口不匹配 | 配置错误、超时、认证问题 |

---

## 架构

```
┌─────────────────────────────────────────────────────────────┐
│                      E2E Test Runner                         │
│                   (tests/e2e_real_services_test.rs)         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
         ┌────────────────────┴────────────────────┐
         │                                          │
    ┌────▼─────┐  ┌─────────┐  ┌─────────┐  ┌────▼─────┐
    │  Auth    │  │  User   │  │ Content │  │Messaging │
    │ Service  │  │ Service │  │ Service │  │ Service  │
    └────┬─────┘  └────┬────┘  └────┬────┘  └────┬─────┘
         │             │             │             │
         └─────────────┴─────────────┴─────────────┘
                              │
                    ┌─────────▼─────────┐
                    │   PostgreSQL      │
                    │  (with Seed Data) │
                    └───────────────────┘
```

---

## Seed Data

### 测试用户

所有测试用户的密码均为：`TestPass123!`

| User ID | Email | Username | Display Name | 特点 |
|---------|-------|----------|--------------|------|
| `00000000-0000-0000-0000-000000000001` | alice@test.nova.com | alice_test | Alice Smith | Verified, 关注 Bob 和 Charlie |
| `00000000-0000-0000-0000-000000000002` | bob@test.nova.com | bob_test | Bob Johnson | Verified, 关注 Alice |
| `00000000-0000-0000-0000-000000000003` | charlie@test.nova.com | charlie_test | Charlie Brown | 未认证用户 |
| `00000000-0000-0000-0000-000000000004` | diana@test.nova.com | diana_test | Diana Prince | Verified, 私密账号 |
| `00000000-0000-0000-0000-000000000005` | eve@test.nova.com | eve_test | Eve Anderson | Backend 架构师 |

### 预置内容

- **Posts**: 5 条测试帖子（来自 Alice, Bob, Charlie, Eve）
- **Conversations**: 3 个对话
  - Alice ↔ Bob（5条消息）
  - Bob ↔ Charlie（3条消息）
  - Alice ↔ Eve（3条消息）
- **Follow 关系**: 6 对关注关系
- **Likes**: 部分帖子已有点赞

---

## 运行 E2E 测试

### 选项 1: 在 Staging 环境运行（推荐）

#### 步骤 1: 初始化 Seed Data

```bash
# 在 K8s 中运行 seed data job
kubectl apply -f k8s/infrastructure/overlays/staging/seed-data-job.yaml

# 等待 job 完成
kubectl wait --for=condition=complete --timeout=300s job/seed-data-init -n nova

# 查看日志
kubectl logs job/seed-data-init -n nova
```

#### 步骤 2: 验证服务健康

```bash
# 检查所有服务是否运行
kubectl get pods -n nova | grep -E "(auth|user|content|messaging)-service"

# 所有 pods 应该显示 1/1 Running
```

#### 步骤 3: 运行测试

```bash
# 设置环境变量
export E2E_ENV=staging

# 配置 kubeconfig（如果需要）
export KUBECONFIG=~/.kube/config

# 运行所有 E2E 测试
cargo test --test e2e_real_services_test -- --ignored --nocapture --test-threads=1

# 运行特定测试
cargo test --test e2e_real_services_test test_e2e_01_authentication_flow -- --ignored --nocapture
```

### 选项 2: 本地运行（通过 Port Forward）

#### 步骤 1: Port Forward 服务

```bash
# Terminal 1: Auth Service
kubectl port-forward -n nova svc/auth-service 8080:8080

# Terminal 2: User Service
kubectl port-forward -n nova svc/user-service 8081:8080

# Terminal 3: Content Service
kubectl port-forward -n nova svc/content-service 8082:8080

# Terminal 4: Messaging Service
kubectl port-forward -n nova svc/messaging-service 8085:8080
```

#### 步骤 2: 初始化 Seed Data

```bash
# 方法 A: 通过 port-forward 连接 PostgreSQL
kubectl port-forward -n nova svc/postgres 5432:5432

# 设置环境变量
export DB_HOST=localhost
export DB_PASSWORD=nova123
export DB_USER=nova
export DB_PORT=5432

# 运行 seed 脚本
cd backend/scripts/seed_data
chmod +x run_seed_data.sh
./run_seed_data.sh local

# 方法 B: 直接在 K8s 中运行 job
kubectl apply -f k8s/infrastructure/overlays/staging/seed-data-job.yaml
```

#### 步骤 3: 运行测试

```bash
export E2E_ENV=local

cargo test --test e2e_real_services_test -- --ignored --nocapture --test-threads=1
```

---

## 测试场景

### Test 0: 健康检查 (`test_e2e_00_health_checks`)

**目的**: 验证所有服务可达且健康

**步骤**:
1. 检查 auth-service `/health`
2. 检查 user-service `/health`
3. 检查 content-service `/health`
4. 检查 messaging-service `/health`

**预期结果**: 所有服务返回 200 OK

---

### Test 1: 认证流程 (`test_e2e_01_authentication_flow`)

**目的**: 验证 auth-service 的登录功能

**步骤**:
1. 使用 Alice 的凭据登录
2. 使用 Bob 的凭据登录
3. 验证两个 token 不同

**预期结果**:
- 返回有效的 JWT access token
- Token 包含正确的 user_id
- 每个用户的 token 是唯一的

**验证的风险**:
- ❌ JWT 密钥配置错误
- ❌ 数据库连接失败
- ❌ Password hash 不匹配

---

### Test 2: 用户资料检索 (`test_e2e_02_user_profile_retrieval`)

**目的**: 验证 user-service 的 gRPC/HTTP 接口

**步骤**:
1. Alice 登录获取 token
2. 使用 token 获取 Alice 的个人资料
3. 使用 token 获取 Bob 的个人资料

**预期结果**:
- 返回完整的用户资料（username, display_name, bio, avatar）
- Verified 状态正确
- Follower/Following 计数正确

**验证的风险**:
- ❌ User service 无法连接 PostgreSQL
- ❌ gRPC 认证 interceptor 失败
- ❌ 跨服务调用超时

---

### Test 3: 关注关系一致性 (`test_e2e_03_follow_relationship_consistency`)

**目的**: 验证社交图谱数据完整性

**步骤**:
1. 获取 Alice 的资料（following_count 应该 >= 2）
2. 获取 Bob 的资料（follower_count 应该 >= 1，因为 Alice 关注他）
3. 验证双向关系

**预期结果**:
- Seed data 中的关注关系正确加载
- 计数器准确
- 数据一致性维护

**验证的风险**:
- ❌ Seed data 未正确加载
- ❌ 关注关系表缺失索引
- ❌ 计数器未更新

---

### Test 4: 创建和检索帖子 (`test_e2e_04_create_and_retrieve_post`)

**目的**: 验证 content-service 的 CRUD 操作

**步骤**:
1. Alice 创建新帖子
2. 通过 ID 检索帖子
3. 验证内容匹配

**预期结果**:
- 帖子成功创建并返回 UUID
- 可以通过 ID 检索
- Author ID 正确
- Content 完整

**验证的风险**:
- ❌ Content service 数据库写入失败
- ❌ 媒体 URL 验证错误
- ❌ Visibility 权限检查失败

---

### Test 5: 消息对话 (`test_e2e_05_messaging_conversations`)

**目的**: 验证 messaging-service 的查询功能

**步骤**:
1. Alice 获取所有对话列表
2. 验证至少有 1 个对话（来自 seed data）
3. 检查对话结构（participants, last_message）

**预期结果**:
- Seed data 中的对话正确加载
- Alice 是参与者之一
- Last message 字段有效

**验证的风险**:
- ❌ Messaging service 无法查询对话
- ❌ 跨服务用户资料查询失败
- ❌ 消息未按时间排序

---

### Test 6: 帖子到 Feed 流程 (`test_e2e_06_post_to_feed_flow`)

**目的**: 验证完整的内容发布和订阅流

**步骤**:
1. Alice 创建新帖子
2. 等待 2 秒（Feed 传播延迟）
3. Bob 获取自己的 feed
4. 验证 Alice 的帖子出现在 Bob 的 feed 中

**预期结果**:
- Bob 的 feed 包含 Alice 的新帖子（因为 Bob 关注 Alice）
- Feed 在 2 秒内传播
- 帖子按时间倒序排列

**验证的风险**:
- ❌ Feed 生成逻辑错误
- ❌ 关注关系查询失败
- ❌ Redis/缓存未同步
- ❌ Event-driven 架构的消息丢失

---

## 测试输出示例

```bash
$ cargo test --test e2e_real_services_test -- --ignored --nocapture

running 7 tests

=== E2E Test: Health Checks ===
Checking auth-service: http://127.0.0.1:8080
✓ auth-service is healthy
Checking user-service: http://127.0.0.1:8081
✓ user-service is healthy
Checking content-service: http://127.0.0.1:8082
✓ content-service is healthy
Checking messaging-service: http://127.0.0.1:8085
✓ messaging-service is healthy
=== All Services Healthy ===

test test_e2e_00_health_checks ... ok

=== E2E Test: Authentication Flow ===
Step 1: Login as Alice
✓ Alice logged in successfully
  Access token: eyJhbGciOiJIUzI1NiIs...
Step 2: Login as Bob
✓ Bob logged in successfully
✓ Tokens are unique
=== Test Passed ===

test test_e2e_01_authentication_flow ... ok

...

test result: ok. 7 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 12.34s
```

---

## 故障排查

### 问题 1: "Failed to connect to service"

**症状**:
```
Error: Failed to send login request
thread 'test_e2e_01_authentication_flow' panicked at 'Failed to send login request'
```

**原因**: 服务未运行或网络不可达

**解决方案**:
```bash
# 检查 pods 状态
kubectl get pods -n nova

# 检查服务端点
kubectl get svc -n nova

# 验证 port-forward（本地测试）
kubectl port-forward -n nova svc/auth-service 8080:8080
curl http://localhost:8080/health
```

---

### 问题 2: "Login failed: 401 Unauthorized"

**症状**:
```
assertion failed: Login failed: 401
```

**原因**: Seed data 未加载或密码 hash 不正确

**解决方案**:
```bash
# 重新运行 seed data job
kubectl delete job seed-data-init -n nova
kubectl apply -f k8s/infrastructure/overlays/staging/seed-data-job.yaml

# 验证用户是否存在
kubectl exec -n nova postgres-xxx -- psql -U nova -d nova_auth -c "SELECT email FROM users WHERE email LIKE '%@test.nova.com';"
```

---

### 问题 3: "Alice's post should appear in Bob's feed"

**症状**:
```
assertion failed: Alice's post should appear in Bob's feed (Bob follows Alice)
```

**原因**: Feed 生成逻辑问题或关注关系未加载

**解决方案**:
```bash
# 检查关注关系
kubectl exec -n nova postgres-xxx -- psql -U nova -d nova_user -c \
  "SELECT follower_id, following_id FROM follows WHERE follower_id = '00000000-0000-0000-0000-000000000002';"

# 检查 content-service 日志
kubectl logs -n nova -l component=content-service --tail=100

# 增加等待时间（如果是异步 feed 生成）
# 在测试代码中将 tokio::time::sleep(Duration::from_secs(2)) 改为 5 秒
```

---

### 问题 4: "Get user profile failed: 500"

**症状**:
```
Get user profile failed: 500 Internal Server Error
```

**原因**: user-service 无法连接数据库或 ClickHouse

**解决方案**:
```bash
# 检查 user-service 日志
kubectl logs -n nova -l component=user-service --tail=50

# 检查数据库连接
kubectl exec -n nova user-service-xxx -- env | grep DB

# 验证 ClickHouse
kubectl exec -n nova chi-nova-ch-single-0-0-0 -- clickhouse-client --query="SELECT 1"
```

---

## 最佳实践

### 1. 测试隔离
- 每个测试使用唯一的数据（如带 UUID 的 post content）
- 不要假设测试执行顺序
- 清理创建的测试数据（或使用事务回滚）

### 2. 超时配置
```rust
// HTTP 客户端超时
Client::builder()
    .timeout(Duration::from_secs(10))
    .build()

// 测试级别超时
#[tokio::test(flavor = "multi_thread")]
#[timeout(Duration::from_secs(30))]
async fn test_e2e_xxx() { ... }
```

### 3. 重试机制
对于可能因网络抖动失败的测试，添加重试：

```rust
for attempt in 1..=3 {
    match perform_test().await {
        Ok(_) => return,
        Err(e) if attempt < 3 => {
            println!("Attempt {} failed: {}, retrying...", attempt, e);
            tokio::time::sleep(Duration::from_secs(1)).await;
        }
        Err(e) => panic!("Test failed after 3 attempts: {}", e),
    }
}
```

### 4. 详细日志
在测试中打印关键信息：
```rust
println!("Step 1: Creating post with content: {}", content);
println!("  Response status: {}", response.status());
println!("  Post ID: {}", post.id);
```

---

## CI/CD 集成

### GitHub Actions 示例

```yaml
name: E2E Tests

on:
  push:
    branches: [main, staging]
  schedule:
    - cron: '0 */6 * * *'  # 每6小时运行一次

jobs:
  e2e-staging:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Configure kubectl
        uses: azure/k8s-set-context@v3
        with:
          kubeconfig: ${{ secrets.KUBECONFIG_STAGING }}

      - name: Initialize seed data
        run: |
          kubectl apply -f k8s/infrastructure/overlays/staging/seed-data-job.yaml
          kubectl wait --for=condition=complete --timeout=300s job/seed-data-init -n nova

      - name: Run E2E tests
        env:
          E2E_ENV: staging
        run: |
          cargo test --test e2e_real_services_test -- --ignored --nocapture --test-threads=1

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: e2e-test-results
          path: target/test-results/
```

---

## 维护和扩展

### 添加新测试场景

1. 在 `tests/e2e_real_services_test.rs` 中添加新函数：
```rust
#[tokio::test]
#[ignore]
async fn test_e2e_07_new_scenario() {
    let config = E2EConfig::from_env();
    // 测试逻辑
}
```

2. 更新本文档，添加测试场景描述

3. 如果需要新的 seed data，更新相应的 SQL 脚本

### 添加新服务

1. 在 `E2EConfig` 中添加服务 URL：
```rust
struct E2EConfig {
    // ...
    new_service_url: String,
}
```

2. 创建 seed data SQL 脚本：`05_seed_new_service.sql`

3. 更新 `run_seed_data.sh` 和 `seed-data-job.yaml`

---

## 参考资料

- [STAGING_RUNBOOK.md](../k8s/docs/STAGING_RUNBOOK.md) - Staging 环境操作手册
- [CLAUDE.md](../CLAUDE.md) - 代码审查标准
- [gRPC Cross-Service Integration Tests](../tests/grpc_cross_service_integration_test.rs) - gRPC 测试示例

---

**最后更新**: 2025-01-07
**维护者**: Nova Platform Team
