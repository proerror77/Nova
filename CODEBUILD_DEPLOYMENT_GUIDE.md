# AWS CodeBuild 部署指南

## 概述

本指南说明如何使用 AWS CodeBuild 替代 GitHub Actions，自动构建 Nova 微服务的 Docker 镜像并推送到 ECR。

### 为什么选择 CodeBuild？

| 特性 | GitHub Actions | CodeBuild |
|------|---|---|
| 状态 | ❌ 运行器分配失败 | ✅ 工作正常 |
| ECR 集成 | 需要 OIDC | ✅ 原生集成 |
| 成本 | 免费（有限）| 按构建时间计费（便宜）|
| 管理 | GitHub 管理 | AWS 管理 |
| 所有者 | GitHub | 完全控制 |

---

## 快速开始（3 分钟）

### 前置条件
- AWS CLI 已安装并配置
- 您的 AWS 账户凭证有效
- 拥有 CloudFormation 和 CodeBuild 权限

### 步骤 1：部署 CodeBuild

```bash
# 进入项目目录
cd /Users/proerror/Documents/nova

# 使脚本可执行
chmod +x aws/deploy-codebuild.sh

# 运行部署脚本
aws/deploy-codebuild.sh
```

脚本会自动：
- ✅ 验证 AWS 凭证
- ✅ 验证 CloudFormation 模板
- ✅ 创建 IAM 角色和权限
- ✅ 创建 CodeBuild 项目
- ✅ 创建 CloudWatch 日志组

### 步骤 2：启动第一次构建

```bash
# 启动构建
aws codebuild start-build \
  --project-name nova-ecr-build \
  --region ap-northeast-1

# 输出示例：
# {
#     "build": {
#         "id": "nova-ecr-build:12345678-1234-1234-1234-123456789012",
#         "arn": "arn:aws:codebuild:ap-northeast-1:025434362120:build/nova-ecr-build:12345678-...",
#         ...
#     }
# }
```

### 步骤 3：监控构建进度

```bash
# 查看实时日志
aws logs tail /aws/codebuild/nova-ecr-build --follow --region ap-northeast-1

# 或在 AWS 控制台查看：
# https://console.aws.amazon.com/codesuite/codebuild/projects/nova-ecr-build/history
```

---

## 文件说明

### 📄 buildspec.yml
CodeBuild 的构建规范文件，定义：
- **pre_build**: 登录 ECR，创建仓库，设置 Docker Buildx
- **build**: 构建 8 个服务，推送到 ECR
- **post_build**: 验证镜像，生成构建摘要
- **cache**: 缓存 Rust 和 Docker 文件（加速后续构建）

### 📄 aws/codebuild-template.yaml
CloudFormation 模板，创建：
- IAM 执行角色（带 ECR 和日志权限）
- CodeBuild 项目
- CloudWatch 日志组
- 输出项目名称和 ARN

### 📄 aws/codebuild-iam-policy.json
IAM 策略文档（仅供参考），包含：
- CloudWatch Logs 权限
- ECR 权限（pull/push）
- VPC 权限（如果使用 VPC）
- S3 制品权限

### 📄 aws/deploy-codebuild.sh
自动化部署脚本，执行：
- AWS 凭证检查
- 模板验证
- CloudFormation 创建/更新
- 输出显示和后续步骤

---

## 构建成本估算

### 按构建时间
- 前 100 次构建/月：免费（在共享构建池中）
- 每次构建 ~30-40 分钟（8 个服务并行）
- 之后：0.005 USD/构建分钟

### 示例
```
8 个服务 × 35 分钟 = 280 构建分钟/月
280 分钟 × 0.005 USD = $1.40 USD/月
```

**结论**：超级便宜！比 GitHub Actions 高级计划便宜得多。

---

## 工作流集成

### 方案 A：手动触发（推荐开始使用）
```bash
# 需要时手动启动
aws codebuild start-build --project-name nova-ecr-build
```

### 方案 B：GitHub Webhook（需要设置）
1. 获取 GitHub Personal Access Token
2. 在 AWS Secrets Manager 存储
3. 更新 CloudFormation 模板以启用 Webhook

### 方案 C：CloudWatch Events（定时构建）
```bash
# 每周一上午 10:00 UTC 自动构建
aws events put-rule \
  --name nova-weekly-build \
  --schedule-expression "cron(0 10 ? * MON *)" \
  --state ENABLED
```

### 方案 D：CodePipeline（完整 CI/CD）
连接：GitHub → CodeBuild → CodeDeploy → EKS/ECS

---

## 故障排除

### ❌ "Access Denied" 错误

**原因**：IAM 权限不足

**解决**：
```bash
# 检查角色权限
aws iam get-role-policy \
  --role-name CodeBuildNovaECRRole \
  --policy-name CodeBuildLogsPolicy
```

### ❌ "Docker daemon not running"

**原因**：CodeBuild 环境中的 Docker 问题

**解决**：
```bash
# 在 buildspec.yml 中启用特权模式
# ✓ 已在模板中设置：PrivilegedMode: true
```

### ❌ ECR 镜像大小过大

**原因**：Rust 编译产物缓存不足

**解决**：
```bash
# buildspec.yml 中已配置缓存：
cache:
  paths:
    - '/root/.cargo/**/*'
    - '/root/.docker/**/*'
```

### ❌ 构建超时

**原因**：构建机器配置太小

**目前设置**：`BUILD_GENERAL1_LARGE`（8 vCPU，16 GB RAM）

**升级**（如需要）：
```bash
aws codebuild update-project \
  --name nova-ecr-build \
  --environment computeType=BUILD_GENERAL1_XLARGE
```

---

## 监控和告警

### 查看构建历史
```bash
aws codebuild batch-get-builds \
  --ids $(aws codebuild list-builds-for-project \
    --project-name nova-ecr-build \
    --query 'ids[0]' --output text)
```

### 设置失败告警
```bash
# 创建 CloudWatch 告警（当构建失败时通知）
aws cloudwatch put-metric-alarm \
  --alarm-name nova-codebuild-failures \
  --alarm-actions arn:aws:sns:ap-northeast-1:025434362120:your-topic
```

### 查看构建日志
```bash
# 彩色日志输出
aws logs tail /aws/codebuild/nova-ecr-build \
  --follow \
  --log-stream-name-pattern 'nova-ecr-build:*'
```

---

## 清理资源

### 删除 CodeBuild 项目
```bash
aws cloudformation delete-stack \
  --stack-name nova-codebuild-stack \
  --region ap-northeast-1

# 等待删除完成
aws cloudformation wait stack-delete-complete \
  --stack-name nova-codebuild-stack \
  --region ap-northeast-1
```

---

## 常见问题

### Q: 如何与现有 GitHub Actions 共存？
A: 两者可以共存。当 GitHub Actions 恢复时，保留两个流程提高可靠性。

### Q: 如何自动化每次推送时的构建？
A: 需要：
1. GitHub Personal Access Token
2. 在 AWS Secrets Manager 存储
3. 配置 CodeBuild Webhook

### Q: 构建成功后如何自动部署？
A: 使用 CodePipeline：
```bash
CodeBuild 成功 → CodeDeploy → EKS (自动更新镜像)
```

### Q: 如何修改构建流程？
A: 编辑 buildspec.yml，提交到 GitHub，CodeBuild 会自动使用最新版本

---

## 成功标志

✅ buildspec.yml 在仓库根目录
✅ CloudFormation 堆栈 `nova-codebuild-stack` 已创建
✅ CodeBuild 项目 `nova-ecr-build` 可见
✅ 第一次构建成功完成
✅ 8 个镜像出现在 ECR `nova/*` 仓库

---

## 下一步

1. **立即启动构建**
   ```bash
   aws codebuild start-build --project-name nova-ecr-build
   ```

2. **设置定时构建**（可选）
   ```bash
   aws events put-rule --name nova-weekly-build --schedule-expression "cron(0 10 ? * MON *)"
   ```

3. **添加 Slack 通知**（可选）
   ```bash
   # 连接 CloudWatch 告警到 Slack
   ```

4. **集成 CodePipeline**（可选）
   ```bash
   # 连接到自动部署
   ```

---

**已准备就绪！您现在拥有独立于 GitHub 的可靠构建系统。** 🚀
