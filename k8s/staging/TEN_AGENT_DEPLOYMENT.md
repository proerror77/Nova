# TEN Agent Staging 部署指南

## 概述

TEN Agent 是 Alice AI 語音對話功能的後端服務，基於 TEN Framework + Agora RTC 構建。

## 架構

```
iOS App (Alice Voice Chat)
        │
        ▼
┌───────────────────┐
│   Agora RTC SDK   │  ← 語音流傳輸
└─────────┬─────────┘
          │
          ▼
┌───────────────────────────────────────┐
│         TEN Agent (K8s)               │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐  │
│  │Deepgram │ │ OpenAI  │ │ElevenLabs│  │
│  │  (STT)  │ │  (LLM)  │ │  (TTS)  │  │
│  └─────────┘ └─────────┘ └─────────┘  │
└───────────────────────────────────────┘
```

## 配置文件

```
k8s/staging/
├── ten-agent-namespace.yaml     # Namespace (共用 nova-staging)
├── ten-agent-configmap.yaml     # ConfigMap 和 Secrets
├── ten-agent-deployment.yaml    # Deployment
├── ten-agent-service.yaml       # Service
├── ten-agent-ingress.yaml       # Ingress (WebSocket 支援)
├── ten-agent-hpa.yaml           # HPA 和 PDB
└── TEN_AGENT_DEPLOYMENT.md      # 本文件
```

## API 金鑰配置

在部署前，確保 `ten-agent-configmap.yaml` 中的 Secrets 已正確配置：

| 服務 | 金鑰 | 狀態 |
|------|------|------|
| Agora RTC | AGORA_APP_ID | ✅ 已配置 |
| Deepgram STT | DEEPGRAM_API_KEY | ✅ 已配置 |
| OpenAI LLM | OPENAI_API_KEY | ✅ 已配置 (tu-zi.com) |
| ElevenLabs TTS | ELEVENLABS_API_KEY | ⚠️ 需要配置 |

## 部署步驟

### 1. 配置 ElevenLabs API Key (如需 TTS)

編輯 `ten-agent-configmap.yaml`，添加 ElevenLabs API Key：
```yaml
ELEVENLABS_API_KEY: "your-elevenlabs-api-key"
```

### 2. 部署到 Kubernetes

```bash
# 確保在正確的 kubectl context
kubectl config current-context

# 部署所有資源
kubectl apply -f k8s/staging/ten-agent-namespace.yaml
kubectl apply -f k8s/staging/ten-agent-configmap.yaml
kubectl apply -f k8s/staging/ten-agent-deployment.yaml
kubectl apply -f k8s/staging/ten-agent-service.yaml
kubectl apply -f k8s/staging/ten-agent-hpa.yaml
kubectl apply -f k8s/staging/ten-agent-ingress.yaml
```

### 3. 驗證部署

```bash
# 檢查 Pod 狀態
kubectl get pods -n nova-staging -l app=ten-agent

# 檢查日誌
kubectl logs -n nova-staging -l app=ten-agent --tail=50 -f

# 檢查 Service
kubectl get svc -n nova-staging ten-agent

# 檢查 Ingress
kubectl get ingress -n nova-staging ten-agent
```

### 4. 測試連接

```bash
# Port-forward 本地測試
kubectl port-forward -n nova-staging svc/ten-agent 8080:80

# 測試健康檢查
curl http://localhost:8080/health

# 測試 WebSocket
wscat -c "ws://localhost:8080/ws/test-channel"
```

## iOS 配置更新

部署成功後，更新 iOS 配置文件：

`ios/NovaSocial/Shared/Services/AI/AliceVoiceConfig.swift`:

```swift
static var tenAgentServerURL: String {
    #if DEBUG
    return "http://localhost:8080"  // 本地開發
    #else
    return "https://alice-voice.staging.nova.social"  // Staging
    #endif
}
```

## 監控

### 查看 Pod 資源使用

```bash
kubectl top pods -n nova-staging -l app=ten-agent
```

### 查看 HPA 狀態

```bash
kubectl get hpa -n nova-staging ten-agent
```

### 查看日誌

```bash
# 實時日誌
kubectl logs -n nova-staging -l app=ten-agent -f

# 特定 Pod 日誌
kubectl logs -n nova-staging <pod-name>
```

## 故障排除

### Pod 無法啟動

```bash
# 查看 Pod 事件
kubectl describe pod -n nova-staging -l app=ten-agent

# 常見問題：
# - Image pull error: 檢查 image 名稱
# - Resource limits: 增加資源限制
# - Secret not found: 確認 Secret 已創建
```

### WebSocket 連接失敗

```bash
# 檢查 Ingress 配置
kubectl describe ingress -n nova-staging ten-agent

# 確認 WebSocket annotations 正確
# nginx.ingress.kubernetes.io/websocket-services: "ten-agent"
```

### API 調用失敗

```bash
# 檢查 Secret 是否正確
kubectl get secret -n nova-staging ten-agent-secrets -o yaml

# 檢查 ConfigMap
kubectl get configmap -n nova-staging ten-agent-config -o yaml
```

## 更新部署

### 更新 Image

```bash
kubectl set image deployment/ten-agent \
  ten-agent=agoraio/ten_agent_server:v1.2.0 \
  -n nova-staging

kubectl rollout status deployment/ten-agent -n nova-staging
```

### 更新配置

```bash
# 編輯 ConfigMap
kubectl edit configmap ten-agent-config -n nova-staging

# 重啟 Deployment
kubectl rollout restart deployment/ten-agent -n nova-staging
```

### 回滾

```bash
kubectl rollout undo deployment/ten-agent -n nova-staging
```

## 清理

```bash
kubectl delete -f k8s/staging/ten-agent-ingress.yaml
kubectl delete -f k8s/staging/ten-agent-hpa.yaml
kubectl delete -f k8s/staging/ten-agent-service.yaml
kubectl delete -f k8s/staging/ten-agent-deployment.yaml
kubectl delete -f k8s/staging/ten-agent-configmap.yaml
```

## 相關文檔

- [TEN Framework 官方文檔](https://doc.theten.ai)
- [Agora RTC iOS SDK](https://docs.agora.io/en/voice-calling/overview/product-overview)
- [Kubernetes Ingress WebSocket](https://kubernetes.github.io/ingress-nginx/user-guide/miscellaneous/#websockets)
