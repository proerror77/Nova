import Foundation

// MARK: - Grok Voice WebSocket Protocol Models
// 基於 xAI Realtime API 規格，與 OpenAI Realtime API 相容

// MARK: - Client → Server Messages

/// 客戶端發送到服務器的訊息類型
enum GrokClientMessageType: String, Codable {
    case sessionUpdate = "session.update"
    case inputAudioBufferAppend = "input_audio_buffer.append"
    case inputAudioBufferCommit = "input_audio_buffer.commit"
    case inputAudioBufferClear = "input_audio_buffer.clear"
    case conversationItemCreate = "conversation.item.create"
    case conversationItemTruncate = "conversation.item.truncate"
    case conversationItemDelete = "conversation.item.delete"
    case responseCreate = "response.create"
    case responseCancel = "response.cancel"
}

/// Session 更新請求
struct GrokSessionUpdate: Codable {
    let type: String = "session.update"
    let session: GrokSessionConfig
}

/// Session 配置
struct GrokSessionConfig: Codable {
    var voice: String?
    var audio: GrokAudioConfig?
    var instructions: String?
    var tools: [GrokTool]?
    var turnDetection: GrokTurnDetection?
    
    enum CodingKeys: String, CodingKey {
        case voice, audio, instructions, tools
        case turnDetection = "turn_detection"
    }
}

/// 音訊配置
struct GrokAudioConfig: Codable {
    let input: GrokAudioFormatConfig
    let output: GrokAudioFormatConfig
}

/// 音訊格式配置
struct GrokAudioFormatConfig: Codable {
    let format: GrokAudioFormat
}

/// 音訊格式
struct GrokAudioFormat: Codable {
    let type: String  // "audio/pcm", "audio/pcmu", "audio/pcma"
    let rate: Int     // 16000 or 24000
}

/// Turn Detection 配置
struct GrokTurnDetection: Codable {
    let type: String  // "server_vad"
    var threshold: Double?
    var prefixPaddingMs: Int?
    var silenceDurationMs: Int?
    
    enum CodingKeys: String, CodingKey {
        case type, threshold
        case prefixPaddingMs = "prefix_padding_ms"
        case silenceDurationMs = "silence_duration_ms"
    }
    
    static let serverVAD = GrokTurnDetection(
        type: "server_vad",
        threshold: 0.5,
        prefixPaddingMs: 300,
        silenceDurationMs: 500
    )
}

/// 工具定義
struct GrokTool: Codable {
    let type: String  // "function"
    let name: String
    let description: String
    let parameters: [String: Any]?
    
    enum CodingKeys: String, CodingKey {
        case type, name, description, parameters
    }
    
    init(type: String = "function", name: String, description: String, parameters: [String: Any]? = nil) {
        self.type = type
        self.name = name
        self.description = description
        self.parameters = parameters
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        parameters = nil  // Skip for now
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        // Skip parameters encoding for simplicity
    }
}

/// 音訊緩衝追加
struct GrokInputAudioBufferAppend: Codable {
    let type: String = "input_audio_buffer.append"
    let audio: String  // Base64 encoded PCM audio
}

/// 提交音訊緩衝
struct GrokInputAudioBufferCommit: Codable {
    let type: String = "input_audio_buffer.commit"
}

/// 清除音訊緩衝
struct GrokInputAudioBufferClear: Codable {
    let type: String = "input_audio_buffer.clear"
}

/// 創建回應請求
struct GrokResponseCreate: Codable {
    let type: String = "response.create"
    var response: GrokResponseConfig?
}

/// 回應配置
struct GrokResponseConfig: Codable {
    var modalities: [String]?  // ["text", "audio"]
    var instructions: String?
}

/// 取消回應
struct GrokResponseCancel: Codable {
    let type: String = "response.cancel"
}

// MARK: - Server → Client Messages

/// 服務器發送到客戶端的訊息類型
enum GrokServerMessageType: String, Codable {
    case error = "error"
    case sessionCreated = "session.created"
    case sessionUpdated = "session.updated"
    case inputAudioBufferCommitted = "input_audio_buffer.committed"
    case inputAudioBufferCleared = "input_audio_buffer.cleared"
    case inputAudioBufferSpeechStarted = "input_audio_buffer.speech_started"
    case inputAudioBufferSpeechStopped = "input_audio_buffer.speech_stopped"
    case conversationItemCreated = "conversation.item.created"
    case conversationItemInputAudioTranscriptionCompleted = "conversation.item.input_audio_transcription.completed"
    case conversationItemInputAudioTranscriptionFailed = "conversation.item.input_audio_transcription.failed"
    case conversationItemTruncated = "conversation.item.truncated"
    case conversationItemDeleted = "conversation.item.deleted"
    case responseCreated = "response.created"
    case responseDone = "response.done"
    case responseOutputItemAdded = "response.output_item.added"
    case responseOutputItemDone = "response.output_item.done"
    case responseContentPartAdded = "response.content_part.added"
    case responseContentPartDone = "response.content_part.done"
    case responseTextDelta = "response.text.delta"
    case responseTextDone = "response.text.done"
    case responseAudioTranscriptDelta = "response.audio_transcript.delta"
    case responseAudioTranscriptDone = "response.audio_transcript.done"
    case responseAudioDelta = "response.audio.delta"
    case responseAudioDone = "response.audio.done"
    case responseFunctionCallArgumentsDelta = "response.function_call_arguments.delta"
    case responseFunctionCallArgumentsDone = "response.function_call_arguments.done"
    case rateLimitsUpdated = "rate_limits.updated"
}

/// 通用服務器訊息（用於解析類型）
struct GrokServerMessage: Codable {
    let type: String
    let eventId: String?
    
    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
    }
}

/// 錯誤訊息
struct GrokErrorMessage: Codable {
    let type: String
    let error: GrokError
}

struct GrokError: Codable {
    let type: String
    let code: String?
    let message: String
    let param: String?
}

/// Session 已創建
struct GrokSessionCreated: Codable {
    let type: String
    let session: GrokSessionInfo
}

struct GrokSessionInfo: Codable {
    let id: String
    let model: String?
    let voice: String?
}

/// 語音開始事件
struct GrokSpeechStarted: Codable {
    let type: String
    let audioStartMs: Int
    let itemId: String?
    
    enum CodingKeys: String, CodingKey {
        case type
        case audioStartMs = "audio_start_ms"
        case itemId = "item_id"
    }
}

/// 語音結束事件
struct GrokSpeechStopped: Codable {
    let type: String
    let audioEndMs: Int
    let itemId: String?
    
    enum CodingKeys: String, CodingKey {
        case type
        case audioEndMs = "audio_end_ms"
        case itemId = "item_id"
    }
}

/// 音訊轉錄完成
struct GrokTranscriptionCompleted: Codable {
    let type: String
    let itemId: String
    let contentIndex: Int
    let transcript: String
    
    enum CodingKeys: String, CodingKey {
        case type
        case itemId = "item_id"
        case contentIndex = "content_index"
        case transcript
    }
}

/// 回應文字增量
struct GrokTextDelta: Codable {
    let type: String
    let responseId: String
    let itemId: String
    let outputIndex: Int
    let contentIndex: Int
    let delta: String
    
    enum CodingKeys: String, CodingKey {
        case type
        case responseId = "response_id"
        case itemId = "item_id"
        case outputIndex = "output_index"
        case contentIndex = "content_index"
        case delta
    }
}

/// 回應音訊增量
struct GrokAudioDelta: Codable {
    let type: String
    let responseId: String
    let itemId: String
    let outputIndex: Int
    let contentIndex: Int
    let delta: String  // Base64 encoded audio
    
    enum CodingKeys: String, CodingKey {
        case type
        case responseId = "response_id"
        case itemId = "item_id"
        case outputIndex = "output_index"
        case contentIndex = "content_index"
        case delta
    }
}

/// 音訊轉錄增量
struct GrokAudioTranscriptDelta: Codable {
    let type: String
    let responseId: String
    let itemId: String
    let outputIndex: Int
    let contentIndex: Int
    let delta: String
    
    enum CodingKeys: String, CodingKey {
        case type
        case responseId = "response_id"
        case itemId = "item_id"
        case outputIndex = "output_index"
        case contentIndex = "content_index"
        case delta
    }
}

/// 回應完成
struct GrokResponseDone: Codable {
    let type: String
    let response: GrokResponseInfo
}

struct GrokResponseInfo: Codable {
    let id: String
    let status: String  // "completed", "cancelled", "failed", "incomplete"
    let output: [GrokOutputItem]?
    let usage: GrokUsage?
}

struct GrokOutputItem: Codable {
    let id: String
    let type: String  // "message", "function_call"
    let role: String?
    let content: [GrokContentPart]?
}

struct GrokContentPart: Codable {
    let type: String  // "text", "audio"
    let text: String?
    let transcript: String?
}

struct GrokUsage: Codable {
    let totalTokens: Int?
    let inputTokens: Int?
    let outputTokens: Int?
    
    enum CodingKeys: String, CodingKey {
        case totalTokens = "total_tokens"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

// MARK: - Voice Chat State

/// 語音對話狀態
enum GrokVoiceChatState: Equatable {
    case disconnected
    case connecting
    case connected
    case listening      // VAD 檢測到用戶開始說話
    case processing     // 正在處理用戶輸入
    case responding     // AI 正在回應（播放音訊）
    case error(String)
    
    var description: String {
        switch self {
        case .disconnected: return "未連線"
        case .connecting: return "連線中..."
        case .connected: return "已連線"
        case .listening: return "正在聆聽..."
        case .processing: return "思考中..."
        case .responding: return "回應中..."
        case .error(let msg): return "錯誤: \(msg)"
        }
    }
    
    var isActive: Bool {
        switch self {
        case .connected, .listening, .processing, .responding:
            return true
        default:
            return false
        }
    }
}

// MARK: - Errors

enum GrokVoiceError: LocalizedError {
    case notConfigured
    case connectionFailed(String)
    case websocketError(String)
    case audioError(String)
    case serverError(String)
    case timeout
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "xAI API Key 未配置"
        case .connectionFailed(let reason):
            return "連線失敗: \(reason)"
        case .websocketError(let reason):
            return "WebSocket 錯誤: \(reason)"
        case .audioError(let reason):
            return "音訊錯誤: \(reason)"
        case .serverError(let reason):
            return "服務器錯誤: \(reason)"
        case .timeout:
            return "連線超時"
        case .cancelled:
            return "已取消"
        }
    }
}
