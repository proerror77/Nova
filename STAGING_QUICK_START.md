# 🚀 Nova Staging 快速开始

## 5 分钟了解整个 Staging Pipeline

### 什么是 Staging？

**Staging** = 将后端代码自动构建、部署到类似生产的环境，以便在发布到生产前验证。

### 完整流程（3 步）

```
步骤 1: 推送代码到 main
        ↓ GitHub 自动触发
步骤 2: 构建镜像 + 更新部署配置
        ↓ 自动推送到 Git
步骤 3: ArgoCD 自动部署到 staging 集群
        ↓
✅ Done! 新版本在 staging 环境运行
```

---

## ⚡ 立即开始

### 最简单的方式：推送代码

```bash
# 1. 修改后端代码
vim backend/auth-service/src/main.rs

# 2. 提交并推送
git add backend/
git commit -m "feat: add new feature"
git push origin main

# 3. 自动触发！
# GitHub Actions 开始：
# - 构建 8 个微服务 (2 个并行)
# - 更新 K8s 部署清单
# - ArgoCD 自动部署
# - 运行烟雾测试验证
```

**完成时间**: ~10-15 分钟

### 或者：手动触发

```bash
# 访问 GitHub Actions
https://github.com/proerror77/Nova/actions

# 找到 "Stage Backend Code to Staging"
# 点击 "Run workflow" 按钮
# 完成！
```

---

## 📦 构成部分

### 1. Docker 镜像构建（自动）

**做什么**：为所有 8 个微服务构建 Docker 镜像

**输出**：镜像推送到 ECR registry
```
025434362120.dkr.ecr.ap-northeast-1.amazonaws.com/nova/{service}:{commit-sha}
```

**时间**: ~8 分钟（2 个并行）

### 2. 部署清单更新（自动）

**做什么**：修改 K8s 配置文件，使用新镜像标签

**修改文件**:
```
k8s/infrastructure/overlays/staging/kustomization.yaml
```

**例子**：
```yaml
# 自动更新为：
images:
- name: nova/auth-service
  newTag: abc123def456...  # 最新 commit SHA
```

**时间**: 即时

### 3. ArgoCD 自动部署（自动）

**做什么**：检测 Git 变更，自动部署到 staging K8s 集群

**配置**（已配置）：
- 监听分支: `main`
- 监听路径: `k8s/infrastructure/overlays/staging`
- 自动同步: `enabled`

**时间**: 3-5 分钟

### 4. 烟雾测试（自动）

**做什么**：验证所有 8 个服务都健康

**检查**:
- ✅ `/health` 端点可用
- ✅ `/metrics` Prometheus 指标可用
- ✅ 所有 Pod 就绪

**时间**: < 1 分钟

---

## 🔍 监控进度

### 实时查看

```bash
# GitHub Actions 进度
https://github.com/proerror77/Nova/actions

# 或通过 GitHub CLI
gh run list --workflow staging-deploy.yml --limit 1
gh run view <run-id>
```

### 查看 Kubernetes 部署

```bash
# 监控 Pod 启动
kubectl -n nova get pods -w

# 查看部署状态
kubectl -n nova get deployments

# 查看最近事件
kubectl -n nova get events --sort-by=.lastTimestamp
```

### 查看 ArgoCD 同步

```bash
# CLI 方式
argocd app get nova-staging

# UI 方式
kubectl port-forward -n argocd svc/argocd-server 8080:443
open https://localhost:8080
```

---

## ❓ 常见问题

### Q1: 多长时间完成整个流程？

**A**: 总共 10-15 分钟
- 构建镜像: 8 分钟
- 更新配置: 1 分钟
- ArgoCD 同步: 3-5 分钟
- 烟雾测试: < 1 分钟

### Q2: 如果构建失败怎么办？

**A**: 检查日志找出原因
```bash
# 查看构建错误
https://github.com/proerror77/Nova/actions

# 常见原因：
# - Dockerfile 语法错误
# - 依赖缺失
# - 编译错误

# 修复后重新推送即可
git commit -m "fix: resolve build error"
git push origin main
```

### Q3: Staging 和 Production 有什么区别？

**A**:
| 维度 | Staging | Production |
|------|---------|------------|
| 副本 | 2 | 3+ |
| 资源 | 中等 | 大 |
| 环保等级 | 一般 | 严格 |
| 触发 | main push | Release tag |

### Q4: 可以部分更新吗（只更新 1 个服务）？

**A**: 目前不行，staging-deploy.yml 会更新所有 8 个服务。
- 如果只想测试 1 个服务：
  - 方案 A: 在 dev 环境测试
  - 方案 B: 修改 workflow 的 matrix strategy

### Q5: 如何回滚到之前的版本？

**A**: 使用 ArgoCD
```bash
# 查看历史
argocd app history nova-staging

# 回滚到上一个版本
argocd app rollback nova-staging 1

# 或指定特定 commit
git checkout <previous-commit>
git push origin main --force  # ⚠️ 谨慎使用
```

---

## 📋 检查清单

部署完成后，验证：

- [ ] GitHub Actions workflow 绿色勾（成功）
- [ ] ECR 有新镜像
  ```bash
  aws ecr describe-images --repository-name nova/auth-service
  ```
- [ ] Kubernetes Pod 就绪
  ```bash
  kubectl -n nova get pods | grep Running
  ```
- [ ] 烟雾测试通过
  ```bash
  bash scripts/smoke-staging.sh
  ```
- [ ] 服务可访问
  ```bash
  kubectl -n nova port-forward svc/auth-service 8084:8084
  curl http://localhost:8084/health
  ```

---

## 🔧 如果需要调试

### 场景 1: 查看最新 8 个镜像

```bash
aws ecr describe-images \
  --repository-name nova/auth-service \
  --region ap-northeast-1 \
  --query 'imageDetails[0:8].[imageTags,imagePushedAt]' \
  --output table
```

### 场景 2: 查看 K8s 部署的镜像标签

```bash
kubectl -n nova get deployments \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.containers[0].image}{"\n"}{end}'
```

### 场景 3: 检查 ArgoCD 同步日志

```bash
argocd app logs nova-staging --follow

# 或查看同步状态
argocd app get nova-staging | grep -A 20 "Status:"
```

### 场景 4: 手动触发 ArgoCD 同步

```bash
# 立即同步
argocd app sync nova-staging

# 强制重新同步
argocd app sync nova-staging --force

# 等待完成
argocd app wait nova-staging
```

---

## 📚 深入学习

- **完整指南**: 查看 `STAGING_DEPLOYMENT_GUIDE.md`
- **Workflow 定义**: 查看 `.github/workflows/staging-deploy.yml`
- **K8s 配置**: 查看 `k8s/infrastructure/overlays/staging/`
- **烟雾测试**: 查看 `scripts/smoke-staging.sh`

---

## 💡 最佳实践

1. **定期检查**: 每次部署后验证烟雾测试通过
2. **代码审查**: 在推送前进行代码审查
3. **监控告警**: 设置 Slack/邮件通知部署失败
4. **文档更新**: 修改配置时更新相关文档
5. **版本标签**: 为每个 release 打上 Git tag

---

## 🚨 应急处理

### 如果 staging 环境崩溃

```bash
# 1. 立即查看发生了什么
kubectl -n nova describe pod <failing-pod>

# 2. 查看最近的日志
kubectl -n nova logs <pod-name> --tail=50

# 3. 回滚到上一个版本
argocd app rollback nova-staging 1

# 4. 调查根本原因
git log --oneline | head -5
```

### 如果 GitHub Actions 失败

```bash
# 1. 查看失败的步骤日志
https://github.com/proerror77/Nova/actions

# 2. 修复问题
vim backend/some-file

# 3. 重新推送
git commit -m "fix: address build issue"
git push origin main
```

---

## 📞 获取帮助

- **Staging 文档**: `STAGING_DEPLOYMENT_GUIDE.md`
- **GitHub Actions 日志**: `https://github.com/proerror77/Nova/actions`
- **Kubernetes 状态**: `kubectl -n nova <command>`
- **ArgoCD UI**: `kubectl port-forward -n argocd svc/argocd-server 8080:443`

---

**现在就开始**: `git push origin main` 🎉
