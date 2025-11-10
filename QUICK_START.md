# 🚀 GraphQL Gateway 快速部署指南

## 现状总结

✅ **已完成**:
- Kubernetes 配置（Deployment, Service, Ingress, HPA, PDB）
- Dockerfile 优化（支持 monorepo 构建）
- GitHub Actions CI/CD workflows
- AWS EKS 基础设施配置
- 文档完善

⚠️  **待解决**: AWS 负载均衡器配额限制

## 立即部署（3 步）

### 第 1 步：推送代码触发构建

```bash
# 已经提交，直接推送
git push origin main
```

这将自动触发：
1. **ecr-build-push.yml** - 构建所有服务（包括 graphql-gateway）
2. **deploy-graphql-gateway.yml** - 部署到 K8s

### 第 2 步：监控部署进度

**方式 A: GitHub Web UI**
```
1. 访问 https://github.com/YOUR_ORG/nova/actions
2. 查看 "Deploy GraphQL Gateway" workflow
3. 等待所有 jobs 完成（约 5-10 分钟）
```

**方式 B: GitHub CLI**
```bash
# 查看最新 run
gh run list --workflow=deploy-graphql-gateway.yml --limit 5

# 实时查看日志
gh run watch
```

### 第 3 步：验证部署

```bash
# 连接到 EKS
aws eks update-kubeconfig --region ap-northeast-1 --name nova-staging

# 检查 pods
kubectl get pods -n nova-gateway -l app=graphql-gateway

# 测试 API
kubectl port-forward -n nova-gateway svc/graphql-gateway 8080:8080

# 打开浏览器
curl http://localhost:8080/health
open http://localhost:8080/playground
```

## 常见问题

### Q: 构建失败怎么办？

**检查日志**:
```bash
gh run view --log-failed
```

**常见原因**:
- Cargo 依赖问题 → 检查 `backend/graphql-gateway/Cargo.toml`
- 网络超时 → GitHub Actions 会自动重试
- ECR 权限 → 检查 IAM 角色配置

### Q: 部署失败怎么办？

**检查 K8s 状态**:
```bash
kubectl describe pod -n nova-gateway -l app=graphql-gateway
kubectl logs -n nova-gateway -l app=graphql-gateway --tail=50
```

**常见原因**:
- 镜像拉取失败 → 检查 ECR 镜像是否存在
- ConfigMap 错误 → 检查服务端点配置
- 资源不足 → 检查节点资源: `kubectl top nodes`

### Q: 如何访问 GraphQL Playground？

**临时方案** (当前 ALB 配额限制):
```bash
# 方式 1: Port forward
kubectl port-forward -n nova-gateway svc/graphql-gateway 8080:8080
# 访问: http://localhost:8080/playground

# 方式 2: 在集群内访问
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://graphql-gateway.nova-gateway.svc.cluster.local:8080/playground
```

**长期方案** (解决 ALB 配额后):
- 访问: https://api.nova.social/playground

### Q: 如何更新配置？

**修改环境变量**:
```bash
# 编辑 ConfigMap
kubectl edit configmap graphql-gateway-config -n nova-gateway

# 重启 pods 应用配置
kubectl rollout restart deployment/graphql-gateway -n nova-gateway
```

**修改 Secret**:
```bash
# 编辑 Secret
kubectl edit secret graphql-gateway-secret -n nova-gateway

# 重启应用
kubectl rollout restart deployment/graphql-gateway -n nova-gateway
```

## 解决 AWS 配额限制

### 选项 1: 联系 AWS Support（推荐）

```
1. 登录 AWS Console
2. Support → Create case
3. 类型: Service Limit Increase
4. 服务: Elastic Load Balancing
5. 请求:
   - Application Load Balancers: 从 0 增加到 5
   - 原因: Production EKS microservices architecture
6. 预计时间: 1-2 工作日
```

### 选项 2: 使用现有方案

如果有其他 AWS 账户或环境：
```bash
# 修改 workflow 中的账户 ID
sed -i 's/025434362120/YOUR_ACCOUNT_ID/g' .github/workflows/*.yml

# 推送触发构建
git add .github/workflows/
git commit -m "chore: update AWS account ID"
git push origin main
```

## 性能优化

### 扩容

```bash
# 手动扩容到 5 个实例
kubectl scale deployment graphql-gateway -n nova-gateway --replicas=5

# 查看自动扩缩容状态
kubectl get hpa graphql-gateway-hpa -n nova-gateway -w
```

### 监控

```bash
# 资源使用情况
kubectl top pods -n nova-gateway

# 实时日志
kubectl logs -n nova-gateway -l app=graphql-gateway -f

# 事件
kubectl get events -n nova-gateway --sort-by='.lastTimestamp'
```

## 回滚

```bash
# 查看历史版本
kubectl rollout history deployment/graphql-gateway -n nova-gateway

# 回滚到上一个版本
kubectl rollout undo deployment/graphql-gateway -n nova-gateway

# 回滚到特定版本
kubectl rollout undo deployment/graphql-gateway -n nova-gateway --to-revision=2
```

## 生产检查清单

部署到生产前确认：

- [ ] 所有测试通过
- [ ] Staging 环境验证完成
- [ ] 数据库 migrations 已运行
- [ ] 配置已更新（尤其是 JWT_SECRET）
- [ ] 监控和告警已配置
- [ ] 团队已通知部署窗口
- [ ] 回滚计划已准备
- [ ] AWS 配额问题已解决（生产必需）

## 下一步

1. **立即**: 推送代码触发首次构建
   ```bash
   git push origin main
   ```

2. **今天**: 提交 AWS Support case 增加配额

3. **本周**: 配置生产域名和 SSL
   - 获取域名: api.nova.social
   - 安装 cert-manager
   - 配置 Let's Encrypt

4. **下周**: iOS 应用集成
   - 更新 Config.swift
   - 测试所有 API 调用
   - 发布新版本

## 获取帮助

- **文档**: `DEPLOYMENT_STATUS.md` - 完整基础设施文档
- **CI/CD**: `GITHUB_ACTIONS_GUIDE.md` - GitHub Actions 详细指南
- **日志**: `kubectl logs -n nova-gateway -l app=graphql-gateway`
- **状态**: `kubectl get all -n nova-gateway`

---

**准备好了吗？** 运行: `git push origin main` 🚀
