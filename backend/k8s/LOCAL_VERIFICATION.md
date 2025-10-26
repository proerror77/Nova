# 本地Docker环境验证指南

## 概述

本指南提供在本地开发环境验证Kubernetes配置的完整步骤。支持三种本地K8s环境：
1. **Docker Desktop** (macOS/Windows) - 最简单
2. **Minikube** (跨平台) - 最轻量
3. **kind** (Kubernetes in Docker) - 最隔离

## 环境检查

### 检查已安装工具

```bash
# 检查Docker
docker --version
# Docker version 20.10+ 推荐

# 检查kubectl
kubectl version --client
# 客户端版本 v1.24+ 推荐

# 检查可用的本地K8s
docker ps  # Docker Desktop需要Docker Engine运行
which minikube  # 如果安装了Minikube
which kind  # 如果安装了kind
```

## 方案1: Docker Desktop (推荐 - macOS/Windows)

### 1.1 启用Kubernetes

**macOS/Windows Docker Desktop:**
1. 打开 Docker Desktop
2. 点击 Settings → Kubernetes
3. 勾选 "Enable Kubernetes"
4. 点击 "Apply & Restart"

等待3-5分钟让Kubernetes启动...

### 1.2 验证集群

```bash
# 检查Kubernetes状态
kubectl cluster-info

# 预期输出:
# Kubernetes control plane is running at https://127.0.0.1:6443
# CoreDNS is running at https://127.0.0.1:6443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

# 检查节点
kubectl get nodes
# NAME             STATUS   ROLES           AGE   VERSION
# docker-desktop   Ready    control-plane   ...   v1.27.x

# 检查可用资源
kubectl describe node docker-desktop
```

### 1.3 资源限制 (重要!)

Docker Desktop默认限制资源，需要增加：

**macOS:**
1. Docker Desktop → Settings → Resources
2. 设置:
   - CPUs: 4 (最少)
   - Memory: 8GB (最少，推荐16GB)
   - Swap: 1GB

**Windows:**
1. Docker Desktop → Settings → Resources
2. WSL 2 engine settings:
   - Memory: 8GB (最少)
   - CPUs: 4 (最少)

## 方案2: Minikube (跨平台)

### 2.1 安装Minikube

```bash
# macOS (Homebrew)
brew install minikube

# Linux
curl -LO https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Windows (Chocolatey)
choco install minikube
```

### 2.2 启动Minikube集群

```bash
# 使用Docker驱动启动（推荐，不需要hypervisor）
minikube start --driver=docker --cpus=4 --memory=8192 --disk-size=50gb

# 验证启动
minikube status
# minikube
# type: Control Plane
# host: Running
# kubelet: Running
# apiserver: Running
# kubeconfig: Configured
```

### 2.3 设置kubectl上下文

```bash
# Minikube自动设置上下文
kubectl config current-context
# minikube

# 如果需要手动切换
kubectl config use-context minikube
```

## 方案3: kind (Kubernetes in Docker)

### 3.1 安装kind

```bash
# macOS (Homebrew)
brew install kind

# Linux
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# Windows (Chocolatey)
choco install kind
```

### 3.2 创建kind集群

创建 `kind-cluster.yaml`:
```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: nova-dev
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 3000
        hostPort: 3000
        protocol: TCP
      - containerPort: 9090
        hostPort: 9090
        protocol: TCP
  - role: worker
  - role: worker
```

启动集群:
```bash
kind create cluster --config kind-cluster.yaml

# 验证
kubectl cluster-info --context kind-nova-dev
kubectl get nodes --context kind-nova-dev
```

---

## 本地开发配置

### 准备本地Secret

创建 `messaging-service-secret-local.yaml` (用于本地开发):

```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: messaging-service-secret
  namespace: nova-messaging
type: Opaque
stringData:
  # 本地开发凭证 (不用于生产!)
  POSTGRES_USER: "postgres"
  POSTGRES_PASSWORD: "postgres"  # 本地简化
  POSTGRES_DB: "nova_messaging"

  # 本地数据库 - 使用Docker Compose或本地Postgres
  DATABASE_URL: "postgresql://postgres:postgres@host.docker.internal:5432/nova_messaging"

  # 本地Redis
  REDIS_PASSWORD: "redis"
  REDIS_URL: "redis://:redis@host.docker.internal:6379/0"

  # 本地开发JWT公钥 (使用测试密钥)
  JWT_PUBLIC_KEY_PEM: |
    -----BEGIN PUBLIC KEY-----
    MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAr1g5jAGoSEJN7qUp4Ogo
    BtfDtdZwY+151jPj3vu8Q7skdB7VX7gTJv2CQkrYtggmD+dUl6ws2A5isXmrr52D
    VKV07as2S7vXkzwP7MvuwWdpNLZIIB0GXD1Iacywu2XlxXBo4Ig24qxDIfSlkW7b
    v0hM9yX+NnW3McXrcAYxlIsdiCz9gDKosVUdQpl/i87Y83cupgg23fqnXGbIb8TI
    j2mnT/GL+cNiZyD+nPdZ7WTRERFZrLVoBC0FdoIwsDdOSwmuN5NjIDTOS7K0rWUt
    jCTIgMJrZEgIQUo2kD7d5KZbp0O6+C6BcpTMt59aoGBc9AH9h+aOwwOFQdtflMc/
    +QIDAQAB
    -----END PUBLIC KEY-----

  # 本地开发加密密钥
  SECRETBOX_KEY_B64: "PH3+9vCdxhXYcOuCy8nXB1L8PnG3lqZ5r9kW2pX8vQA="

  # 本地Kafka
  KAFKA_BROKERS: "kafka:9092"  # Docker Compose中的服务名
  KAFKA_SASL_USERNAME: ""
  KAFKA_SASL_PASSWORD: ""
```

### 准备本地ConfigMap

创建 `messaging-service-configmap-local.yaml`:

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: messaging-service-config
  namespace: nova-messaging
data:
  # 本地开发设置
  APP_ENV: "development"
  PORT: "3000"
  RUST_LOG: "debug,messaging_service=debug,axum=debug"  # 更详细日志
  HOST: "0.0.0.0"

  # 本地数据库设置
  DATABASE_MAX_CONNECTIONS: "5"   # 本地减少连接
  DATABASE_POOL_TIMEOUT: "30"
  DATABASE_IDLE_TIMEOUT: "600"

  # 本地Redis设置
  REDIS_POOL_SIZE: "5"   # 本地减少连接
  REDIS_CONNECT_TIMEOUT: "5"
  REDIS_POOL_TIMEOUT: "10"

  # Kafka设置
  KAFKA_COMPRESSION_TYPE: "snappy"
  KAFKA_REQUEST_TIMEOUT_MS: "30000"
  KAFKA_CONSUMER_GROUP: "messaging-service-local"

  # WebSocket本地设置
  WS_DEV_ALLOW_ALL: "true"   # 本地开发允许所有WebSocket
  WS_MAX_FRAME_SIZE: "1048576"
  WS_MESSAGE_BUFFER_SIZE: "256"

  # 视频通话设置
  VIDEO_CALL_MAX_DURATION_HOURS: "12"
  VIDEO_CALL_IDLE_TIMEOUT_MINUTES: "5"
  VIDEO_CALL_ICE_GATHERING_TIMEOUT: "10"

  # 消息设置
  MESSAGE_RECALL_WINDOW_HOURS: "2"
  MESSAGE_MAX_LENGTH: "4096"
  AUDIO_MESSAGE_MAX_DURATION_SECS: "600"

  # 本地性能设置
  MESSAGE_BATCH_SIZE: "10"     # 本地减少批次
  ICE_CANDIDATE_BATCH_SIZE: "5"
  BROADCAST_TIMEOUT_SECS: "30"

  # 健康检查设置
  HEALTH_CHECK_INTERVAL_SECS: "10"
  HEALTH_CHECK_TIMEOUT_SECS: "5"
```

---

## 本地验证步骤

### 步骤1: 启动本地依赖

**选项A: 使用Docker Compose启动依赖**

在项目根目录运行:
```bash
# 只启动必要的服务
docker-compose up -d postgres redis kafka zookeeper

# 验证启动
docker-compose ps
```

**选项B: 使用本地已安装的服务**

确保运行:
```bash
# 启动PostgreSQL
# macOS: brew services start postgresql
# 或使用本地PostgreSQL

# 启动Redis
# macOS: brew services start redis
# 或使用本地Redis

# Kafka可选 - 本地开发可以跳过
```

### 步骤2: 创建本地命名空间

```bash
kubectl create namespace nova-messaging
kubectl config set-context --current --namespace=nova-messaging
```

### 步骤3: 应用本地配置

```bash
# 应用ServiceAccount和RBAC
kubectl apply -f messaging-service-serviceaccount.yaml

# 应用本地ConfigMap
kubectl apply -f messaging-service-configmap-local.yaml

# 应用本地Secret
kubectl apply -f messaging-service-secret-local.yaml

# 验证
kubectl get configmap messaging-service-config -o yaml
kubectl get secret messaging-service-secret -o yaml
```

### 步骤4: 修改Deployment用于本地开发

创建 `messaging-service-deployment-local.yaml`:

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: messaging-service
  namespace: nova-messaging
spec:
  replicas: 1  # 本地只用1个副本
  strategy:
    type: RollingUpdate
  selector:
    matchLabels:
      app: nova
      component: messaging-service
  template:
    metadata:
      labels:
        app: nova
        component: messaging-service
    spec:
      serviceAccountName: messaging-service

      containers:
        - name: messaging-service
          image: nova/messaging-service:latest
          imagePullPolicy: Never  # 本地镜像，不拉取

          ports:
            - name: http
              containerPort: 3000
            - name: metrics
              containerPort: 9090

          env:
            - name: APP_ENV
              valueFrom:
                configMapKeyRef:
                  name: messaging-service-config
                  key: APP_ENV
            - name: PORT
              valueFrom:
                configMapKeyRef:
                  name: messaging-service-config
                  key: PORT
            - name: RUST_LOG
              valueFrom:
                configMapKeyRef:
                  name: messaging-service-config
                  key: RUST_LOG
            - name: HOST
              valueFrom:
                configMapKeyRef:
                  name: messaging-service-config
                  key: HOST

            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: messaging-service-secret
                  key: DATABASE_URL
            - name: DATABASE_MAX_CONNECTIONS
              valueFrom:
                configMapKeyRef:
                  name: messaging-service-config
                  key: DATABASE_MAX_CONNECTIONS

            - name: REDIS_URL
              valueFrom:
                secretKeyRef:
                  name: messaging-service-secret
                  key: REDIS_URL
            - name: REDIS_POOL_SIZE
              valueFrom:
                configMapKeyRef:
                  name: messaging-service-config
                  key: REDIS_POOL_SIZE

            - name: JWT_PUBLIC_KEY_PEM
              valueFrom:
                secretKeyRef:
                  name: messaging-service-secret
                  key: JWT_PUBLIC_KEY_PEM

            - name: SECRETBOX_KEY_B64
              valueFrom:
                secretKeyRef:
                  name: messaging-service-secret
                  key: SECRETBOX_KEY_B64

          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi

          livenessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 30
            periodSeconds: 10
            failureThreshold: 3

          readinessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 10
            periodSeconds: 5
            failureThreshold: 2
```

### 步骤5: 构建并加载本地镜像

**如果使用Docker Desktop或kind:**

```bash
# 构建镜像
cd backend/messaging-service
docker build -t nova/messaging-service:latest -f Dockerfile .

# 对于kind，需要加载到集群
kind load docker-image nova/messaging-service:latest --name nova-dev

# 对于Docker Desktop，镜像自动可用
```

### 步骤6: 部署到本地K8s

```bash
# 使用本地部署配置
kubectl apply -f messaging-service-deployment-local.yaml

# 创建服务
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: messaging-service
  namespace: nova-messaging
spec:
  type: NodePort
  ports:
    - name: http
      port: 3000
      targetPort: 3000
      nodePort: 30000
    - name: metrics
      port: 9090
      targetPort: 9090
      nodePort: 30090
  selector:
    app: nova
    component: messaging-service
EOF

# 检查服务
kubectl get svc messaging-service -n nova-messaging
```

---

## 验证部署

### 1. 检查Pod状态

```bash
# 监控Pod启动
kubectl get pods -n nova-messaging -w

# 查看Pod详细信息
kubectl describe pod -l component=messaging-service -n nova-messaging

# 查看日志
kubectl logs -f -l component=messaging-service -n nova-messaging
```

### 2. 端口转发 (Docker Desktop/Minikube)

```bash
# 端口转发到本地
kubectl port-forward svc/messaging-service 3000:3000 -n nova-messaging

# 或用于Metrics
kubectl port-forward svc/messaging-service 9090:9090 -n nova-messaging
```

### 3. 测试健康检查

```bash
# Docker Desktop/Minikube
curl http://localhost:3000/health

# kind (使用NodePort)
curl http://localhost:30000/health

# 预期响应:
# {"status":"ok"}
```

### 4. 检查Metrics

```bash
# 端口转发
kubectl port-forward svc/messaging-service 9090:9090 -n nova-messaging

# 在浏览器访问
http://localhost:9090/metrics

# 或使用curl
curl http://localhost:9090/metrics | head -20
```

### 5. 检查数据库连接

```bash
# 查看日志中的数据库连接信息
kubectl logs -l component=messaging-service -n nova-messaging | grep -i database

# 测试连接 (如果使用本地Postgres)
psql -h localhost -U postgres -d nova_messaging -c "SELECT version();"
```

---

## 实用验证脚本

创建 `verify-local.sh`:

```bash
#!/bin/bash

echo "=== Nova Messaging Service 本地验证 ==="
echo ""

# 1. 检查集群
echo "1️⃣ 检查K8s集群..."
kubectl cluster-info | head -2
echo ""

# 2. 检查命名空间
echo "2️⃣ 检查命名空间..."
kubectl get ns nova-messaging
echo ""

# 3. 检查Pod
echo "3️⃣ 检查Pod..."
kubectl get pods -n nova-messaging
echo ""

# 4. 检查服务
echo "4️⃣ 检查服务..."
kubectl get svc -n nova-messaging
echo ""

# 5. 检查ConfigMap
echo "5️⃣ 检查ConfigMap..."
kubectl get configmap -n nova-messaging
echo ""

# 6. 检查Secret
echo "6️⃣ 检查Secret..."
kubectl get secret -n nova-messaging
echo ""

# 7. 检查部署状态
echo "7️⃣ 检查部署状态..."
kubectl describe deployment messaging-service -n nova-messaging | grep -A 5 "Replicas:"
echo ""

# 8. 测试健康检查
echo "8️⃣ 测试健康检查..."
POD_NAME=$(kubectl get pod -l component=messaging-service -n nova-messaging -o jsonpath='{.items[0].metadata.name}')
if [ -n "$POD_NAME" ]; then
    kubectl exec -it $POD_NAME -n nova-messaging -- curl -s http://localhost:3000/health
    echo ""
else
    echo "❌ 没有找到运行的Pod"
    echo ""
fi

# 9. 检查日志
echo "9️⃣ 最近日志 (最后10行)..."
kubectl logs -l component=messaging-service -n nova-messaging --tail=10
echo ""

# 10. 检查资源使用
echo "🔟 资源使用..."
kubectl top pods -n nova-messaging 2>/dev/null || echo "⚠️  Metrics还未收集"
echo ""

echo "✅ 验证完成!"
```

运行验证脚本:
```bash
chmod +x verify-local.sh
./verify-local.sh
```

---

## 故障排查

### Pod无法启动

```bash
# 查看详细错误
kubectl describe pod <pod-name> -n nova-messaging

# 查看完整日志 (包括错误)
kubectl logs <pod-name> -n nova-messaging --all-containers=true

# 常见问题:
# 1. ImagePullBackOff: 镜像不存在
#    → 检查docker build是否成功
#    → 对于kind: kind load docker-image ...
#
# 2. CrashLoopBackOff: 应用启动失败
#    → 检查RUST_LOG日志
#    → 检查数据库连接
#    → 检查SECRET正确性
```

### 数据库连接失败

```bash
# 进入Pod测试连接
kubectl exec -it <pod-name> -n nova-messaging -- bash

# 在Pod内测试
# Linux
apt-get update && apt-get install -y postgresql-client
psql -h host.docker.internal -U postgres -d nova_messaging -c "SELECT 1;"

# 或测试Redis
# apt-get install -y redis-tools
redis-cli -h host.docker.internal -p 6379 ping
```

### 端口无法访问

```bash
# 检查服务
kubectl get svc -n nova-messaging -o wide

# 检查端口转发
kubectl port-forward svc/messaging-service 3000:3000 -n nova-messaging

# 测试
curl http://localhost:3000/health

# 对于kind，使用NodePort
kubectl port-forward svc/messaging-service 30000:3000 -n nova-messaging
```

---

## 清理本地环境

```bash
# 删除部署
kubectl delete -f messaging-service-deployment-local.yaml -n nova-messaging

# 删除命名空间 (删除所有资源)
kubectl delete namespace nova-messaging

# 删除本地镜像 (可选)
docker rmi nova/messaging-service:latest

# 停止Minikube (如果使用)
minikube stop

# 删除Minikube集群 (如果使用)
minikube delete

# 停止kind集群
kind delete cluster --name nova-dev
```

---

## 本地开发工作流

```bash
# 1. 编辑代码
vim backend/messaging-service/src/main.rs

# 2. 构建镜像
docker build -t nova/messaging-service:latest -f backend/Dockerfile.messaging .

# 3. 加载到kind (如果使用)
kind load docker-image nova/messaging-service:latest --name nova-dev

# 4. 重启Pod
kubectl rollout restart deployment/messaging-service -n nova-messaging

# 5. 监控日志
kubectl logs -f -l component=messaging-service -n nova-messaging

# 6. 测试
curl http://localhost:3000/health
```

---

## 性能优化提示

| 环境 | 优化建议 |
|------|--------|
| Docker Desktop | 增加内存到8GB+，关闭不需要的镜像 |
| Minikube | 使用 `--memory=8192 --cpus=4` |
| kind | 关闭不需要的control-plane节点 |
| 通用 | 减少副本数(1个), 减少连接池, 禁用健康检查 |

---

## 下一步

✅ 验证本地K8s部署工作
→ 修改并重建镜像
→ 测试API端点
→ 部署到生产K8s集群

