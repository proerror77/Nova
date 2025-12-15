import Foundation

// MARK: - Alice Voice Chat Configuration
/// 配置 TEN Agent + Agora 語音對話功能
/// 
/// 使用說明：
/// 1. 將此文件中的佔位符替換為實際的 API 金鑰
/// 2. 生產環境建議從服務器獲取這些配置，不要硬編碼
enum AliceVoiceConfig {
    
    // MARK: - Agora RTC 配置
    /// Agora App ID
    /// 從 https://console.agora.io 獲取
    static let agoraAppId = "d371c9215217473abe07541327cbf3d4"
    
    /// Agora App Certificate（可選，用於 Token 驗證）
    static let agoraAppCertificate = "YOUR_AGORA_APP_CERTIFICATE"
    
    // MARK: - TEN Agent 服務器配置
    /// Alice Voice Service 後端服務器地址（通過 GCE URL Map routeRules 進行 URL 重寫）
    /// 開發環境: http://localhost:8080
    /// Staging 環境: http://34.8.163.8/alice-voice (通過主 API 網關)
    /// 生產環境: https://api.nova.social/alice-voice
    static var tenAgentServerURL: String {
        APIConfig.AliceVoice.baseURL
    }

    /// TEN Agent API Endpoints
    static var startSessionURL: String { APIConfig.AliceVoice.start }
    static var stopSessionURL: String { APIConfig.AliceVoice.stop }
    static var pingSessionURL: String { APIConfig.AliceVoice.ping }
    static var healthCheckURL: String { APIConfig.AliceVoice.health }
    
    // MARK: - 頻道配置
    /// 頻道名稱前綴
    static let channelPrefix = "alice_voice_"
    
    /// 默認超時時間（秒）
    static let connectionTimeout: TimeInterval = 30
    
    // MARK: - 驗證方法
    /// 檢查配置是否有效
    static var isConfigured: Bool {
        return agoraAppId != "YOUR_AGORA_APP_ID" &&
               !agoraAppId.isEmpty
    }
    
    /// 獲取配置錯誤信息
    static var configurationError: String? {
        if agoraAppId == "YOUR_AGORA_APP_ID" || agoraAppId.isEmpty {
            return "請配置 Agora App ID"
        }
        return nil
    }
}

// MARK: - 使用說明
/*
 ## TEN Agent + Agora 語音對話設置指南
 
 ### 1. 獲取 Agora 憑證
 - 訪問 https://console.agora.io
 - 創建新專案或選擇現有專案
 - 複製 App ID 和 App Certificate
 
 ### 2. 部署 TEN Agent 後端
 - 進入 infra/ten-agent 目錄
 - 複製 .env.example 為 .env
 - 填入所需的 API 金鑰：
   - AGORA_APP_ID
   - AGORA_APP_CERTIFICATE
   - DEEPGRAM_API_KEY (STT)
   - OPENAI_API_KEY (LLM)
   - ELEVENLABS_API_KEY (TTS)
 - 執行 docker-compose up -d
 
 ### 3. 更新此配置文件
 - 將 agoraAppId 替換為你的 Agora App ID
 - 如果使用 Token 驗證，更新 agoraAppCertificate
 - 更新 tenAgentServerURL 為實際部署地址
 
 ### 4. 測試
 - 在 Alice 頁面點擊 "Voice Mode" 按鈕
 - 授予麥克風權限
 - 開始與 Alice AI 進行語音對話
 */
