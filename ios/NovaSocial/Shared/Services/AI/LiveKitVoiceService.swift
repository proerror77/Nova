import Foundation
import AVFoundation
import os.log

// ============================================================================
// MARK: - LiveKit Voice Service
// ============================================================================
// 使用 LiveKit Swift SDK + xAI Grok Voice Agent 的語音對話服務
// 提供可靠的 WebRTC 回音消除和 barge-in 支援
//
// 架構:
// iOS App (LiveKit SDK) → LiveKit Cloud (WebRTC) → Python Agent → xAI Grok Voice API
//
// 依賴: 需要添加 LiveKit Swift SDK
// SPM: https://github.com/livekit/client-sdk-swift.git (from 2.0.0)
// ============================================================================

// 暫時使用條件編譯，SDK 添加後啟用
#if canImport(LiveKit)
import LiveKit
#endif

// MARK: - State
enum LiveKitVoiceChatState: Equatable {
    case disconnected
    case connecting
    case connected
    case listening
    case userSpeaking    // 用戶正在說話
    case aiSpeaking
    case error(String)

    var description: String {
        switch self {
        case .disconnected: return "已斷開"
        case .connecting: return "連接中..."
        case .connected: return "已連接"
        case .listening: return "聆聽中..."
        case .userSpeaking: return "你正在說話"
        case .aiSpeaking: return "Alice 正在說話"
        case .error(let msg): return "錯誤: \(msg)"
        }
    }
}

// MARK: - Delegate Protocol
protocol LiveKitVoiceServiceDelegate: AnyObject {
    func liveKitVoiceStateDidChange(_ state: LiveKitVoiceChatState)
    func liveKitVoiceDidReceiveTranscript(_ text: String, isFinal: Bool)
    func liveKitVoiceDidReceiveResponse(_ text: String)
    func liveKitVoiceAudioLevelDidChange(_ level: Float)
    func liveKitVoiceDidReceiveError(_ code: String, message: String)
}

// MARK: - Token Response
struct LiveKitTokenResponse: Codable {
    let token: String
    let url: String
    let room: String
}

// MARK: - Logging
private let lkLog = OSLog(subsystem: "com.app.icered.pro", category: "LiveKitVoice")

private func liveKitLog(_ message: String) {
    os_log("[LiveKitVoice] %{public}@", log: lkLog, type: .info, message)
    print("[LiveKitVoice] \(message)")
}

// MARK: - Service
@Observable
@MainActor
final class LiveKitVoiceService: NSObject {

    // MARK: - Singleton
    static let shared = LiveKitVoiceService()

    // MARK: - Public Properties
    private(set) var state: LiveKitVoiceChatState = .disconnected
    private(set) var isConnected: Bool = false
    private(set) var isMuted: Bool = false
    private(set) var currentTranscript: String = ""
    private(set) var aiResponse: String = ""

    weak var delegate: LiveKitVoiceServiceDelegate?

    // MARK: - LiveKit Components
    #if canImport(LiveKit)
    private var room: Room?
    #endif

    // MARK: - Audio Session
    private let audioSession = AVAudioSession.sharedInstance()

    // MARK: - Configuration
    private var currentToken: String?
    private var serverURL: String = ""

    // MARK: - Initialization
    private override init() {
        super.init()
        liveKitLog("LiveKitVoiceService initialized")
    }

    // MARK: - Public API (Compatible with GrokVoiceService)

    /// 開始語音對話
    func startVoiceChat(voice: GrokVoiceConfig.Voice = .ara) {
        liveKitLog("Starting voice chat with voice: \(voice.rawValue)")

        guard state == .disconnected else {
            liveKitLog("Already connected or connecting")
            return
        }

        Task {
            await connect()
        }
    }

    /// 結束語音對話
    func endVoiceChat() {
        liveKitLog("Ending voice chat")
        disconnect()
    }

    /// 切換靜音
    func toggleMute() {
        isMuted.toggle()
        liveKitLog("Mute toggled: \(isMuted)")

        #if canImport(LiveKit)
        Task {
            // LiveKit 2.x: 使用 setMicrophone 控制麥克風
            try? await room?.localParticipant.setMicrophone(enabled: !isMuted)
        }
        #endif
    }

    /// 設置靜音狀態
    func setMuted(_ muted: Bool) {
        isMuted = muted
        liveKitLog("Setting muted: \(muted)")

        #if canImport(LiveKit)
        Task {
            // LiveKit 2.x: 使用 setMicrophone 控制麥克風
            try? await room?.localParticipant.setMicrophone(enabled: !muted)
        }
        #endif
    }

    // MARK: - Audio Session Setup

    private func setupAudioSession() async {
        do {
            // Configure audio session for voice chat
            // - .playAndRecord: allows both playing received audio and recording microphone
            // - .voiceChat: optimized for voice conversations with echo cancellation
            // - .defaultToSpeaker: output to speaker by default
            // - .allowBluetoothHFP: support Bluetooth headsets
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetoothHFP]
            )
            try audioSession.setActive(true)
            liveKitLog("Audio session configured successfully")
        } catch {
            liveKitLog("Failed to configure audio session: \(error.localizedDescription)")
            updateState(.error("無法配置音訊: \(error.localizedDescription)"))
        }
    }

    private func deactivateAudioSession() {
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            liveKitLog("Audio session deactivated")
        } catch {
            liveKitLog("Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }

    // MARK: - Connection

    private func connect() async {
        updateState(.connecting)

        // 0. 配置音訊會話（必須在連接前設置）
        await setupAudioSession()

        // Check if audio session setup failed
        if case .error = state {
            return
        }

        do {
            // 1. 從後端獲取 LiveKit Token
            let tokenResponse = try await fetchToken()
            currentToken = tokenResponse.token
            serverURL = tokenResponse.url

            // 2. 連接到 LiveKit Room
            #if canImport(LiveKit)
            try await connectToRoom(url: tokenResponse.url, token: tokenResponse.token)
            #else
            // SDK 未添加時的提示
            liveKitLog("⚠️ LiveKit SDK not imported - Please add via SPM:")
            liveKitLog("   URL: https://github.com/livekit/client-sdk-swift.git")
            liveKitLog("   Version: From 2.0.0")
            throw NSError(domain: "LiveKitVoice", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "LiveKit SDK not integrated. Add package via Xcode."])
            #endif

        } catch {
            liveKitLog("Connection failed: \(error.localizedDescription)")
            updateState(.error(error.localizedDescription))
        }
    }

    private func disconnect() {
        liveKitLog("Disconnecting...")

        #if canImport(LiveKit)
        Task {
            await room?.disconnect()
            room = nil
        }
        #endif

        currentToken = nil
        isConnected = false
        currentTranscript = ""
        aiResponse = ""
        updateState(.disconnected)

        // 釋放音訊會話
        deactivateAudioSession()
    }

    // MARK: - Token Fetching

    private func fetchToken() async throws -> LiveKitTokenResponse {
        liveKitLog("Fetching LiveKit token...")

        // 獲取用戶身份
        let userId = AuthenticationManager.shared.currentUser?.id ?? "anonymous-\(UUID().uuidString.prefix(8))"
        let roomName = "voice-\(userId)-\(Int(Date().timeIntervalSince1970))"

        // 構建請求
        guard let url = URL(string: "\(APIConfig.current.baseURL)\(APIConfig.LiveKit.token)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 添加認證 Token
        if let authToken = AuthenticationManager.shared.authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "room_name": roomName,
            "participant_name": userId,
            "agent_name": "alice",  // 指定要分派的 agent
            "metadata": [
                "voice": "ara",
                "platform": "ios"
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            liveKitLog("Token request failed: \(httpResponse.statusCode) - \(errorBody)")
            throw NSError(domain: "LiveKitVoice", code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Token request failed: \(httpResponse.statusCode)"])
        }

        let tokenResponse = try JSONDecoder().decode(LiveKitTokenResponse.self, from: data)
        liveKitLog("Token received for room: \(tokenResponse.room)")

        return tokenResponse
    }

    // MARK: - LiveKit Room Connection
    #if canImport(LiveKit)

    private func connectToRoom(url: String, token: String) async throws {
        liveKitLog("Connecting to LiveKit room at \(url)...")

        // 創建 RoomOptions 配置音訊
        let roomOptions = RoomOptions(
            defaultAudioCaptureOptions: AudioCaptureOptions(
                echoCancellation: true,
                autoGainControl: true,
                noiseSuppression: true
            ),
            defaultAudioPublishOptions: AudioPublishOptions(
                dtx: true  // 啟用不連續傳輸以節省帶寬
            ),
            adaptiveStream: true,  // 自適應串流
            dynacast: true  // 動態廣播
        )

        // 創建 Room 並設置 delegate
        room = Room(roomOptions: roomOptions)
        room?.add(delegate: self)

        // 使用 ConnectOptions 連接
        let connectOptions = ConnectOptions(
            autoSubscribe: true  // 自動訂閱遠端 tracks
        )

        // 連接到 LiveKit 服務器
        try await room?.connect(url: url, token: token, connectOptions: connectOptions)

        isConnected = true
        updateState(.connected)
        liveKitLog("Connected to room successfully")

        // 延遲啟用麥克風，確保音訊引擎已初始化
        try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 秒延遲

        do {
            try await room?.localParticipant.setMicrophone(enabled: true)
            liveKitLog("Microphone enabled successfully")
        } catch {
            // 如果麥克風啟用失敗，記錄但不中斷連接
            // 在模擬器上這是常見的，用戶仍可接收音訊
            liveKitLog("⚠️ Failed to enable microphone: \(error.localizedDescription)")
            liveKitLog("Note: Microphone may not work on iOS Simulator")
            // 不拋出錯誤，讓連接保持活躍
        }
    }

    #endif

    // MARK: - State Management

    private func updateState(_ newState: LiveKitVoiceChatState) {
        state = newState
        delegate?.liveKitVoiceStateDidChange(newState)
        liveKitLog("State: \(newState.description)")
    }

    // MARK: - Data Message Handling

    private func handleDataMessage(_ data: Data, from participant: String) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "transcript":
            if let text = json["text"] as? String {
                let isFinal = json["is_final"] as? Bool ?? false
                currentTranscript = text
                delegate?.liveKitVoiceDidReceiveTranscript(text, isFinal: isFinal)
            }

        case "response":
            if let text = json["text"] as? String {
                aiResponse = text
                delegate?.liveKitVoiceDidReceiveResponse(text)
            }

        case "agent_speaking":
            if let speaking = json["speaking"] as? Bool {
                updateState(speaking ? .aiSpeaking : .listening)
            }

        case "error":
            let code = json["code"] as? String ?? "unknown"
            let message = json["message"] as? String ?? "發生錯誤"
            liveKitLog("Received error: \(code) - \(message)")
            delegate?.liveKitVoiceDidReceiveError(code, message: message)
            // 更新狀態為錯誤
            updateState(.error(message))

        case "session_closed":
            let reason = json["reason"] as? String ?? "Session ended"
            liveKitLog("Session closed: \(reason)")
            updateState(.disconnected)

        default:
            liveKitLog("Unknown message type: \(type)")
        }
    }
}

// MARK: - LiveKit Room Delegate
#if canImport(LiveKit)

extension LiveKitVoiceService: RoomDelegate {

    nonisolated func room(_ room: Room, didUpdateConnectionState connectionState: ConnectionState, from oldState: ConnectionState) {
        Task { @MainActor in
            switch connectionState {
            case .connected:
                updateState(.connected)
                isConnected = true
                liveKitLog("Room connected")

            case .disconnected:
                updateState(.disconnected)
                isConnected = false
                liveKitLog("Room disconnected")

            case .connecting, .reconnecting:
                updateState(.connecting)
                liveKitLog("Room connecting/reconnecting")

            @unknown default:
                liveKitLog("Unknown connection state: \(connectionState)")
            }
        }
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        Task { @MainActor in
            if publication.kind == .audio {
                liveKitLog("Subscribed to agent audio track")
                updateState(.aiSpeaking)
            }
        }
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant, didUnsubscribeTrack publication: RemoteTrackPublication) {
        Task { @MainActor in
            if publication.kind == .audio {
                liveKitLog("Agent audio track ended")
                updateState(.listening)
            }
        }
    }

    nonisolated func room(_ room: Room, participant: Participant, didUpdateIsSpeaking isSpeaking: Bool) {
        Task { @MainActor in
            if participant is RemoteParticipant {
                // Agent speaking state
                updateState(isSpeaking ? .aiSpeaking : .listening)
                delegate?.liveKitVoiceAudioLevelDidChange(isSpeaking ? 0.8 : 0.0)
            } else {
                // Local participant (user) speaking
                if isSpeaking {
                    updateState(.userSpeaking)
                } else if state == .userSpeaking {
                    // 用戶停止說話，切回聆聽狀態
                    updateState(.listening)
                }
                delegate?.liveKitVoiceAudioLevelDidChange(isSpeaking ? 0.7 : 0.0)
            }
        }
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant?, didReceiveData data: Data, forTopic topic: String, encryptionType: EncryptionType) {
        Task { @MainActor in
            let participantId: String
            if let identity = participant?.identity {
                participantId = identity.stringValue
            } else {
                participantId = "agent"
            }
            handleDataMessage(data, from: participantId)
        }
    }
}

#endif

// MARK: - GrokVoiceChatState Compatibility
// 讓 VoiceChatView 可以同時使用 GrokVoiceService 和 LiveKitVoiceService

extension LiveKitVoiceChatState {
    /// 轉換為 GrokVoiceChatState 以兼容現有 UI
    var asGrokState: GrokVoiceChatState {
        switch self {
        case .disconnected: return .disconnected
        case .connecting: return .connecting
        case .connected: return .connected
        case .listening: return .listening
        case .userSpeaking: return .listening  // 用戶說話時也算聆聽中
        case .aiSpeaking: return .responding
        case .error(let msg): return .error(msg)
        }
    }
}
