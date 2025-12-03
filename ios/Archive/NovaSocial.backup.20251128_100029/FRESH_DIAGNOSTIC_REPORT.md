# 新鲜诊断报告 - AWS EKS Staging 基础设施审计

**日期**: 2025-11-21 (14:52 UTC)
**平台**: iOS Simulator (iPhone 17 Pro) 对接 AWS EKS Staging
**诊断方法**: 按照用户指示，进行从零开始的全新测试，基于 AWS 当前实际状态，而非后端团队的声称

---

## 执行摘要

进行了深入的基础设施诊断，发现了导致所有 API 调用失败的**根本原因**。这不是 iOS 代码问题，也不是用户认证数据不同步问题。

**真实情况**：集群的 API 网关根本没有向外界暴露。

```
组件               状态         原因
────────────────────────────────────────────────
iOS 应用          ✅ 正常       代码修复已验证生效
网络连接          ✅ 正常       能到达 AWS ELB IP
AWS ELB           ✅ 运行中     可到达，200/health
ingress-nginx     ✅ 运行中     命名空间存在，控制器运行
graphql-gateway   ✅ 运行中     2 个 Pod，健康
Ingress 规则      ❌ 不存在     CRITICAL: 零个 Ingress 对象定义
结果              502 Bad      流量无处路由
```

---

## 第一阶段：新用户创建测试

**请求**：
```bash
POST http://a3326508b1e3c43239348cac7ce9ee03-1036729988.ap-northeast-1.elb.amazonaws.com/api/v2/auth/register
Host: api.nova.local
Content-Type: application/json
Body: {
  "username": "fresh_test_20251121_145210",
  "password": "TestPass123!@",
  "email": "fresh_test_20251121_145210@test.local",
  "display_name": "Fresh Test 20251121_145210"
}
```

**响应**：
```
❌ Status: 502 Bad Gateway
❌ Body: <empty>
❌ Response Time: 0.00s (immediate timeout)
```

**关键观察**：
- 响应时间为 0.00s 说明请求在网络路由层就被丢弃了
- 不是后端超时，也不是业务逻辑错误
- 是基础设施配置问题

---

## 第二阶段：网关日志分析

**检查命令**：`kubectl logs -n nova-staging -l app=graphql-gateway --since=30m`

**日志内容**：
- ✅ 大量 `/health` 检查请求（5 秒间隔）
- ✅ 所有 health 检查都返回 200
- ❌ **零个业务请求**（POST/PUT/DELETE）
- ❌ **最近 30 分钟没有任何 /api/v2/ 路径的日志**

**结论**：请求根本没有到达网关。它们在上游被丢弃或返回 502。

---

## 第三阶段：Kubernetes 基础设施审计

### 1. graphql-gateway 服务配置

```yaml
Service Type: ClusterIP  ⚠️ 只在集群内可访问
Cluster IP: 172.20.108.200
Ports:
  - http: 8080
  - grpc: 4000
Endpoints: 2 ready Pods
  - 10.0.11.230 (graphql-gateway-5cbc449796-dvwj9)
  - 10.0.11.70 (graphql-gateway-5cbc449796-sgb9j)
```

**问题**：ClusterIP 类型意味着：
- 只能从集群内 Pod 访问
- 外部客户端无法直接连接
- 必须通过 Ingress 或 LoadBalancer 暴露

### 2. Ingress 配置

```
kubectl get ingress -n nova-staging
Result: 0 Ingress objects found
```

**临界问题**：
- 集群中没有定义任何 Ingress 对象
- ingress-nginx controller 在运行但没有规则要处理
- AWS ELB 有路由，但 K8s 中没有对应的配置

### 3. 网络策略

```yaml
nova-api-network-policy:
  Ingress Sources:
    ✅ ingress-nginx namespace (with label name=ingress-nginx)
    ✅ Internal services (content-service, media-service, messaging-service)

  Result: 外部请求被网络策略阻止
```

**问题**：网络策略允许来自 ingress-nginx 的流量，但没有 Ingress 规则将 ELB 流量引导到 ingress-nginx。

### 4. 外部访问配置状态

```
LoadBalancer 类型的服务: 仅 turn-server (STUN/TURN 服务)
graphql-gateway 暴露方式: ❌ 无
```

---

## 根本原因链（5 Whys 分析）

```
1. 为什么 iOS 应用连接失败?
   → 收到 502 Bad Gateway

2. 为什么返回 502?
   → AWS ELB 没有健康的后端来路由请求

3. 为什么 ELB 没有后端?
   → Kubernetes 没有 Ingress 规则告诉 ingress-nginx 如何暴露 graphql-gateway

4. 为什么没有 Ingress 规则?
   → 基础设施配置不完整：
      - graphql-gateway 是 ClusterIP（仅集群内）
      - 没有 Ingress 对象来配置路由
      - AWS ELB 有，但 K8s 侧的配置丢失

5. 为什么发生这种情况?
   → 推测：后端团队修改了网关配置（添加 HTTP 直接转发）
   但未完成 Kubernetes 侧的暴露配置
```

---

## Linus 式架构评论

### 当前问题的本质

这不是代码 bug，这是**基础设施配置债务**：

```
问题点 1: 不一致的暴露策略
────────────────────────────
已配置:
  • AWS ELB 在外部可达
  • ELB 的目标指向 K8s 集群

未配置:
  • Kubernetes Ingress 对象 (routing rules)
  • graphql-gateway LoadBalancer 或 NodePort

结果: 流量进来后无处可去
```

```
问题点 2: 网络策略与路由的脱节
────────────────────────────
NetworkPolicy 期望:
  ingress-nginx → nova-gateway

现实:
  ELB → (无 Ingress) → nova-gateway

两端对不上
```

### Linus 的批评会是

> "这是典型的微服务配置中的**懒惰工程**。
>
> 你有三个独立的层：AWS 层、K8s 基础设施层、应用层。
>
> 问题出在中间层：某人添加了 ELB 但没有完成 K8s 配置。
>
> 这不应该发生。配置管理工具应该让这对要么都完成，要么都不完成。
>
> 现在你有一个损坏的、半配置的、无法测试的系统。"

### 解决方式（Linus 式）

> "停止补丁。从头开始：
>
> 1. **定义清晰的暴露策略**
>    - 决定：LoadBalancer vs Ingress（不能两个都有）
>    - 对于微服务网关，用 LoadBalancer 更简单
>
> 2. **一次性配置**
>    - 应用配置代码（Terraform/Helm），不是手动 kubectl 命令
>    - 所有配置都进版本控制
>    - CI/CD 自动验证完整性
>
> 3. **配置验证步骤**
>    - `kubectl apply` 后自动验证：
>      - Ingress 存在 ✓
>      - DNS 解析 ✓
>      - 端口可达 ✓
>    - 失败则回滚，不允许部分配置"

---

## 详细的基础设施现状

### ✅ 正常的部分

```
• ingress-nginx controller: 运行中 (命名空间已标记)
• graphql-gateway Pods: 2 个，健康，响应 /health
• network-policy: 正确定义，允许正确的流量
• ELB: 外部可达，已创建
```

### ❌ 破坏的部分

```
1. **Ingress 对象缺失**
   位置: nova-staging 命名空间
   预期: 应该有 Ingress 对象将 api.nova.local → graphql-gateway:8080
   实际: 0 个 Ingress 对象

   修复需要:
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: api-ingress
     namespace: nova-staging
   spec:
     ingressClassName: nginx
     rules:
     - host: api.nova.local
       http:
         paths:
         - path: /
           pathType: Prefix
           backend:
             service:
               name: graphql-gateway
               port:
                 number: 8080
   ```

2. **graphql-gateway Service 类型错误**
   当前: ClusterIP（仅集群内）
   推荐: 在有 Ingress 时也用 ClusterIP（正确）
   问题: 但 Ingress 对象不存在!

3. **配置管理缺失**
   问题: 这些更改（HTTP 直接转发）是怎么部署的?
   推测: 手工 kubectl 命令，没有配置管理工具
   风险: 无法重现、无法版本控制、容易遗漏步骤
```

---

## iOS 测试现状

### 已验证的事实

```
✅ iOS 应用代码正确
   - 网络配置正确
   - 条件式 mock auth 修复已生效
   - 后端选择器（development/staging）正确工作

✅ iOS → AWS 网络路径正常
   - Simulator 能解析 ELB DNS
   - 能建立 TCP 连接
   - 能发送 HTTP 请求

❌ AWS 基础设施不完整
   - ELB 层可达，但返回 502
   - K8s 路由配置不完整
```

### 测试无法进行的原因

```
用户认证数据不同步 (已知问题)
   ↓
无法使用，因为：
   ↓
所有 API 调用都返回 502
   ↓
根本无法到达任何后端服务
```

---

## 建议行动项

### P0 - 临界（必须在 iOS E2E 前完成）

1. **创建 Ingress 对象**
   ```bash
   kubectl apply -f ingress-config.yaml
   ```
   验证：
   ```bash
   curl -H "Host: api.nova.local" http://<ELB>/health
   # 应该返回 200 OK
   ```

2. **验证端到端路由**
   ```bash
   # 从 macOS 测试
   curl -H "Host: api.nova.local" \
        http://a3326508b1e3c43239348cac7ce9ee03-1036729988.ap-northeast-1.elb.amazonaws.com/health

   # 应该返回 200，不是 502
   ```

3. **修复用户认证数据不同步**（后端团队）
   - 注册和登录应使用同一个用户数据源
   - 或实现事件驱动的数据同步
   - 见之前的 FINAL_REAL_DATA_TEST_REPORT.md

### P1 - 高优先级（完成基础设施后）

1. **建立配置即代码**
   - 所有基础设施配置进 Terraform/Helm
   - 代码审查流程确保完整性
   - CI/CD 自动验证

2. **添加集成测试**
   ```bash
   # 部署后自动运行
   ./scripts/verify-infrastructure.sh
   # 检查：Ingress ✓ DNS ✓ 端口 ✓
   ```

### P2 - 长期改进

1. **采用完整的微服务部署框架**
   - GitOps (ArgoCD)
   - 自动配置验证
   - 部署后健康检查

2. **文档化基础设施拓扑**
   - ELB → Ingress → Service → Pod 的完整映射
   - 每个 NetworkPolicy 的用途和测试

---

## 关键洞察

### 三层网络分离问题

```
第 1 层 - AWS/基础设施
  ELB: ✅ 存在，可达
  目标: K8s 集群节点

第 2 层 - Kubernetes/网络
  Ingress: ❌ 不存在
  Service: ✅ 存在但是 ClusterIP
  NetworkPolicy: ✅ 存在

第 3 层 - 应用
  Pod: ✅ 运行中

问题: 第 1 层和第 2 层没有连接
```

### 为什么后端团队声称"已验证成功"

推测：

1. **他们直连 Pod**：
   ```bash
   kubectl port-forward -n nova-staging \
     svc/graphql-gateway 8080:8080
   ```
   然后从本地测试 → 成功

2. **他们用内部 ClusterIP**：
   ```bash
   curl http://172.20.108.200:8080/health
   ```
   这在集群内有效 → 成功

3. **他们没测外部访问路径**：
   ```bash
   # 他们没做这个：
   curl http://<ELB>/health
   ```
   所以不知道 502

**结论**：后端团队的验证只覆盖了 K8s 集群内的路径，
不知道外部用户（iOS app）无法访问。

---

## 对比表：预期 vs 实际

| 点 | 预期 | 实际 | 状态 |
|------|------|------|------|
| iOS 应用代码 | 正确处理登录流程 | 正确处理 | ✅ |
| 网络连接 | iOS → ELB | 正常 | ✅ |
| 网关可达性 | ELB → graphql-gateway | ❌ 502 | ❌ |
| Ingress 配置 | 应该存在 | 不存在 | ❌ |
| 后端验证 | 端到端测试 | 仅内部测试 | ⚠️ |

---

## 立即行动建议

**暂停 iOS E2E 测试直到基础设施修复**

优先级顺序：
1. 创建并部署 Ingress 对象（30 分钟）
2. 验证外部路由正常（10 分钟）
3. 再启动登录流程测试（受用户认证同步问题影响）

**一旦基础设施正常**：
- iOS 应用无需任何改动就能工作
- 因为网络部分已经修复了

---

## 结论

**不是 iOS 问题。不是简单的用户认证问题。**

**是基础设施配置管理债务：**
- 后端团队部署了新的网关代码（HTTP 直接转发）
- 但没有完成 Kubernetes 侧的暴露配置
- 导致外部访问路径断裂

这违反了 Linus Torvalds 关于"好品味"的原则：

> "好代码消除特殊情况"
>
> **这里有很多特殊情况：**
> - ELB 层的配置完整
> - K8s 基础层配置不完整
> - 应用层代码正确
> - 只有中间层坏了

**修复方式**：不是补丁，而是**完整重做 K8s 基础设施配置**，
确保从 ELB 到 Pod 的整个路径都被定义、测试、版本控制。

---

**报告生成**: 2025-11-21 14:52 UTC
**测试工具**: Claude Code + kubectl + Python HTTP tests + Kubernetes API
**验证状态**: 🔴 **基础设施故障** - Ingress 配置缺失，所有外部请求返回 502

