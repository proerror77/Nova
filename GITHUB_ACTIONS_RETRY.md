# GitHub Actions 重新尝试指南

## 📋 概述

创建了新的简化 GitHub Actions workflow：`.github/workflows/simple-ecr-build.yml`

这个 workflow 针对之前的 runner 分配失败进行了优化。

---

## 🔄 变更内容

### 问题分析
之前失败：所有 runner 类型（ubuntu-latest, ubuntu-24.04 等）都报"0 steps executing"
新方案：
- ✅ 最小化配置（移除复杂的条件和特殊逻辑）
- ✅ 逐个构建（sequential，不并行）
- ✅ 添加调试信息（debug AWS credentials）
- ✅ 简化 trigger（workflow_dispatch + push）

### 工作流特点

| 特点 | 配置 |
|------|------|
| 触发方式 | `workflow_dispatch` (手动) + `push` (自动) |
| 并行度 | `max-parallel: 1`（逐个构建） |
| 服务数 | 8 个微服务 |
| 构建目标 | ECR (ap-northeast-1) |
| 镜像标签 | commit SHA + latest |
| 缓存策略 | Docker registry cache |

---

## 🚀 测试步骤

### 方式 1：GitHub UI 手动触发（推荐）

1. 访问：https://github.com/proerror77/Nova
2. 点击：**Actions** 标签
3. 左侧菜单找到：**Simple ECR Build & Push**
4. 点击：**Run workflow**
5. 保持默认分支（main）
6. 点击：**Run workflow** 按钮
7. 等待构建完成（预计 20-30 分钟）

### 方式 2：Git Push 自动触发

```bash
# 推送到 main 分支时自动触发
git push origin main

# 或推送到任何 feature 分支
git push origin feature/test-workflow
```

---

## 📊 预期输出

### 如果成功 ✅

1. **GitHub Actions UI**：
   - ✅ Build job 显示绿色对勾
   - ✅ 每个服务都有单独的 step 输出
   - ✅ Summary job 显示"All services built and pushed to ECR"

2. **AWS ECR**：
   ```bash
   # 查看推送的镜像
   aws ecr describe-repositories --region ap-northeast-1 \
     --query 'repositories[?repositoryName==`nova/*`]'

   # 查看每个服务的镜像
   for service in auth-service user-service content-service \
                  feed-service media-service messaging-service \
                  search-service streaming-service; do
     aws ecr describe-images \
       --repository-name nova/$service \
       --region ap-northeast-1 \
       --query 'imageDetails[-1].[imageTags,imageSizeInBytes,imagePushedAt]'
   done
   ```

### 如果失败 ❌

1. **0 steps executing**（之前的问题）：
   - 说明 GitHub 仍有 runner 分配问题
   - 建议：回到 AWS CodeBuild（见下文）

2. **AWS credentials 失败**：
   - 检查 `secrets.AWS_ROLE_ARN` 是否正确
   - 运行本地诊断：
     ```bash
     aws sts get-caller-identity
     ```

3. **Docker build 失败**：
   - 检查 Dockerfile 是否有错误
   - 尝试本地构建：
     ```bash
     docker buildx build --platform linux/amd64 \
       -f backend/auth-service/Dockerfile \
       ./backend
     ```

4. **ECR 推送失败**：
   - 检查 ECR 仓库是否存在
   - 创建缺失的仓库：
     ```bash
     for service in auth-service user-service content-service \
                    feed-service media-service messaging-service \
                    search-service streaming-service; do
       aws ecr create-repository \
         --repository-name nova/$service \
         --region ap-northeast-1 2>/dev/null || true
     done
     ```

---

## 🔧 故障排除

### 如果 GitHub Actions 仍然失败

**问题**：GitHub Actions runner 分配超时或 0 steps executing

**解决**：
1. GitHub 的 runner 分配存在已知问题
2. 回到 AWS CodeBuild（需要等待 AWS Support 解决账户限制）
3. 或使用本地构建：
   ```bash
   cd backend
   REGISTRY="025434362120.dkr.ecr.ap-northeast-1.amazonaws.com"

   for service in auth-service user-service content-service \
                  feed-service media-service messaging-service \
                  search-service streaming-service; do
     docker buildx build --platform linux/amd64 --push \
       -f $service/Dockerfile \
       -t ${REGISTRY}/nova/$service:latest .
   done
   ```

---

## 📝 对比三种方案

| 方案 | 成本 | 速度 | 易用性 | 状态 |
|------|------|------|--------|------|
| **GitHub Actions** | ✅ 免费 | ⭐⭐ | ⭐⭐⭐ | 🔄 测试中 |
| **AWS CodeBuild** | 💰 $1.40/月 | ⭐⭐⭐ | ⭐⭐ | ⏳ 等待 Support |
| **本地 Docker** | ✅ 免费 | ⭐⭐⭐⭐ | ⭐⭐ | ✅ 即用 |

---

## 🎯 推荐流程

### 立即（现在）
1. **测试 GitHub Actions**（这个 workflow）
   - 如果成功 → 继续使用 GitHub Actions
   - 如果失败 → 进到下一步

2. **如果 GitHub 失败** → 继续使用本地 Docker 构建（已经在用）

### 等待期间
3. **提交 AWS Support 案例**（见 AWS_SUPPORT_REQUEST.md）
   - 等待 AWS 解除账户限制
   - 一旦解除 → 可以启用 AWS CodeBuild

### 长期
- ✅ **优先**：GitHub Actions（免费，集成好）
- ✅ **备选**：AWS CodeBuild（快速，稳定）
- ✅ **本地**：Docker buildx（完全控制）

---

## 📚 相关文档

| 文档 | 用途 |
|------|------|
| `AWS_SUPPORT_REQUEST.md` | AWS CodeBuild 账户限制诊断和 Support 申请 |
| `CODEBUILD_DEPLOYMENT_STATUS.md` | CodeBuild 部署状态和三个验证步骤 |
| `CODEBUILD_DEPLOYMENT_GUIDE.md` | CodeBuild 完整部署指南 |
| 本文件 | GitHub Actions 重新尝试指南 |

---

## ✅ 检查清单

- [ ] 已访问 GitHub Actions workflow UI
- [ ] 已点击"Run workflow"按钮
- [ ] 已观察构建日志
- [ ] 已在 ECR 确认镜像
- [ ] 已记录成功/失败结果

---

**状态**：🔄 等待您的测试反馈

如果 GitHub Actions 成功，这将是最简单的 CI/CD 解决方案。
如果仍然失败，我们将完全依赖本地构建或等待 AWS CodeBuild 的账户限制被解除。
