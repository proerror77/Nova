# Kubernetes Configuration for Nova Messaging Service

## 概述 (Overview)

本目录包含Nova消息服务的完整Kubernetes部署配置。该服务处理实时消息、WebSocket连接和视频通话信令。

**This directory contains complete Kubernetes deployment configuration for the Nova Messaging Service, which handles real-time messaging, WebSocket connections, and video call signaling.**

## 文件列表 (Files)

### 核心配置文件 (Core Configuration Files)

#### 1. `messaging-service-namespace.yaml`
- **用途**: Kubernetes命名空间定义
- **内容**: 创建 `nova-messaging` 命名空间用于隔离服务
- **大小**: 13 行

#### 2. `messaging-service-configmap.yaml`
- **用途**: 非敏感配置管理
- **内容**: 20+ 配置参数，包括应用设置、数据库连接限制、Redis设置、Kafka设置、WebSocket配置、视频通话设置、消息设置、性能设置
- **大小**: 57 行
- **关键变量**:
  - `APP_ENV`: 应用环境 (production)
  - `DATABASE_MAX_CONNECTIONS`: 数据库连接池大小 (10)
  - `REDIS_POOL_SIZE`: Redis连接池 (20)
  - `VIDEO_CALL_MAX_DURATION_HOURS`: 最长通话时长 (12小时)
  - `MESSAGE_MAX_LENGTH`: 最大消息长度 (4096字符)
  - `WS_MAX_FRAME_SIZE`: WebSocket帧大小 (1MB)

#### 3. `messaging-service-secret.yaml`
- **用途**: 敏感数据管理（凭证、密钥、令牌）
- **内容**: 数据库凭证、Redis密码、JWT公钥、服务器端加密密钥、Kafka连接
- **大小**: 45 行
- **关键密钥**:
  - `POSTGRES_PASSWORD`: 数据库密码
  - `POSTGRES_DB`: 数据库名称 (nova_messaging)
  - `DATABASE_URL`: PostgreSQL连接字符串
  - `REDIS_URL`: Redis连接字符串
  - `JWT_PUBLIC_KEY_PEM`: JWT令牌验证公钥
  - `SECRETBOX_KEY_B64`: 32字节消息加密密钥
  - `KAFKA_BROKERS`: Kafka代理地址

#### 4. `messaging-service-serviceaccount.yaml`
- **用途**: RBAC (基于角色的访问控制) 配置
- **内容**: ServiceAccount + Role + RoleBinding
- **权限**:
  - ConfigMap 读取权限
  - Secret 读取权限
  - Pod 查询权限
  - 事件创建权限
- **大小**: 60 行

#### 5. `messaging-service-deployment.yaml`
- **用途**: Kubernetes部署规范
- **内容**: 完整的部署配置，包含280+ 行高度详细的配置
- **关键特性**:
  - 3个副本用于高可用
  - 滚动更新策略 (maxSurge: 1, maxUnavailable: 1)
  - 初始化容器用于数据库迁移
  - 资源请求和限制
  - 三层健康检查 (启动、就绪、活性)
  - Pod反亲和性确保跨节点分布
  - 安全上下文 (非root用户、只读文件系统、能力删除)
  - Prometheus指标暴露 (端口 9090)
- **大小**: 280 行

#### 6. `messaging-service-service.yaml`
- **用途**: 服务暴露
- **内容**: 两个服务定义
  - **ClusterIP服务**: 内部集群访问
    - 端口 3000: HTTP/WebSocket
    - 端口 9090: Prometheus指标
    - 会话亲和性: ClientIP (3小时超时)
  - **LoadBalancer服务**: 外部访问
    - 为WebSocket客户端提供外部IP
    - 同样的会话亲和性配置
- **大小**: 46 行

#### 7. `messaging-service-hpa.yaml`
- **用途**: 水平Pod自动伸缩器
- **内容**: 基于CPU和内存利用率的自动伸缩配置
- **伸缩规则**:
  - 最少副本: 3
  - 最多副本: 10
  - CPU阈值: 70% 利用率
  - 内存阈值: 80% 利用率
  - 缩减稳定化窗口: 300秒
  - 扩展速度: 可在15秒内翻倍
- **大小**: 50 行

#### 8. `messaging-service-pdb.yaml`
- **用途**: Pod中断预算
- **内容**: 保证最少可用副本数
- **配置**:
  - 最少可用副本: 2
  - 允许自动驱逐不健康的Pod
- **大小**: 17 行

### 文档文件 (Documentation Files)

#### `DEPLOYMENT_GUIDE.md`
- **用途**: 完整的部署指南
- **内容**:
  - 前提条件检查清单
  - 架构图表
  - 分步部署说明
  - 验证和监控步骤
  - 数据库迁移指导
  - 网络配置说明
  - 手动和自动伸缩指南
  - 更新和回滚步骤
  - 故障排查指南
  - 安全考虑事项
  - 灾难恢复程序
  - 性能调优建议
  - 生产检查清单

#### `README.md` (本文件)
- **用途**: 快速参考指南
- **内容**: 文件清单、快速开始、架构、安全性

## 快速开始 (Quick Start)

### 1. 准备集群
```bash
# 创建命名空间
kubectl create namespace nova-messaging

# 设置默认命名空间
kubectl config set-context --current --namespace=nova-messaging
```

### 2. 更新敏感数据
```bash
# 编辑Secret文件，更新所有生产凭证
vim messaging-service-secret.yaml

# 需要更新的字段:
# - POSTGRES_PASSWORD
# - REDIS_PASSWORD
# - SECRETBOX_KEY_B64 (使用 openssl rand -base64 32 生成)
# - JWT_PUBLIC_KEY_PEM
# - KAFKA_BROKERS
```

### 3. 部署
```bash
# 按顺序应用清单 (顺序很重要)
kubectl apply -f messaging-service-namespace.yaml
kubectl apply -f messaging-service-serviceaccount.yaml
kubectl apply -f messaging-service-configmap.yaml
kubectl apply -f messaging-service-secret.yaml
kubectl apply -f messaging-service-deployment.yaml
kubectl apply -f messaging-service-service.yaml
kubectl apply -f messaging-service-hpa.yaml
kubectl apply -f messaging-service-pdb.yaml
```

或一次性应用所有文件:
```bash
kubectl apply -f .
```

### 4. 验证部署
```bash
# 检查部署状态
kubectl get deployment messaging-service -n nova-messaging

# 检查Pod
kubectl get pods -n nova-messaging

# 查看日志
kubectl logs -l component=messaging-service -n nova-messaging -f
```

## 架构 (Architecture)

```
┌─────────────────────────────────────┐
│    nova-messaging Namespace         │
├─────────────────────────────────────┤
│ Deployment (3 replicas)             │
│ ├─ Init Container (DB Migrations)   │
│ └─ messaging-service Container      │
│    ├─ Port 3000: HTTP/WebSocket    │
│    └─ Port 9090: Prometheus        │
├─────────────────────────────────────┤
│ Service (ClusterIP)                 │
│ └─ Internal cluster access          │
├─────────────────────────────────────┤
│ Service (LoadBalancer)              │
│ └─ External client access           │
├─────────────────────────────────────┤
│ HPA (3-10 replicas)                 │
│ ├─ CPU threshold: 70%               │
│ └─ Memory threshold: 80%            │
├─────────────────────────────────────┤
│ PDB (Disruption Budget)             │
│ └─ Min available: 2                 │
└─────────────────────────────────────┘
         ↓      ↓      ↓
    PostgreSQL Redis Kafka
```

## 资源要求 (Resource Requirements)

### Requests (保证获得)
```yaml
cpu: 500m        # 0.5个CPU核心
memory: 512Mi    # 512MB内存
```

### Limits (最大限制)
```yaml
cpu: 2000m       # 2个CPU核心
memory: 2Gi      # 2GB内存
```

### 集群最低要求
- 3个工作节点 (用于Pod反亲和性)
- 每个节点 4GB 内存
- 每个节点 2个 CPU核心

## 安全性 (Security)

### Pod安全
- ✅ 以非root用户运行 (UID: 1001)
- ✅ 只读根文件系统
- ✅ 所有Linux能力已删除
- ✅ 禁止特权升级

### 网络安全
- ✅ 服务账户与最小RBAC权限
- ✅ ConfigMap用于非敏感配置
- ✅ Secret (不透明) 用于敏感数据
- ✅ 会话亲和性防止会话劫持

### 数据保护
- ✅ 数据库密码在Secret中
- ✅ Redis密码在Secret中
- ✅ JWT公钥在Secret中
- ✅ 加密密钥 (SECRETBOX_KEY_B64) 在Secret中

## 监控 (Monitoring)

### Prometheus指标
服务在端口9090暴露Prometheus指标:

```bash
# 端口转发
kubectl port-forward svc/messaging-service 9090:9090 -n nova-messaging

# 访问指标: http://localhost:9090/metrics
```

### 关键指标
- `http_requests_total`: HTTP请求总数
- `http_request_duration_seconds`: 请求延迟
- `websocket_connections_active`: 活跃WebSocket连接数
- `database_query_duration_seconds`: 数据库查询延迟
- `message_queue_length`: 待处理消息数

## 故障排查 (Troubleshooting)

### Pod未启动
```bash
# 检查Pod状态和事件
kubectl describe pod <pod-name> -n nova-messaging

# 查看所有容器日志
kubectl logs <pod-name> -n nova-messaging --all-containers=true
```

### 数据库连接失败
```bash
# 验证Secret内容
kubectl get secret messaging-service-secret -n nova-messaging -o yaml

# 从Pod内测试数据库连接
kubectl exec -it <pod-name> -n nova-messaging -- \
  psql -h postgres.nova-db -U postgres -d nova_messaging
```

### WebSocket连接问题
```bash
# 查看WebSocket错误日志
kubectl logs <pod-name> -n nova-messaging | grep -i websocket

# 获取LoadBalancer外部IP
kubectl get svc messaging-service-external -n nova-messaging

# 测试健康检查
curl -i http://<EXTERNAL-IP>:3000/health
```

## 升级和回滚 (Updates and Rollback)

### 更新镜像
```bash
# 设置新镜像
kubectl set image deployment/messaging-service \
  messaging-service=nova/messaging-service:v1.1.0 \
  -n nova-messaging

# 监控部署进度
kubectl rollout status deployment/messaging-service -n nova-messaging

# 需要回滚时
kubectl rollout undo deployment/messaging-service -n nova-messaging
```

### 更新配置
```bash
# 编辑ConfigMap
kubectl edit configmap messaging-service-config -n nova-messaging

# 更新Secret
kubectl patch secret messaging-service-secret -n nova-messaging \
  -p='{"stringData":{"POSTGRES_PASSWORD":"new-password"}}'

# 重启Pod应用更改
kubectl rollout restart deployment/messaging-service -n nova-messaging
```

## 生产检查清单 (Production Checklist)

在部署到生产之前:

- [ ] 更新Secret中的数据库凭证
- [ ] 设置Redis密码
- [ ] 配置JWT公钥
- [ ] 生成SECRETBOX_KEY_B64 (32字节)
- [ ] 正确配置Kafka代理
- [ ] 配置LoadBalancer IP/域名
- [ ] 配置数据库备份
- [ ] 设置监控和告警
- [ ] 配置日志聚合
- [ ] 测试备份和恢复程序
- [ ] 定义集群备份策略
- [ ] 配置网络策略 (如需要)

## 扩展 (Scaling)

### 手动伸缩
```bash
# 扩展到特定副本数
kubectl scale deployment messaging-service --replicas=5 -n nova-messaging
```

### 自动伸缩
```bash
# 监控HPA状态
kubectl describe hpa messaging-service-hpa -n nova-messaging

# 实时观察HPA决策
kubectl get hpa messaging-service-hpa -n nova-messaging -w
```

## 相关文件 (Related Files)

- `DEPLOYMENT_GUIDE.md` - 完整部署指南和故障排查
- `messaging-service-namespace.yaml` - 命名空间定义
- `messaging-service-configmap.yaml` - 配置管理
- `messaging-service-secret.yaml` - 敏感数据 (需要编辑)
- `messaging-service-serviceaccount.yaml` - RBAC配置
- `messaging-service-deployment.yaml` - 部署规范
- `messaging-service-service.yaml` - 服务定义
- `messaging-service-hpa.yaml` - 自动伸缩配置
- `messaging-service-pdb.yaml` - Pod中断预算

## 下一步 (Next Steps)

1. **部署TURN服务器** (可选但推荐用于视频通话)
   - 部署coturn或类似的TURN服务器
   - 在消息服务中配置TURN凭证
   - 在iOS客户端更新WebRTC配置

2. **配置Ingress**
   - 为API访问配置Ingress
   - 设置TLS/SSL证书
   - 配置域名

3. **监控设置**
   - 安装Prometheus
   - 配置Grafana仪表板
   - 设置告警规则

4. **CI/CD集成**
   - 配置GitOps (ArgoCD, Flux)
   - 设置自动部署
   - 配置镜像仓库

## 参考 (References)

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [kubectl Cheatsheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [Deployment Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)
- [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) - 详细的部署指南
