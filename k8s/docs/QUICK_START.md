# Nova Kubernetes Quick Start Guide

快速开始部署 Nova 微服务到 Kubernetes。

## 5 分钟快速开始

### 前提条件
- `kubectl` 已安装且配置好
- `kustomize` 已安装 (或使用 `kubectl apply -k`)
- Kubernetes 1.24+ 集群可用
- Nginx Ingress Controller 已安装

### 第 1 步：配置 Secrets (2 分钟)

```bash
cd k8s/base

# 编辑 secrets.yaml，替换以下占位符：
vi secrets.yaml

# 必需替换的内容：
# ${AWS_ACCESS_KEY_ID}        -> 你的 AWS 访问密钥
# ${AWS_SECRET_ACCESS_KEY}    -> 你的 AWS 密钥
# ${DB_PASSWORD}              -> PostgreSQL 密码
# ${JWT_PUBLIC_KEY}           -> JWT 公钥 (base64)
# ${JWT_PRIVATE_KEY}          -> JWT 私钥 (base64)
```

### 第 2 步：部署到开发环境 (1 分钟)

```bash
# 确认你在 nova 项目根目录
cd /Users/proerror/Documents/nova

# 应用开发环境配置
kubectl apply -k k8s/overlays/dev

# 检查部署状态
kubectl -n nova get pods
```

### 第 3 步：验证部署 (2 分钟)

```bash
# 等待所有 Pod 进入 Running 状态
kubectl -n nova get pods -w

# 验证 Services
kubectl -n nova get svc

# 测试 API 可用性
kubectl -n nova port-forward svc/content-service 8081:8081
# 在另一个终端
curl http://localhost:8081/api/v1/health
```

## 环境选择

### 开发环境部署
```bash
kubectl apply -k k8s/overlays/dev

# 特点：
# - 1 个副本
# - 较低资源限制
# - Debug 日志级别
# - 最小化资源使用
```

### 生产环境部署
```bash
kubectl apply -k k8s/overlays/prod

# 特点：
# - 3 个副本（高可用）
# - 更高资源限制
# - Info 日志级别
# - Pod 自动扩展
```

## 常用命令

```bash
# 查看所有资源
kubectl -n nova get all

# 查看特定 Service 的日志
kubectl -n nova logs -f deployment/content-service

# 进入 Pod 调试
kubectl -n nova exec -it <pod-name> -- /bin/bash

# 查看 Pod 详细信息
kubectl -n nova describe pod <pod-name>

# 扩展副本数
kubectl -n nova scale deployment/content-service --replicas=5

# 查看资源使用
kubectl -n nova top pods

# 查看 Ingress 状态
kubectl -n nova describe ingress nova-api-gateway
```

## 故障排查

### Pod 无法启动？

```bash
# 1. 检查 Pod 状态
kubectl -n nova describe pod <pod-name>

# 2. 查看错误日志
kubectl -n nova logs <pod-name>

# 3. 常见原因：
# - 镜像不存在：检查 Docker registry 和版本号
# - 环境变量缺失：检查 Secrets 和 ConfigMap
# - 数据库连接失败：检查 DATABASE_URL 和网络连通性
```

### Service 无法访问？

```bash
# 1. 检查 Service 是否存在
kubectl -n nova get svc <service-name>

# 2. 检查 Endpoints
kubectl -n nova get endpoints <service-name>

# 3. 测试连通性
kubectl -n nova run -it --rm debug --image=busybox --restart=Never -- \
  wget -O- http://content-service:8081/api/v1/health
```

## 目录结构说明

```
k8s/
├── base/                      # 所有环境的基础配置
│   ├── *.yaml                 # Deployment, Service, ConfigMap 等
│   └── kustomization.yaml     # 基础配置管理
├── overlays/
│   ├── dev/                   # 开发环境特定配置
│   └── prod/                  # 生产环境特定配置
├── README.md                  # 详细部署指南
├── DEPLOYMENT_CHECKLIST.md    # 部署前/后检查清单
└── QUICK_START.md            # 本文件
```

## API 端点

部署完成后，所有 API 可通过 Ingress 访问：

```
POST /api/v1/posts                    # 创建贴文
GET  /api/v1/posts/{id}               # 获取贴文
GET  /api/v1/posts/user/{user_id}     # 获取用户贴文

POST /api/v1/uploads                  # 创建上传会话
POST /api/v1/uploads/{id}/presigned   # 获取 S3 预签名 URL

POST /api/v1/videos                   # 创建视频
GET  /api/v1/videos/{id}              # 获取视频

POST /api/v1/messages                 # 发送消息
WS   /ws                              # WebSocket 连接

GET  /api/v1/health                   # 健康检查
```

## 监控

### 查看日志
```bash
# 查看特定服务的日志
kubectl -n nova logs -f deployment/content-service

# 查看最近 50 行日志
kubectl -n nova logs --tail=50 <pod-name>

# 查看上一个已终止的 Pod 的日志
kubectl -n nova logs <pod-name> --previous
```

### 查看性能指标
```bash
# Pod CPU 和内存使用
kubectl -n nova top pods

# 节点使用情况
kubectl top nodes

# 实时监控
kubectl -n nova top pods --watch
```

## 持久化存储

如果使用持久化数据库（不是 Docker Compose 中的临时数据库），确保：

1. 数据库连接字符串正确配置在 Secrets 中
2. 数据库用户权限足够
3. 数据库防火墙允许 Kubernetes 集群访问

```bash
# 测试数据库连接
kubectl -n nova run -it --rm psql --image=postgres:15 --restart=Never -- \
  psql -h <db-host> -U nova -d nova_content
```

## 关闭部署

```bash
# 删除所有资源（保留 namespace）
kubectl delete -k k8s/overlays/dev

# 删除整个 namespace（包括所有资源）
kubectl delete namespace nova
```

## 下一步

- 阅读 [详细部署指南](README.md)
- 检查 [部署前检查清单](DEPLOYMENT_CHECKLIST.md)
- 配置监控和日志聚合
- 设置备份和灾难恢复策略

## 获取帮助

遇到问题？

1. 查看 Pod 日志：`kubectl -n nova logs <pod-name>`
2. 查看事件：`kubectl -n nova get events`
3. 描述资源：`kubectl -n nova describe pod <pod-name>`
4. 检查网络连通性：`kubectl -n nova exec -it <pod-name> -- ping <service>`

---

**祝您部署愉快！** 🚀
