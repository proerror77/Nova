import Foundation
import AVFoundation
#if !targetEnvironment(simulator)
import AgoraRtcKit
#endif

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

    /// Whether running in simulator demo mode (no real Agora connection)
    private(set) var isSimulatorMode: Bool = false

    weak var delegate: VoiceChatServiceDelegate?

    #if !targetEnvironment(simulator)
    // Agora RTC Engine - only available on real devices
    private var agoraKit: AgoraRtcEngineKit?
    #endif

    private var channelName: String = ""
    private var uid: UInt = 0

    // Audio Session
    private let audioSession = AVAudioSession.sharedInstance()

    // TEN Agent API
    private var tenAgentRequestId: String?
    // Use AliceVoiceConfig for endpoint URLs
    private var tenAgentBaseURL: String { AliceVoiceConfig.tenAgentServerURL }

    // Demo mode timer for simulating state changes
    private var demoTimer: Timer?

    // Track if backend is available
    private var backendAvailable: Bool = false

    // MARK: - Initialization
    private override init() {
        super.init()

        #if targetEnvironment(simulator)
        isSimulatorMode = true
        #if DEBUG
        print("[VoiceChatService] Running in SIMULATOR DEMO MODE - Agora SDK disabled")
        #endif
        #endif
    }

    deinit {
        demoTimer?.invalidate()
        #if !targetEnvironment(simulator)
        leaveChannel()
        agoraKit?.leaveChannel(nil)
        AgoraRtcEngineKit.destroy()
        #endif
    }

    // MARK: - Setup (Real Device Only)
    #if !targetEnvironment(simulator)
    private func setupAgoraEngine() -> Bool {
        // Check if already initialized
        if agoraKit != nil {
            return true
        }

        // Validate App ID
        guard !VoiceChatConfig.agoraAppId.isEmpty,
              VoiceChatConfig.agoraAppId != "YOUR_AGORA_APP_ID" else {
            #if DEBUG
            print("[VoiceChatService] Error: Invalid Agora App ID")
            #endif
            updateState(.error("語音服務未配置"))
            return false
        }

        let config = AgoraRtcEngineConfig()
        config.appId = VoiceChatConfig.agoraAppId

        // Try to initialize Agora engine safely
        agoraKit = AgoraRtcEngineKit.sharedEngine(with: config, delegate: self)

        guard agoraKit != nil else {
            #if DEBUG
            print("[VoiceChatService] Error: Failed to create Agora engine")
            #endif
            updateState(.error("無法初始化語音引擎"))
            return false
        }

        // 配置音頻設置
        agoraKit?.setChannelProfile(.communication)
        agoraKit?.setAudioProfile(.speechStandard, scenario: .chatRoom)
        agoraKit?.enableAudio()
        agoraKit?.setEnableSpeakerphone(true)

        // 啟用音量指示
        agoraKit?.enableAudioVolumeIndication(200, smooth: 3, reportVad: true)

        #if DEBUG
        print("[VoiceChatService] Agora engine initialized successfully")
        #endif

        return true
    }
    #endif

    private func setupAudioSession() {
        #if !targetEnvironment(simulator)
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
        #else
        #if DEBUG
        print("[VoiceChatService] Simulator mode - skipping audio session setup")
        #endif
        #endif
    }

    // MARK: - Public Methods

    /// 開始語音對話
    /// - Parameter userId: 用戶 ID（可選）
    func startVoiceChat(userId: String? = nil) {
        guard state == .disconnected || state.description.contains("錯誤") else {
            #if DEBUG
            print("[VoiceChatService] Already connected or connecting")
            #endif
            return
        }

        updateState(.connecting)

        #if targetEnvironment(simulator)
        // SIMULATOR DEMO MODE
        startDemoMode()
        #else
        // REAL DEVICE MODE
        // Initialize Agora engine lazily
        guard setupAgoraEngine() else {
            #if DEBUG
            print("[VoiceChatService] Failed to setup Agora engine")
            #endif
            // State already set to error in setupAgoraEngine
            return
        }

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
        #endif
    }

    /// 結束語音對話
    func endVoiceChat() {
        #if targetEnvironment(simulator)
        stopDemoMode()
        #else
        leaveChannel()
        disconnectFromTENAgent()
        #endif

        updateState(.disconnected)
        currentTranscript = ""
        aiResponse = ""
    }

    /// 切換靜音狀態
    func toggleMute() {
        isMuted.toggle()

        #if !targetEnvironment(simulator)
        agoraKit?.muteLocalAudioStream(isMuted)
        #endif

        #if DEBUG
        print("[VoiceChatService] Mute toggled: \(isMuted)")
        #endif
    }

    /// 切換揚聲器
    func toggleSpeaker() {
        #if !targetEnvironment(simulator)
        let currentSpeaker = audioSession.currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
        agoraKit?.setEnableSpeakerphone(!currentSpeaker)
        #endif
    }

    // MARK: - Demo Mode (Simulator Only)

    private func startDemoMode() {
        #if DEBUG
        print("[VoiceChatService] Starting DEMO MODE")
        #endif

        // Simulate connection after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, self.state == .connecting else { return }
            self.updateState(.connected)

            // Start cycling through demo states
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.updateState(.speaking)
                self?.startDemoStateSimulation()
            }
        }
    }

    private func startDemoStateSimulation() {
        // Create a timer to simulate audio level changes
        demoTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self, self.isConnected else {
                self?.demoTimer?.invalidate()
                return
            }

            // Simulate random audio levels
            let randomLevel = Float.random(in: 0.1...0.8)
            self.delegate?.voiceChatAudioLevelDidChange(randomLevel)
        }

        // Simulate a demo conversation
        simulateDemoConversation()
    }

    private func simulateDemoConversation() {
        // Demo transcript messages (user speech)
        let transcriptMessages: [(delay: TimeInterval, text: String)] = [
            (delay: 3.0, text: "你好 Alice"),
            (delay: 15.0, text: "這是模擬模式嗎？"),
        ]

        // Demo AI response messages
        let responseMessages: [(delay: TimeInterval, text: String)] = [
            (delay: 5.0, text: "你好！我是 Alice，你的 AI 助理。\n\n⚠️ 目前正在模擬器上運行演示模式，無法進行真正的語音對話。\n\n請在真機上測試，並確保 TEN Agent 後端服務正在運行。"),
            (delay: 17.0, text: "是的，這是演示模式。要啟用真正的語音對話功能：\n\n1. 在真機上運行 App\n2. 部署 TEN Agent 後端服務\n3. 確保 Agora、Deepgram、OpenAI API 金鑰已配置\n\n詳見 infra/ten-agent/README.md"),
        ]

        // Schedule transcript messages
        for message in transcriptMessages {
            DispatchQueue.main.asyncAfter(deadline: .now() + message.delay) { [weak self] in
                guard let self = self, self.isConnected else { return }
                self.currentTranscript = message.text
                self.delegate?.voiceChatDidReceiveTranscript(message.text, isFinal: true)
                self.updateState(.processing)
            }
        }

        // Schedule AI response messages
        for message in responseMessages {
            DispatchQueue.main.asyncAfter(deadline: .now() + message.delay) { [weak self] in
                guard let self = self, self.isConnected else { return }
                self.aiResponse = message.text
                self.delegate?.voiceChatDidReceiveAIResponse(message.text)
                self.updateState(.listening)

                // Go back to speaking state after response
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let self = self, self.isConnected else { return }
                    self.updateState(.speaking)
                }
            }
        }
    }

    private func stopDemoMode() {
        demoTimer?.invalidate()
        demoTimer = nil

        #if DEBUG
        print("[VoiceChatService] Stopped DEMO MODE")
        #endif
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

    #if !targetEnvironment(simulator)
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
    #endif

    // MARK: - TEN Agent Connection (HTTP API)

    /// Start TEN Agent session via HTTP POST /start
    /// The agent will join the same Agora channel and handle STT->LLM->TTS pipeline
    private func connectToTENAgent(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(tenAgentBaseURL)/start") else {
            #if DEBUG
            print("[VoiceChatService] Invalid TEN Agent URL")
            #endif
            completion(false)
            return
        }

        // Generate unique request ID
        let requestId = UUID().uuidString
        tenAgentRequestId = requestId

        // Generate user UID (must match Agora channel)
        let userUid = UInt.random(in: 10000...99999)

        // Build request body per TEN Agent API
        let requestBody: [String: Any] = [
            "request_id": requestId,
            "channel_name": channelName,
            "user_uid": userUid,
            "graph_name": "voice_assistant",  // or "alice_voice" if custom
            "properties": [
                "llm": [
                    "greeting": "你好！我是 Alice，有什麼我可以幫助你的嗎？"
                ]
            ],
            "timeout": 60
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            #if DEBUG
            print("[VoiceChatService] Failed to encode request: \(error)")
            #endif
            completion(false)
            return
        }

        #if DEBUG
        print("[VoiceChatService] Connecting to TEN Agent: \(url)")
        print("[VoiceChatService] Channel: \(channelName), Request ID: \(requestId)")
        #endif

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                #if DEBUG
                print("[VoiceChatService] TEN Agent connection error: \(error)")
                #endif
                DispatchQueue.main.async {
                    self.backendAvailable = false
                    completion(false)
                }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                #if DEBUG
                print("[VoiceChatService] Invalid response from TEN Agent")
                #endif
                DispatchQueue.main.async {
                    self.backendAvailable = false
                    completion(false)
                }
                return
            }

            #if DEBUG
            print("[VoiceChatService] TEN Agent response status: \(httpResponse.statusCode)")
            if let data = data, let responseStr = String(data: data, encoding: .utf8) {
                print("[VoiceChatService] Response: \(responseStr)")
            }
            #endif

            DispatchQueue.main.async {
                if httpResponse.statusCode == 200 {
                    self.backendAvailable = true
                    completion(true)
                } else {
                    self.backendAvailable = false
                    completion(false)
                }
            }
        }.resume()
    }

    /// Stop TEN Agent session via HTTP POST /stop
    private func disconnectFromTENAgent() {
        guard let requestId = tenAgentRequestId,
              let url = URL(string: "\(tenAgentBaseURL)/stop") else {
            return
        }

        let requestBody: [String: Any] = [
            "request_id": requestId,
            "channel_name": channelName
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

        URLSession.shared.dataTask(with: request) { _, _, error in
            #if DEBUG
            if let error = error {
                print("[VoiceChatService] Failed to stop TEN Agent: \(error)")
            } else {
                print("[VoiceChatService] TEN Agent stopped")
            }
            #endif
        }.resume()

        tenAgentRequestId = nil
    }

    /// Keep TEN Agent session alive via HTTP POST /ping
    private func pingTENAgent() {
        guard let requestId = tenAgentRequestId,
              let url = URL(string: "\(tenAgentBaseURL)/ping") else {
            return
        }

        let requestBody: [String: Any] = [
            "request_id": requestId,
            "channel_name": channelName
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

        URLSession.shared.dataTask(with: request) { _, _, _ in
            // Silent ping
        }.resume()
    }
}

// MARK: - Agora RTC Delegate (Real Device Only)
#if !targetEnvironment(simulator)
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
#endif

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
