# Alice Voice Chat - TEN Agent Backend

## Architecture Overview

Alice Voice Chat uses the TEN Framework for real-time voice conversations:

```
iOS App (Agora RTC) <---> Agora Cloud <---> TEN Agent Server (GKE)
                                              |
                                              +-- STT (Deepgram)
                                              +-- LLM (OpenAI/GPT-4)
                                              +-- TTS (OpenAI TTS)
```

**Key Point**: The iOS app does NOT call STT/TTS APIs directly. The TEN Agent server joins the same Agora RTC channel and handles the entire voice pipeline.

## Deployment Options

### Option 1: GKE Kubernetes Deployment (Recommended)

Deploy to Google Kubernetes Engine using GitHub Actions:

```bash
# Manual deployment trigger
gh workflow run deploy-alice-voice-service.yml -f environment=staging

# Or push changes to trigger auto-deploy
git push origin main  # If infra/ten-agent/** files changed
```

**Endpoints after deployment:**
- Staging: `https://api.staging.novaplatform.me/alice-voice`
- Production: `https://api.nova.social/alice-voice`

**K8s Resources:**
- `k8s/microservices/alice-voice-service-deployment.yaml`
- `k8s/microservices/alice-voice-service-service.yaml`
- `k8s/microservices/alice-voice-service-ingress.yaml`
- `k8s/microservices/alice-voice-service-configmap.yaml`
- `k8s/microservices/alice-voice-service-secret.yaml`

See `GCP_SECRETS_SETUP.md` for API keys configuration.

### Option 2: Cloud Server Deployment

Deploy the TEN Agent to a Linux server (AWS EC2, GCP, Azure, etc.):

```bash
# On your cloud server
git clone https://github.com/TEN-framework/TEN-Agent.git
cd TEN-Agent/ai_agents

# Create .env with your API keys
cp .env.example .env
# Edit .env with:
# - AGORA_APP_ID
# - DEEPGRAM_API_KEY
# - OPENAI_API_KEY
# - OPENAI_API_BASE (if using proxy)

# Start the server
docker-compose up -d
cd agents/examples/voice-assistant
task install
task run
```

The server will be available at `http://your-server:8080`

### Option 2: Agora Conversational AI Engine

Use Agora's managed cloud service instead of self-hosting:

1. Enable Conversational AI in [Agora Console](https://console.agora.io)
2. Configure STT, LLM, and TTS providers
3. Update iOS app to use Agora's Conversational AI APIs

See: https://docs.agora.io/en/conversational-ai/

### Option 3: Local Development (macOS)

**Note**: Docker on Apple Silicon has issues with x64 images. Use Rosetta or native tools:

```bash
# Install Go
brew install go

# Build and run server natively
cd TEN-Agent/ai_agents/server
go run main.go

# In another terminal, run the agent
cd TEN-Agent/ai_agents/agents/examples/voice-assistant
# ... (requires tman tool setup)
```

## API Endpoints

The TEN Agent server exposes:

- `POST /start` - Start a voice agent session
- `POST /stop` - Stop a session
- `POST /ping` - Keep session alive

### Start Request

```json
{
  "request_id": "uuid",
  "channel_name": "alice_voice_<user_id>",
  "user_uid": 12345,
  "graph_name": "voice_assistant",
  "properties": {},
  "timeout": 60
}
```

## Configuration

Required environment variables:

| Variable | Description | Example |
|----------|-------------|---------|
| AGORA_APP_ID | Agora App ID | d371c9215217473abe07541327cbf3d4 |
| AGORA_APP_CERTIFICATE | Agora certificate (optional) | |
| DEEPGRAM_API_KEY | Deepgram STT API key | 6a79fabe... |
| OPENAI_API_KEY | OpenAI/compatible API key | sk-... |
| OPENAI_BASE_URL | API base URL | https://api.openai.com/v1 |
| OPENAI_MODEL | LLM model name | gpt-4o |

### Voice Features Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| STT_LANGUAGE | Speech-to-text language | zh-TW |
| TTS_VOICE | Text-to-speech voice | nova |
| ALICE_PROMPT | System prompt for Alice | 你是 Alice... |
| ALICE_GREETING | Initial greeting message | 你好！我是 Alice... |
| TTD_BASE_URL | Turn Detection API URL | https://api.openai.com/v1 |
| TTD_API_KEY | Turn Detection API key | (uses OPENAI_API_KEY) |

## Voice Pipeline Architecture

The voice assistant now supports **continuous conversation** and **voice interruption**:

```
User speaks → Agora RTC → STT (Deepgram) → Turn Detection
                                                  ↓
                                        [Detect turn complete?]
                                                  ↓
                              ┌─────────────────────────────────┐
                              │                                 │
                         [Yes: flush]                    [No: continue]
                              │                                 │
                              ↓                                 ↓
                      Interrupt current              Wait for more speech
                      LLM/TTS output
                              │
                              ↓
                   main_control → LLM → TTS → Agora RTC → User hears
```

### Key Components

- **turn_detection**: Detects when user finishes speaking, sends `flush` command to interrupt
- **main_control**: Coordinates the conversation flow, handles interruptions
- **message_collector**: Collects messages for display/logging
- **max_memory_length**: Keeps last 10 conversation turns for context

## iOS Integration

Update `AliceVoiceConfig.swift` with your server URL:

```swift
static var tenAgentServerURL: String {
    return "https://your-server.com:8080"
}
```

## Troubleshooting

### Demo Mode Active
If you see fake transcripts like "Hello Alice", the app is in demo mode because:
1. Running on iOS Simulator (Agora doesn't work on simulator)
2. Backend server is not reachable

### Backend Connection Failed
Check:
1. Server is running and accessible
2. Agora App ID matches between iOS and server
3. Network allows WebSocket/RTC connections
