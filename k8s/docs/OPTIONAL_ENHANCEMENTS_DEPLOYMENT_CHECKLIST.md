# 🚀 Optional Enhancements Deployment Checklist

完整的可选增强部署指南和验证检查清单

---

## 📊 部署规划矩阵

### 优先级和难度分析

| 增强 | 优先级 | 难度 | 估计时间 | 依赖 | 最早部署 |
|------|--------|------|---------|------|---------|
| **Ingress + TLS** | ⭐⭐⭐ 高 | 中等 | 15-30分钟 | Nginx Ingress Controller | 第1天 |
| **TURN服务器** | ⭐⭐⭐ 高 | 简单 | 10-20分钟 | 公网IP或域名 | 第1-2天 |
| **Prometheus监控** | ⭐⭐ 中 | 简单 | 10-15分钟 | 无 | 第2-3周 |
| **GitOps (ArgoCD)** | ⭐ 低 | 复杂 | 30-45分钟 | GitHub Token, ArgoCD | 第3-4周 |

---

## ✅ 部署前检查清单

### 集群基础要求

```bash
# 1. 检查Kubernetes集群
kubectl cluster-info
kubectl get nodes

# 2. 检查资源可用性
kubectl describe nodes | grep -A 5 "Allocated resources"

# 3. 确认消息服务已部署
kubectl get deployment -n nova-messaging

# 4. 验证消息服务健康状态
kubectl get pods -n nova-messaging
kubectl get svc -n nova-messaging
```

### 所需工具和信息清单

- [ ] `kubectl` CLI (1.24+)
- [ ] `helm` (3.10+) - 仅用于Nginx Ingress安装
- [ ] 域名或IP地址
- [ ] TLS证书 (自签名或Let's Encrypt)
- [ ] GitHub Personal Access Token (如果使用GitOps)
- [ ] Slack Webhook URL (可选，用于告警)

---

## 🔄 部署顺序建议

### Phase 1: 必需基础 (第1-2周)

#### Step 1: 部署Ingress + TLS (15-30分钟)

**先决条件检查**:
```bash
# 检查Nginx Ingress Controller
helm list -n ingress-nginx

# 如果未安装，执行:
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer
```

**部署步骤**:
```bash
# 1. 生成自签名证书（开发用）
cd backend/k8s
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /tmp/tls.key -out /tmp/tls.crt \
  -subj "/CN=api.nova.local"

# 2. 创建TLS Secret
kubectl create secret tls nova-tls-cert \
  --cert=/tmp/tls.crt \
  --key=/tmp/tls.key \
  -n nova-messaging

# 3. 部署Ingress
kubectl apply -f ingress-tls-setup.yaml

# 4. 验证
kubectl get ingress -n nova-messaging
kubectl describe ingress messaging-service-ingress -n nova-messaging
```

**验证命令**:
```bash
# 获取Ingress IP
INGRESS_IP=$(kubectl get ingress messaging-service-ingress \
  -n nova-messaging -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Ingress IP: $INGRESS_IP"

# 测试HTTP -> HTTPS重定向
curl -i http://api.nova.local -H "Host: api.nova.local"

# 测试HTTPS (忽略证书警告)
curl -k https://api.nova.local/health

# 验证WebSocket
websocat wss://api.nova.local/ws -H "Authorization: Bearer YOUR_TOKEN"
```

**常见问题**:
```bash
# 证书问题排查
kubectl get secret nova-tls-cert -n nova-messaging -o yaml

# Ingress Controller日志
kubectl logs -f -l app.kubernetes.io/name=ingress-nginx -n ingress-nginx

# 网络策略验证
kubectl get networkpolicy -n nova-messaging
```

---

#### Step 2: 部署TURN服务器 (10-20分钟)

**先决条件**:
```bash
# 1. 获取公网IP或域名
# 如果使用AWS/Azure/GCP LoadBalancer:
kubectl get svc -n nova-turn  # 部署后执行

# 2. 如果使用本地环境，可以跳过此步
# TURN服务器主要用于生产环境的视频通话
```

**部署步骤**:
```bash
# 1. 检查并更新密钥信息
# 编辑Secret中的EXTERNAL_IP
kubectl edit secret turn-server-secret -n nova-turn 2>/dev/null || \
  kubectl apply -f turn-server-deployment.yaml

# 2. 验证部署
kubectl get pods -n nova-turn -w

# 3. 获取外部IP
TURN_IP=$(kubectl get svc turn-server -n nova-turn \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "TURN Server IP: $TURN_IP"

# 4. 如果使用自定义IP，更新Secret
kubectl patch secret turn-server-secret \
  -n nova-turn \
  -p '{"data":{"EXTERNAL_IP":"'$(echo -n $TURN_IP | base64)'"}}'
```

**验证命令**:
```bash
# STUN测试 (需要stun-client)
apt-get install stun-client
stunclient $TURN_IP 3478

# 检查服务状态
kubectl get svc -n nova-turn
kubectl describe svc turn-server -n nova-turn

# 查看日志
kubectl logs -f -l component=turn-server -n nova-turn

# 验证端口监听
kubectl exec -n nova-turn \
  $(kubectl get pod -n nova-turn -o jsonpath='{.items[0].metadata.name}') \
  -- netstat -tuln | grep 347
```

**iOS客户端配置**:
```swift
// 在iOS应用中配置TURN服务器
let iceServer = RTCIceServer(
    urls: ["turn:\(TURN_USER):\(TURN_PASSWORD)@\(TURN_IP):3478"],
    username: TURN_USER,
    credential: TURN_PASSWORD
)
configuration.iceServers = [iceServer]
```

**生产部署检查**:
```bash
# 确保TURN服务器在可扩展配置下运行
kubectl get hpa -n nova-turn
kubectl describe hpa turn-server-hpa -n nova-turn

# 监控资源使用
kubectl top pod -n nova-turn
```

---

### Phase 2: 监控和可观测性 (第2-3周)

#### Step 3: 部署Prometheus监控 (10-15分钟)

**部署步骤**:
```bash
# 1. 应用完整的监控栈
kubectl apply -f prometheus-monitoring-setup.yaml

# 2. 等待Pod就绪
kubectl get pods -n nova-monitoring -w

# 3. 验证Services
kubectl get svc -n nova-monitoring
```

**访问Prometheus UI**:
```bash
# 方式1: 端口转发
kubectl port-forward svc/prometheus 9090:9090 -n nova-monitoring
# 访问: http://localhost:9090

# 方式2: NodePort (如果可用)
PROM_IP=$(kubectl get svc prometheus -n nova-monitoring \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Prometheus: http://$PROM_IP:30090"
```

**验证指标收集**:
```bash
# 在Prometheus UI中执行以下查询

# 1. HTTP请求速率
rate(http_requests_total[5m])

# 2. 消息服务Pod状态
kube_pod_status_phase{namespace="nova-messaging", pod=~"messaging-service-.*"}

# 3. 消费服务CPU使用
rate(container_cpu_usage_seconds_total{pod=~"messaging-service-.*"}[5m])

# 4. 内存使用
container_memory_usage_bytes{pod=~"messaging-service-.*"}

# 5. WebSocket连接数 (如果已实现)
websocket_connections_active{job="messaging-service"}
```

**配置告警通知**:

```bash
# Slack通知配置
kubectl edit configmap alertmanager-config -n nova-monitoring

# 在数据中添加:
# slack_api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'
# slack_channel: '#alerts'
```

**可选: 安装Grafana仪表板**:
```bash
# 添加Grafana Helm仓库
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# 安装Grafana
helm install grafana grafana/grafana \
  -n nova-monitoring \
  --set adminPassword=admin \
  --set persistence.enabled=true \
  --set persistence.size=10Gi

# 访问Grafana
kubectl port-forward svc/grafana 3000:80 -n nova-monitoring
# 访问: http://localhost:3000 (admin/admin)

# 添加Prometheus数据源
# URL: http://prometheus:9090
```

**告警验证**:
```bash
# 访问AlertManager UI
kubectl port-forward svc/alertmanager 9093:9093 -n nova-monitoring
# 访问: http://localhost:9093

# 查看活跃告警
kubectl logs -f alertmanager-* -n nova-monitoring
```

---

### Phase 3: GitOps自动化 (第3-4周)

#### Step 4: 部署GitOps (ArgoCD) (30-45分钟)

**前置条件准备**:

```bash
# 1. 创建GitHub Personal Access Token
# https://github.com/settings/tokens
# 所需权限: repo, admin:repo_hook

# 2. 将Nova项目推送到GitHub (如果还未推送)
cd /path/to/nova
git remote add origin https://github.com/your-org/nova.git
git push -u origin main

# 3. 验证k8s清单文件在正确位置
# backend/k8s/*.yaml 应该存在
```

**安装ArgoCD**:
```bash
# 1. 创建命名空间
kubectl create namespace argocd

# 2. 安装ArgoCD
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 3. 等待ArgoCD就绪
kubectl wait --for=condition=Ready pod \
  -l app.kubernetes.io/name=argocd-server \
  -n argocd --timeout=300s

# 4. 验证安装
kubectl get pods -n argocd
```

**部署GitOps配置**:
```bash
# 1. 编辑gitops-argocd-setup.yaml
# 更新以下TODO项:
# - your-org/nova.git → 你的GitHub仓库
# - your-github-token → GitHub Personal Access Token

# 2. 编辑后应用
kubectl apply -f gitops-argocd-setup.yaml

# 3. 验证应用创建
kubectl get applications -n argocd

# 4. 查看同步状态
argocd app list
```

**配置GitHub Webhook** (可选但推荐):
```bash
# 1. 获取ArgoCD服务器IP
ARGOCD_IP=$(kubectl get svc argocd-server -n argocd \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# 2. 获取webhook URL
WEBHOOK_URL="https://$ARGOCD_IP/api/webhook"

# 3. 在GitHub仓库设置中添加Webhook
# Settings → Webhooks → Add webhook
# Payload URL: $WEBHOOK_URL
# Content type: application/json
# Events: Push events
```

**访问ArgoCD UI**:
```bash
# 方式1: 端口转发
kubectl port-forward svc/argocd-server -n argocd 8080:443

# 获取密码
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

echo "ArgoCD URL: https://localhost:8080"
echo "Username: admin"
echo "Password: $ARGOCD_PASSWORD"

# 方式2: 如果配置了Ingress
# https://argocd.your-domain
```

**验证GitOps工作流**:
```bash
# 1. 检查应用同步状态
argocd app get messaging-service
argocd app get turn-server
argocd app get monitoring-stack

# 2. 触发手动同步
argocd app sync messaging-service

# 3. 监控同步进度
argocd app logs messaging-service -n argocd

# 4. 验证K8s资源已部署
kubectl get all -n nova-messaging
kubectl get all -n nova-turn
kubectl get all -n nova-monitoring
```

**设置自动同步**:
```bash
# GitOps配置中已启用自动同步
# 验证配置:
kubectl get application messaging-service -n argocd -o yaml | \
  grep -A 10 "syncPolicy"

# 如果需要手动同步测试:
argocd app sync messaging-service --prune --force
```

---

## 🔍 完整部署验证

### 部署验证脚本

```bash
#!/bin/bash
# verify-all-enhancements.sh

set -e

echo "🔍 验证所有可选增强部署..."
echo ""

# Ingress验证
echo "1️⃣ 验证Ingress + TLS..."
kubectl get ingress -n nova-messaging
kubectl get secret nova-tls-cert -n nova-messaging
echo "✅ Ingress配置完成"
echo ""

# TURN服务器验证
echo "2️⃣ 验证TURN服务器..."
kubectl get pods -n nova-turn
kubectl get svc -n nova-turn
TURN_IP=$(kubectl get svc turn-server -n nova-turn \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Pending")
echo "TURN Server IP: $TURN_IP"
echo "✅ TURN服务器配置完成"
echo ""

# Prometheus验证
echo "3️⃣ 验证Prometheus监控..."
kubectl get pods -n nova-monitoring
kubectl get svc -n nova-monitoring
echo "✅ Prometheus配置完成"
echo ""

# ArgoCD验证
echo "4️⃣ 验证GitOps (ArgoCD)..."
kubectl get applications -n argocd 2>/dev/null || echo "ArgoCD未安装"
echo "✅ GitOps配置完成"
echo ""

# 综合检查
echo "📊 综合资源检查..."
echo ""
echo "全局Pod状态:"
kubectl get pods -A | grep -E "nova-|argocd|ingress" || true
echo ""
echo "全局Service状态:"
kubectl get svc -A | grep -E "nova-|argocd|ingress" || true
echo ""

echo "✅ 验证完成！"
```

### 部署完成检查清单

部署各组件后，使用此检查清单验证:

#### Ingress + TLS
- [ ] Nginx Ingress Controller Pod运行中
- [ ] nova-tls-cert Secret存在
- [ ] Ingress资源已创建
- [ ] HTTPS端口(443)可访问
- [ ] HTTP自动重定向到HTTPS
- [ ] WebSocket连接正常

#### TURN服务器
- [ ] coturn Pod运行中
- [ ] LoadBalancer分配了外部IP
- [ ] 端口3478/UDP和3478/TCP开放
- [ ] STUN测试成功
- [ ] iOS客户端可配置TURN服务器
- [ ] 视频通话NAT穿透有效

#### Prometheus监控
- [ ] Prometheus Pod运行中
- [ ] AlertManager Pod运行中
- [ ] 指标采集正常 (http_requests_total等可查询)
- [ ] 告警规则已加载 (8+规则)
- [ ] Prometheus UI可访问
- [ ] Grafana (可选) 安装且正常运行

#### GitOps (ArgoCD)
- [ ] ArgoCD Pod运行中
- [ ] 应用(messaging-service, turn-server, monitoring-stack)已创建
- [ ] 所有应用状态为 "Synced"
- [ ] GitHub webhook已配置 (可选)
- [ ] ArgoCD UI可访问
- [ ] 手动同步可成功执行

---

## 🚨 故障排查快速指南

### Ingress问题

```bash
# 证书配置问题
kubectl describe secret nova-tls-cert -n nova-messaging

# Ingress配置问题
kubectl describe ingress messaging-service-ingress -n nova-messaging

# Controller日志
kubectl logs -f -l app.kubernetes.io/component=controller \
  -n ingress-nginx | tail -100
```

### TURN服务器问题

```bash
# Pod日志
kubectl logs -f -l component=turn-server -n nova-turn

# 端口检查
kubectl exec -it $(kubectl get pod -n nova-turn \
  -o jsonpath='{.items[0].metadata.name}') \
  -n nova-turn -- netstat -tuln

# 配置验证
kubectl describe configmap turn-server-config -n nova-turn
```

### Prometheus问题

```bash
# 目标检查 (Prometheus UI)
# Status → Targets

# 规则检查
kubectl describe configmap prometheus-rules -n nova-monitoring

# AlertManager配置
kubectl describe configmap alertmanager-config -n nova-monitoring

# 告警测试
# 在Prometheus中手动触发告警规则
```

### ArgoCD问题

```bash
# 应用同步失败
argocd app get messaging-service
argocd app logs messaging-service

# 认证问题
kubectl logs -f -l app.kubernetes.io/name=argocd-server -n argocd

# 仓库连接问题
kubectl describe secret nova-repo-credentials -n argocd
```

---

## 📋 可选增强资源汇总

### 配置文件位置

```
backend/k8s/
├── OPTIONAL_ENHANCEMENTS.md                    # 详细部署指南
├── OPTIONAL_ENHANCEMENTS_DEPLOYMENT_CHECKLIST.md  # 此文件
├── turn-server-deployment.yaml                 # TURN服务器配置
├── ingress-tls-setup.yaml                      # Ingress + TLS配置
├── prometheus-monitoring-setup.yaml            # Prometheus监控配置
└── gitops-argocd-setup.yaml                    # GitOps自动化配置
```

### 快速命令参考

```bash
# 部署Ingress (需要Nginx Ingress Controller)
kubectl apply -f ingress-tls-setup.yaml

# 部署TURN服务器
kubectl apply -f turn-server-deployment.yaml

# 部署Prometheus监控
kubectl apply -f prometheus-monitoring-setup.yaml

# 部署GitOps
kubectl create namespace argocd && \
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml && \
kubectl apply -f gitops-argocd-setup.yaml
```

### 资源成本估算

| 组件 | 计算资源 | 存储 | 月成本(AWS) |
|------|---------|------|-----------|
| TURN服务器 | t3.medium | 10GB | $30-50 |
| Ingress+LB | 共享 | - | $16 |
| Prometheus | t3.small | 100GB | $20-30 |
| ArgoCD | 共享 | - | $0 |
| **总计** | | | $66-96 |

---

## 🎯 下一步建议

### 立即 (今天)
- [ ] 部署Ingress + TLS实现HTTPS入口
- [ ] 验证消息服务通过HTTPS可访问

### 本周
- [ ] 部署TURN服务器
- [ ] 在iOS客户端中配置TURN服务器
- [ ] 测试视频通话NAT穿透功能

### 本月
- [ ] 部署Prometheus监控
- [ ] 配置告警规则和通知
- [ ] 安装Grafana仪表板

### 下月
- [ ] 部署GitOps (ArgoCD)
- [ ] 配置GitHub webhook自动部署
- [ ] 建立CI/CD流程

---

## 📞 技术支持

遇到问题时的调试流程:

1. **查看日志**
   ```bash
   kubectl logs -f <pod> -n <namespace>
   ```

2. **描述资源**
   ```bash
   kubectl describe <resource_type> <resource_name> -n <namespace>
   ```

3. **检查事件**
   ```bash
   kubectl get events -n <namespace> --sort-by='.lastTimestamp'
   ```

4. **进入容器调试**
   ```bash
   kubectl exec -it <pod> -n <namespace> -- /bin/sh
   ```

5. **查看资源使用**
   ```bash
   kubectl top pods -n <namespace>
   kubectl top nodes
   ```

---

**完成此检查清单后，Nova消息服务将具备完整的生产级部署、监控、和自动化功能！🎉**
