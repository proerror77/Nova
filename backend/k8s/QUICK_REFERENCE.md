# Nova Messaging Service K8s - 快速参考卡片

## 📁 K8s目录文件总览

```
backend/k8s/
├── README.md                                 ← 开始这里！
├── QUICK_REFERENCE.md                        ← 本文件
├── DEPLOYMENT_GUIDE.md                       ← 生产部署指南
│
├── 本地验证文件 (LOCAL)
│   ├── LOCAL_VERIFICATION.md                ← 详细本地验证指南
│   ├── LOCAL_FILES_SUMMARY.md               ← 本地文件总结
│   ├── quick-start-local.sh                 ← ⭐ 一键部署脚本
│   ├── verify-local.sh                      ← ⭐ 验证脚本
│   ├── messaging-service-deployment-local.yaml
│   ├── messaging-service-configmap-local.yaml
│   └── messaging-service-secret-local.yaml
│
├── 生产配置文件 (PRODUCTION)
│   ├── messaging-service-namespace.yaml
│   ├── messaging-service-serviceaccount.yaml
│   ├── messaging-service-configmap.yaml
│   ├── messaging-service-secret.yaml
│   ├── messaging-service-deployment.yaml
│   ├── messaging-service-service.yaml
│   ├── messaging-service-hpa.yaml
│   ├── messaging-service-pdb.yaml
│   └── ingress.yaml
```

---

## 🎯 快速开始 (本地验证)

### 1️⃣ 检查环境 (1分钟)
```bash
cd backend/k8s
./quick-start-local.sh check
```

### 2️⃣ 一键部署 (5-10分钟)
```bash
./quick-start-local.sh deploy
```

### 3️⃣ 验证状态 (30秒)
```bash
./verify-local.sh
```

### 4️⃣ 测试API (1分钟)
```bash
# 端口转发
kubectl port-forward svc/messaging-service 3000:3000 -n nova-messaging

# 新终端中测试
curl http://localhost:3000/health
```

---

## 📚 文档导航

### 快速查找 (按需求)

| 需求 | 文档 | 时间 |
|------|------|------|
| 想快速本地测试 | `LOCAL_VERIFICATION.md` | 5分钟读 |
| 想了解本地文件 | `LOCAL_FILES_SUMMARY.md` | 3分钟读 |
| 想部署到生产 | `DEPLOYMENT_GUIDE.md` | 10分钟读 |
| 想了解整个架构 | `README.md` | 5分钟读 |
| 想看故障排查 | `DEPLOYMENT_GUIDE.md` 第8.6节 | 查找即读 |

### 按场景

**场景1: 我是新手，想快速上手**
1. 阅读 `README.md` (5分钟)
2. 运行 `./quick-start-local.sh deploy`
3. 运行 `./verify-local.sh`
4. 完成！

**场景2: 我想理解所有细节**
1. 阅读 `README.md` - 架构概览
2. 阅读 `LOCAL_VERIFICATION.md` - 本地验证
3. 阅读 `DEPLOYMENT_GUIDE.md` - 生产部署
4. 探索各个 `.yaml` 文件

**场景3: 我想在生产部署**
1. 阅读 `DEPLOYMENT_GUIDE.md`
2. 编辑 `messaging-service-secret.yaml` 输入生产凭证
3. 编辑 `messaging-service-configmap.yaml` 调整参数
4. 按 `DEPLOYMENT_GUIDE.md` 步骤4部署

**场景4: 我的部署有问题**
1. 运行 `./verify-local.sh` 了解状态
2. 查看 `DEPLOYMENT_GUIDE.md` 第8.6节 故障排查
3. 按照问题描述找到解决方案

---

## 🔧 常用命令速查

### 部署和管理

```bash
# 本地一键部署
./quick-start-local.sh deploy

# 手动部署 (按顺序)
kubectl apply -f messaging-service-namespace.yaml
kubectl apply -f messaging-service-serviceaccount.yaml
kubectl apply -f messaging-service-configmap.yaml
kubectl apply -f messaging-service-secret.yaml
kubectl apply -f messaging-service-deployment.yaml
kubectl apply -f messaging-service-service.yaml
kubectl apply -f messaging-service-hpa.yaml
kubectl apply -f messaging-service-pdb.yaml

# 删除部署
kubectl delete namespace nova-messaging

# 重启部署
kubectl rollout restart deployment/messaging-service -n nova-messaging
```

### 监控和调试

```bash
# 检查状态
./verify-local.sh

# 监控Pod
kubectl get pods -n nova-messaging -w

# 查看日志 (实时)
kubectl logs -f -l component=messaging-service -n nova-messaging

# 查看最近日志
kubectl logs -l component=messaging-service -n nova-messaging --tail=50

# 进入Pod
kubectl exec -it <pod-name> -n nova-messaging -- bash

# 查看详细信息
kubectl describe deployment messaging-service -n nova-messaging
kubectl describe pod <pod-name> -n nova-messaging

# 查看事件
kubectl get events -n nova-messaging --sort-by='.lastTimestamp'
```

### 网络和测试

```bash
# 端口转发
kubectl port-forward svc/messaging-service 3000:3000 9090:9090 -n nova-messaging

# 测试健康检查
curl http://localhost:3000/health

# 获取Metrics
curl http://localhost:9090/metrics | head -20

# 获取Pod IP
kubectl get pods -o wide -n nova-messaging

# 测试集群内连接
kubectl run debug --image=busybox --rm -it -n nova-messaging -- wget -qO- http://messaging-service:3000/health
```

### 配置更新

```bash
# 编辑ConfigMap
kubectl edit configmap messaging-service-config -n nova-messaging

# 编辑Secret
kubectl patch secret messaging-service-secret -n nova-messaging \
  -p='{"stringData":{"POSTGRES_PASSWORD":"new-password"}}'

# 查看当前配置
kubectl get configmap messaging-service-config -o yaml -n nova-messaging
kubectl get secret messaging-service-secret -o yaml -n nova-messaging
```

---

## 📊 快速对比: 本地 vs 生产

| 特性 | 本地 | 生产 |
|------|------|------|
| 文件 | `*-local.yaml` | `*.yaml` |
| 副本数 | 1 | 3 |
| 环境 | development | production |
| 日志级别 | debug | info |
| WebSocket | 允许所有 | 需认证 |
| 资源请求 | 100m/128Mi | 500m/512Mi |
| 资源限制 | 500m/512Mi | 2000m/2Gi |
| HPA | ❌ | ✅ |
| PDB | ❌ | ✅ |
| 初始化容器 | ❌ | ✅ 数据库迁移 |
| 镜像策略 | Never | IfNotPresent |

---

## ✅ 部署检查清单

### 本地验证 (第1次)
- [ ] 运行 `./quick-start-local.sh check` 通过
- [ ] 运行 `./quick-start-local.sh deploy` 完成
- [ ] 运行 `./verify-local.sh` 全部 ✅
- [ ] 健康检查成功: `curl http://localhost:3000/health`
- [ ] Pod日志无错误

### 生产部署前
- [ ] 更新 `messaging-service-secret.yaml` 的所有密码
- [ ] 生成 `SECRETBOX_KEY_B64`: `openssl rand -base64 32`
- [ ] 配置 `JWT_PUBLIC_KEY_PEM` (从auth service获取)
- [ ] 配置数据库连接字符串
- [ ] 配置Redis连接字符串
- [ ] 配置Kafka代理
- [ ] 验证网络连接到所有外部服务
- [ ] 配置备份策略
- [ ] 设置监控和告警
- [ ] 测试灾难恢复流程

### 部署后验证
- [ ] 所有3个Pod运行中
- [ ] 健康检查通过
- [ ] Metrics可访问
- [ ] 数据库连接成功
- [ ] 日志无错误
- [ ] 自动扩展工作
- [ ] 备份按计划运行
- [ ] 告警配置完成

---

## 📞 获取帮助

### 快速故障排查

**问题: Pod无法启动**
```bash
kubectl describe pod <name> -n nova-messaging
kubectl logs <name> -n nova-messaging --all-containers=true
```
→ 查看 `DEPLOYMENT_GUIDE.md` 第8.6节

**问题: 健康检查失败**
```bash
kubectl exec -it <pod> -n nova-messaging -- curl -v http://localhost:3000/health
```
→ 检查数据库和Redis连接

**问题: 端口无法访问**
```bash
kubectl port-forward svc/messaging-service 3000:3000 -n nova-messaging
```
→ 检查防火墙规则

**问题: 镜像找不到**
```bash
docker build -t nova/messaging-service:latest -f backend/Dockerfile.messaging .
kind load docker-image nova/messaging-service:latest  # 如果使用kind
```

### 详细文档

- **本地验证问题**: 见 `LOCAL_VERIFICATION.md` → "故障排查"
- **生产部署问题**: 见 `DEPLOYMENT_GUIDE.md` → "故障排查"
- **网络问题**: 见 `DEPLOYMENT_GUIDE.md` → "网络"
- **性能问题**: 见 `DEPLOYMENT_GUIDE.md` → "性能调优"

---

## 🎓 学习路径

### Level 1: 基础使用 (1-2小时)
1. ✅ 阅读 `README.md`
2. ✅ 运行 `./quick-start-local.sh deploy`
3. ✅ 运行 `./verify-local.sh`
4. ✅ 修改代码并重新部署

### Level 2: 理解细节 (2-3小时)
1. ✅ 阅读 `LOCAL_VERIFICATION.md`
2. ✅ 手动部署 (不使用脚本)
3. ✅ 理解每个YAML文件
4. ✅ 尝试故障排查

### Level 3: 生产就绪 (3-4小时)
1. ✅ 阅读 `DEPLOYMENT_GUIDE.md`
2. ✅ 准备生产凭证
3. ✅ 配置监控
4. ✅ 测试灾难恢复
5. ✅ 部署到生产集群

---

## 🔗 相关资源

### 官方文档
- [Kubernetes官方文档](https://kubernetes.io/docs/)
- [kubectl参考](https://kubernetes.io/docs/reference/kubectl/)
- [Deployment最佳实践](https://kubernetes.io/docs/concepts/configuration/overview/)

### Nova项目
- 后端代码: `backend/messaging-service/`
- Docker镜像: `backend/Dockerfile.messaging`
- iOS客户端: `ios/NovaSocialApp/`

### 视频通话相关
- [视频通话实现总结](../iOS_INTEGRATION_TESTING_PLAN.md)
- [WebRTC配置](../messaging-service/src/websocket/handlers.rs)
- [TURN服务器设置](https://coturn.net/turnserver.org/)

---

## 💾 文件大小汇总

```
生产配置         (8 files):  ~22KB
本地配置         (5 files):  ~14KB
文档             (5 files):  ~52KB
脚本             (2 files):  ~16KB
─────────────────────────────────
总计             (20 files): ~104KB
```

---

## 🚀 下一步

✅ **现在**: 本地验证完成
→ **接下来**: 生产部署 (参考 `DEPLOYMENT_GUIDE.md`)
→ **然后**: TURN服务器设置 (视频通话优化)
→ **最后**: 监控和告警配置

---

**最后更新**: 2025-10-26
**版本**: 1.0
**状态**: ✅ 完成并验证
