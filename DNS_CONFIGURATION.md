# DNS 配置指南

## 域名配置概览

**生产域名**: `api.nova.social`

**配置状态**:
- ✅ Kubernetes Ingress 已配置域名
- ✅ Let's Encrypt SSL 证书自动签发已配置
- ⚠️  等待 AWS ALB 配额批准后获取 LoadBalancer 地址
- ⏳ DNS 记录需要在 ALB 就绪后配置

## 前置条件

### 1. AWS ALB 配额问题已解决

在配置 DNS 前，必须：
1. AWS Support case 已批准
2. ALB 成功创建
3. 获得 ALB DNS 地址

验证 ALB 状态：
```bash
# 检查 Ingress 是否获得地址
kubectl get ingress -n nova-gateway

# 输出应该类似：
# NAME                           CLASS   HOSTS              ADDRESS
# graphql-gateway-ingress        nginx   api.nova.social    k8s-nova-xxx-yyy.ap-northeast-1.elb.amazonaws.com
```

### 2. 确认域名所有权

确保您拥有 `nova.social` 域名的 DNS 管理权限。

## DNS 配置步骤

### 选项 A: 使用 AWS Route53（推荐）

#### 步骤 1: 获取 ALB 地址

```bash
# 获取 ALB DNS 名称
ALB_DNS=$(kubectl get ingress graphql-gateway-ingress -n nova-gateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ALB DNS: $ALB_DNS"

# 获取 ALB Hosted Zone ID
ALB_ZONE=$(aws elbv2 describe-load-balancers --region ap-northeast-1 --query "LoadBalancers[?DNSName=='$ALB_DNS'].CanonicalHostedZoneId" --output text)
echo "ALB Zone: $ALB_ZONE"
```

#### 步骤 2: 创建 Route53 记录

**使用 AWS CLI**:
```bash
# 获取 Route53 托管区域 ID
ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='nova.social.'].Id" --output text | cut -d'/' -f3)

# 创建 A 记录（Alias 到 ALB）
cat > /tmp/route53-record.json <<EOF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "api.nova.social",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "$ALB_ZONE",
          "DNSName": "$ALB_DNS",
          "EvaluateTargetHealth": true
        }
      }
    }
  ]
}
EOF

# 应用 DNS 更改
aws route53 change-resource-record-sets \
  --hosted-zone-id $ZONE_ID \
  --change-batch file:///tmp/route53-record.json
```

**使用 AWS Console**:
1. 访问 Route53 控制台
2. 选择 `nova.social` 托管区域
3. 创建记录：
   - 记录名称: `api`
   - 记录类型: `A`
   - 值/路由流量至: `Application and Classic Load Balancer 的别名`
   - 区域: `ap-northeast-1`
   - 选择 ALB: `k8s-nova-graphqlg-xxx`
   - 评估目标运行状况: `是`

#### 步骤 3: 验证 DNS 解析

```bash
# 等待 DNS 传播（通常 1-5 分钟）
dig api.nova.social

# 测试 HTTPS 访问
curl https://api.nova.social/health

# 访问 GraphQL Playground
open https://api.nova.social/playground
```

### 选项 B: 使用其他 DNS 提供商

如果使用 Cloudflare、GoDaddy 等其他 DNS 提供商：

#### 步骤 1: 获取 ALB 地址（同上）

#### 步骤 2: 添加 CNAME 记录

在您的 DNS 提供商控制面板：

| 类型  | 名称 | 值（目标）                                           | TTL  |
|-------|------|-----------------------------------------------------|------|
| CNAME | api  | k8s-nova-xxx.ap-northeast-1.elb.amazonaws.com       | 300  |

**⚠️  注意**: CNAME 记录会增加一次 DNS 查询，推荐使用 Route53 的 A 记录 Alias。

#### 步骤 3: 验证

```bash
# 等待 DNS 传播（可能需要 5-60 分钟）
nslookup api.nova.social

# 测试访问
curl https://api.nova.social/health
```

## SSL 证书自动签发

### cert-manager 自动化流程

一旦 DNS 配置完成并生效：

1. **cert-manager 检测到新的 Ingress**
   ```bash
   # 查看证书请求
   kubectl get certificaterequest -n nova-gateway
   ```

2. **Let's Encrypt HTTP-01 挑战**
   - Let's Encrypt 访问 `http://api.nova.social/.well-known/acme-challenge/xxx`
   - Ingress 自动响应挑战
   - 验证域名所有权

3. **证书签发和存储**
   ```bash
   # 查看证书状态
   kubectl get certificate -n nova-gateway

   # 查看证书详情
   kubectl describe certificate nova-api-tls -n nova-gateway

   # 证书存储在 Secret 中
   kubectl get secret nova-api-tls -n nova-gateway -o yaml
   ```

4. **自动更新**
   - cert-manager 在证书过期前 30 天自动续期
   - 无需手动干预

### 证书故障排查

```bash
# 查看 cert-manager 日志
kubectl logs -n cert-manager -l app=cert-manager

# 查看证书事件
kubectl describe certificate nova-api-tls -n nova-gateway

# 查看挑战状态
kubectl get challenge -n nova-gateway

# 手动删除并重新创建证书（如果失败）
kubectl delete certificate nova-api-tls -n nova-gateway
kubectl apply -f k8s/graphql-gateway/ingress.yaml
```

## 临时访问方案（DNS 配置前）

在域名配置完成前，您可以使用以下方式访问：

### 方式 1: kubectl port-forward

```bash
# Port forward 到本地
kubectl port-forward -n nova-gateway svc/graphql-gateway 8080:8080

# 访问
curl http://localhost:8080/health
open http://localhost:8080/playground
```

### 方式 2: 直接使用 ALB DNS

```bash
# 获取 ALB DNS
ALB_DNS=$(kubectl get ingress graphql-gateway-ingress -n nova-gateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# 访问（需要设置 Host header）
curl -H "Host: api.nova.social" http://$ALB_DNS/health

# 或者直接访问（如果 Ingress 配置了 catch-all）
curl http://$ALB_DNS/health
```

## 生产检查清单

在启用生产域名前确认：

- [ ] AWS ALB 配额已批准并成功创建
- [ ] ALB DNS 地址已获取
- [ ] 域名所有权已确认
- [ ] DNS 记录已配置（Route53 或其他提供商）
- [ ] DNS 解析验证通过
- [ ] SSL 证书自动签发成功
- [ ] HTTPS 访问测试通过
- [ ] GraphQL Playground 可访问
- [ ] 所有 API 端点正常工作
- [ ] iOS 应用已更新生产 API 地址

## 监控和维护

### 监控 DNS 解析

```bash
# 定期检查 DNS 解析
watch -n 60 'dig api.nova.social +short'

# 监控全球 DNS 传播
# 使用在线工具: https://www.whatsmydns.net/#A/api.nova.social
```

### 监控证书有效期

```bash
# 检查证书过期时间
kubectl get certificate nova-api-tls -n nova-gateway -o jsonpath='{.status.notAfter}'

# 查看证书详情
openssl s_client -connect api.nova.social:443 -servername api.nova.social < /dev/null 2>/dev/null | openssl x509 -noout -dates
```

### 设置告警

建议配置以下告警：
- DNS 解析失败
- SSL 证书即将过期（<30 天）
- ALB 健康检查失败
- 域名无法访问

## 故障排查

### 问题 1: DNS 不解析

```bash
# 检查 DNS 记录
dig api.nova.social

# 检查 Route53 记录
aws route53 list-resource-record-sets --hosted-zone-id $ZONE_ID | grep -A 5 "api.nova.social"

# 检查 ALB 状态
aws elbv2 describe-load-balancers --region ap-northeast-1
```

### 问题 2: SSL 证书签发失败

```bash
# 查看 cert-manager 日志
kubectl logs -n cert-manager -l app=cert-manager --tail=100

# 查看证书状态
kubectl describe certificate nova-api-tls -n nova-gateway

# 常见原因:
# - DNS 未正确配置
# - ALB 健康检查失败
# - Let's Encrypt rate limit
```

### 问题 3: HTTPS 无法访问

```bash
# 检查 Ingress 状态
kubectl describe ingress graphql-gateway-ingress -n nova-gateway

# 检查 TLS Secret
kubectl get secret nova-api-tls -n nova-gateway

# 测试 SSL
openssl s_client -connect api.nova.social:443 -servername api.nova.social
```

## 多环境配置

### Staging 环境

域名: `api-staging.nova.social`

```bash
# 使用相同流程，但指向 staging ALB
# 修改 Ingress host 为 api-staging.nova.social
```

### Development 环境

域名: `api-dev.nova.social`

或者使用 IP + nip.io:
```
http://52-123-45-67.nip.io
```

## 参考资源

- [AWS Route53 文档](https://docs.aws.amazon.com/route53/)
- [cert-manager 文档](https://cert-manager.io/docs/)
- [Let's Encrypt 文档](https://letsencrypt.org/docs/)
- [Kubernetes Ingress 文档](https://kubernetes.io/docs/concepts/services-networking/ingress/)

---

**最后更新**: 2025-11-10
**维护者**: Nova Platform Team
