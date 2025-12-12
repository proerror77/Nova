# TEN Agent Docker Image 構建
# 基於 TEN Framework 官方代碼構建

FROM python:3.11-slim AS builder

WORKDIR /app

# 安裝系統依賴
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# 克隆 TEN Agent 代碼
RUN git clone --depth 1 https://github.com/TEN-framework/TEN-Agent.git /app/ten-agent

WORKDIR /app/ten-agent/ai_agents

# 安裝 Python 依賴
RUN pip install --no-cache-dir -r requirements.txt 2>/dev/null || \
    pip install --no-cache-dir \
    fastapi \
    uvicorn \
    websockets \
    httpx \
    pydantic \
    python-dotenv \
    aiohttp

# ===== 生產環境映象 =====
FROM python:3.11-slim

WORKDIR /app

# 複製構建產物
COPY --from=builder /app/ten-agent/ai_agents /app
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages

# 創建非 root 用戶
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

# 暴露端口
EXPOSE 8080

# 健康檢查
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# 啟動服務
CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
