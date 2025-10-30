# 可选增强部署指南

本指南涵盖Nova消息服务的四个可选增强功能，可以在核心部署之后逐步添加。

## 📋 可选增强清单

| 增强 | 文件 | 用途 | 难度 | 优先级 |
|------|------|------|------|--------|
| **TURN服务器** | `turn-server-deployment.yaml` | WebRTC NAT穿透 | 中等 | ⭐⭐⭐ 高 |
| **Ingress + TLS** | `ingress-tls-setup.yaml` | HTTPS入口 | 中等 | ⭐⭐⭐ 高 |
| **Prometheus监控** | `prometheus-monitoring-setup.yaml` | 指标收集告警 | 简单 | ⭐⭐ 中 |
| **GitOps CI/CD** | `gitops-argocd-setup.yaml` | 自动部署 | 复杂 | ⭐ 低 |

---

## 1. 🎯 TURN服务器部署 (视频通话优化)

### 什么是TURN服务器？

TURN (Traversal Using Relays around NAT) 服务器帮助WebRTC连接穿越防火墙和NAT，对于视频通话至关重要。

### 何时需要
✅ **必需** (如果启用视频通话功能)
❌ 仅用于测试时可选

### 前置要求
- 公网IP或域名
- 开放端口: 3478/UDP, 3479/UDP, 3478/TCP
- 1-2Gi 内存

### 部署步骤

#### Step 1: 获取公网IP
```bash
# 如果使用云提供商的LoadBalancer
kubectl get svc turn-server -n nova-turn

# 记录EXTERNAL-IP
TURN_IP="x.x.x.x"
```

#### Step 2: 编辑配置
```bash
# 编辑Secret，设置外部IP
kubectl edit secret turn-server-secret -n nova-turn

# 更新以下字段:
# TURN_USER: "nova"
# TURN_PASSWORD: "secure-password-here"
# REALM: "turn.nova.local"
# EXTERNAL_IP: "x.x.x.x"  ← 你的公网IP
```

#### Step 3: 部署
```bash
kubectl apply -f turn-server-deployment.yaml
```

#### Step 4: 验证
```bash
# 检查Pod
kubectl get pods -n nova-turn -w

# 检查服务
kubectl get svc -n nova-turn

# 测试STUN (需要stunclient工具)
apt-get install stun-client
stunclient <EXTERNAL-IP> 3478
```

#### Step 5: 配置iOS客户端
在iOS应用中配置TURN服务器:

```swift
// WebRTCConfig.swift
let configuration = RTCConfiguration()
let iceServer = RTCIceServer(
    urls: ["turn:nova:password@x.x.x.x:3478"],
    username: "nova",
    credential: "password"
)
configuration.iceServers = [iceServer]
```

### 📊 配置参考
```yaml
监听端口:     3478 (STUN/TURN)
备用端口:     3479 (可选)
协议:         UDP, TCP
并发连接:     取决于资源限制
带宽限制:     1Mbps (可调整)
```

### ⚠️ 故障排查

```bash
# 查看日志
kubectl logs -f -l component=turn-server -n nova-turn

# 常见问题:
# 1. 连接超时 → 检查防火墙规则
# 2. 认证失败 → 检查用户名/密码
# 3. 高内存使用 → 减少max-bps或连接限制
```

---

## 2. 🔒 Ingress + TLS部署 (HTTPS入口)

### 什么是Ingress？

Ingress 是Kubernetes的HTTP(S)入口控制器，提供:
- HTTPS加密
- 域名路由
- 速率限制
- 安全头

### 何时需要
✅ **推荐** (用于生产环境)
⚠️ 本地开发可选

### 前置要求
- Nginx Ingress Controller
- TLS证书 (自签名或Let's Encrypt)
- 域名 (或/etc/hosts条目)

### 部署步骤

#### Step 1: 安装Nginx Ingress Controller
```bash
# 使用Helm
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer
```

#### Step 2: 生成/获取TLS证书

**自签名证书 (开发用)**:
```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /tmp/tls.key \
  -out /tmp/tls.crt \
  -subj "/CN=api.nova.local"

kubectl create secret tls nova-tls-cert \
  --cert=/tmp/tls.crt \
  --key=/tmp/tls.key \
  -n nova-messaging
```

**Let's Encrypt (生产用)**:
```bash
# 安装cert-manager
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager -n cert-manager --create-namespace

# 在Ingress上添加注解:
# cert-manager.io/cluster-issuer: "letsencrypt-prod"
```

#### Step 3: 编辑配置
```bash
# 编辑Ingress，更新你的域名
kubectl edit ingress messaging-service-ingress -n nova-messaging

# 更新:
# - hosts: api.nova.com
# - email: admin@nova.com
```

#### Step 4: 部署
```bash
kubectl apply -f ingress-tls-setup.yaml
```

#### Step 5: 验证
```bash
# 检查Ingress
kubectl get ingress -n nova-messaging

# 获取IP地址
INGRESS_IP=$(kubectl get ingress messaging-service-ingress -n nova-messaging \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# 测试HTTPS (忽略证书警告)
curl -k https://api.nova.local/health

# 或更新/etc/hosts
echo "$INGRESS_IP api.nova.local" | sudo tee -a /etc/hosts
curl https://api.nova.local/health
```

### 📊 配置参考
```yaml
入口类型:      Nginx
HTTPS:        启用
速率限制:      100 RPS
连接限制:      10 per IP
WebSocket:     支持 (3600s超时)
CORS:          启用
安全头:        完整
```

### 常用命令
```bash
# 检查证书
kubectl get secret nova-tls-cert -n nova-messaging -o yaml

# 查看Ingress详情
kubectl describe ingress messaging-service-ingress -n nova-messaging

# 端口转发 (如果没有LoadBalancer)
kubectl port-forward svc/ingress-nginx-controller 443:443 -n ingress-nginx
```

---

## 3. 📊 Prometheus监控部署 (指标和告警)

### 什么是Prometheus？

Prometheus 是开源的监控和告警系统，能够:
- 收集应用指标
- 存储时间序列数据
- 评估告警规则
- 与Alertmanager集成

### 何时需要
✅ **推荐** (用于生产环境)
⚠️ 开发环境可选

### 前置要求
- Kubernetes 1.24+
- 2GB可用内存

### 部署步骤

#### Step 1: 部署
```bash
kubectl apply -f prometheus-monitoring-setup.yaml

# 等待Pod就绪
kubectl get pods -n nova-monitoring -w
```

#### Step 2: 访问Prometheus UI
```bash
# 端口转发
kubectl port-forward svc/prometheus 9090:9090 -n nova-monitoring

# 打开浏览器
http://localhost:9090
```

#### Step 3: 验证数据收集
```bash
# 在Prometheus UI中执行查询
rate(http_requests_total[5m])
container_memory_usage_bytes{pod=~"messaging-service-.*"}
```

#### Step 4: 配置告警通知

**Slack通知**:
```bash
# 编辑alertmanager配置
kubectl edit configmap alertmanager-config -n nova-monitoring

# 添加Slack webhook:
# slack_configs:
#   - api_url: https://hooks.slack.com/services/YOUR/WEBHOOK/URL
#     channel: '#alerts'
```

**Email通知**:
```bash
# 编辑alertmanager配置
# email_configs:
#   - to: 'admin@nova.com'
#     from: 'alerts@nova.com'
#     smarthost: 'smtp.example.com:587'
```

#### Step 5: 访问Alertmanager
```bash
# 端口转发
kubectl port-forward svc/alertmanager 9093:9093 -n nova-monitoring

# 打开浏览器
http://localhost:9093
```

### 📊 主要指标
```
HTTP请求:
  - http_requests_total: 总请求数
  - http_request_duration_seconds: 请求延迟

WebSocket:
  - websocket_connections_active: 活跃连接数
  - websocket_errors_total: 错误计数

数据库:
  - database_query_duration_seconds: 查询延迟
  - database_errors_total: 错误计数

系统:
  - container_memory_usage_bytes: 内存使用
  - container_cpu_usage_seconds_total: CPU使用
```

### 可选: 安装Grafana仪表板
```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm install grafana grafana/grafana -n nova-monitoring \
  --set adminPassword=admin \
  --set persistence.enabled=true \
  --set persistence.size=10Gi
```

---

## 4. 🚀 GitOps CI/CD部署 (自动化部署)

### 什么是GitOps？

GitOps 使用Git作为真实源，自动同步集群状态与Git仓库。

**优点**:
- 声明式部署
- 自动化同步
- 易于审计和回滚
- 减少手动操作

### 何时需要
❌ **可选** (适合大型团队)
⚠️ 小团队可以跳过

### 前置要求
- 已有GitHub/GitLab仓库
- GitHub Personal Access Token
- ArgoCD或Flux CD

### 部署步骤

#### Step 1: 安装ArgoCD
```bash
# 创建命名空间
kubectl create namespace argocd

# 安装ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 等待就绪
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
```

#### Step 2: 配置Git仓库访问
```bash
# 获取GitHub Token
# https://github.com/settings/tokens

# 创建Secret
kubectl create secret generic nova-repo-credentials \
  --from-literal=username=git \
  --from-literal=password=<your-github-token> \
  -n argocd
```

#### Step 3: 部署
```bash
kubectl apply -f gitops-argocd-setup.yaml
```

#### Step 4: 访问ArgoCD UI
```bash
# 端口转发
kubectl port-forward svc/argocd-server -n argocd 8080:443

# 获取密码
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

echo "ArgoCD URL: https://localhost:8080"
echo "Username: admin"
echo "Password: $ARGOCD_PASSWORD"
```

#### Step 5: GitHub Webhook (自动同步)
```bash
# 1. 获取ArgoCD webhook URL
WEBHOOK_URL="https://your-argocd-domain/api/webhook"

# 2. 在GitHub中添加:
# Repo Settings → Webhooks → Add webhook
# Payload URL: $WEBHOOK_URL
# Content type: application/json
# Events: Push events
```

#### Step 6: 手动同步
```bash
# 查看应用
argocd app list

# 同步应用
argocd app sync messaging-service

# 监控同步进度
argocd app get messaging-service
argocd app logs messaging-service

# 回滚到上一个版本
argocd app rollback messaging-service
```

### 📊 GitOps工作流
```
1. 开发者 → 提交代码到Git
   ↓
2. GitHub Actions → 构建镜像，推送到仓库
   ↓
3. Git Webhook → 触发ArgoCD同步
   ↓
4. ArgoCD → 自动部署到K8s
   ↓
5. Kubernetes → 滚动更新Pod
   ↓
6. 完成 → 新版本上线
```

---

## 🔀 部署顺序建议

### 第1阶段 (必需 - 第1天)
```
✅ 消息服务核心部署
```

### 第2阶段 (高优先 - 第1-2周)
```
1️⃣ 部署Ingress + TLS
   └─ 启用HTTPS访问

2️⃣ 部署TURN服务器
   └─ 启用视频通话
```

### 第3阶段 (中优先 - 第2-4周)
```
1️⃣ 部署Prometheus监控
   └─ 启用指标收集和告警
```

### 第4阶段 (可选 - 第4周+)
```
1️⃣ 部署GitOps (ArgoCD)
   └─ 自动化CI/CD流程
```

---

## 🔄 配置协议

### 所有配置中的TODO项

搜索并更新所有 `TODO:` 注释:

```bash
# 搜索所有TODO
grep -r "TODO:" backend/k8s/*.yaml

# 必须更新的内容:
TURN_PASSWORD           # TURN服务器密码
EXTERNAL_IP            # 公网IP或域名
api.nova.com           # 你的域名
admin@nova.com         # 管理员邮箱
your-org/nova.git      # GitHub仓库URL
your-github-token      # GitHub Personal Access Token
```

---

## 📊 成本估算

| 增强 | 资源 | 月成本 (AWS) |
|------|------|------------|
| **TURN服务器** | t3.medium + 10GB流量 | $30-50 |
| **Ingress + LB** | 1 LoadBalancer | $16 |
| **Prometheus** | t3.small + 100GB存储 | $20-30 |
| **GitOps** | 基础设施内 | $0 (额外) |
| **总计** | | $66-96 |

---

## ✅ 完成检查

### Ingress + TLS验证
```bash
curl -k https://api.nova.local/health
# 应返回: {"status":"ok"}
```

### TURN服务器验证
```bash
# iOS客户端测试视频通话
# 应该能够建立P2P连接
```

### Prometheus验证
```bash
# 访问 http://localhost:9090
# 验证消息服务指标在采集
```

### GitOps验证
```bash
argocd app get messaging-service
# 状态应该是 "Synced"
```

---

## 🚀 后续步骤

✅ 完成可选增强
→ 配置备份和灾难恢复
→ 设置成本监控和优化
→ 规划高可用性策略

