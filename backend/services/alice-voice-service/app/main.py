"""
Alice Voice Service - 語音 AI 對話服務

整合：
- Deepgram: STT (語音轉文字)
- OpenAI Compatible API: LLM (對話生成)
- WebSocket: 實時通訊
"""

import os
import json
import asyncio
from typing import Optional
from contextlib import asynccontextmanager

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import httpx

# ============= 配置 =============
class Settings:
    # Deepgram STT
    DEEPGRAM_API_KEY: str = os.getenv("DEEPGRAM_API_KEY", "")
    
    # OpenAI Compatible LLM
    OPENAI_API_KEY: str = os.getenv("OPENAI_API_KEY", "")
    OPENAI_BASE_URL: str = os.getenv("OPENAI_BASE_URL", "https://api.openai.com/v1")
    OPENAI_MODEL: str = os.getenv("OPENAI_MODEL", "gpt-4o")
    
    # Agora (用於 RTC Token 生成)
    AGORA_APP_ID: str = os.getenv("AGORA_APP_ID", "")
    AGORA_APP_CERTIFICATE: str = os.getenv("AGORA_APP_CERTIFICATE", "")
    
    # Server
    LOG_LEVEL: str = os.getenv("LOG_LEVEL", "info")

settings = Settings()

# ============= 連接管理 =============
class ConnectionManager:
    def __init__(self):
        self.active_connections: dict[str, WebSocket] = {}
        self.conversation_history: dict[str, list] = {}
    
    async def connect(self, channel_id: str, websocket: WebSocket):
        await websocket.accept()
        self.active_connections[channel_id] = websocket
        self.conversation_history[channel_id] = []
        print(f"[ConnectionManager] Client connected: {channel_id}")
    
    def disconnect(self, channel_id: str):
        if channel_id in self.active_connections:
            del self.active_connections[channel_id]
        if channel_id in self.conversation_history:
            del self.conversation_history[channel_id]
        print(f"[ConnectionManager] Client disconnected: {channel_id}")
    
    async def send_message(self, channel_id: str, message: dict):
        if channel_id in self.active_connections:
            await self.active_connections[channel_id].send_json(message)
    
    def add_to_history(self, channel_id: str, role: str, content: str):
        if channel_id in self.conversation_history:
            self.conversation_history[channel_id].append({
                "role": role,
                "content": content
            })
            # 保持最近 20 條消息
            if len(self.conversation_history[channel_id]) > 20:
                self.conversation_history[channel_id] = self.conversation_history[channel_id][-20:]
    
    def get_history(self, channel_id: str) -> list:
        return self.conversation_history.get(channel_id, [])

manager = ConnectionManager()

# ============= LLM 服務 =============
class LLMService:
    def __init__(self):
        self.client = httpx.AsyncClient(timeout=60.0)
        self.base_url = settings.OPENAI_BASE_URL
        self.api_key = settings.OPENAI_API_KEY
        self.model = settings.OPENAI_MODEL
    
    async def chat(self, messages: list, system_prompt: Optional[str] = None) -> str:
        """發送消息到 LLM 並獲取回覆"""
        url = f"{self.base_url}/chat/completions"
        
        # 添加系統提示
        full_messages = []
        if system_prompt:
            full_messages.append({"role": "system", "content": system_prompt})
        full_messages.extend(messages)
        
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        
        payload = {
            "model": self.model,
            "messages": full_messages,
            "max_tokens": 500,
            "temperature": 0.7
        }
        
        try:
            response = await self.client.post(url, json=payload, headers=headers)
            response.raise_for_status()
            data = response.json()
            return data["choices"][0]["message"]["content"]
        except Exception as e:
            print(f"[LLMService] Error: {e}")
            raise

llm_service = LLMService()

# ============= FastAPI 應用 =============
@asynccontextmanager
async def lifespan(app: FastAPI):
    # 啟動時
    print("[Alice Voice Service] Starting up...")
    yield
    # 關閉時
    print("[Alice Voice Service] Shutting down...")
    await llm_service.client.aclose()

# 獲取路徑前綴（用於在 Ingress 後運行）
ROOT_PATH = os.getenv("ROOT_PATH", "")

app = FastAPI(
    title="Alice Voice Service",
    description="語音 AI 對話服務",
    version="1.0.0",
    lifespan=lifespan,
    root_path=ROOT_PATH
)

# CORS 配置
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ============= API 端點 =============

# 支持帶路徑前綴和不帶路徑前綴的訪問
@app.get("/health")
@app.get("/alice-voice/health")
async def health_check():
    """健康檢查"""
    return {
        "status": "healthy",
        "service": "alice-voice-service",
        "version": "1.0.0"
    }

@app.get("/")
@app.get("/alice-voice")
@app.get("/alice-voice/")
async def root():
    """根路徑"""
    return {
        "service": "Alice Voice Service",
        "status": "running",
        "endpoints": {
            "health": "/health",
            "websocket": "/ws/{channel_id}",
            "chat": "/api/chat"
        }
    }

class ChatRequest(BaseModel):
    message: str
    channel_id: Optional[str] = "default"
    system_prompt: Optional[str] = "你是 Alice，一個友好、智慧的 AI 助手。請用簡潔的語言回答問題。"

class ChatResponse(BaseModel):
    response: str
    channel_id: str

@app.post("/api/chat", response_model=ChatResponse)
@app.post("/alice-voice/api/chat", response_model=ChatResponse)
async def chat_endpoint(request: ChatRequest):
    """文字聊天端點"""
    try:
        # 添加用戶消息到歷史
        manager.add_to_history(request.channel_id, "user", request.message)
        
        # 獲取對話歷史
        history = manager.get_history(request.channel_id)
        
        # 調用 LLM
        response = await llm_service.chat(history, request.system_prompt)
        
        # 添加助手回覆到歷史
        manager.add_to_history(request.channel_id, "assistant", response)
        
        return ChatResponse(response=response, channel_id=request.channel_id)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# ============= WebSocket 端點 =============

ALICE_SYSTEM_PROMPT = """你是 Alice，一個友好、智慧的 AI 語音助手。
請用簡潔、自然的語言回答問題，就像在進行真實的對話一樣。
回覆應該簡短（1-3 句話），除非用戶要求更詳細的解釋。
保持友好和專業的語氣。"""

@app.websocket("/ws/{channel_id}")
@app.websocket("/alice-voice/ws/{channel_id}")
async def websocket_endpoint(websocket: WebSocket, channel_id: str):
    """WebSocket 語音對話端點"""
    await manager.connect(channel_id, websocket)
    
    try:
        # 發送連接成功消息
        await manager.send_message(channel_id, {
            "type": "connected",
            "channel_id": channel_id,
            "message": "已連接到 Alice Voice Service"
        })
        
        while True:
            # 接收消息
            data = await websocket.receive_text()
            message = json.loads(data)
            
            msg_type = message.get("type", "")
            
            if msg_type == "init":
                # 初始化消息
                await manager.send_message(channel_id, {
                    "type": "ready",
                    "message": "準備就緒，可以開始對話"
                })
            
            elif msg_type == "transcript":
                # 收到語音轉文字結果
                text = message.get("text", "")
                is_final = message.get("is_final", False)
                
                if is_final and text.strip():
                    # 通知正在處理
                    await manager.send_message(channel_id, {
                        "type": "processing",
                        "text": text
                    })
                    
                    # 添加到對話歷史
                    manager.add_to_history(channel_id, "user", text)
                    
                    # 調用 LLM
                    try:
                        history = manager.get_history(channel_id)
                        response = await llm_service.chat(history, ALICE_SYSTEM_PROMPT)
                        
                        # 添加回覆到歷史
                        manager.add_to_history(channel_id, "assistant", response)
                        
                        # 發送回覆
                        await manager.send_message(channel_id, {
                            "type": "response",
                            "text": response
                        })
                    except Exception as e:
                        await manager.send_message(channel_id, {
                            "type": "error",
                            "message": f"處理消息時發生錯誤: {str(e)}"
                        })
            
            elif msg_type == "text":
                # 直接收到文字消息
                text = message.get("text", "")
                
                if text.strip():
                    # 添加到對話歷史
                    manager.add_to_history(channel_id, "user", text)
                    
                    # 調用 LLM
                    try:
                        history = manager.get_history(channel_id)
                        response = await llm_service.chat(history, ALICE_SYSTEM_PROMPT)
                        
                        # 添加回覆到歷史
                        manager.add_to_history(channel_id, "assistant", response)
                        
                        # 發送回覆
                        await manager.send_message(channel_id, {
                            "type": "response",
                            "text": response
                        })
                    except Exception as e:
                        await manager.send_message(channel_id, {
                            "type": "error",
                            "message": f"處理消息時發生錯誤: {str(e)}"
                        })
            
            elif msg_type == "ping":
                # 心跳
                await manager.send_message(channel_id, {"type": "pong"})
    
    except WebSocketDisconnect:
        manager.disconnect(channel_id)
    except Exception as e:
        print(f"[WebSocket] Error: {e}")
        manager.disconnect(channel_id)

# ============= 啟動 =============
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
