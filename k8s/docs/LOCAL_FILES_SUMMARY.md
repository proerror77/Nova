# 本地验证文件总结

## 概述

本目录包含的本地验证文件用于在本地Docker环境（Docker Desktop、Minikube、kind）中快速验证Kubernetes配置。

## 📋 本地验证文件清单

### 1. 配置文件 (修改后用于本地开发)

#### `messaging-service-configmap-local.yaml` (57行)
**用途**: 本地开发配置
**关键改动**:
- `APP_ENV`: "development" (vs "production")
- `RUST_LOG`: "debug,messaging_service=debug" (更详细的日志)
- `WS_DEV_ALLOW_ALL`: "true" (本地开发模式)
- `DATABASE_MAX_CONNECTIONS`: "5" (减少以节省资源)
- `REDIS_POOL_SIZE`: "5" (减少以节省资源)

**何时使用**: 所有本地开发测试

#### `messaging-service-secret-local.yaml` (45行)
**用途**: 本地开发密钥和凭证
**关键点**:
- 使用简化的凭证: `postgres:postgres`
- `DATABASE_URL`: 指向 `host.docker.internal` (本地机器)
- `REDIS_URL`: 指向 `host.docker.internal`
- 包含测试JWT公钥
- 包含测试加密密钥

**何时使用**: 所有本地开发测试

#### `messaging-service-deployment-local.yaml` (234行)
**用途**: 本地开发部署配置
**关键改动**:
- `replicas: 1` (vs 3 在生产)
- `imagePullPolicy: Never` (使用本地镜像)
- 移除初始化容器 (无需数据库迁移在dev)
- 资源限制: 100m/128Mi requests (vs 500m/512Mi)
- `recreate` 策略 (vs rolling update)

**何时使用**: 本地开发部署

### 2. 快速启动脚本

#### `quick-start-local.sh` (可执行, 400+行)
**用途**: 一键部署本地K8s环境
**功能**:
- 检查前提条件 (kubectl, docker, K8s集群)
- 创建命名空间
- 部署RBAC配置
- 部署ConfigMap/Secret
- 构建Docker镜像
- 加载镜像到kind (如果使用)
- 部署应用
- 等待就绪
- 显示访问信息

**使用方式**:

```bash
# 交互式菜单
./quick-start-local.sh

# 完整自动部署
./quick-start-local.sh deploy

# 仅检查前提条件
./quick-start-local.sh check

# 清理环境
./quick-start-local.sh cleanup
```

**执行时间**: 约5-10分钟 (含镜像构建)

#### `verify-local.sh` (可执行, 250+行)
**用途**: 快速验证部署状态
**检查项**:
1. K8s集群运行状态
2. 命名空间存在
3. RBAC配置 (ServiceAccount, Role, RoleBinding)
4. ConfigMap和Secret存在
5. Deployment存在
6. Pod运行状态 (个数、状态)
7. 服务创建 (名称、类型、端口)
8. 部署就绪状态
9. 健康检查 (HTTP /health)
10. 最近日志
11. 资源使用
12. 最近事件

**使用方式**:

```bash
# 完整验证报告
./verify-local.sh

# 可重复运行监控状态变化
./verify-local.sh
```

**执行时间**: 5-10秒

### 3. 文档文件

#### `LOCAL_VERIFICATION.md` (400+行)
**内容**:
- 三种本地K8s环境设置:
  - Docker Desktop (macOS/Windows)
  - Minikube (跨平台)
  - kind (Docker in Docker)
- 详细的部署步骤
- 配置说明
- 验证方法
- 端口转发指南
- 故障排查
- 清理环节

**何时查看**: 需要详细理解本地验证过程

#### `LOCAL_FILES_SUMMARY.md` (本文件)
**内容**: 快速参考本地验证文件
**何时查看**: 需要快速了解有哪些文件和用法

---

## 🚀 快速开始 (3步)

### 步骤1: 验证前提条件
```bash
./quick-start-local.sh check
```

### 步骤2: 一键部署
```bash
./quick-start-local.sh deploy
```
**预期**: 5-10分钟后部署完成

### 步骤3: 验证部署
```bash
./verify-local.sh
```
**预期**: 看到 "✅ 部署成功!" 信息

---

## 📊 文件使用流程图

```
开始
  ↓
检查前提条件?
  ↓
./quick-start-local.sh check
  ↓ 通过 → 继续
  ↓ 失败 → 按提示安装依赖
  ↓
部署本地环境?
  ↓
./quick-start-local.sh deploy
  ↓
自动:
  • 创建命名空间
  • 部署RBAC
  • 部署本地ConfigMap/Secret
  • 构建镜像
  • 部署应用
  • 等待就绪
  ↓
验证部署?
  ↓
./verify-local.sh
  ↓
检查项:
  • 命名空间 ✓
  • Pod运行 ✓
  • 健康检查 ✓
  ↓ 全部通过
  ↓
可以测试API了!
  ↓
kubectl port-forward svc/messaging-service 3000:3000
curl http://localhost:3000/health
```

---

## 🔧 常见操作

### 监控Pod启动
```bash
kubectl get pods -n nova-messaging -w
```

### 查看实时日志
```bash
kubectl logs -f -l component=messaging-service -n nova-messaging
```

### 进行端口转发
```bash
# HTTP API (3000) + Metrics (9090)
kubectl port-forward svc/messaging-service 3000:3000 9090:9090 -n nova-messaging

# 或分开转发
kubectl port-forward svc/messaging-service 3000:3000 -n nova-messaging
kubectl port-forward svc/messaging-service 9090:9090 -n nova-messaging
```

### 测试API
```bash
# 健康检查
curl http://localhost:3000/health

# 美化输出
curl http://localhost:3000/health | jq

# Prometheus指标
curl http://localhost:9090/metrics
```

### 进入Pod进行调试
```bash
# 获取Pod名称
POD_NAME=$(kubectl get pod -l component=messaging-service -n nova-messaging -o jsonpath='{.items[0].metadata.name}')

# 进入Pod
kubectl exec -it $POD_NAME -n nova-messaging -- bash

# 在Pod内测试数据库
psql -h host.docker.internal -U postgres -d nova_messaging -c "SELECT 1;"
```

### 重启部署 (更新镜像后)
```bash
# 方法1: 重新构建并重启
docker build -t nova/messaging-service:latest -f backend/Dockerfile.messaging .
kind load docker-image nova/messaging-service:latest --name nova-dev  # 如果使用kind
kubectl rollout restart deployment/messaging-service -n nova-messaging

# 方法2: 设置新镜像版本
kubectl set image deployment/messaging-service \
  messaging-service=nova/messaging-service:v1.1.0 \
  -n nova-messaging
```

### 清理环境
```bash
# 删除所有本地部署
./quick-start-local.sh cleanup

# 或手动删除
kubectl delete namespace nova-messaging

# 停止本地K8s (可选)
# Docker Desktop: 取消选中 Kubernetes
# Minikube: minikube stop
# kind: kind delete cluster --name nova-dev
```

---

## 📁 文件清单总结

| 文件 | 类型 | 行数 | 用途 |
|------|------|------|------|
| `messaging-service-configmap-local.yaml` | 配置 | 57 | 本地开发配置 |
| `messaging-service-secret-local.yaml` | 密钥 | 45 | 本地开发凭证 |
| `messaging-service-deployment-local.yaml` | 部署 | 234 | 本地开发部署 |
| `quick-start-local.sh` | 脚本 | 400+ | 一键部署脚本 |
| `verify-local.sh` | 脚本 | 250+ | 状态验证脚本 |
| `LOCAL_VERIFICATION.md` | 文档 | 400+ | 详细验证指南 |
| `LOCAL_FILES_SUMMARY.md` | 文档 | - | 本文件 |

---

## 🌍 支持的本地环境

### ✅ Docker Desktop (推荐)
- **平台**: macOS, Windows
- **优点**: 内置K8s, 无需额外工具
- **设置**: 2步 (启用Kubernetes, 增加资源)
- **命令**: `./quick-start-local.sh deploy`

### ✅ Minikube
- **平台**: macOS, Linux, Windows
- **优点**: 轻量级, 跨平台
- **设置**: 3步 (安装, 启动, 配置)
- **命令**: `minikube start --driver=docker --memory=8192` → `./quick-start-local.sh deploy`

### ✅ kind
- **平台**: macOS, Linux, Windows
- **优点**: 最隔离, Docker in Docker
- **设置**: 3步 (安装, 创建集群, 加载镜像)
- **命令**: `kind create cluster` → `./quick-start-local.sh deploy`

---

## 📝 验证清单

部署后的验证项:

- [ ] `./verify-local.sh` 显示所有 ✅
- [ ] Pod状态: Running
- [ ] 健康检查: 返回 `{"status":"ok"}`
- [ ] 端口转发: 命令成功
- [ ] API测试: curl 返回200
- [ ] 日志: 无错误信息
- [ ] 资源使用: CPU和内存合理

---

## 🚨 故障排查快速参考

| 问题 | 命令 |
|------|------|
| Pod无法启动 | `kubectl describe pod <name> -n nova-messaging` |
| 镜像找不到 | `docker build -t nova/messaging-service:latest ...` |
| 数据库连接失败 | `kubectl exec -it <pod> -- psql -h host.docker.internal ...` |
| 端口无法访问 | `kubectl port-forward svc/messaging-service 3000:3000` |
| 卡在"Pending" | `kubectl get events -n nova-messaging` |
| 需要清理 | `./quick-start-local.sh cleanup` |

---

## 💡 最佳实践

1. **始终运行检查**: 部署前先运行 `./quick-start-local.sh check`
2. **逐步部署**: 不要跳过RBAC和配置步骤
3. **监控日志**: 部署时保持一个终端显示日志
4. **保存验证**: 定期运行 `./verify-local.sh` 保存输出
5. **清理旧部署**: 测试新配置前删除旧部署
6. **使用NodePort**: kind环境用NodePort (30000/30090)，Docker Desktop用端口转发

---

## 📞 下一步

✅ 本地验证完成
→ 修改代码并重建镜像
→ 部署到生产K8s集群 (参考 `DEPLOYMENT_GUIDE.md`)

