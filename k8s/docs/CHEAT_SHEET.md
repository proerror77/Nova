# Nova Kubernetes Cheat Sheet

## 快速命令参考

### 部署命令

```bash
# 开发环境部署
kubectl apply -k k8s/overlays/dev

# 生产环境部署
kubectl apply -k k8s/overlays/prod

# 查看会应用什么资源
kubectl apply -k k8s/overlays/dev --dry-run=client

# 删除所有资源
kubectl delete -k k8s/overlays/dev
```

### 查看资源

```bash
# 查看所有资源
kubectl -n nova get all

# 查看 Pods
kubectl -n nova get pods -o wide

# 查看 Services
kubectl -n nova get svc

# 查看 Deployments
kubectl -n nova get deployments

# 查看 Ingress
kubectl -n nova get ingress

# 查看 ConfigMap/Secrets
kubectl -n nova get configmap,secret
```

### Pod 管理

```bash
# 查看 Pod 详细信息
kubectl -n nova describe pod <pod-name>

# 查看 Pod 日志
kubectl -n nova logs <pod-name>

# 跟随日志
kubectl -n nova logs -f <pod-name>

# 查看上个 Pod 的日志（已崩溃）
kubectl -n nova logs <pod-name> --previous

# 进入 Pod 内部
kubectl -n nova exec -it <pod-name> -- /bin/bash

# 获取 Pod 中的文件
kubectl -n nova cp <pod-name>:/path/to/file ./local-file

# 删除 Pod（会自动重启）
kubectl -n nova delete pod <pod-name>
```

### Deployment 操作

```bash
# 查看 Deployment 状态
kubectl -n nova describe deployment <deployment-name>

# 扩展副本数
kubectl -n nova scale deployment/<deployment-name> --replicas=5

# 更新镜像
kubectl -n nova set image deployment/<deployment-name> \
  <container-name>=<image>:<tag>

# 查看部署历史
kubectl -n nova rollout history deployment/<deployment-name>

# 回滚到上一个版本
kubectl -n nova rollout undo deployment/<deployment-name>

# 回滚到特定版本
kubectl -n nova rollout undo deployment/<deployment-name> --to-revision=2

# 查看部署状态
kubectl -n nova rollout status deployment/<deployment-name>

# 重启 Deployment（重启所有 Pod）
kubectl -n nova rollout restart deployment/<deployment-name>
```

### Service 和网络

```bash
# 查看 Service Endpoints
kubectl -n nova get endpoints

# 端口转发本地访问
kubectl -n nova port-forward svc/<service-name> 8081:8081

# 端口转发到特定 Pod
kubectl -n nova port-forward pod/<pod-name> 8081:8081

# 在 Pod 内执行命令进行网络测试
kubectl -n nova exec <pod-name> -- wget -O- http://content-service:8081/health

# 检查 Ingress 状态
kubectl -n nova describe ingress nova-api-gateway
```

### Configmap 和 Secret

```bash
# 查看 ConfigMap 内容
kubectl -n nova get configmap nova-config -o yaml

# 编辑 ConfigMap
kubectl -n nova edit configmap nova-config

# 查看 Secret（base64 编码）
kubectl -n nova get secret nova-db-credentials -o yaml

# 创建 Secret
kubectl -n nova create secret generic my-secret --from-literal=key=value

# 更新 Secret 字段
kubectl -n nova patch secret nova-s3-credentials \
  -p '{"data":{"AWS_ACCESS_KEY_ID":"'$(echo -n 'new-key' | base64)'"}}'

# ConfigMap 变更后重启 Pod
kubectl -n nova rollout restart deployment/content-service
```

### 监控和性能

```bash
# 查看 Pod 资源使用
kubectl -n nova top pods

# 查看节点资源使用
kubectl top nodes

# 实时监控 Pod 资源
kubectl -n nova top pods --watch

# 查看 HPA 状态
kubectl -n nova get hpa

# 查看 HPA 详情
kubectl -n nova describe hpa content-service-hpa

# 查看事件
kubectl -n nova get events
kubectl -n nova get events --sort-by='.lastTimestamp'
```

### 调试技巧

```bash
# 启动调试 Pod
kubectl -n nova run -it --rm debug --image=busybox --restart=Never -- sh

# 查看 Pod 环境变量
kubectl -n nova exec <pod-name> -- env | sort

# 在 Pod 中安装工具
kubectl -n nova exec <pod-name> -- apt-get update && apt-get install -y curl

# 查看 Pod 中的进程
kubectl -n nova exec <pod-name> -- ps aux

# 检查 Pod 中的网络
kubectl -n nova exec <pod-name> -- netstat -tlnp

# 获取 Pod 中的完整信息
kubectl -n nova get pod <pod-name> -o json | jq '.'
```

### Node 管理

```bash
# 查看所有 Node
kubectl get nodes -o wide

# 查看 Node 详情
kubectl describe node <node-name>

# 查看 Node 资源使用
kubectl top node <node-name>

# 标记 Node
kubectl label node <node-name> key=value

# 污点 Node（防止 Pod 调度）
kubectl taint node <node-name> key=value:NoSchedule

# 移除污点
kubectl taint node <node-name> key=value:NoSchedule-
```

### Namespace 操作

```bash
# 创建 Namespace
kubectl create namespace nova

# 查看所有 Namespace
kubectl get namespace

# 查看特定 Namespace 的资源
kubectl -n nova get all

# 删除 Namespace（会删除其中所有资源）
kubectl delete namespace nova

# 设置默认 Namespace
kubectl config set-context --current --namespace=nova
```

### 故障排查

```bash
# 获取最后 100 行日志
kubectl -n nova logs <pod-name> --tail=100

# 查看所有 Pod 状态
kubectl -n nova get pods --show-all

# 查看未就绪的 Pod
kubectl -n nova get pods --field-selector=status.phase!=Running

# 查看错误事件
kubectl -n nova get events --field-selector type=Warning,type=Error

# describe 命令看完整错误
kubectl -n nova describe pod <pod-name> | tail -30

# 查看 Pod 中容器的启动日志
kubectl -n nova logs <pod-name> -c <container-name>

# 检查 DNS 解析
kubectl -n nova run -it --rm debug --image=busybox --restart=Never -- nslookup content-service
```

### 高级操作

```bash
# 使用 Patch 更新资源
kubectl -n nova patch deployment content-service -p '{"spec":{"replicas":5}}'

# 使用 JSON Patch 更新
kubectl -n nova patch pod <pod-name> --type json -p '[{"op":"add","path":"/metadata/labels/app","value":"nova"}]'

# 导出资源到文件
kubectl -n nova get deployment content-service -o yaml > content-service-backup.yaml

# 从文件恢复资源
kubectl apply -f content-service-backup.yaml

# 执行多个命令
kubectl -n nova get pods | grep content | awk '{print $1}' | xargs kubectl -n nova logs

# 查找特定标签的 Pod
kubectl -n nova get pods -l app=content-service

# 标记 Pod
kubectl -n nova label pod <pod-name> version=v1
```

## 常见问题快速查询

| 问题 | 命令 |
|------|------|
| Pod 为什么无法启动？ | `kubectl -n nova describe pod <pod>` |
| 如何查看应用日志？ | `kubectl -n nova logs -f <pod>` |
| 如何访问 Service？ | `kubectl -n nova port-forward svc/<svc> 8080:8080` |
| 如何扩展副本？ | `kubectl -n nova scale deployment/<dep> --replicas=5` |
| 如何更新镜像？ | `kubectl -n nova set image deployment/<dep> <cont>=<img>:<tag>` |
| 如何回滚版本？ | `kubectl -n nova rollout undo deployment/<dep>` |
| 如何重启 Pod？ | `kubectl -n nova rollout restart deployment/<dep>` |
| 如何查看资源使用？ | `kubectl -n nova top pods` |
| 如何进入 Pod 内部？ | `kubectl -n nova exec -it <pod> -- bash` |
| 如何查看事件？ | `kubectl -n nova get events --sort-by='.lastTimestamp'` |

## 常用参数

```bash
# 输出格式
-o json      # JSON 格式
-o yaml      # YAML 格式
-o wide      # 宽表格
-o name      # 仅名称
-o custom-columns=...  # 自定义列

# 选择器
-l key=value  # 按标签选择
--field-selector=key=value  # 按字段选择

# 排序
--sort-by=<field>  # 按字段排序

# 其他
--all-namespaces  # 所有命名空间
-n <namespace>    # 指定命名空间
--dry-run=client  # 模拟运行（不实际执行）
-w / --watch      # 实时监控
--tail=<lines>    # 最后 N 行
```

## 快速检查列表

```bash
# 部署前检查
□ kubectl cluster-info
□ kubectl get nodes -o wide
□ kubectl get ns | grep nova
□ docker pull nova/content-service:v1.0.0

# 部署后检查
□ kubectl -n nova get pods
□ kubectl -n nova get svc
□ kubectl -n nova get ingress
□ kubectl -n nova get hpa

# 功能验证
□ kubectl -n nova port-forward svc/content-service 8081:8081
□ curl http://localhost:8081/api/v1/health
□ kubectl -n nova logs -f deployment/content-service

# 故障排查
□ kubectl -n nova describe pod <pod-name>
□ kubectl -n nova logs <pod-name> --previous
□ kubectl -n nova top pods
□ kubectl -n nova get events
```

---

**提示**: 将常用命令添加到 shell 别名以提高效率

```bash
# ~/.bashrc 或 ~/.zshrc
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgd='kubectl get deployment'
alias kl='kubectl logs -f'
alias kex='kubectl exec -it'
alias kns='kubectl -n nova'
```

---

**最后更新**: 2025-10-29
