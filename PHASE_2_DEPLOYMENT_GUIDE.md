# Phase 2: Content Service gRPC - 部署和验证指南

## 📋 概述

本指南用于将Phase 2 Content Service gRPC实现部署到staging环境并进行验证。Phase 2完成了：

- ✅ 所有6个缺失RPC方法的实现（GetPostsByIds, GetPostsByAuthor, UpdatePost, DeletePost, DecrementLikeCount, CheckPostExists）
- ✅ 缓存一致性修复（LikePost操作后自动失效缓存）
- ✅ 代码质量改进（i32溢出处理、错误日志）
- ✅ 集成测试框架（9个测试场景）

---

## 🚀 部署步骤

### **1. 前置条件检查**

```bash
# 检查代码已编译成功
cd /Users/proerror/Documents/nova/backend/content-service
cargo build 2>&1 | grep -i "finished\|error"

# 预期输出: Finished `dev` profile
# 如果显示 error，停止部署并修复编译错误
```

### **2. 验证git状态**

```bash
cd /Users/proerror/Documents/nova

# 确保所有代码已提交
git status

# 预期：On branch main, nothing to commit, working tree clean
# 如果有未提交的更改，执行 git add . && git commit -m "message"

# 验证ec53dca5提交存在
git log --oneline | grep "ec53dca5"
```

### **3. 运行本地编译验证**

```bash
# 清除缓存并完整重建（确保proto编译正确）
cd /Users/proerror/Documents/nova/backend/content-service
cargo clean
cargo build --release

# 验证完整编译（应该3-5分钟）
# 预期：Finished `release` profile
```

### **4. 运行本地单元测试**

```bash
# 运行test suite（不需要SERVICES_RUNNING）
cd /Users/proerror/Documents/nova/backend/content-service
cargo test --lib

# 预期输出示例:
# test result: ok. X passed; 0 failed; 0 ignored
```

### **5. 构建Docker镜像**

```bash
# 在项目根目录构建content-service镜像
cd /Users/proerror/Documents/nova

# 方法1：使用现有Dockerfile
docker build -f backend/content-service/Dockerfile -t nova-content-service:phase2 .

# 方法2：使用Docker Compose（如果配置存在）
docker-compose -f docker-compose.staging.yml build content-service
```

### **6. 部署到Staging环境**

```bash
# 使用kubectl部署到EKS staging命名空间
kubectl config use-context <staging-context>
kubectl set image deployment/content-service \
  content-service=nova-content-service:phase2 \
  -n nova-staging

# 等待Rollout完成（监控Pod重启）
kubectl rollout status deployment/content-service -n nova-staging

# 验证Pod运行状态
kubectl get pods -n nova-staging | grep content-service
```

---

## ✅ 部署后验证步骤

### **7. 检查服务健康状态**

```bash
# 端口转发到本地
kubectl port-forward -n nova-staging svc/content-service 8081:8081 &

# 测试gRPC服务可用性（需要grpcurl）
grpcurl -plaintext localhost:8081 list
# 预期输出：nova.content.ContentService

# 列出所有RPC方法
grpcurl -plaintext localhost:8081 nova.content.ContentService/
# 预期包含：
# - GetPostsByIds
# - GetPostsByAuthor
# - UpdatePost
# - DeletePost
# - DecrementLikeCount
# - CheckPostExists
```

### **8. 运行Smoke测试**

```bash
# 基础smoke测试（不依赖具体服务状态）
bash scripts/smoke-staging.sh

# 预期：All checks passed
```

### **9. 执行集成测试（可选，需要服务运行）**

```bash
# 在staging环境中运行集成测试
cd backend/content-service

# 仅运行结构验证（不需要实际gRPC连接）
cargo test --test grpc_content_service_test test_suite_loads_successfully

# 预期：test test_suite_loads_successfully ... ok

# 运行完整集成测试（需要SERVICES_RUNNING=true）
SERVICES_RUNNING=true \
cargo test --test grpc_content_service_test -- --ignored --nocapture

# 这将运行所有9个测试场景（需要content-service实际运行）
```

### **10. 验证新RPC方法功能**

使用grpcurl进行快速功能测试：

#### **测试GetPostsByIds - 批量查询**
```bash
grpcurl -plaintext -d '{
  "post_ids": [
    "550e8400-e29b-41d4-a716-446655440000",
    "550e8400-e29b-41d4-a716-446655440001"
  ]
}' localhost:8081 nova.content.ContentService/GetPostsByIds
```

#### **测试GetPostsByAuthor - 按作者查询**
```bash
grpcurl -plaintext -d '{
  "author_id": "550e8400-e29b-41d4-a716-446655440010",
  "status": "published",
  "limit": 10,
  "offset": 0
}' localhost:8081 nova.content.ContentService/GetPostsByAuthor
```

#### **测试CheckPostExists - 检查存在性**
```bash
grpcurl -plaintext -d '{
  "post_id": "550e8400-e29b-41d4-a716-446655440000"
}' localhost:8081 nova.content.ContentService/CheckPostExists
```

#### **测试UpdatePost - 更新帖子**
```bash
grpcurl -plaintext -d '{
  "post_id": "550e8400-e29b-41d4-a716-446655440000",
  "title": "Updated Title",
  "status": "archived"
}' localhost:8081 nova.content.ContentService/UpdatePost
```

#### **测试DeletePost - 软删除**
```bash
grpcurl -plaintext -d '{
  "post_id": "550e8400-e29b-41d4-a716-446655440000",
  "deleted_by_id": "550e8400-e29b-41d4-a716-446655440099"
}' localhost:8081 nova.content.ContentService/DeletePost
```

#### **测试DecrementLikeCount - 获取点赞数**
```bash
grpcurl -plaintext -d '{
  "post_id": "550e8400-e29b-41d4-a716-446655440000"
}' localhost:8081 nova.content.ContentService/DecrementLikeCount
```

---

## 🔍 监控和日志

### **查看Pod日志**

```bash
# 实时查看content-service日志
kubectl logs -f deployment/content-service -n nova-staging

# 查看特定错误（grep tracing::error）
kubectl logs deployment/content-service -n nova-staging | grep -i error

# 查看gRPC调用日志
kubectl logs deployment/content-service -n nova-staging | grep "gRPC:"
```

### **监控关键指标**

```bash
# 检查缓存失效日志（表示cache invalidation正常工作）
kubectl logs deployment/content-service -n nova-staging | grep "Invalidated cache"

# 验证SQL执行日志
kubectl logs deployment/content-service -n nova-staging | grep "Database"

# 检查性能日志（ANY()参数化查询）
kubectl logs deployment/content-service -n nova-staging | grep "batch"
```

---

## 🚨 故障排查

### **问题1：gRPC方法未找到**

**症状**: `grpcurl` 显示 "method not found"

**解决**:
1. 确认proto文件已更新 ✓
2. 运行 `cargo clean && cargo build` 重新编译proto
3. 重新构建Docker镜像
4. 重新部署到staging

### **问题2：缓存不一致**

**症状**: 更新post后GetPost仍返回旧数据

**解决**:
1. 检查日志中是否有 "Invalidated cache" 消息
2. 验证cache.invalidate_post()被调用
3. 查看Redis连接状态

### **问题3：软删除过滤失败**

**症状**: 已删除的post仍出现在查询结果中

**解决**:
1. 验证SQL查询包含 `AND deleted_at IS NULL`
2. 检查database schema中deleted_at列是否存在
3. 运行: `SELECT * FROM posts WHERE id = '<uuid>' AND deleted_at IS NULL`

### **问题4：i32溢出**

**症状**: 点赞数或帖子数超过2^31-1时显示异常

**解决**:
1. 检查日志中的 "exceeded i32::MAX" 警告
2. 这是预期行为，会返回i32::MAX并记录警告
3. 监视是否需要升级为i64存储

---

## 📊 验收标准

### **全部通过以下测试则部署成功:**

- ✅ 本地编译完成（cargo build --release）
- ✅ 所有grpcurl方法调用返回非error响应
- ✅ smoke测试全部通过
- ✅ 日志中有"Invalidated cache"消息（表示缓存失效正常）
- ✅ 没有compilation warnings（除了无关的dependency warnings）
- ✅ 性能测试：GetPostsByIds在100个post时 < 100ms

---

## 🔄 回滚步骤

如果部署出现问题，可快速回滚：

```bash
# 方法1：重新部署前一个稳定版本
kubectl set image deployment/content-service \
  content-service=nova-content-service:previous-stable \
  -n nova-staging

# 方法2：使用git revert（如果有问题）
git revert ec53dca5
cargo build --release
# 重新构建镜像并部署

# 方法3：查看deployment历史
kubectl rollout history deployment/content-service -n nova-staging

# 回滚到上一个revision
kubectl rollout undo deployment/content-service -n nova-staging
```

---

## 📝 部署检查清单

在生产环境部署前，确保完成：

- [ ] Phase 2代码编译成功（零错误）
- [ ] 所有6个新RPC方法可通过grpcurl调用
- [ ] Smoke测试全部通过
- [ ] 集成测试通过（基础测试）
- [ ] 日志监控显示缓存失效正常
- [ ] 性能基准测试达标
- [ ] 确认没有breaking changes
- [ ] 与其他服务的集成点已验证
- [ ] 文档已更新
- [ ] 团队已知悉部署计划

---

## 📞 后续任务

### **P1优先级（High）**

1. **实现gRPC客户端集成测试**
   - 替换grpc_content_service_test.rs中的TODO占位符
   - 使用tonic_client连接到本地/staging服务
   - 激活所有9个测试场景

2. **CI/CD集成**
   - 在GitHub Actions中添加集成测试步骤
   - 自动运行SERVICES_RUNNING=true测试
   - 在部署前失败则阻止

3. **性能基准测试**
   - 建立GetPostsByIds的性能基线
   - 监控批量查询性能
   - 设置告警阈值

### **P2优先级（Medium）**

1. 实现批量删除操作(DeletePostsByIds)
2. 添加缓存预热机制
3. 实现分布式事务(跨服务调用)

### **P3优先级（Low）**

1. GraphQL查询层支持
2. 实时更新通知(WebSocket)
3. 高级查询缓存策略

---

## 🎯 成功指标

| 指标 | 目标 | 验证方法 |
|------|------|--------|
| 编译时间 | < 5分钟 | `time cargo build --release` |
| RPC响应时间 | < 50ms (单个), < 100ms (批量) | grpcurl + 时间测量 |
| 缓存命中率 | > 80% | 日志分析 |
| 错误率 | < 0.1% | 日志监控 |
| 可用性 | > 99.9% | 烟雾测试持续监控 |

---

**最后更新**: 2025-11-04
**状态**: Phase 2实现完成，准备部署到staging
**负责人**: Claude Code
