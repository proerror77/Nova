# ICERED Voice Agent - Alice

使用 LiveKit Agents + xAI Grok Voice Agent API 的語音助手。

## 架構

```
iOS App (LiveKit Swift SDK)
        ↓ WebRTC
LiveKit Cloud (wss://kok-fjbuamt4.livekit.cloud)
        ↓
Python Agent (本服務)
        ↓
xAI Grok Voice API
```

## 設置

### 1. 安裝依賴

```bash
cd backend/livekit-agent
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt
```

### 2. 配置環境變數

複製 `.env.example` 到 `.env` 並填入你的密鑰：

```bash
cp .env.example .env
```

編輯 `.env`：
- `LIVEKIT_URL`: LiveKit Cloud WebSocket URL
- `LIVEKIT_API_KEY`: LiveKit API Key
- `LIVEKIT_API_SECRET`: LiveKit API Secret
- `XAI_API_KEY`: xAI API Key (從 https://console.x.ai/ 獲取)

### 3. 運行 Agent

開發模式（自動重載）：
```bash
python agent.py dev
```

生產模式：
```bash
python agent.py start
```

## Docker 部署

```bash
docker build -t icered-voice-agent .
docker run --env-file .env icered-voice-agent
```

## iOS 整合

iOS 端需要使用 LiveKit Swift SDK 連接到 LiveKit Cloud 房間。

### SPM 依賴

```swift
.package(url: "https://github.com/livekit/client-sdk-swift.git", from: "2.0.0")
```

### 基本流程

1. 從後端 API 獲取 LiveKit Token
2. 連接到 LiveKit Room
3. 發布麥克風音軌
4. 接收 Agent 的音頻回應

## 功能

- **語音對話**: 支援自然語音交互
- **Barge-in 中斷**: 可在 AI 說話時打斷（WebRTC 內建回聲消除）
- **多語言**: 自動識別並用用戶語言回應
- **搜索工具**: 可配置網頁搜索和 X 搜索功能
