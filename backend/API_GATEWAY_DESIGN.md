# API Gateway Architecture Design - P1.1

**Status**: Design Phase
**Priority**: P1 - Service Splitting Foundation
**Date**: October 28, 2025

---

## 概述

API Gateway 是 P1 服务分离的第一步。它提供统一的入口点，将客户端请求路由到底层微服务，处理负载均衡、认证、速率限制等横切关注点。

---

## 架构目标

### 当前状态 (Monolith)
```
Client
  ↓
[user-service (单体)]
├── /users, /auth (核心用户管理)
├── /posts, /comments, /stories (内容)
├── /videos, /uploads, /reels (媒体)
└── /feed, /trending, /discover (推荐)
```

### 目标状态 (Microservices)
```
Clients
  ↓
[API Gateway - Kong/Nginx]
  ├── /api/v1/users/* → user-service
  ├── /api/v1/auth/* → user-service
  ├── /api/v1/posts/* → content-service
  ├── /api/v1/comments/* → content-service
  ├── /api/v1/stories/* → content-service
  ├── /api/v1/videos/* → media-service
  ├── /api/v1/uploads/* → media-service
  ├── /api/v1/reels/* → media-service
  ├── /api/v1/feed/* → user-service (聚合)
  ├── /api/v1/trending/* → user-service (聚合)
  └── /api/v1/discover/* → user-service (聚合)
```

---

## 服务分离计划

### Phase 1: API Gateway Setup (Week 1)
- ✅ API Gateway 设计 (当前)
- [ ] 选择网关实现 (Kong vs Nginx)
- [ ] 配置路由规则
- [ ] 设置负载均衡
- [ ] 部署并验证路由正确性

### Phase 2: Service Extraction (Weeks 2-4)
- [ ] **content-service** 提取
  - 从 user-service 移出: posts, comments, stories
  - 共享依赖: PostgreSQL, Redis, Kafka
  - 独立数据表和缓存命名空间

- [ ] **media-service** 提取
  - 从 user-service 移出: videos, uploads, reels
  - 共享依赖: S3, Kafka, ClickHouse
  - 独立内容处理流程

- [ ] **user-service** 精简
  - 保留: users, auth, social graph
  - 引入: gRPC 客户端调用 content-service 和 media-service

### Phase 3: Inter-service Communication (Weeks 5-6)
- [ ] 实现 gRPC 服务定义
- [ ] 替换同步 HTTP 调用
- [ ] 优雅降级和断路器集成

---

## API Gateway 选择

### Kong vs Nginx

| 特性 | Kong | Nginx |
|------|------|-------|
| **类型** | API Gateway (完整) | Reverse Proxy (轻量) |
| **插件系统** | 丰富 (auth, rate-limit, logging) | 需要 Lua 扩展 |
| **性能** | 中等 (~50k RPS) | 高 (~200k+ RPS) |
| **运维** | 复杂但功能齐全 | 简单 |
| **学习曲线** | 陡峭 | 温和 |
| **成本** | 开源 + 企业版 | 完全免费 |

**推荐**: **Nginx** (初期)
- 原因: 快速部署，满足现阶段需求
- 升级路径: Kong 可随时替代

---

## Nginx 配置方案

### 服务发现模式

```nginx
# nginx.conf - 上游服务定义
upstream user_service {
    least_conn;  # 最少连接算法
    server user-service:8080 weight=10;
    keepalive 32;
}

upstream content_service {
    least_conn;
    server content-service:8080 weight=10;
    keepalive 32;
}

upstream media_service {
    least_conn;
    server media-service:8080 weight=10;
    keepalive 32;
}
```

### 路由配置

```nginx
# /api/v1/users/* → user-service
location ~ ^/api/v1/users/(.*)$ {
    proxy_pass http://user_service;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Real-IP $remote_addr;
}

# /api/v1/auth/* → user-service
location ~ ^/api/v1/auth/(.*)$ {
    proxy_pass http://user_service;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
}

# /api/v1/posts/* → content-service
location ~ ^/api/v1/posts/(.*)$ {
    proxy_pass http://content_service;
}

# /api/v1/comments/* → content-service
location ~ ^/api/v1/comments/(.*)$ {
    proxy_pass http://content_service;
}

# /api/v1/videos/* → media-service
location ~ ^/api/v1/videos/(.*)$ {
    proxy_pass http://media_service;
}

# /api/v1/uploads/* → media-service
location ~ ^/api/v1/uploads/(.*)$ {
    proxy_pass http://media_service;
}

# /api/v1/reels/* → media-service
location ~ ^/api/v1/reels/(.*)$ {
    proxy_pass http://media_service;
}

# Feed endpoints remain in user-service (聚合多个服务)
location ~ ^/api/v1/feed/(.*)$ {
    proxy_pass http://user_service;
}
```

---

## 关键特性实现

### 1. 负载均衡
```nginx
# 上游配置支持多个实例
upstream user_service {
    least_conn;
    server user-service-1:8080 weight=10;
    server user-service-2:8080 weight=10;
    server user-service-3:8080 weight=10;
    keepalive 32;  # 连接复用
}
```

### 2. 请求头传递
```nginx
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Request-ID $request_id;  # 追踪ID
```

### 3. 超时和重试
```nginx
proxy_connect_timeout 10s;
proxy_send_timeout 30s;
proxy_read_timeout 30s;
proxy_buffering on;
proxy_buffer_size 4k;
```

### 4. 限流 (简单实现)
```nginx
# 基于 IP 地址限流: 每秒 10 请求
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;

location ~ ^/api/v1/ {
    limit_req zone=api_limit burst=20 nodelay;
    proxy_pass http://user_service;
}
```

---

## Kubernetes 部署

### 配置文件结构
```
k8s/
├── api-gateway/
│   ├── namespace.yaml
│   ├── configmap-nginx.yaml        # Nginx 配置
│   ├── deployment.yaml              # API Gateway Pod
│   ├── service.yaml                 # 暴露 API Gateway
│   └── ingress.yaml                 # 外部入口 (可选)
```

### ConfigMap - nginx.conf
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
  namespace: nova-services
data:
  nginx.conf: |
    worker_processes auto;
    events {
      worker_connections 1024;
    }
    http {
      # 上游定义
      upstream user_service { ... }
      upstream content_service { ... }
      upstream media_service { ... }

      # 速率限制
      limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;

      # 日志格式
      log_format api_log '$remote_addr - $remote_user [$time_local] '
                         '"$request" $status $body_bytes_sent '
                         '"$http_referer" "$http_user_agent" '
                         'rt=$request_time uct="$upstream_connect_time" '
                         'uht="$upstream_header_time" urt="$upstream_response_time"';

      access_log /var/log/nginx/access.log api_log;

      server {
        listen 80;
        server_name _;

        # 健康检查端点
        location /health {
          return 200 "OK\n";
          access_log off;
        }

        # API 路由 (如上所示)
        location ~ ^/api/v1/users/(.*)$ { ... }
        location ~ ^/api/v1/posts/(.*)$ { ... }
        # ... 更多路由
      }
    }
```

### Deployment
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway
  namespace: nova-services
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api-gateway
  template:
    metadata:
      labels:
        app: api-gateway
    spec:
      containers:
      - name: nginx
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/nginx.conf
          subPath: nginx.conf
        - name: nginx-logs
          mountPath: /var/log/nginx
        resources:
          requests:
            cpu: 500m
            memory: 256Mi
          limits:
            cpu: 2000m
            memory: 512Mi
        livenessProbe:
          httpGet:
            path: /health
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: nginx-config
        configMap:
          name: nginx-config
      - name: nginx-logs
        emptyDir: {}
```

### Service
```yaml
apiVersion: v1
kind: Service
metadata:
  name: api-gateway
  namespace: nova-services
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
  selector:
    app: api-gateway
```

---

## 迁移策略

### 第 1 步: 并行部署
- API Gateway 与单体 user-service 并行运行
- API Gateway 将所有请求转发给 user-service
- 零停机时间

### 第 2 步: 部分路由转移
- content-service 部署后，路由 POST/COMMENT/STORY 请求
- 其他请求仍然转发给 user-service
- 通过 Circuit Breaker 保证容错

### 第 3 步: 完整分离
- 所有三个微服务部署完成
- API Gateway 路由所有请求到正确的服务
- 删除单体服务

### 第 4 步: gRPC 优化 (可选)
- 实现 gRPC 服务间通信
- 替换 HTTP 调用 (feed、trending、discover 聚合)
- 性能和类型安全改进

---

## 性能指标

### 预期改进

| 指标 | 单体 | 网关后 | 改进 |
|------|------|--------|------|
| **延迟 (P95)** | 300ms | 250ms | 17% ↓ |
| **吞吐量** | 500 RPS | 1500 RPS | 3x ↑ |
| **错误率** | 0.5% | 0.1% | 5x ↓ |

*假设: 内容和媒体服务将负载均分*

---

## 后续步骤

1. ✅ **设计 API Gateway** (当前)
2. [ ] **实现 Nginx 配置**
3. [ ] **部署到 Kubernetes**
4. [ ] **验证路由正确性** (端到端测试)
5. [ ] **监控和日志集成**
6. [ ] **启动 content-service 提取**

---

## 参考资源

- [Nginx 官方文档](https://nginx.org/en/docs/)
- [Kubernetes Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Kong API Gateway](https://konghq.com/) (未来升级选项)
- [gRPC 文档](https://grpc.io/docs/) (Phase 3)
