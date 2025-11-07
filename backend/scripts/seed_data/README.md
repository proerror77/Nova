# Seed Data Scripts

这个目录包含用于初始化测试环境的种子数据脚本。

## 快速开始

### 本地运行

```bash
# 设置环境变量
export DB_HOST=localhost
export DB_PASSWORD=nova123
export DB_USER=nova
export DB_PORT=5432

# 运行脚本
chmod +x run_seed_data.sh
./run_seed_data.sh local
```

### Staging 环境（Kubernetes）

```bash
# 应用 Kubernetes Job
kubectl apply -f ../../../k8s/infrastructure/overlays/staging/seed-data-job.yaml

# 等待完成
kubectl wait --for=condition=complete --timeout=300s job/seed-data-init -n nova

# 查看日志
kubectl logs job/seed-data-init -n nova
```

## 文件说明

| 文件 | 数据库 | 内容 |
|------|--------|------|
| `01_seed_auth_users.sql` | nova_auth | 5个测试用户（alice, bob, charlie, diana, eve） |
| `02_seed_user_profiles.sql` | nova_user | 用户资料、关注关系、统计数据 |
| `03_seed_content_posts.sql` | nova_content | 5条测试帖子、点赞、评论 |
| `04_seed_messaging_conversations.sql` | nova_messaging | 3个对话、11条消息 |
| `run_seed_data.sh` | - | 执行脚本（按顺序运行所有SQL） |

## 测试用户

所有用户密码：`TestPass123!`

| Email | User ID | Username | 特点 |
|-------|---------|----------|------|
| alice@test.nova.com | `00000000-0000-0000-0000-000000000001` | alice_test | Verified, 关注2人 |
| bob@test.nova.com | `00000000-0000-0000-0000-000000000002` | bob_test | Verified, 有帖子 |
| charlie@test.nova.com | `00000000-0000-0000-0000-000000000003` | charlie_test | 未认证 |
| diana@test.nova.com | `00000000-0000-0000-0000-000000000004` | diana_test | 私密账号 |
| eve@test.nova.com | `00000000-0000-0000-0000-000000000005` | eve_test | Backend架构师 |

## 安全警告

⚠️ **永远不要在生产环境运行这些脚本！**

脚本包含以下安全检查：
- 环境变量验证（阻止 `production`）
- SQL 使用 `ON CONFLICT DO NOTHING` 避免覆盖现有数据
- 仅插入测试域名邮箱（`@test.nova.com`）

## 重置数据

如果需要重置测试数据：

```bash
# 删除测试用户（级联删除相关数据）
kubectl exec -n nova postgres-xxx -- psql -U nova -d nova_auth -c \
  "DELETE FROM users WHERE email LIKE '%@test.nova.com';"

# 重新运行 seed data
./run_seed_data.sh local
```

## 故障排查

### 问题: "psql: connection refused"

**解决方案**: 检查 PostgreSQL 是否运行
```bash
kubectl get pods -n nova | grep postgres
kubectl port-forward -n nova svc/postgres 5432:5432
```

### 问题: "password authentication failed"

**解决方案**: 验证 DB_PASSWORD 环境变量
```bash
echo $DB_PASSWORD
# 应该输出: nova123

# 或从 secret 获取
kubectl get secret nova-db-credentials -n nova -o jsonpath='{.data.DB_PASSWORD}' | base64 -d
```

### 问题: "duplicate key value violates unique constraint"

这是正常的 - 脚本使用 `ON CONFLICT DO NOTHING`，如果数据已存在会跳过。

## 扩展

添加新服务的 seed data：

1. 创建新文件 `05_seed_new_service.sql`
2. 更新 `run_seed_data.sh` 添加新数据库
3. 更新 K8s ConfigMap 在 `seed-data-job.yaml`

示例：
```sql
-- 05_seed_new_service.sql
INSERT INTO new_table (id, name) VALUES
    ('test-id-1', 'Test Name 1')
ON CONFLICT (id) DO NOTHING;
```

## 相关文档

- [E2E Testing Guide](../../../docs/E2E_TESTING_GUIDE.md) - 完整的E2E测试指南
- [Staging Runbook](../../../k8s/docs/STAGING_RUNBOOK.md) - Staging环境操作手册
