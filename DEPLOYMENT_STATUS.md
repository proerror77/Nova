# Nova 项目部署状态

**最后更新**: 2025-11-10
**环境**: AWS EKS (ap-northeast-1)
**集群**: nova-staging

## 当前架构

```
                         ┌─────────────────┐
                         │   AWS EKS       │
                         │   VPC:          │
                         │   vpc-008612..  │
                         └────────┬────────┘
                                  │
         ┌────────────────────────┼────────────────────────┐
         │                        │                        │
    ┌────▼─────┐            ┌────▼─────┐           ┌─────▼────┐
    │  Public  │            │  Public  │           │ Private  │
    │  Subnet  │            │  Subnet  │           │ Subnets  │
    │  1a      │            │  1c      │           │ (Nodes)  │
    └──────────┘            └──────────┘           └─────┬────┘
         │                        │                       │
    NAT Gateway            NAT Gateway              ┌────▼────┐
         │                        │                 │  EKS    │
         └────────────────────────┘                 │  Nodes  │
                                                    └─────┬───┘
                                                          │
                                              ┌───────────┴───────────┐
                                              │                       │
                                         ┌────▼─────┐          ┌─────▼────┐
                                         │  Nginx   │          │  微服务   │
                                         │ Ingress  │          │          │
                                         │ NodePort │          │ Pods     │
                                         │ 31742    │          │          │
                                         └──────────┘          └──────────┘
```

## 部署组件状态

### ✅ 已完成

| 组件 | 状态 | 备注 |
|------|------|------|
| EKS 集群 | 运行中 | nova-staging, Kubernetes v1.28 |
| Nginx Ingress | 运行中 | NodePort 模式 (31742/31894) |
| AWS LB Controller | 运行中 | 已配置 IAM 角色和 OIDC |
| user-service | 运行中 | 3 replicas |
| messaging-service | 运行中 | 3 replicas |
| notification-service | 运行中 | 3 replicas |
| events-service | 运行中 | 3 replicas |
| cdn-service | 运行中 | 3 replicas |

### ⚠️  待解决

| 问题 | 影响 | 解决方案 |
|------|------|----------|
| AWS 负载均衡器配额 | 无法创建 ALB | 联系 AWS Support |
| 缺少公网入口 | API 无法从外部访问 | 需要 ALB 或替代方案 |
| GraphQL Gateway 镜像 | Gateway 未部署 | Docker build 超时 |

### 📋 待部署

- [ ] GraphQL Gateway
  - Docker 镜像未构建
  - Kubernetes manifests 已创建
  - 需要网络稳定后推送到 ECR

## 网络配置

### VPC
- **VPC ID**: vpc-008612ead90beedd8
- **CIDR**: 10.0.0.0/16
- **区域**: ap-northeast-1 (Tokyo)

### 子网

| 子网 | 类型 | AZ | CIDR | 标签 |
|------|------|----|----|------|
| subnet-0e8636c9ff0a73b49 | 公有 | 1a | 10.0.0.0/24 | kubernetes.io/role/elb=1 |
| subnet-0d5563a0c714075b5 | 公有 | 1c | 10.0.1.0/24 | kubernetes.io/role/elb=1 |
| subnet-0435b89dbfb0a8a28 | 私有 | 1a | 10.0.10.0/24 | kubernetes.io/role/internal-elb=1 |
| subnet-00d61e9dcc25ac174 | 私有 | 1c | 10.0.11.0/24 | kubernetes.io/role/internal-elb=1 |

### NAT Gateways

- **NAT-1a**: nat-0279b20012558c112 (57.181.95.174)
- **NAT-1c**: nat-01ce9f3f3d3d27643 (18.180.233.22)

### 安全组

- **节点安全组**: sg-023b3e44998ff4a20
  - 已开放: 31742 (HTTP NodePort)
  - 已开放: 31894 (HTTPS NodePort)

## IAM 配置

### OIDC Provider
- **ARN**: arn:aws:iam::025434362120:oidc-provider/oidc.eks.ap-northeast-1.amazonaws.com/id/E755641A287E7B09B6053CB28057CAD9

### IAM 角色

| 角色 | ARN | 用途 |
|------|-----|------|
| AmazonEKSLoadBalancerControllerRole | arn:aws:iam::025434362120:role/AmazonEKSLoadBalancerControllerRole | AWS LB Controller |
| nova-staging-eks-node-group-role | - | EKS 节点 |

### IAM 策略

- **AWSLoadBalancerControllerIAMPolicy**: arn:aws:iam::025434362120:policy/AWSLoadBalancerControllerIAMPolicy

## 服务端点

### 当前可用（内部）

```yaml
Auth Service:         http://auth-service.nova-auth.svc.cluster.local:50051
User Service:         http://user-service.nova.svc.cluster.local:9052
Content Service:      http://content-service.nova-content.svc.cluster.local:50053
Messaging Service:    http://messaging-service.nova-backend.svc.cluster.local:9085
Notification Service: http://notification-service.nova-backend.svc.cluster.local:9088
Feed Service:         http://feed-service.nova-feed.svc.cluster.local:50056
```

### 临时访问方式

```bash
# 使用 kubectl port-forward
kubectl port-forward -n nova svc/user-service 8080:8080

# 访问地址
curl http://localhost:8080/health
```

## AWS 配额问题详情

### 错误信息
```
OperationNotPermitted: This AWS account currently does not support creating load balancers.
status code: 400
```

### 影响范围
- 无法创建 Application Load Balancer (ALB)
- 无法创建 Classic Load Balancer (CLB)
- 无法通过 LoadBalancer Service 类型暴露服务

### 解决步骤

1. **联系 AWS Support**
   - 登录 AWS Console
   - 访问 Support Center
   - 创建 "Service Limit Increase" case
   - 选择 "Elastic Load Balancing"
   - 请求增加以下配额:
     - Application Load Balancers: 至少 5
     - Classic Load Balancers: 至少 2
   - 说明用途: Production EKS microservices architecture

2. **监控配额请求**
   - 通常 1-2 个工作日内处理
   - 通过 email 和 Support case 跟踪进度

## 后续步骤

### 短期（1-2天）

1. **解决 AWS 配额限制**
   - [ ] 提交 AWS Support case
   - [ ] 等待配额提升
   - [ ] 测试 ALB 创建

2. **部署 GraphQL Gateway**
   - [ ] 在稳定网络环境构建 Docker 镜像
   - [ ] 推送镜像到 ECR
   - [ ] 应用 Kubernetes manifests
   - [ ] 测试 Gateway 功能

### 中期（1周）

3. **配置域名和 SSL**
   - [ ] 获取或配置域名 (api.nova.social)
   - [ ] 使用 cert-manager 配置 Let's Encrypt
   - [ ] 配置 HTTPS

4. **iOS 应用集成**
   - [ ] 更新 Config.swift 中的 API endpoint
   - [ ] 测试 iOS 应用与生产 API 的连接
   - [ ] 验证所有 API 调用

### 长期

5. **监控和优化**
   - [ ] 配置 CloudWatch/Prometheus
   - [ ] 设置告警
   - [ ] 性能优化

6. **CI/CD 配置**
   - [ ] GitHub Actions 或 AWS CodePipeline
   - [ ] 自动化部署流程

## 故障排查命令

```bash
# 检查集群状态
kubectl get nodes
kubectl get pods --all-namespaces

# 检查 Ingress
kubectl get ingress -n nova
kubectl describe ingress nova-api-temp -n nova

# 检查 AWS LB Controller
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# 检查服务
kubectl get svc -n nova
kubectl describe svc user-service -n nova

# Port forward 测试
kubectl port-forward -n nova svc/user-service 8080:8080
```

## 配置文件位置

```
k8s/
├── graphql-gateway/
│   ├── deployment.yaml      # GraphQL Gateway Kubernetes 配置
│   └── ingress.yaml         # GraphQL Gateway Ingress
├── temp-user-service-ingress.yaml  # 临时 user-service Ingress
backend/
└── graphql-gateway/
    └── Dockerfile           # GraphQL Gateway Docker 配置
```

## 联系信息

- **AWS 账户**: 025434362120
- **区域**: ap-northeast-1
- **EKS 集群**: nova-staging
- **ECR 仓库**: 025434362120.dkr.ecr.ap-northeast-1.amazonaws.com/nova-*
