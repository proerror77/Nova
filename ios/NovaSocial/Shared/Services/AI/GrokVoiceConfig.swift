import Foundation

// MARK: - Grok Voice Agent Configuration
/// xAI Grok Voice Agent API 配置
///
/// 官方文檔: https://docs.x.ai/docs/guides/voice/agent
/// WebSocket 端點: wss://api.x.ai/v1/realtime
///
/// 安全性: 使用後端代理獲取 ephemeral token，不在客戶端暴露 API key
enum GrokVoiceConfig {

    // MARK: - API Configuration

    /// 後端 API 基礎 URL
    private static var backendBaseURL: String { APIConfig.current.baseURL }

    /// WebSocket 端點 (由後端返回)
    static let defaultWebSocketURL = "wss://api.x.ai/v1/realtime"

    // MARK: - Audio Configuration

    /// 輸入音訊格式
    enum AudioFormat: String {
        case pcm = "audio/pcm"
        case pcmu = "audio/pcmu"  // G.711 μ-law
        case pcma = "audio/pcma"  // G.711 A-law
    }

    /// 音訊採樣率
    enum SampleRate: Int {
        case rate16000 = 16000
        case rate24000 = 24000

        // xAI/OpenAI Realtime API expects 24kHz
        static let `default`: SampleRate = .rate24000
    }

    /// 預設音訊配置
    static let defaultAudioFormat: AudioFormat = .pcm
    static let defaultSampleRate: SampleRate = .rate24000

    // MARK: - Voice Options

    /// 可用的語音選項
    enum Voice: String, CaseIterable {
        case ara = "Ara"    // 標準女聲
        case rex = "Rex"    // 標準男聲
        case sal = "Sal"
        case eve = "Eve"
        case leo = "Leo"

        var displayName: String {
            switch self {
            case .ara: return "Ara (女聲)"
            case .rex: return "Rex (男聲)"
            case .sal: return "Sal"
            case .eve: return "Eve"
            case .leo: return "Leo"
            }
        }

        static let `default`: Voice = .ara
    }

    // MARK: - Session Configuration

    /// 連線超時時間（秒）
    static let connectionTimeout: TimeInterval = 30

    /// 心跳間隔（秒）
    static let heartbeatInterval: TimeInterval = 30

    /// 最大重連次數
    static let maxReconnectAttempts = 3

    /// 重連間隔（秒）
    static let reconnectDelay: TimeInterval = 2

    // MARK: - Token Response Model

    struct VoiceTokenResponse: Codable {
        let clientSecret: ClientSecret
        let websocketUrl: String

        enum CodingKeys: String, CodingKey {
            case clientSecret = "client_secret"
            case websocketUrl = "websocket_url"
        }
    }

    struct ClientSecret: Codable {
        let value: String
        let expiresAt: Int64

        enum CodingKeys: String, CodingKey {
            case value
            case expiresAt = "expires_at"
        }
    }

    // MARK: - Token Fetching

    /// 從後端獲取 ephemeral token
    /// - Returns: VoiceTokenResponse containing the token and WebSocket URL
    static func fetchEphemeralToken() async throws -> VoiceTokenResponse {
        guard let url = URL(string: backendBaseURL + APIConfig.XAI.voiceToken) else {
            throw GrokVoiceError.connectionFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add auth token if available (MainActor access requires await)
        if let token = await AuthenticationManager.shared.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GrokVoiceError.connectionFailed("Invalid response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorJson["message"] as? String {
                throw GrokVoiceError.serverError(message)
            }
            throw GrokVoiceError.serverError("HTTP \(httpResponse.statusCode)")
        }

        let tokenResponse = try JSONDecoder().decode(VoiceTokenResponse.self, from: data)

        #if DEBUG
        print("[GrokVoiceConfig] Got ephemeral token, expires at: \(tokenResponse.clientSecret.expiresAt)")
        #endif

        return tokenResponse
    }

    // MARK: - Function Tool Definition

    /// 自定義函數工具定義
    struct FunctionTool {
        let name: String
        let description: String
        let parameters: [String: Any]

        func toDict() -> [String: Any] {
            return [
                "type": "function",
                "name": name,
                "description": description,
                "parameters": parameters
            ]
        }
    }

    // MARK: - Session Configuration Builder

    /// 建立 WebSocket session 配置
    /// 使用 xAI Grok Voice Agent API 官方格式
    static func buildSessionConfig(
        voice: Voice = .default,
        sampleRate: SampleRate = defaultSampleRate,
        instructions: String? = nil,
        enableWebSearch: Bool = true,
        enableXSearch: Bool = true,
        customFunctions: [FunctionTool] = []
    ) -> [String: Any] {
        var session: [String: Any] = [
            "voice": voice.rawValue,
            "turn_detection": [
                "type": "server_vad",
                "threshold": 0.5,              // VAD 閾值 (0-1)，提高到 0.5 減少誤觸發
                "prefix_padding_ms": 150,       // 語音開始前的填充時間（增加以捕捉完整開頭）
                "silence_duration_ms": 500,     // 靜音持續時間（增加到 500ms 以容許自然停頓）
                "create_response": true,        // 自動創建回應
                "interrupt_response": true      // 允許中斷回應 (barge-in)
            ],
            "audio": [
                "input": [
                    "format": [
                        "type": "audio/pcm",
                        "rate": sampleRate.rawValue
                    ]
                ],
                "output": [
                    "format": [
                        "type": "audio/pcm",
                        "rate": sampleRate.rawValue
                    ]
                ]
            ]
        ]

        if let instructions = instructions {
            session["instructions"] = instructions
        }

        // 組合所有工具
        var tools: [[String: Any]] = []

        // 網頁搜索
        if enableWebSearch {
            tools.append(["type": "web_search"])
        }

        // X/Twitter 搜索
        if enableXSearch {
            tools.append(["type": "x_search"])
        }

        // 自定義函數
        for function in customFunctions {
            tools.append(function.toDict())
        }

        if !tools.isEmpty {
            session["tools"] = tools
        }

        return [
            "type": "session.update",
            "session": session
        ]
    }

    /// 預定義的 ICERED 平台函數工具
    static var iceredFunctionTools: [FunctionTool] {
        return [
            // 查詢用戶資料
            FunctionTool(
                name: "get_user_profile",
                description: "Get user profile information by username or user ID",
                parameters: [
                    "type": "object",
                    "properties": [
                        "username": [
                            "type": "string",
                            "description": "The username to look up"
                        ]
                    ],
                    "required": ["username"]
                ]
            ),
            // 創建貼文
            FunctionTool(
                name: "create_post",
                description: "Create a new post on ICERED platform",
                parameters: [
                    "type": "object",
                    "properties": [
                        "content": [
                            "type": "string",
                            "description": "The text content of the post"
                        ]
                    ],
                    "required": ["content"]
                ]
            ),
            // 搜索貼文
            FunctionTool(
                name: "search_posts",
                description: "Search for posts on ICERED platform",
                parameters: [
                    "type": "object",
                    "properties": [
                        "query": [
                            "type": "string",
                            "description": "Search query keywords"
                        ],
                        "limit": [
                            "type": "number",
                            "description": "Maximum number of results (default 10)"
                        ]
                    ],
                    "required": ["query"]
                ]
            ),
            // 獲取熱門話題
            FunctionTool(
                name: "get_trending_topics",
                description: "Get current trending topics on ICERED",
                parameters: [
                    "type": "object",
                    "properties": [
                        "limit": [
                            "type": "number",
                            "description": "Number of trending topics to return (default 5)"
                        ]
                    ],
                    "required": []
                ]
            )
        ]
    }

    /// Alice System Prompt
    static let aliceSystemPrompt = """
    # You are Alice - The AI Assistant for ICERED Social Platform

    ## Character
    - Name: Alice
    - Role: Official AI assistant for ICERED social platform
    - Personality: Friendly, enthusiastic, witty, and helpful
    - Speaking style: Natural and conversational, like chatting with a friend. Avoid being too formal or robotic.
    - Language: ALWAYS respond in the same language the user speaks (Chinese, English, Japanese, etc.)

    ## About ICERED
    ICERED is a next-generation social platform featuring:
    - Share life moments (photos, videos, stories)
    - Discover trending topics and content
    - Private messaging with friends (end-to-end encrypted)
    - AI-powered content recommendations
    - Diverse content channels (Fashion, Travel, Food, Tech, etc.)

    ## Your Capabilities
    1. **Web Search**: Search the internet for real-time information (news, weather, stocks, etc.)
    2. **X/Twitter Search**: Search trending discussions on X platform
    3. **Platform Functions**: Help users look up profiles, create posts, search content, view trending topics

    ## Response Guidelines
    - Keep responses short and punchy, suitable for voice conversation (usually 2-3 sentences)
    - For complex questions, break down your response
    - Proactively use tools to get real-time information - never guess or make things up
    - Be honest when you don't know something and offer suggestions
    - Add friendly interactions naturally (e.g., "That's a great question!")

    ## Example Interactions
    User: "What's the weather like today?"
    Alice: "Let me check for you!" (uses search tool) "It's sunny in Taipei today, around 25°C - perfect weather for going out!"

    User: "How do I post on ICERED?"
    Alice: "Super easy! Tap the red plus button at the bottom center, choose to take a photo or pick from your gallery, add a caption, and hit post. Done! Want me to walk you through it?"

    Remember: You are the user's best friend and assistant on ICERED!
    """

    /// Alice AI configuration with all tools
    static func aliceSessionConfig(voice: Voice = .ara) -> [String: Any] {
        buildSessionConfig(
            voice: voice,
            instructions: aliceSystemPrompt,
            enableWebSearch: true,
            enableXSearch: true,
            customFunctions: iceredFunctionTools
        )
    }
}

// MARK: - Pricing Information
/*
 ## Grok Voice Agent API 定價

 - 連線時間費率: $0.05/分鐘
 - 按連線時間計費，非按 token 計費
 - 包含 STT + LLM + TTS 全部功能

 ## 對比舊方案 (TEN Agent + Agora)

 舊方案成本組成:
 - Agora RTC: ~$0.99/1000分鐘
 - Deepgram STT: ~$0.0043/分鐘
 - OpenAI GPT-4: ~$0.03/1K tokens
 - ElevenLabs TTS: ~$0.30/1K characters

 Grok 方案優勢:
 - 單一費率，成本可預測
 - 無需管理多個服務
 - 無需部署後端服務
 */
