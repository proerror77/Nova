import Foundation

// MARK: - Grok Voice Agent Configuration
/// xAI Grok Voice Agent API 配置
/// 
/// 官方文檔: https://docs.x.ai/docs/guides/voice
/// WebSocket 端點: wss://api.x.ai/v1/realtime
enum GrokVoiceConfig {
    
    // MARK: - API Configuration
    
    /// xAI API Key
    /// 從 https://console.x.ai 獲取
    /// 生產環境建議從服務器動態獲取，不要硬編碼
    static var apiKey: String {
        // 優先從環境變量讀取
        if let key = ProcessInfo.processInfo.environment["XAI_API_KEY"], !key.isEmpty {
            return key
        }
        // 開發用 API Key (Grok 4)
        return "xai-z3V0rtZ6DAQSVBaRgEnvdrTK19r9xbSC4wbwwOKbv4Ku7tfG5nP2SfqJ4fizgrZbwoUpPevvjLNf9AOX"
    }
    
    /// WebSocket 端點
    static let webSocketURL = "wss://api.x.ai/v1/realtime"
    
    /// REST API 基礎 URL
    static let restAPIBaseURL = "https://api.x.ai/v1"
    
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
        
        static let `default`: SampleRate = .rate16000
    }
    
    /// 預設音訊配置
    static let defaultAudioFormat: AudioFormat = .pcm
    static let defaultSampleRate: SampleRate = .rate16000
    
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
    
    // MARK: - Validation
    
    /// 檢查配置是否有效
    static var isConfigured: Bool {
        return apiKey != "YOUR_XAI_API_KEY" && !apiKey.isEmpty
    }
    
    /// 獲取配置錯誤信息
    static var configurationError: String? {
        if apiKey == "YOUR_XAI_API_KEY" || apiKey.isEmpty {
            return "請配置 xAI API Key"
        }
        return nil
    }
    
    // MARK: - Session Configuration Builder
    
    /// 建立 WebSocket session 配置
    static func buildSessionConfig(
        voice: Voice = .default,
        audioFormat: AudioFormat = defaultAudioFormat,
        sampleRate: SampleRate = defaultSampleRate,
        instructions: String? = nil
    ) -> [String: Any] {
        var session: [String: Any] = [
            "voice": voice.rawValue,
            "audio": [
                "input": [
                    "format": [
                        "type": audioFormat.rawValue,
                        "rate": sampleRate.rawValue
                    ]
                ],
                "output": [
                    "format": [
                        "type": audioFormat.rawValue,
                        "rate": sampleRate.rawValue
                    ]
                ]
            ]
        ]
        
        if let instructions = instructions {
            session["instructions"] = instructions
        }
        
        return [
            "type": "session.update",
            "session": session
        ]
    }
    
    /// Alice AI 專用配置
    static func aliceSessionConfig(voice: Voice = .ara) -> [String: Any] {
        buildSessionConfig(
            voice: voice,
            instructions: """
            你是 Alice，ICERED 社交平台的 AI 助理。
            你友善、有幫助，並且能夠用自然的方式與用戶對話。
            你可以幫助用戶了解平台功能、回答問題、提供建議。
            請用繁體中文回應，除非用戶使用其他語言。
            保持回應簡潔，適合語音對話。
            """
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
