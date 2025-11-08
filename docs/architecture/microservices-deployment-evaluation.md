# Nova 微服务架构评估报告

## 1. 当前部署状态分析

### 1.1 已识别的服务列表（12个核心服务）

基于代码库分析，Nova 平台包含以下微服务：

1. **user-service** (用户服务) - 端口 8080/9080
2. **auth-service** (认证服务) - 端口 8084/9084
3. **content-service** (内容服务) - 端口 8081/9081
4. **feed-service** (推送服务) - 端口 8089/9089
5. **media-service** (媒体服务) - 端口 8082/9082
6. **messaging-service** (消息服务) - 端口 8085/9085
7. **search-service** (搜索服务) - 端口 8086/9086
8. **notification-service** (通知服务)
9. **streaming-service** (流媒体服务)
10. **events-service** (事件服务)
11. **cdn-service** (CDN服务)
12. **video-service** (视频服务 - 已迁移到 media-service)

### 1.2 K8s 部署文件状态

**已有部署文件的服务：**
- ✅ user-service-deployment.yaml
- ✅ auth-service-deployment.yaml
- ✅ messaging-service-deployment.yaml
- ✅ turn-server-deployment.yaml (WebRTC)

**缺失部署文件的服务（8个）：**
- ❌ content-service
- ❌ feed-service
- ❌ media-service
- ❌ search-service
- ❌ notification-service
- ❌ streaming-service
- ❌ events-service
- ❌ cdn-service

### 1.3 user-service 的硬性依赖关系

根据 `main.rs` 分析，user-service 在启动时会尝试连接以下 gRPC 服务：

1. **content-service** (9081) - 内容管理
2. **auth-service** (9084) - 认证服务
3. **feed-service** (9089) - 推送生成
4. **media-service** (9082) - 媒体处理

**当前问题：**
- 代码使用 "优雅降级" 模式（第286-346行）
- 如果依赖服务不可达，只记录 `warn` 日志，服务继续启动
- 但某些功能（如 EventsConsumer、CacheWarmer）会被禁用
- 用户希望采用 **严格依赖** 模式，不接受降级启动


## 2. 根本原因分析

### 2.1 架构问题

**问题 1: 部署不完整**
- 只部署了 4/12 个服务
- user-service 依赖的 content/feed/media 服务均未部署
- 导致 user-service 启动时无法建立 gRPC 连接

**问题 2: 优雅降级 vs 严格依赖的矛盾**
- 当前代码实现了优雅降级（可选依赖）
- 但业务需求是严格依赖（必须等待所有下游服务）
- 这是设计哲学的根本冲突

**问题 3: Kubernetes 部署缺少依赖等待机制**
- user-service-deployment.yaml 没有 InitContainer
- 没有健康检查依赖服务的机制
- Kubernetes 会立即启动 Pod，不管依赖是否就绪

### 2.2 技术债务

**TD-1: gRPC 客户端初始化策略**
```rust
// 当前实现：容忍失败
let content_client: Option<Arc<ContentServiceClient>> = match ContentServiceClient::new(...).await {
    Ok(client) => {
        tracing::info!("content-service gRPC client initialized");
        Some(Arc::new(client))
    }
    Err(e) => {
        tracing::warn!("content-service gRPC client initialization failed: {:#} (running in degraded mode)", e);
        None  // ← 允许 None，服务继续启动
    }
};
```

**问题：**
- 返回 `Option<Arc<Client>>` 允许服务在依赖缺失时启动
- 后续代码需要处理 `None` 情况
- 不符合用户的"硬性依赖"需求

**TD-2: 连接重试配置不足**
```rust
// config.rs 第162-165行
let connect_retry_attempts = std::env::var("GRPC_CONNECT_RETRY_ATTEMPTS")
    .ok()
    .and_then(|s| s.parse().ok())
    .unwrap_or(3);  // ← 只重试 3 次，失败后放弃
```

**问题：**
- 重试次数少（3次）
- 退避时间短（200ms）
- 总等待时间 < 1秒，不足以等待依赖服务启动

### 2.3 Kubernetes 配置缺陷

**user-service-deployment.yaml 问题：**

1. **缺少 InitContainer**
   - 应该等待 content/feed/media/auth 服务就绪
   - 应该执行 gRPC 健康检查

2. **ReadinessProbe 不完整**
   ```yaml
   readinessProbe:
     httpGet:
       path: /api/v1/health/ready
       port: 8081
     initialDelaySeconds: 5  # ← 太短，依赖服务可能未启动
   ```

3. **没有服务依赖声明**
   - Kubernetes 不知道启动顺序
   - 所有 Pod 并行启动


## 3. 解决方案设计

### 3.1 架构决策

**决策 1: 采用严格依赖模式**

**原则：**
- "Never break userspace" - 服务必须完整可用，不接受降级启动
- 遵循 Twelve-Factor App 原则：依赖显式声明
- 快速失败优于慢速降级（Fail-fast over degraded operation）

**实施方案：**
1. 将 `Option<Arc<Client>>` 改为 `Arc<Client>`（强制依赖）
2. 连接失败时立即 `std::process::exit(1)`
3. 增加重试次数和等待时间

### 3.2 Kubernetes 依赖管理策略

**策略 A: InitContainer 健康检查（推荐）**

**优点：**
- ✅ 清晰的依赖声明
- ✅ 阻塞式等待，确保依赖就绪
- ✅ 日志可见性高
- ✅ 符合 Kubernetes 最佳实践

**实现：**
```yaml
initContainers:
- name: wait-for-content-service
  image: curlimages/curl:8.5.0
  command:
  - sh
  - -c
  - |
    until curl -f http://content-service.nova-content:8081/health; do
      echo "Waiting for content-service..."
      sleep 2
    done
- name: wait-for-feed-service
  image: curlimages/curl:8.5.0
  command:
  - sh
  - -c
  - |
    until curl -f http://feed-service.nova-feed:8089/health; do
      echo "Waiting for feed-service..."
      sleep 2
    done
- name: wait-for-media-service
  image: curlimages/curl:8.5.0
  command:
  - sh
  - -c
  - |
    until curl -f http://media-service.nova-media:8082/health; do
      echo "Waiting for media-service..."
      sleep 2
    done
- name: wait-for-auth-service
  image: curlimages/curl:8.5.0
  command:
  - sh
  - -c
  - |
    until curl -f http://auth-service.nova-auth:8084/health; do
      echo "Waiting for auth-service..."
      sleep 2
    done
```

**策略 B: 应用层重试（备选）**

**修改 gRPC 客户端配置：**
```bash
# 环境变量
GRPC_CONNECT_RETRY_ATTEMPTS=30        # 30 次重试
GRPC_CONNECT_RETRY_BACKOFF_MS=2000    # 2 秒退避
GRPC_CONNECTION_TIMEOUT_SECS=60       # 60 秒超时
```

**总等待时间：** 30 × 2s = 60 秒

**缺点：**
- ❌ 服务会启动但 readiness probe 会失败
- ❌ Kubernetes 会频繁重启 Pod
- ❌ 日志混乱，难以调试

**结论：推荐 策略 A（InitContainer）**

### 3.3 服务部署顺序

**Layer 0: 基础设施**
1. PostgreSQL（RDS）
2. Redis（ElastiCache）
3. Kafka（MSK）
4. ClickHouse

**Layer 1: 独立服务（无依赖）**
1. auth-service
2. content-service
3. media-service
4. search-service

**Layer 2: 聚合服务（有依赖）**
1. feed-service（依赖 content-service）
2. notification-service（依赖 auth-service）
3. events-service（依赖 Kafka）

**Layer 3: 网关服务**
1. user-service（依赖 auth/content/feed/media）
2. messaging-service（依赖 user-service）
3. streaming-service（依赖 media-service）

**Layer 4: 边缘服务**
1. api-gateway（Nginx）
2. cdn-service

### 3.4 健康检查改进

**推荐实现：分层健康检查**

**Level 1: Liveness（存活探针）**
- 检查进程是否运行
- 检查 HTTP 服务器是否响应
- 失败 → Kubernetes 重启 Pod

**Level 2: Readiness（就绪探针）**
- 检查所有依赖服务是否可达
- 检查数据库连接池
- 检查 Redis 连接
- 失败 → 从 Service 移除，停止接收流量

**Level 3: Startup（启动探针）**
- 允许服务长时间启动（如数据库迁移）
- 适用于初始化缓慢的服务

**user-service 健康检查实现建议：**

```rust
// handlers/health.rs
pub async fn readiness_check(
    state: web::Data<HealthCheckState>,
) -> Result<HttpResponse, actix_web::Error> {
    // 1. 检查 gRPC 依赖
    let content_healthy = state.health_checker
        .check_content_service()
        .await
        .is_ok();
    
    let feed_healthy = state.health_checker
        .check_feed_service()
        .await
        .is_ok();
    
    let media_healthy = state.health_checker
        .check_media_service()
        .await
        .is_ok();
    
    let auth_healthy = state.health_checker
        .check_auth_service()
        .await
        .is_ok();
    
    // 2. 检查数据库
    let db_healthy = state.db
        .acquire()
        .await
        .is_ok();
    
    // 3. 检查 Redis
    let redis_healthy = state.redis
        .get()
        .await
        .is_ok();
    
    // 4. 汇总结果
    let all_healthy = content_healthy 
        && feed_healthy 
        && media_healthy 
        && auth_healthy
        && db_healthy 
        && redis_healthy;
    
    if all_healthy {
        Ok(HttpResponse::Ok().json(json!({
            "status": "ready",
            "dependencies": {
                "content_service": "healthy",
                "feed_service": "healthy",
                "media_service": "healthy",
                "auth_service": "healthy",
                "database": "healthy",
                "redis": "healthy"
            }
        })))
    } else {
        Ok(HttpResponse::ServiceUnavailable().json(json!({
            "status": "not_ready",
            "dependencies": {
                "content_service": if content_healthy { "healthy" } else { "unhealthy" },
                "feed_service": if feed_healthy { "healthy" } else { "unhealthy" },
                "media_service": if media_healthy { "healthy" } else { "unhealthy" },
                "auth_service": if auth_healthy { "healthy" } else { "unhealthy" },
                "database": if db_healthy { "healthy" } else { "unhealthy" },
                "redis": if redis_healthy { "healthy" } else { "unhealthy" }
            }
        })))
    }
}
```


## 4. 具体实施方案

### 4.1 阶段 1: 创建缺失服务的 K8s 部署文件

**优先级 P0（user-service 硬性依赖）：**

1. **content-service-deployment.yaml**
2. **feed-service-deployment.yaml**  
3. **media-service-deployment.yaml**

**优先级 P1（其他核心服务）：**

4. **search-service-deployment.yaml**
5. **notification-service-deployment.yaml**
6. **streaming-service-deployment.yaml**
7. **events-service-deployment.yaml**
8. **cdn-service-deployment.yaml**

**模板结构（以 content-service 为例）：**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: nova-content
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: content-service-config
  namespace: nova-content
data:
  RUST_LOG: "info,content_service=debug"
  SERVER_HOST: "0.0.0.0"
  SERVER_PORT: "8081"
  REDIS_URL: "redis://redis.nova-infra:6379"
  KAFKA_BROKERS: "kafka.nova-infra:9092"
---
apiVersion: v1
kind: Secret
metadata:
  name: content-service-secret
  namespace: nova-content
type: Opaque
stringData:
  database-url: "postgres://user:pass@postgres.nova-infra:5432/content_db"
---
apiVersion: v1
kind: Service
metadata:
  name: content-service
  namespace: nova-content
  labels:
    app: content-service
spec:
  type: ClusterIP
  ports:
  - name: http
    port: 8081
    targetPort: 8081
    protocol: TCP
  - name: grpc
    port: 9081
    targetPort: 9081
    protocol: TCP
  selector:
    app: content-service
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: content-service
  namespace: nova-content
spec:
  replicas: 3
  selector:
    matchLabels:
      app: content-service
  template:
    metadata:
      labels:
        app: content-service
    spec:
      serviceAccountName: content-service
      containers:
      - name: content-service
        image: nova/content-service:latest
        imagePullPolicy: IfNotPresent
        ports:
        - name: http
          containerPort: 8081
        - name: grpc
          containerPort: 9081
        envFrom:
        - configMapRef:
            name: content-service-config
        - secretRef:
            name: content-service-secret
        livenessProbe:
          httpGet:
            path: /health
            port: 8081
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health/ready
            port: 8081
          initialDelaySeconds: 5
          periodSeconds: 5
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "1000m"
```

### 4.2 阶段 2: 修改 user-service-deployment.yaml

**添加 InitContainers：**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-service
  namespace: nova-user
spec:
  replicas: 3
  selector:
    matchLabels:
      app: user-service
  template:
    metadata:
      labels:
        app: user-service
    spec:
      # ========== 新增: InitContainers ==========
      initContainers:
      # 等待 auth-service 就绪
      - name: wait-for-auth-service
        image: curlimages/curl:8.5.0
        command:
        - sh
        - -c
        - |
          echo "Waiting for auth-service to be ready..."
          until curl -sf http://auth-service.nova-auth:8084/health; do
            echo "auth-service not ready yet, retrying in 2s..."
            sleep 2
          done
          echo "auth-service is ready!"
      
      # 等待 content-service 就绪
      - name: wait-for-content-service
        image: curlimages/curl:8.5.0
        command:
        - sh
        - -c
        - |
          echo "Waiting for content-service to be ready..."
          until curl -sf http://content-service.nova-content:8081/health; do
            echo "content-service not ready yet, retrying in 2s..."
            sleep 2
          done
          echo "content-service is ready!"
      
      # 等待 feed-service 就绪
      - name: wait-for-feed-service
        image: curlimages/curl:8.5.0
        command:
        - sh
        - -c
        - |
          echo "Waiting for feed-service to be ready..."
          until curl -sf http://feed-service.nova-feed:8089/health; do
            echo "feed-service not ready yet, retrying in 2s..."
            sleep 2
          done
          echo "feed-service is ready!"
      
      # 等待 media-service 就绪
      - name: wait-for-media-service
        image: curlimages/curl:8.5.0
        command:
        - sh
        - -c
        - |
          echo "Waiting for media-service to be ready..."
          until curl -sf http://media-service.nova-media:8082/health; do
            echo "media-service not ready yet, retrying in 2s..."
            sleep 2
          done
          echo "media-service is ready!"
      
      # ========== 主容器 ==========
      serviceAccountName: user-service
      containers:
      - name: user-service
        image: nova/user-service:latest
        imagePullPolicy: IfNotPresent
        ports:
        - name: http
          containerPort: 8081
        - name: grpc
          containerPort: 9081
        
        # ========== 新增: 环境变量 - 严格依赖模式 ==========
        env:
        - name: GRPC_STRICT_DEPENDENCY_MODE
          value: "true"
        - name: GRPC_CONNECT_RETRY_ATTEMPTS
          value: "10"
        - name: GRPC_CONNECT_RETRY_BACKOFF_MS
          value: "1000"
        - name: GRPC_CONNECTION_TIMEOUT_SECS
          value: "30"
        
        envFrom:
        - configMapRef:
            name: user-service-config
        - secretRef:
            name: user-service-secret
        
        # ========== 修改: 健康检查 ==========
        livenessProbe:
          httpGet:
            path: /api/v1/health/live
            port: 8081
          initialDelaySeconds: 10
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        
        readinessProbe:
          httpGet:
            path: /api/v1/health/ready
            port: 8081
          initialDelaySeconds: 15  # 增加到 15 秒
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        
        # ========== 新增: 启动探针 ==========
        startupProbe:
          httpGet:
            path: /api/v1/health/live
            port: 8081
          initialDelaySeconds: 5
          periodSeconds: 5
          failureThreshold: 30  # 允许 150 秒启动时间
        
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "1000m"
        
        volumeMounts:
        - name: tmp
          mountPath: /tmp
        - name: var-tmp
          mountPath: /var/tmp
      
      volumes:
      - name: tmp
        emptyDir: {}
      - name: var-tmp
        emptyDir: {}
```

### 4.3 阶段 3: 修改应用代码 - 严格依赖模式

**修改 `backend/user-service/src/main.rs`：**

```rust
// 第273-346行：gRPC 客户端初始化

// 读取严格依赖模式配置
let strict_dependency_mode = std::env::var("GRPC_STRICT_DEPENDENCY_MODE")
    .ok()
    .map(|s| s.to_lowercase() == "true")
    .unwrap_or(true);  // 默认启用严格模式

tracing::info!("gRPC client strict dependency mode: {}", strict_dependency_mode);

// Content Service 客户端（必需）
let content_client = match ContentServiceClient::new(&grpc_config, health_checker.clone()).await {
    Ok(client) => {
        tracing::info!("content-service gRPC client initialized");
        Arc::new(client)
    }
    Err(e) => {
        tracing::error!("content-service gRPC client initialization failed: {:#}", e);
        if strict_dependency_mode {
            eprintln!("FATAL: content-service is required but unavailable");
            std::process::exit(1);
        } else {
            tracing::warn!("Running in degraded mode without content-service");
            // 返回一个 Mock 客户端或者使用 Option
            panic!("Not implemented: Mock client for degraded mode");
        }
    }
};

// Auth Service 客户端（必需）
let auth_client = match AuthServiceClient::new(&grpc_config, health_checker.clone()).await {
    Ok(client) => {
        tracing::info!("auth-service gRPC client initialized");
        Arc::new(client)
    }
    Err(e) => {
        tracing::error!("auth-service gRPC client initialization failed: {:#}", e);
        if strict_dependency_mode {
            eprintln!("FATAL: auth-service is required but unavailable");
            std::process::exit(1);
        } else {
            tracing::warn!("Running in degraded mode without auth-service");
            panic!("Not implemented: Mock client for degraded mode");
        }
    }
};

// Media Service 客户端（必需）
let media_client = match MediaServiceClient::new(&grpc_config, health_checker.clone()).await {
    Ok(client) => {
        tracing::info!("media-service gRPC client initialized");
        Arc::new(client)
    }
    Err(e) => {
        tracing::error!("media-service gRPC client initialization failed: {:#}", e);
        if strict_dependency_mode {
            eprintln!("FATAL: media-service is required but unavailable");
            std::process::exit(1);
        } else {
            tracing::warn!("Running in degraded mode without media-service");
            panic!("Not implemented: Mock client for degraded mode");
        }
    }
};

// Feed Service 客户端（必需）
let feed_client = match FeedServiceClient::new(&grpc_config, health_checker.clone()).await {
    Ok(client) => {
        tracing::info!("feed-service gRPC client initialized");
        Arc::new(client)
    }
    Err(e) => {
        tracing::error!("feed-service gRPC client initialization failed: {:#}", e);
        if strict_dependency_mode {
            eprintln!("FATAL: feed-service is required but unavailable");
            std::process::exit(1);
        } else {
            tracing::warn!("Running in degraded mode without feed-service");
            panic!("Not implemented: Mock client for degraded mode");
        }
    }
};

// 后续代码不再使用 Option，直接使用 Arc<Client>
let content_client_data = web::Data::new(content_client.clone());
let feed_client_data = web::Data::new(feed_client.clone());
let auth_client_data = web::Data::new(auth_client.clone());
let media_client_data = web::Data::new(media_client.clone());
```

### 4.4 阶段 4: 部署脚本和 CI/CD

**创建部署脚本：`scripts/deploy-all-services.sh`**

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/../k8s/microservices"
NAMESPACE_PREFIX="nova"

echo "========================================="
echo "Nova Microservices Deployment"
echo "========================================="

# Layer 0: 基础设施（假设已部署）
echo "Checking infrastructure services..."
kubectl get namespace ${NAMESPACE_PREFIX}-infra || kubectl create namespace ${NAMESPACE_PREFIX}-infra

# Layer 1: 独立服务（无依赖）
echo ""
echo "Deploying Layer 1: Independent Services..."
LAYER1_SERVICES=(
  "auth-service"
  "content-service"
  "media-service"
  "search-service"
)

for service in "${LAYER1_SERVICES[@]}"; do
  echo "  → Deploying ${service}..."
  kubectl apply -f "${K8S_DIR}/${service}-namespace.yaml" || true
  kubectl apply -f "${K8S_DIR}/${service}-configmap.yaml"
  kubectl apply -f "${K8S_DIR}/${service}-secret.yaml"
  kubectl apply -f "${K8S_DIR}/${service}-serviceaccount.yaml" || true
  kubectl apply -f "${K8S_DIR}/${service}-service.yaml"
  kubectl apply -f "${K8S_DIR}/${service}-deployment.yaml"
done

# 等待 Layer 1 就绪
echo ""
echo "Waiting for Layer 1 services to be ready..."
for service in "${LAYER1_SERVICES[@]}"; do
  namespace="${NAMESPACE_PREFIX}-${service%-service}"
  echo "  → Waiting for ${service} in ${namespace}..."
  kubectl wait --for=condition=available --timeout=300s \
    deployment/${service} -n ${namespace}
done

# Layer 2: 聚合服务（有依赖）
echo ""
echo "Deploying Layer 2: Aggregation Services..."
LAYER2_SERVICES=(
  "feed-service"
  "notification-service"
  "events-service"
)

for service in "${LAYER2_SERVICES[@]}"; do
  echo "  → Deploying ${service}..."
  kubectl apply -f "${K8S_DIR}/${service}-namespace.yaml" || true
  kubectl apply -f "${K8S_DIR}/${service}-configmap.yaml"
  kubectl apply -f "${K8S_DIR}/${service}-secret.yaml"
  kubectl apply -f "${K8S_DIR}/${service}-serviceaccount.yaml" || true
  kubectl apply -f "${K8S_DIR}/${service}-service.yaml"
  kubectl apply -f "${K8S_DIR}/${service}-deployment.yaml"
done

# 等待 Layer 2 就绪
echo ""
echo "Waiting for Layer 2 services to be ready..."
for service in "${LAYER2_SERVICES[@]}"; do
  namespace="${NAMESPACE_PREFIX}-${service%-service}"
  echo "  → Waiting for ${service} in ${namespace}..."
  kubectl wait --for=condition=available --timeout=300s \
    deployment/${service} -n ${namespace}
done

# Layer 3: 网关服务
echo ""
echo "Deploying Layer 3: Gateway Services..."
LAYER3_SERVICES=(
  "user-service"
  "messaging-service"
  "streaming-service"
)

for service in "${LAYER3_SERVICES[@]}"; do
  echo "  → Deploying ${service}..."
  kubectl apply -f "${K8S_DIR}/${service}-namespace.yaml" || true
  kubectl apply -f "${K8S_DIR}/${service}-configmap.yaml"
  kubectl apply -f "${K8S_DIR}/${service}-secret.yaml"
  kubectl apply -f "${K8S_DIR}/${service}-serviceaccount.yaml" || true
  kubectl apply -f "${K8S_DIR}/${service}-service.yaml"
  kubectl apply -f "${K8S_DIR}/${service}-deployment.yaml"
done

# Layer 4: 边缘服务
echo ""
echo "Deploying Layer 4: Edge Services..."
kubectl apply -f "${K8S_DIR}/api-gateway/"
kubectl apply -f "${K8S_DIR}/cdn-service-deployment.yaml" || true

echo ""
echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo ""
echo "Verify services:"
echo "  kubectl get pods -A | grep nova"
echo ""
echo "Check service health:"
echo "  kubectl exec -it -n nova-user deploy/user-service -- curl http://localhost:8081/api/v1/health/ready"
```


## 5. 架构风险评估

### 5.1 高风险（P0）

**风险 1: 循环依赖风险**
- **描述**: 如果服务之间存在循环依赖（如 A → B → C → A），InitContainer 会死锁
- **缓解措施**: 
  - 绘制完整的服务依赖图
  - 执行静态分析检测循环
  - 使用分层架构（单向依赖）

**风险 2: 启动超时导致 Kubernetes 驱逐**
- **描述**: InitContainer 等待时间过长，Pod 被标记为 Failed
- **缓解措施**:
  - 设置合理的 `initialDelaySeconds`
  - 使用 `startupProbe` 允许长时间启动
  - 监控启动时间指标

**风险 3: 数据库迁移失败导致级联故障**
- **描述**: user-service 迁移失败 → Pod 重启 → 依赖服务连接失败
- **缓解措施**:
  - 迁移失败时 `exit(1)`（已实现）
  - 使用 Flyway/Liquibase 事务性迁移
  - 分离迁移 Job 和应用 Pod

### 5.2 中风险（P1）

**风险 4: 服务雪崩**
- **描述**: content-service 宕机 → user-service 重启 → 级联重启
- **缓解措施**:
  - 实现断路器（Circuit Breaker）
  - 健康检查降级（部分依赖失败时不重启）
  - 使用 PodDisruptionBudget 限制同时重启的 Pod 数量

**风险 5: gRPC 连接泄漏**
- **描述**: 连接池未正确释放，导致资源耗尽
- **缓解措施**:
  - 监控连接池指标
  - 设置连接超时和 keep-alive
  - 使用 Prometheus 监控 `grpc_client_connections_active`

### 5.3 低风险（P2）

**风险 6: InitContainer 镜像拉取失败**
- **描述**: `curlimages/curl:8.5.0` 镜像不可用
- **缓解措施**:
  - 使用私有镜像仓库
  - 预拉取镜像到节点
  - 使用多个镜像源（fallback）

## 6. Terraform 集成

### 6.1 EKS 配置检查

**当前配置（eks.tf）：**
- ✅ EKS 集群版本 1.28
- ✅ Node Group 配置正确
- ✅ 安全组允许 gRPC 端口（50000-50100）
- ❌ 缺少 Service Mesh（Istio/Linkerd）
- ❌ 缺少自动扩展配置（Cluster Autoscaler）

**建议增强：**

```hcl
# terraform/eks.tf

# 启用 IRSA（IAM Roles for Service Accounts）
resource "aws_iam_openid_connect_provider" "eks_oidc" {
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
}

# Cluster Autoscaler IAM 角色
resource "aws_iam_role" "cluster_autoscaler" {
  name = "nova-${var.environment}-cluster-autoscaler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks_oidc.arn
      }
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.eks_oidc.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:cluster-autoscaler"
        }
      }
    }]
  })
}

# 附加 Autoscaler 权限
resource "aws_iam_role_policy" "cluster_autoscaler" {
  name = "nova-${var.environment}-cluster-autoscaler-policy"
  role = aws_iam_role.cluster_autoscaler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:DescribeInstanceTypes"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
          "ec2:DescribeInstanceTypes"
        ]
        Resource = "*"
      }
    ]
  })
}
```

### 6.2 网络配置检查

**当前配置（networking.tf）：**
- ✅ VPC CIDR 正确
- ✅ 公有/私有子网配置
- ❌ 缺少 NAT Gateway 高可用配置
- ❌ 缺少 VPC Flow Logs

**建议：**
```hcl
# terraform/networking.tf

# 为每个 AZ 创建 NAT Gateway（高可用）
resource "aws_nat_gateway" "main" {
  count         = length(var.availability_zones)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "nova-${var.environment}-nat-${var.availability_zones[count.index]}"
  }
}

# VPC Flow Logs（安全审计）
resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.vpc_flow_logs.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id
}
```

## 7. 监控和可观测性

### 7.1 关键指标

**服务健康指标：**
```yaml
# Prometheus ServiceMonitor
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: user-service
  namespace: nova-user
spec:
  selector:
    matchLabels:
      app: user-service
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
```

**关键 SLI（Service Level Indicators）：**
1. **可用性**: `up{job="user-service"}` > 99.9%
2. **gRPC 成功率**: `grpc_client_requests_success_rate` > 99.5%
3. **P99 延迟**: `grpc_client_request_duration_p99` < 500ms
4. **依赖健康**: `dependency_health{service="content-service"}` == 1

### 7.2 告警规则

```yaml
# prometheus-rules.yaml
groups:
- name: nova-grpc-dependencies
  interval: 30s
  rules:
  # 依赖服务不可达
  - alert: GrpcDependencyDown
    expr: dependency_health == 0
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "gRPC dependency {{ $labels.service }} is down"
      description: "Service {{ $labels.caller }} cannot reach {{ $labels.service }}"

  # InitContainer 失败
  - alert: InitContainerFailed
    expr: kube_pod_init_container_status_restarts_total > 5
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "InitContainer {{ $labels.container }} failing repeatedly"
      description: "Pod {{ $labels.pod }} in {{ $labels.namespace }} cannot initialize"

  # Pod 频繁重启
  - alert: PodCrashLooping
    expr: rate(kube_pod_container_status_restarts_total[15m]) > 0.1
    for: 10m
    labels:
      severity: critical
    annotations:
      summary: "Pod {{ $labels.pod }} is crash looping"
```

## 8. 实施时间线

### 第 1 周：准备阶段
- **Day 1-2**: 创建缺失服务的 K8s 部署文件（content/feed/media）
- **Day 3-4**: 修改 user-service-deployment.yaml 添加 InitContainers
- **Day 5**: 本地测试（Kind/Minikube）验证启动顺序

### 第 2 周：代码修改
- **Day 6-7**: 修改 main.rs 实现严格依赖模式
- **Day 8**: 增强健康检查逻辑
- **Day 9-10**: 编写单元测试和集成测试

### 第 3 周：Staging 部署
- **Day 11-12**: Staging 环境部署（分层部署）
- **Day 13**: 压力测试和故障注入测试
- **Day 14-15**: 修复 Staging 发现的问题

### 第 4 周：Production 部署
- **Day 16-17**: 生产环境部署（金丝雀发布）
- **Day 18**: 监控和性能优化
- **Day 19-20**: 文档更新和知识转移

## 9. 回滚计划

**触发条件：**
- InitContainer 超时率 > 10%
- Pod 重启率 > 5 次/小时
- gRPC 连接失败率 > 5%

**回滚步骤：**
```bash
# 1. 恢复旧版本 deployment
kubectl rollout undo deployment/user-service -n nova-user

# 2. 禁用严格依赖模式
kubectl set env deployment/user-service -n nova-user \
  GRPC_STRICT_DEPENDENCY_MODE=false

# 3. 移除 InitContainers（紧急情况）
kubectl patch deployment user-service -n nova-user --type=json \
  -p='[{"op": "remove", "path": "/spec/template/spec/initContainers"}]'

# 4. 验证服务恢复
kubectl rollout status deployment/user-service -n nova-user
```

## 10. 最终建议

### 10.1 Linus 的视角评估

作为 Linus，我会这样评价当前架构：

**好品味（Good Taste）：**
- ✅ **服务分层清晰**：Layer 0-4 架构符合"单一职责"
- ✅ **健康检查分离**：Liveness/Readiness/Startup 各司其职
- ✅ **显式依赖声明**：InitContainer 让依赖关系一目了然

**需要改进（Bad Taste）：**
- ❌ **Option<Arc<Client>> 是个错误**：这是"理论完美"但实际复杂的方案
  - 正确做法：要么强制依赖（Arc<Client>），要么不依赖
  - `Option` 制造了大量的 `if let Some()` 检查，代码臭
- ❌ **优雅降级是个陷阱**：
  - 你无法同时拥有"可选依赖"和"完整功能"
  - 降级模式会导致隐藏的 bug（某些路径未测试）
  - Linus 语录："要么做，要么不做。没有试试看。"

**架构决策建议：**
1. **删除优雅降级代码**：全部改为严格依赖（`std::process::exit(1)`）
2. **InitContainer 是正确的解决方案**：简单、清晰、可调试
3. **不要过度设计重试逻辑**：让 Kubernetes 处理重启，应用只负责快速失败

### 10.2 最高优先级任务

**P0（立即执行）：**
1. 创建 content-service/feed-service/media-service 的 K8s 部署文件
2. 修改 user-service-deployment.yaml 添加 InitContainers
3. 修改 main.rs 移除 `Option<Arc<Client>>`，全部改为强制依赖

**P1（本周完成）：**
4. 增强健康检查逻辑（依赖服务状态检查）
5. 编写部署脚本（分层部署）
6. 配置监控告警

**P2（下周完成）：**
7. Staging 环境测试
8. 压力测试和故障注入
9. 文档和 Runbook

### 10.3 不要做的事情

**❌ 不要实现服务网格（现阶段）：**
- Istio/Linkerd 增加复杂度
- 当前问题可以用 InitContainer 解决
- 遵循 YAGNI 原则（You Aren't Gonna Need It）

**❌ 不要使用 Operator/CRD：**
- 过度工程化
- 维护成本高
- Kubernetes 原生机制已足够

**❌ 不要混合同步和异步健康检查：**
- 要么全部用 HTTP
- 要么全部用 gRPC Health Check
- 不要在 InitContainer 里调用 gRPC（使用 HTTP）

## 11. 总结

**核心问题：**
Nova 项目的 user-service 启动失败是因为：
1. 缺少 8 个服务的 K8s 部署文件
2. 代码使用"优雅降级"但用户需要"严格依赖"
3. 没有 InitContainer 等待依赖服务

**解决方案：**
1. 补全所有服务的 K8s 部署文件
2. 使用 InitContainer 强制等待依赖服务
3. 修改代码移除 Option，改为强制依赖
4. 分层部署（Layer 0-4）确保启动顺序

**预期效果：**
- user-service 只在所有依赖就绪后启动
- 启动失败会立即报错，而非静默降级
- 清晰的日志和监控，易于调试
- 符合"快速失败"（Fail-fast）原则

**Linus 会怎么说：**
"这个设计很简单——如果依赖不可用，就 exit(1)。不要搞什么优雅降级，那只会让代码变得更复杂。InitContainer 是正确的工具，用它。"

