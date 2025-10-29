# API Gateway 路由配置

本文档说明如何在 API Gateway 中配置路由，以将客户端请求转发到相应的微服务。

## 架构概览

```
                        ┌─────────────────┐
                        │  客户端/前端     │
                        └────────┬─────────┘
                                 │
                                 ▼
                        ┌─────────────────┐
                        │  API Gateway    │
                        │ (端口 80/443)   │
                        └────┬────────┬───┘
                             │        │
                ┌────────────┘        └──────────────┐
                │                                    │
                ▼                                    ▼
        ┌──────────────────┐            ┌──────────────────┐
        │ Content Service  │            │  Media Service   │
        │  (端口 8081)     │            │   (端口 8082)    │
        │  posts, stories  │            │ uploads, videos  │
        └──────────────────┘            └──────────────────┘
```

## 路由配置表

### Content Service (8081)

| 优先级 | 路径模式 | 目标服务 | 方法 | 说明 |
|-------|---------|--------|------|------|
| 1 | `/api/v1/posts*` | content-service:8081 | ALL | 贴文 CRUD |
| 2 | `/api/v1/stories*` | content-service:8081 | ALL | 故事 CRUD |
| 3 | `/api/v1/feed` | content-service:8081 | GET | 信息流 |
| 4 | `/api/v1/openapi.json` | content-service:8081 | GET | OpenAPI 文档 |
| 5 | `/api/v1/health*` | content-service:8081 | GET | 健康检查 |

### Media Service (8082)

| 优先级 | 路径模式 | 目标服务 | 方法 | 说明 |
|-------|---------|--------|------|------|
| 1 | `/api/v1/uploads*` | media-service:8082 | ALL | 文件上传 |
| 2 | `/api/v1/videos*` | media-service:8082 | ALL | 视频 CRUD |
| 3 | `/api/v1/reels*` | media-service:8082 | ALL | Reel CRUD |
| 4 | `/api/v1/openapi.json` | media-service:8082 | GET | OpenAPI 文档 |
| 5 | `/api/v1/health*` | media-service:8082 | GET | 健康检查 |

## 实现示例

### 1. Nginx 配置

```nginx
upstream content_service {
    server localhost:8081;
    keepalive 32;
}

upstream media_service {
    server localhost:8082;
    keepalive 32;
}

server {
    listen 80;
    server_name api.nova.local;

    # Content Service 路由
    location ~ ^/api/v1/(posts|stories|feed)(/|$) {
        proxy_pass http://content_service;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Media Service 路由
    location ~ ^/api/v1/(uploads|videos|reels)(/|$) {
        proxy_pass http://media_service;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # 上传文件需要更大的超时
        proxy_connect_timeout 60s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }

    # OpenAPI 文档 - 从 content-service 代理
    location = /api/v1/openapi.json {
        proxy_pass http://content_service;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
    }

    # 健康检查
    location /api/v1/health {
        access_log off;
        proxy_pass http://content_service;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
    }
}
```

### 2. Kubernetes Ingress 配置

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nova-api-ingress
  namespace: nova
spec:
  ingressClassName: nginx
  rules:
    - host: api.nova.local
      http:
        paths:
          # Content Service
          - path: /api/v1/posts
            pathType: Prefix
            backend:
              service:
                name: content-service
                port:
                  number: 8081

          - path: /api/v1/stories
            pathType: Prefix
            backend:
              service:
                name: content-service
                port:
                  number: 8081

          - path: /api/v1/feed
            pathType: Prefix
            backend:
              service:
                name: content-service
                port:
                  number: 8081

          # Media Service
          - path: /api/v1/uploads
            pathType: Prefix
            backend:
              service:
                name: media-service
                port:
                  number: 8082

          - path: /api/v1/videos
            pathType: Prefix
            backend:
              service:
                name: media-service
                port:
                  number: 8082

          - path: /api/v1/reels
            pathType: Prefix
            backend:
              service:
                name: media-service
                port:
                  number: 8082

          # Health checks
          - path: /api/v1/health
            pathType: Prefix
            backend:
              service:
                name: content-service
                port:
                  number: 8081
```

### 3. AWS API Gateway 配置

**使用 CloudFormation 或 Terraform：**

```yaml
# 创建两个 VPC Link（每个后端服务一个）
ContentServiceVPCLink:
  Type: AWS::ApiGateway::VpcLink
  Properties:
    Name: content-service-vpc-link
    TargetArns:
      - arn:aws:elasticloadbalancing:region:account:targetgroup/content-service/...

MediaServiceVPCLink:
  Type: AWS::ApiGateway::VpcLink
  Properties:
    Name: media-service-vpc-link
    TargetArns:
      - arn:aws:elasticloadbalancing:region:account:targetgroup/media-service/...

# 创建资源和方法
PostsResource:
  Type: AWS::ApiGateway::Resource
  Properties:
    ParentId: !GetAtt ApiGateway.RootResourceId
    PathPart: posts
    RestApiId: !Ref ApiGateway

PostsMethod:
  Type: AWS::ApiGateway::Method
  Properties:
    AuthorizationType: AWS_IAM
    HttpMethod: ANY
    ResourceId: !Ref PostsResource
    RestApiId: !Ref ApiGateway
    Integration:
      Type: HTTP_PROXY
      IntegrationHttpMethod: ANY
      Uri: http://content-service:8081/api/v1/posts
      VpcLinkId: !Ref ContentServiceVPCLink
```

### 4. Kong API Gateway 配置

```bash
# 添加 upstream
curl -X POST http://localhost:8001/upstreams \
  -d "name=content-service"

curl -X POST http://localhost:8001/upstreams \
  -d "name=media-service"

# 添加 targets
curl -X POST http://localhost:8001/upstreams/content-service/targets \
  -d "target=localhost:8081"

curl -X POST http://localhost:8001/upstreams/media-service/targets \
  -d "target=localhost:8082"

# 添加服务
curl -X POST http://localhost:8001/services \
  -d "name=content-service" \
  -d "host=content-service" \
  -d "port=8081"

curl -X POST http://localhost:8001/services \
  -d "name=media-service" \
  -d "host=media-service" \
  -d "port=8082"

# 添加路由
curl -X POST http://localhost:8001/services/content-service/routes \
  -d "paths[]=/api/v1/posts" \
  -d "paths[]=/api/v1/stories" \
  -d "paths[]=/api/v1/feed"

curl -X POST http://localhost:8001/services/media-service/routes \
  -d "paths[]=/api/v1/uploads" \
  -d "paths[]=/api/v1/videos" \
  -d "paths[]=/api/v1/reels"
```

## 测试路由

### 使用 curl 测试

```bash
# 测试 Content Service 路由
curl -i http://localhost/api/v1/posts \
  -H "Authorization: Bearer YOUR_TOKEN"

# 测试 Media Service 路由
curl -i http://localhost/api/v1/uploads \
  -H "Authorization: Bearer YOUR_TOKEN"

# 检查 routing 是否正确
curl -i http://localhost/api/v1/health
```

### 监控和日志

**Nginx：**
```bash
# 查看访问日志
tail -f /var/log/nginx/access.log | grep "/api/v1"

# 查看错误日志
tail -f /var/log/nginx/error.log
```

**Kubernetes：**
```bash
# 查看 Ingress 状态
kubectl get ingress -n nova

# 查看 Ingress 详情
kubectl describe ingress nova-api-ingress -n nova

# 查看微服务 Pod
kubectl get pods -n nova -l app=content-service
kubectl get pods -n nova -l app=media-service
```

## 性能优化建议

### 1. 连接池
- Nginx: `keepalive 32` - 保持连接
- Kong: 默认已启用
- AWS ALB: 自动管理

### 2. 超时配置

```nginx
# 普通请求：30秒
proxy_connect_timeout 30s;
proxy_send_timeout 30s;
proxy_read_timeout 30s;

# 上传请求：5分钟
location ~ ^/api/v1/uploads {
    proxy_connect_timeout 60s;
    proxy_send_timeout 300s;
    proxy_read_timeout 300s;
}
```

### 3. 缓存策略

```nginx
# 缓存不可变的响应
location ~ ^/api/v1/posts/[a-f0-9-]+$ {
    proxy_cache_valid 200 1h;
    proxy_cache_key "$scheme$request_method$host$request_uri";
    add_header X-Cache-Status $upstream_cache_status;
}
```

### 4. 速率限制

```nginx
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=100r/s;

location ~ ^/api/v1/ {
    limit_req zone=api_limit burst=200 nodelay;
    proxy_pass http://backend;
}
```

## 故障排除

### 502 Bad Gateway

**症状：** API Gateway 无法连接到后端服务

**原因检查：**
```bash
# 检查服务是否运行
curl http://localhost:8081/api/v1/health
curl http://localhost:8082/api/v1/health

# 检查网络连接
netstat -tlnp | grep -E ':(8081|8082)'

# 查看 Nginx 错误日志
tail -f /var/log/nginx/error.log
```

### 401 Unauthorized

**症状：** 请求被拒绝，显示未授权

**原因检查：**
```bash
# 验证 JWT token 格式
curl -H "Authorization: Bearer YOUR_TOKEN" http://localhost/api/v1/posts

# 检查 token 有效期
jwt decode YOUR_TOKEN
```

### 504 Gateway Timeout

**症状：** 请求超时

**原因检查：**
```bash
# 增加超时时间
# 对于上传特别需要增加

# 检查后端服务性能
curl http://localhost:8082/api/v1/uploads -v
```

## 部署检查清单

- [ ] 验证两个微服务都在运行
- [ ] 验证健康检查端点可访问
- [ ] 验证路由规则配置正确
- [ ] 测试所有 API 端点
- [ ] 配置超时和重试策略
- [ ] 启用日志和监控
- [ ] 配置速率限制
- [ ] 设置 TLS/SSL（生产环境）
- [ ] 配置 CORS 策略
- [ ] 验证 JWT 认证正常工作

## 参考资源

- [Nginx 反向代理文档](https://nginx.org/en/docs/http/ngx_http_upstream_module.html)
- [Kubernetes Ingress 文档](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Kong API Gateway 文档](https://docs.konghq.com/)
- [AWS API Gateway 文档](https://docs.aws.amazon.com/apigateway/)
