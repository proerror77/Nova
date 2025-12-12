import Foundation
import AVFoundation
import AgoraRtcKit

// MARK: - Voice Chat Configuration
/// 使用 AliceVoiceConfig 統一管理配置
private struct VoiceChatConfig {
    static var agoraAppId: String { AliceVoiceConfig.agoraAppId }
    static var tenAgentServerURL: String { AliceVoiceConfig.tenAgentServerURL }
    static var channelPrefix: String { AliceVoiceConfig.channelPrefix }
}

// MARK: - Voice Chat State
enum VoiceChatState: Equatable {
    case disconnected
    case connecting
    case connected
    case speaking
    case listening
    case processing
    case error(String)
    
    var description: String {
        switch self {
        case .disconnected: return "未連線"
        case .connecting: return "連線中..."
        case .connected: return "已連線"
        case .speaking: return "正在說話..."
        case .listening: return "正在聆聽..."
        case .processing: return "AI 思考中..."
        case .error(let msg): return "錯誤: \(msg)"
        }
    }
}

// MARK: - Voice Chat Delegate
protocol VoiceChatServiceDelegate: AnyObject {
    func voiceChatStateDidChange(_ state: VoiceChatState)
    func voiceChatDidReceiveTranscript(_ text: String, isFinal: Bool)
    func voiceChatDidReceiveAIResponse(_ text: String)
    func voiceChatAudioLevelDidChange(_ level: Float)
}

// MARK: - Voice Chat Service
@Observable
final class VoiceChatService: NSObject {
    static let shared = VoiceChatService()
    
    // MARK: - Properties
    private(set) var state: VoiceChatState = .disconnected
    private(set) var isConnected: Bool = false
    private(set) var isMuted: Bool = false
    private(set) var currentTranscript: String = ""
    private(set) var aiResponse: String = ""
    
    weak var delegate: VoiceChatServiceDelegate?
    
    // Agora RTC Engine
    private var agoraKit: AgoraRtcEngineKit?
    private var channelName: String = ""
    private var uid: UInt = 0
    
    // Audio Session
    private let audioSession = AVAudioSession.sharedInstance()
    
    // TEN Agent API
    private var tenAgentSession: URLSessionWebSocketTask?
    private var tenAgentURL: URL?
    
    // MARK: - Initialization
    private override init() {
        super.init()
        setupAgoraEngine()
    }
    
    deinit {
        leaveChannel()
        agoraKit?.leaveChannel(nil)
        AgoraRtcEngineKit.destroy()
    }
    
    // MARK: - Setup
    private func setupAgoraEngine() {
        let config = AgoraRtcEngineConfig()
        config.appId = VoiceChatConfig.agoraAppId
        
        agoraKit = AgoraRtcEngineKit.sharedEngine(with: config, delegate: self)
        
        // 配置音頻設置
        agoraKit?.setChannelProfile(.communication)
        agoraKit?.setAudioProfile(.speechStandard, scenario: .chatRoom)
        agoraKit?.enableAudio()
        agoraKit?.setEnableSpeakerphone(true)
        
        // 啟用音量指示
        agoraKit?.enableAudioVolumeIndication(200, smooth: 3, reportVad: true)
        
        #if DEBUG
        print("[VoiceChatService] Agora engine initialized")
        #endif
    }
    
    private func setupAudioSession() {
        do {
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
            #if DEBUG
            print("[VoiceChatService] Audio session configured")
            #endif
        } catch {
            #if DEBUG
            print("[VoiceChatService] Failed to configure audio session: \(error)")
            #endif
            updateState(.error("無法配置音頻: \(error.localizedDescription)"))
        }
    }
    
    // MARK: - Public Methods
    
    /// 開始語音對話
    /// - Parameter userId: 用戶 ID（可選）
    func startVoiceChat(userId: String? = nil) {
        guard state == .disconnected || state == .error("") else {
            #if DEBUG
            print("[VoiceChatService] Already connected or connecting")
            #endif
            return
        }
        
        updateState(.connecting)
        setupAudioSession()
        
        // 生成唯一的頻道名稱
        let uniqueId = userId ?? UUID().uuidString.prefix(8).lowercased()
        channelName = "\(VoiceChatConfig.channelPrefix)\(uniqueId)"
        
        // 先連接到 TEN Agent
        connectToTENAgent { [weak self] success in
            guard let self = self else { return }
            
            if success {
                // 加入 Agora 頻道
                self.joinAgoraChannel()
            } else {
                self.updateState(.error("無法連接到 AI 服務"))
            }
        }
    }
    
    /// 結束語音對話
    func endVoiceChat() {
        leaveChannel()
        disconnectFromTENAgent()
        updateState(.disconnected)
        currentTranscript = ""
        aiResponse = ""
    }
    
    /// 切換靜音狀態
    func toggleMute() {
        isMuted.toggle()
        agoraKit?.muteLocalAudioStream(isMuted)
        
        #if DEBUG
        print("[VoiceChatService] Mute toggled: \(isMuted)")
        #endif
    }
    
    /// 切換揚聲器
    func toggleSpeaker() {
        let currentSpeaker = audioSession.currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
        agoraKit?.setEnableSpeakerphone(!currentSpeaker)
    }
    
    // MARK: - Private Methods
    
    private func updateState(_ newState: VoiceChatState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.state = newState
            self.isConnected = (newState == .connected || newState == .speaking || newState == .listening || newState == .processing)
            self.delegate?.voiceChatStateDidChange(newState)
        }
    }
    
    private func joinAgoraChannel() {
        // 生成臨時 token（生產環境應從服務器獲取）
        let token: String? = nil  // TODO: 從服務器獲取 token
        
        let option = AgoraRtcChannelMediaOptions()
        option.publishMicrophoneTrack = true
        option.autoSubscribeAudio = true
        option.clientRoleType = .broadcaster
        
        let result = agoraKit?.joinChannel(
            byToken: token,
            channelId: channelName,
            uid: 0,
            mediaOptions: option
        )
        
        if result != 0 {
            #if DEBUG
            print("[VoiceChatService] Failed to join channel: \(result ?? -1)")
            #endif
            updateState(.error("無法加入語音頻道"))
        }
    }
    
    private func leaveChannel() {
        agoraKit?.leaveChannel(nil)
        isConnected = false
        
        #if DEBUG
        print("[VoiceChatService] Left channel")
        #endif
    }
    
    // MARK: - TEN Agent Connection
    
    private func connectToTENAgent(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(VoiceChatConfig.tenAgentServerURL)/ws/\(channelName)") else {
            completion(false)
            return
        }
        
        tenAgentURL = url
        let session = URLSession(configuration: .default)
        tenAgentSession = session.webSocketTask(with: url)
        tenAgentSession?.resume()
        
        // 發送初始化消息
        let initMessage: [String: Any] = [
            "type": "init",
            "channel": channelName,
            "config": [
                "stt": "deepgram",
                "llm": "openai",
                "tts": "elevenlabs"
            ]
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: initMessage),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            tenAgentSession?.send(.string(jsonString)) { error in
                if let error = error {
                    #if DEBUG
                    print("[VoiceChatService] Failed to send init message: \(error)")
                    #endif
                    completion(false)
                } else {
                    self.startReceivingMessages()
                    completion(true)
                }
            }
        } else {
            completion(false)
        }
    }
    
    private func disconnectFromTENAgent() {
        tenAgentSession?.cancel(with: .goingAway, reason: nil)
        tenAgentSession = nil
    }
    
    private func startReceivingMessages() {
        tenAgentSession?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                self.handleTENAgentMessage(message)
                // 繼續接收下一條消息
                self.startReceivingMessages()
                
            case .failure(let error):
                #if DEBUG
                print("[VoiceChatService] WebSocket error: \(error)")
                #endif
                self.updateState(.error("連線中斷"))
            }
        }
    }
    
    private func handleTENAgentMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else {
                return
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                switch type {
                case "transcript":
                    // STT 轉錄結果
                    if let transcript = json["text"] as? String {
                        let isFinal = json["is_final"] as? Bool ?? false
                        self.currentTranscript = transcript
                        self.delegate?.voiceChatDidReceiveTranscript(transcript, isFinal: isFinal)
                        
                        if isFinal {
                            self.updateState(.processing)
                        }
                    }
                    
                case "response":
                    // AI 回覆
                    if let response = json["text"] as? String {
                        self.aiResponse = response
                        self.delegate?.voiceChatDidReceiveAIResponse(response)
                        self.updateState(.listening)
                    }
                    
                case "speaking":
                    // TTS 正在播放
                    self.updateState(.listening)
                    
                case "listening":
                    // 等待用戶說話
                    self.updateState(.speaking)
                    
                case "error":
                    if let errorMsg = json["message"] as? String {
                        self.updateState(.error(errorMsg))
                    }
                    
                default:
                    break
                }
            }
            
        case .data:
            // 處理二進制數據（如果需要）
            break
            
        @unknown default:
            break
        }
    }
}

// MARK: - Agora RTC Delegate
extension VoiceChatService: AgoraRtcEngineDelegate {
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinChannel channel: String, withUid uid: UInt, elapsed: Int) {
        #if DEBUG
        print("[VoiceChatService] Joined channel: \(channel), uid: \(uid)")
        #endif
        
        self.uid = uid
        updateState(.connected)
        
        // 短暫延遲後開始聆聽
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.updateState(.speaking)
        }
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didLeaveChannelWith stats: AgoraChannelStats) {
        #if DEBUG
        print("[VoiceChatService] Left channel")
        #endif
        updateState(.disconnected)
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurError errorCode: AgoraErrorCode) {
        #if DEBUG
        print("[VoiceChatService] Agora error: \(errorCode.rawValue)")
        #endif
        updateState(.error("語音連線錯誤: \(errorCode.rawValue)"))
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurWarning warningCode: AgoraWarningCode) {
        #if DEBUG
        print("[VoiceChatService] Agora warning: \(warningCode.rawValue)")
        #endif
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, reportAudioVolumeIndicationOfSpeakers speakers: [AgoraRtcAudioVolumeInfo], totalVolume: Int) {
        // 報告音量級別
        for speaker in speakers {
            if speaker.uid == 0 {
                // 本地用戶的音量
                let normalizedLevel = Float(speaker.volume) / 255.0
                delegate?.voiceChatAudioLevelDidChange(normalizedLevel)
            }
        }
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinedOfUid uid: UInt, elapsed: Int) {
        #if DEBUG
        print("[VoiceChatService] Remote user joined: \(uid)")
        #endif
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOfflineOfUid uid: UInt, reason: AgoraUserOfflineReason) {
        #if DEBUG
        print("[VoiceChatService] Remote user offline: \(uid), reason: \(reason.rawValue)")
        #endif
    }
}

// MARK: - Voice Chat Error
enum VoiceChatError: LocalizedError {
    case notConnected
    case microphonePermissionDenied
    case agoraError(Int)
    case tenAgentError(String)
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "未連接到語音服務"
        case .microphonePermissionDenied:
            return "需要麥克風權限才能使用語音功能"
        case .agoraError(let code):
            return "語音連線錯誤 (\(code))"
        case .tenAgentError(let message):
            return "AI 服務錯誤: \(message)"
        }
    }
}
