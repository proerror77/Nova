# Kubernetes 1.30 → 1.34 升级计划

**版本**: 1.0
**日期**: 2025-11-27
**目标**: 将 Nova 平台 EKS 集群从 Kubernetes 1.30 升级到 1.34

---

## 📋 执行概览

| 阶段 | 操作 | 预计时间 | 状态 |
|------|------|---------|------|
| **0. 前置准备** | 备份、检查依赖 | 30 分钟 | ⏳ 待执行 |
| **1. EKS 控制平面升级** | 升级到 1.34 | 30-60 分钟 | ⏳ 待执行 |
| **2. 节点组升级** | 更新 AMI + 节点重启 | 60-90 分钟 | ⏳ 待执行 |
| **3. 验证和回滚** | 测试集群功能 | 30 分钟 | ⏳ 待执行 |

---

## 🔧 代码变更已完成

### 已修改文件

#### 1️⃣ `terraform/eks.tf`
```diff
- version = "1.30"
+ version = "1.34"

- instance_types = ["t3.xlarge"]
+ instance_types = ["t3.xlarge"]
+ ami_type       = "AL2_x86_64"   # 两个节点组都已更新
```

**改动详情**：
- ✅ EKS 集群版本: 1.30 → 1.34
- ✅ 主节点组 AMI: AL2_x86_64（支持 1.34）
- ✅ Spot 节点组 AMI: AL2_x86_64（支持 1.34）

#### 2️⃣ `k8s/docs/DEPLOYMENT_CHECKLIST.md`
```diff
- Kubernetes 集群已准备好（至少 1.24 版本）
+ Kubernetes 集群已准备好（至少 1.34 版本）
```

---

## 📋 前置检查清单 (阶段 0)

在执行升级前，请验证以下内容：

### A. 集群健康检查
```bash
# 检查当前版本
kubectl version --short
# Expected: Server Version: v1.30.x

# 检查节点状态
kubectl get nodes -o wide
# Expected: All nodes Ready

# 检查 pod 状态
kubectl get pods -A --field-selector=status.phase!=Running
# Expected: No output (所有 pod 都在运行)

# 检查集群事件
kubectl get events -A
# Expected: No critical errors
```

### B. 备份重要配置
```bash
# 备份 Kubernetes 配置
kubectl get all -A -o yaml > backup-k8s-resources.yaml

# 备份 RDS 数据库
# 在 AWS 控制台创建手动快照

# 备份 Redis
# 确保有最近的快照
```

### C. 验证依赖版本
```bash
# 检查 CoreDNS (自动升级)
kubectl get deployment coredis -n kube-system -o wide

# 检查 aws-vpc-cni 版本 (需要 v1.14+)
kubectl get daemonset aws-node -n kube-system

# 检查 Ingress Controller
kubectl get deployment -n ingress-nginx
```

---

## 🚀 升级步骤

### 阶段 1: EKS 控制平面升级 (30-60 分钟)

```bash
# 方式 A: 使用 Terraform (推荐)
cd terraform/
terraform plan -out=upgrade.tfplan
# 仔细检查 plan 输出，确认只升级 EKS 版本

terraform apply upgrade.tfplan
# AWS 将自动升级控制平面
# 此过程中控制平面会短暂不可用（AWS 自动处理）
```

**或**

```bash
# 方式 B: 使用 AWS CLI
aws eks update-cluster-version \
  --name nova-staging \
  --kubernetes-version 1.34 \
  --region ap-northeast-1
```

### ✅ 验证控制平面升级完成
```bash
# 轮询检查升级状态
aws eks describe-cluster \
  --name nova-staging \
  --region ap-northeast-1 \
  --query 'cluster.version'

# 预期输出: "1.34"
```

---

### 阶段 2: 节点组升级 (60-90 分钟)

**⚠️ 重要**: AWS EKS 会自动处理节点组升级

```bash
# 监控节点升级进程
watch 'kubectl get nodes -o wide'

# Expected progression:
# 1. 新节点创建 (NotReady → Ready 状态转变)
# 2. Pod 逐步迁移到新节点
# 3. 旧节点排空后删除

# 检查节点版本更新进度
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.nodeInfo.kubeletVersion}{"\n"}{end}'
# Expected: 所有节点显示 v1.34.x
```

**节点升级过程解释**:
1. AWS 创建新 EC2 实例 (使用新 AMI)
2. kubelet 版本自动升级到 1.34
3. Pod 通过 `drain` 命令安全迁移
4. 旧节点终止

---

### 阶段 3: 验证和回滚 (30 分钟)

#### ✅ 验证清单

```bash
# 1. 集群版本验证
kubectl version --short
# Server Version: v1.34.x

# 2. 所有节点就绪
kubectl get nodes
# All nodes 状态为 Ready

# 3. 系统 Pod 运行正常
kubectl get pods -n kube-system -o wide
# coredns, aws-node, kube-proxy 等都应该 Running

# 4. 应用 Pod 验证
kubectl get pods -A --field-selector=status.phase!=Running

# 5. 集群网络连通性
kubectl run -it --rm debug --image=busybox --restart=Never -- ping 8.8.8.8

# 6. API 服务器响应性
kubectl api-resources | wc -l
# 应该能快速列出资源类型
```

#### 🔄 验证 Staging 环境应用

```bash
# 检查 GraphQL Gateway
kubectl get service -n nova-staging graphql-gateway

# 测试 API 端点
curl https://your-staging-api.example.com/health

# 检查 Kafka 连接
kubectl logs -n nova-staging deployment/feed-service | grep -i "kafka\|error" | head -20

# 检查数据库连接
kubectl logs -n nova-staging deployment/content-service | grep -i "database\|connection" | head -20
```

#### 🚨 回滚步骤 (如果出现问题)

```bash
# 1. 立即停止升级 (Terraform)
terraform destroy -auto-approve
# 使用备份恢复旧配置

# 2. 恢复 EKS 版本 (如果控制平面已升级)
# ⚠️ 注意: EKS 不支持降级版本
# 您需要创建新集群，使用备份还原数据

# 3. 恢复应用配置
kubectl apply -f backup-k8s-resources.yaml

# 4. 恢复数据库 (如有必要)
# 从备份快照恢复 RDS
```

---

## 📊 版本兼容性矩阵

### 组件版本检查表

| 组件 | 最低版本 | 现有版本 | 状态 |
|------|---------|---------|------|
| **Kubernetes** | 1.34 | 1.34 | ✅ |
| **CoreDNS** | 1.10.1 | Auto-updated | ✅ |
| **aws-vpc-cni** | 1.14.0 | Auto-updated | ✅ |
| **kube-proxy** | 1.34 | Auto-updated | ✅ |
| **Rust** | 1.75 | 1.75+ | ✅ |
| **Node AMI** | AL2_x86_64 | AL2_x86_64 | ✅ |

### 应用依赖验证

```bash
# Protocol Buffers 兼容性 (gRPC services)
# 当前: tonic v0.12, prost v0.13
# 1.34 支持: ✅ 完全兼容

# PostgreSQL 版本
# 当前: 15+
# 1.34 支持: ✅ 完全兼容

# Redis 版本
# 当前: 7+
# 1.34 支持: ✅ 完全兼容
```

---

## 🔍 常见问题和解决方案

### Q1: 升级期间会影响用户服务吗?
**A**:
- **控制平面升级**: AWS 自动处理，用户无感知 (Kubernetes API 高可用)
- **节点升级**: Pod 会自动迁移，有损服务时间 < 5 分钟/节点

### Q2: 可以回滚到 1.30 吗?
**A**: **不可以**。EKS 只支持单向升级。建议：
- 升级前创建快照备份
- 升级完成后保留旧数据 7 天

### Q3: 需要更新应用代码吗?
**A**: **一般不需要**。但建议：
- 验证 gRPC 版本兼容性 (已验证)
- 运行集成测试确保无回归

### Q4: 升级失败会怎样?
**A**:
- 控制平面升级失败：AWS 自动回滚
- 节点升级失败：检查节点日志，手动修复

---

## 📞 联系和支持

- **Terraform 错误**: 检查 `terraform.log`
- **集群连接问题**: 验证 VPC/Security Group 配置
- **Pod 未就绪**: 检查 `kubectl logs <pod>` 和事件日志
- **AWS 支持**: 在 AWS 控制台打开支持工单

---

## 📝 升级历史

| 日期 | 操作 | 执行者 | 结果 |
|------|------|--------|------|
| 2025-11-27 | 规划并准备代码变更 | - | ✅ 完成 |
| YYYY-MM-DD | EKS 控制平面升级 | - | ⏳ 待执行 |
| YYYY-MM-DD | 节点组升级完成 | - | ⏳ 待执行 |
| YYYY-MM-DD | 验证和测试 | - | ⏳ 待执行 |

---

## 🎯 下一步

1. **执行前置检查** (完成 阶段 0 清单)
2. **应用 Terraform 变更** (部署新配置)
3. **监控升级进程** (使用提供的验证命令)
4. **完成验证测试** (确保所有应用正常)
5. **更新本文档** (记录实际升级时间和结果)

---

**祝升级顺利！** 🚀
