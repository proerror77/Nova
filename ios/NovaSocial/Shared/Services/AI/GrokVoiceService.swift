import Foundation
import AVFoundation
import os.log

// MARK: - Logging
private let voiceLog = OSLog(subsystem: "com.app.icered.pro", category: "GrokVoice")

/// 使用 print 確保 log 在設備上可見
private func voiceNSLog(_ message: String) {
    print("[GrokVoice] \(message)")
}

// MARK: - Function Call Model
struct GrokFunctionCall {
    let name: String
    let callId: String
    let arguments: [String: Any]
}

// MARK: - Grok Voice Service Delegate
protocol GrokVoiceServiceDelegate: AnyObject {
    func grokVoiceStateDidChange(_ state: GrokVoiceChatState)
    func grokVoiceDidReceiveTranscript(_ text: String, isFinal: Bool)
    func grokVoiceDidReceiveResponse(_ text: String)
    func grokVoiceAudioLevelDidChange(_ level: Float)
    func grokVoiceDidReceiveAudio(_ audioData: Data)
    /// 處理函數調用，返回結果 JSON 字符串
    func grokVoiceDidReceiveFunctionCall(_ call: GrokFunctionCall) async -> String?
}

// MARK: - Grok Voice Service
/// xAI Grok Voice Agent API 整合服務
/// 使用後端代理獲取 ephemeral token，然後連接到 wss://api.x.ai/v1/realtime
@Observable
@MainActor
final class GrokVoiceService: NSObject {

    // MARK: - Singleton
    static let shared = GrokVoiceService()

    // MARK: - Properties
    private(set) var state: GrokVoiceChatState = .disconnected
    private(set) var isConnected: Bool = false
    private(set) var isMuted: Bool = false
    private(set) var isPlayingResponse: Bool = false  // 防止迴音迴圈
    private(set) var currentTranscript: String = ""
    private(set) var aiResponse: String = ""
    private(set) var selectedVoice: GrokVoiceConfig.Voice = .ara

    weak var delegate: GrokVoiceServiceDelegate?

    // Token management
    private var currentToken: GrokVoiceConfig.VoiceTokenResponse?
    private var webSocketURL: String = GrokVoiceConfig.defaultWebSocketURL

    // WebSocket
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var pingTimer: Timer?
    private var reconnectAttempts = 0

    // Audio - 使用單一 AVAudioEngine 處理輸入和輸出
    // 這對於回音消除至關重要！
    private var audioEngine: AVAudioEngine?
    private var audioFormat: AVAudioFormat?
    private let audioSession = AVAudioSession.sharedInstance()
    private var inputNode: AVAudioInputNode?
    private var audioBuffer: Data = Data()
    private var isCapturingAudio = false

    // Audio playback - 使用同一個 engine 的 player node
    private var playerNode: AVAudioPlayerNode?
    private var playbackFormat: AVAudioFormat?
    private var isPlaybackSetup = false
    private var pendingAudioBuffers: Int = 0  // 追蹤待播放的音訊緩衝區數量

    // 輸出預緩衝 - 防止網路抖動導致音頻斷斷續續
    private var outputBuffer: Data = Data()
    private var isPreBuffering: Bool = true
    private let preBufferThreshold: Int = 4800  // 200ms @ 24kHz (24000 * 0.2 * 2 bytes)
    private let minScheduleSize: Int = 2400     // 最小排程大小 100ms，合併小 buffer

    // Barge-in (語音中斷) support
    private var currentResponseItemId: String?  // 追蹤當前回應的 item ID
    private var playedAudioSamples: Int = 0     // 已播放的音訊樣本數

    // 線程安全的播放狀態標記（用於音訊線程訪問）
    private let playingLock = NSLock()
    private var _isPlayingAtomic: Bool = false
    private var isPlayingAtomic: Bool {
        get {
            playingLock.lock()
            defer { playingLock.unlock() }
            return _isPlayingAtomic
        }
        set {
            playingLock.lock()
            _isPlayingAtomic = newValue
            playingLock.unlock()
        }
    }

    // MARK: - Initialization

    private override init() {
        super.init()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = GrokVoiceConfig.connectionTimeout
        urlSession = URLSession(configuration: config, delegate: nil, delegateQueue: .main)
    }

    // MARK: - Public Methods

    /// 開始語音對話
    func startVoiceChat(voice: GrokVoiceConfig.Voice = .ara) {
        guard state == .disconnected || state.description.contains("錯誤") else {
            #if DEBUG
            print("[GrokVoice] Already connected or connecting")
            #endif
            return
        }

        selectedVoice = voice
        updateState(.connecting)

        Task {
            do {
                // Step 1: Fetch ephemeral token from backend
                voiceNSLog("📡 Fetching ephemeral token from backend...")
                let tokenResponse = try await GrokVoiceConfig.fetchEphemeralToken()
                self.currentToken = tokenResponse
                self.webSocketURL = tokenResponse.websocketUrl

                voiceNSLog("🔑 Got token, WebSocket URL: \(tokenResponse.websocketUrl)")

                // Step 2: Setup audio and connect
                await setupAudioSession()
                await connect(with: tokenResponse.clientSecret.value)
            } catch {
                voiceNSLog("❌ Failed to start voice chat: \(error.localizedDescription)")
                updateState(.error(error.localizedDescription))
            }
        }
    }

    /// 結束語音對話
    func endVoiceChat() {
        disconnect()
        stopAudioCapture()
        stopAudioPlayback()
        updateState(.disconnected)
        currentTranscript = ""
        aiResponse = ""
        currentToken = nil
    }

    /// 切換靜音
    func toggleMute() {
        isMuted.toggle()

        if isMuted {
            stopAudioCapture()
        } else if isConnected {
            startAudioCapture()
        }

        #if DEBUG
        print("[GrokVoice] Mute toggled: \(isMuted)")
        #endif
    }

    /// 設置語音
    func setVoice(_ voice: GrokVoiceConfig.Voice) {
        selectedVoice = voice

        // 如果已連線，發送 session update
        if isConnected {
            sendSessionUpdate()
        }
    }

    /// 發送文字訊息（可選，用於文字輸入）
    func sendTextMessage(_ text: String) {
        guard isConnected else { return }

        let message: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [
                    ["type": "input_text", "text": text]
                ]
            ]
        ]

        sendJSON(message)

        // 請求回應
        let responseRequest: [String: Any] = [
            "type": "response.create",
            "response": [
                "modalities": ["text", "audio"]
            ]
        ]
        sendJSON(responseRequest)
    }

    // MARK: - WebSocket Connection

    private func connect(with token: String) async {
        guard let url = URL(string: webSocketURL) else {
            updateState(.error("無效的 WebSocket URL"))
            return
        }

        var request = URLRequest(url: url)
        // Use ephemeral token instead of API key
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Note: xAI uses OpenAI-compatible protocol
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()

        #if DEBUG
        print("[GrokVoice] Connecting to \(url)")
        #endif

        // 開始接收訊息
        receiveMessage()

        // 啟動心跳計時器
        startPingTimer()

        // 注意：session.update 會在收到 session.created 事件後發送
        // 不要在這裡發送，否則可能會在 session 建立前發送
    }

    private func disconnect() {
        pingTimer?.invalidate()
        pingTimer = nil

        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
        reconnectAttempts = 0
    }

    private func reconnect() {
        guard reconnectAttempts < GrokVoiceConfig.maxReconnectAttempts else {
            updateState(.error("重連失敗"))
            return
        }

        reconnectAttempts += 1
        updateState(.connecting)

        Task {
            try? await Task.sleep(nanoseconds: UInt64(GrokVoiceConfig.reconnectDelay * 1_000_000_000))

            // Re-fetch token and connect
            do {
                let tokenResponse = try await GrokVoiceConfig.fetchEphemeralToken()
                self.currentToken = tokenResponse
                await connect(with: tokenResponse.clientSecret.value)
            } catch {
                updateState(.error(error.localizedDescription))
            }
        }
    }

    // MARK: - WebSocket Messages

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                Task { @MainActor [weak self] in
                    await self?.handleMessage(message)
                    await self?.receiveMessage()
                }

            case .failure(let error):
                #if DEBUG
                print("[GrokVoice] WebSocket error: \(error)")
                #endif
                Task { @MainActor [weak self] in
                    self?.handleDisconnection(error: error)
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) async {
        switch message {
        case .string(let text):
            parseServerMessage(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseServerMessage(text)
            }
        @unknown default:
            break
        }
    }

    private func parseServerMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        #if DEBUG
        print("[GrokVoice] Received: \(type)")
        #endif

        switch type {
        case "conversation.created":
            // 收到 conversation.created 後發送 session.update
            handleConversationCreated(json)

        case "session.updated":
            // session 配置已更新，開始音訊捕獲
            handleSessionUpdated(json)

        case "input_audio_buffer.speech_started":
            print("[GrokVoice] 🎤 Speech started (server VAD), isPlaying=\(isPlayingResponse)")
            // 伺服器 VAD 檢測到用戶說話
            // 如果 AI 正在播放，這就是 barge-in 信號！
            if isPlayingResponse {
                print("[GrokVoice] 🛑 BARGE-IN! Server detected user speech during AI response")
                handleUserInterruption()
            }
            updateState(.listening)

        case "input_audio_buffer.speech_stopped":
            updateState(.processing)

        case "conversation.item.input_audio_transcription.completed":
            if let transcript = json["transcript"] as? String {
                currentTranscript = transcript
                delegate?.grokVoiceDidReceiveTranscript(transcript, isFinal: true)
            }

        case "response.output_item.added":
            // 追蹤當前回應的 item ID (用於 barge-in 中斷)
            if let item = json["item"] as? [String: Any],
               let itemId = item["id"] as? String {
                currentResponseItemId = itemId
                playedAudioSamples = 0
                #if DEBUG
                print("[GrokVoice] Response item started: \(itemId)")
                #endif
            }

        case "response.audio_transcript.delta":
            // xAI 實際事件名稱 (不是 response.output_audio_transcript.delta)
            if let delta = json["delta"] as? String {
                aiResponse += delta
                delegate?.grokVoiceDidReceiveResponse(aiResponse)
            }

        case "response.audio.delta":
            // xAI 實際事件名稱 (不是 response.output_audio.delta)
            // 保持麥克風運行以支援 barge-in (語音中斷)
            // iOS .voiceChat 模式提供硬體級回音消除
            if !isPlayingResponse {
                isPlayingResponse = true
                isPlayingAtomic = true  // 同步設置線程安全變量
                print("[GrokVoice] 🔊 AI response started")
            }
            if let deltaBase64 = json["delta"] as? String,
               let audioData = Data(base64Encoded: deltaBase64) {
                handleAudioDelta(audioData)
            }
            updateState(.responding)

        case "response.audio.done":
            // 音訊播放完成
            break

        case "response.function_call_arguments.done":
            // 處理函數調用
            handleFunctionCall(json)

        case "response.done":
            voiceNSLog("📨 response.done received")
            handleResponseDone(json)

        case "error":
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                updateState(.error(message))
            }

        default:
            break
        }
    }

    private func handleConversationCreated(_ json: [String: Any]) {
        #if DEBUG
        if let conversation = json["conversation"] as? [String: Any],
           let id = conversation["id"] as? String {
            print("[GrokVoice] Conversation created: \(id)")
        }
        #endif

        // 收到 conversation.created 後，發送 session.update 配置
        sendSessionUpdate()
    }

    private func handleSessionUpdated(_ json: [String: Any]) {
        isConnected = true
        reconnectAttempts = 0
        updateState(.connected)

        voiceNSLog("✅ Session updated successfully")
        if let session = json["session"] as? [String: Any],
           let voice = session["voice"] as? String {
            voiceNSLog("🎙️ Voice: \(voice)")
        }

        // Session 配置完成後，開始音訊捕獲
        if !isMuted {
            startAudioCapture()
            voiceNSLog("🎤 Audio capture started")
        }
    }

    private func handleResponseDone(_ json: [String: Any]) {
        if let response = json["response"] as? [String: Any],
           let status = response["status"] as? String {
            voiceNSLog("✅ Response done: status=\(status), pendingBuffers=\(pendingAudioBuffers)")

            if status == "completed" || status == "cancelled" {
                // 刷新任何剩餘的緩衝音頻（確保最後的音頻不會丟失）
                if !outputBuffer.isEmpty {
                    voiceNSLog("🎵 Flushing remaining \(outputBuffer.count) bytes of audio")
                    scheduleBufferedAudio()
                }

                // 重置預緩衝狀態，為下一個回應做準備
                isPreBuffering = true

                // 清空回應，準備下一輪
                aiResponse = ""
                currentResponseItemId = nil
                updateState(.connected)

                // 標記回應已完成
                isPlayingResponse = false
                isPlayingAtomic = false  // 同步設置線程安全變量
                print("[GrokVoice] 🔄 Response done, ready for next input")

                // 如果沒有待播放的音訊緩衝區，立即恢復麥克風
                // 否則等待音訊播放完成後由 scheduleAudioBuffer 的完成處理器恢復
                if pendingAudioBuffers == 0 {
                    resumeMicrophoneAfterPlayback()
                }
                // 如果還有待播放的緩衝區，scheduleAudioBuffer 的完成處理器會處理
            } else {
                voiceNSLog("⚠️ Response done with unexpected status: \(status)")
            }
        } else {
            voiceNSLog("⚠️ Response done but couldn't parse response/status")
        }
    }

    // MARK: - Barge-in (語音中斷)

    /// 處理用戶中斷 AI 回應
    private func handleUserInterruption() {
        print("[GrokVoice] 🛑 User interruption! Cancelling response...")

        // 1. 立即停止本地音訊播放
        clearLocalAudioPlayback()

        // 2. 發送 response.cancel 到伺服器停止生成
        sendResponseCancel()

        // 3. 如果有 item ID，發送 truncate 同步對話狀態
        if let itemId = currentResponseItemId, playedAudioSamples > 0 {
            let audioEndMs = calculatePlayedAudioMs()
            print("[GrokVoice] 📝 Truncating at \(audioEndMs) ms")
            sendConversationItemTruncate(itemId: itemId, audioEndMs: audioEndMs)
        }

        // 4. 重置狀態
        isPlayingResponse = false
        isPlayingAtomic = false  // 同步設置線程安全變量
        aiResponse = ""
        currentResponseItemId = nil

        print("[GrokVoice] ✅ Interruption handled, ready for new input")
    }

    /// 清空本地音訊播放緩衝區
    private func clearLocalAudioPlayback() {
        // 停止並重置 player node
        playerNode?.stop()
        pendingAudioBuffers = 0

        // 重置預緩衝狀態，為下一個回應做準備
        outputBuffer = Data()
        isPreBuffering = true

        // 重新開始 player 以準備新的音訊
        playerNode?.play()

        voiceNSLog("🔄 Local audio playback cleared for barge-in")
    }

    /// 發送 response.cancel 事件
    private func sendResponseCancel() {
        let cancelEvent: [String: Any] = [
            "type": "response.cancel"
        ]
        sendJSON(cancelEvent)

        #if DEBUG
        print("[GrokVoice] Sent response.cancel")
        #endif
    }

    /// 發送 conversation.item.truncate 事件
    private func sendConversationItemTruncate(itemId: String, audioEndMs: Int) {
        let truncateEvent: [String: Any] = [
            "type": "conversation.item.truncate",
            "item_id": itemId,
            "content_index": 0,
            "audio_end_ms": audioEndMs
        ]
        sendJSON(truncateEvent)

        #if DEBUG
        print("[GrokVoice] Sent conversation.item.truncate: itemId=\(itemId), audioEndMs=\(audioEndMs)")
        #endif
    }

    /// 計算已播放的音訊毫秒數
    private func calculatePlayedAudioMs() -> Int {
        // 24kHz 採樣率，每個樣本 = 1/24000 秒
        let sampleRate = GrokVoiceConfig.defaultSampleRate.rawValue
        let playedMs = (playedAudioSamples * 1000) / sampleRate
        return playedMs
    }

    private func handleFunctionCall(_ json: [String: Any]) {
        guard let name = json["name"] as? String,
              let callId = json["call_id"] as? String,
              let argumentsString = json["arguments"] as? String else {
            #if DEBUG
            print("[GrokVoice] Invalid function call event")
            #endif
            return
        }

        #if DEBUG
        print("[GrokVoice] Function called: \(name) with call_id: \(callId)")
        #endif

        // 解析參數 JSON
        var arguments: [String: Any] = [:]
        if let data = argumentsString.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            arguments = parsed
        }

        let functionCall = GrokFunctionCall(name: name, callId: callId, arguments: arguments)

        // 調用 delegate 執行函數
        Task {
            if let result = await delegate?.grokVoiceDidReceiveFunctionCall(functionCall) {
                // 發送函數結果
                sendFunctionResult(callId: callId, output: result)
            } else {
                // 沒有結果，發送空結果
                sendFunctionResult(callId: callId, output: "{\"error\": \"Function not implemented\"}")
            }
        }
    }

    /// 發送函數執行結果
    private func sendFunctionResult(callId: String, output: String) {
        // 發送 conversation.item.create 帶函數輸出
        let createItem: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": callId,
                "output": output
            ]
        ]

        sendJSON(createItem)

        #if DEBUG
        print("[GrokVoice] Sent function result for call_id: \(callId)")
        #endif

        // 發送 response.create 讓 agent 繼續
        let responseCreate: [String: Any] = [
            "type": "response.create"
        ]
        sendJSON(responseCreate)

        #if DEBUG
        print("[GrokVoice] Sent response.create to continue")
        #endif
    }

    private func handleDisconnection(error: Error) {
        isConnected = false

        if state != .disconnected {
            reconnect()
        }
    }

    // MARK: - Send Messages

    private func sendJSON(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else {
            return
        }

        webSocketTask?.send(.string(text)) { error in
            if let error = error {
                #if DEBUG
                print("[GrokVoice] Send error: \(error)")
                #endif
            }
        }
    }

    private func sendSessionUpdate() {
        let config = GrokVoiceConfig.aliceSessionConfig(voice: selectedVoice)
        sendJSON(config)
    }

    // 追蹤音訊發送狀態
    private var lastAudioSentTime: Date = .distantPast
    private var audioSendCount: Int = 0

    private func sendAudioBuffer(_ audioData: Data) {
        let base64Audio = audioData.base64EncodedString()
        let message: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": base64Audio
        ]
        sendJSON(message)

        // 每 50 次發送記錄一次，避免日誌過多
        audioSendCount += 1
        if audioSendCount % 50 == 1 {
            voiceNSLog("📤 Sending audio #\(audioSendCount), isPlaying=\(isPlayingResponse)")
        }
    }

    // MARK: - Ping/Pong

    private func startPingTimer() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: GrokVoiceConfig.heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.webSocketTask?.sendPing { error in
                    if let error = error {
                        #if DEBUG
                        print("[GrokVoice] Ping error: \(error)")
                        #endif
                    }
                }
            }
        }
    }

    // MARK: - Audio Session

    private func setupAudioSession() async {
        do {
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try audioSession.setActive(true)

            #if DEBUG
            print("[GrokVoice] Audio session configured")
            #endif
        } catch {
            #if DEBUG
            print("[GrokVoice] Audio session error: \(error)")
            #endif
            updateState(.error("無法配置音訊: \(error.localizedDescription)"))
        }
    }

    // MARK: - Audio Capture

    private func startAudioCapture() {
        guard !isCapturingAudio else { return }

        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }

        inputNode = audioEngine.inputNode
        guard let inputNode = inputNode else { return }

        // 啟用語音處理進行回音消除
        // 這是 iOS 上實現 barge-in 的關鍵！
        do {
            try inputNode.setVoiceProcessingEnabled(true)
            voiceNSLog("🔊 Voice processing enabled on input node (echo cancellation)")
        } catch {
            voiceNSLog("⚠️ Failed to enable voice processing on input: \(error.localizedDescription)")
        }

        // 同時設置播放節點在同一個 engine 上
        // 這樣回音消除可以正確工作
        setupPlayerNodeOnEngine(audioEngine)

        // 目標格式: 24kHz PCM16 mono
        let targetSampleRate = Double(GrokVoiceConfig.defaultSampleRate.rawValue)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        ) else { return }

        audioFormat = targetFormat

        // 獲取輸入節點的原生格式
        let inputFormat = inputNode.outputFormat(forBus: 0)

        voiceNSLog("📥 Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")
        voiceNSLog("🎯 Target format: \(targetSampleRate)Hz, 1 channel, PCM16")

        // 創建格式轉換器
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            voiceNSLog("❌ Failed to create audio converter")
            return
        }

        // 安裝 tap 來捕獲音訊
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, converter: converter, targetFormat: targetFormat)
        }

        do {
            try audioEngine.start()
            isCapturingAudio = true
            playerNode?.play()  // 確保 player 也開始
            voiceNSLog("✅ Audio engine started (capture + playback on same engine)")
        } catch {
            voiceNSLog("❌ Failed to start audio engine: \(error.localizedDescription)")
        }
    }

    /// 在同一個 engine 上設置 player node
    private func setupPlayerNodeOnEngine(_ engine: AVAudioEngine) {
        // 創建並附加 player node
        playerNode = AVAudioPlayerNode()
        guard let player = playerNode else { return }

        // 24kHz PCM16 mono - 與 xAI API 輸出格式匹配
        let sampleRate = Double(GrokVoiceConfig.defaultSampleRate.rawValue)
        playbackFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        )

        guard let format = playbackFormat else { return }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        // 啟用輸出節點的語音處理以配合回音消除
        do {
            try engine.outputNode.setVoiceProcessingEnabled(true)
            voiceNSLog("🔊 Voice processing enabled on output node (echo cancellation)")
        } catch {
            voiceNSLog("⚠️ Failed to enable voice processing on output: \(error.localizedDescription)")
        }

        isPlaybackSetup = true
        voiceNSLog("🎵 Player node attached to unified engine")
    }

    private func stopAudioCapture() {
        guard isCapturingAudio else { return }

        inputNode?.removeTap(onBus: 0)
        playerNode?.stop()  // 停止播放節點
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        playerNode = nil
        isCapturingAudio = false
        isPlaybackSetup = false

        voiceNSLog("🛑 Audio engine stopped (capture + playback)")
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat) {
        // 使用線程安全的方式檢查連接和靜音狀態
        let connected = isConnected
        let muted = isMuted
        guard connected, !muted else { return }

        // 計算轉換後的幀數
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
            return
        }

        // 執行格式轉換
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            #if DEBUG
            print("[GrokVoice] Audio conversion error: \(error)")
            #endif
            return
        }

        // 獲取轉換後的 PCM16 數據
        guard let channelData = outputBuffer.int16ChannelData else { return }

        let frameCount = Int(outputBuffer.frameLength)
        let data = Data(bytes: channelData[0], count: frameCount * 2)

        // 計算音量級別
        var sum: Float = 0
        for i in 0..<frameCount {
            let sample = Float(channelData[0][i]) / Float(Int16.max)
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameCount))
        let level = min(1.0, rms * 3)  // 放大以便更好地可視化

        Task { @MainActor in
            self.delegate?.grokVoiceAudioLevelDidChange(level)
        }

        // 關鍵改動：始終發送音訊到伺服器！
        // 伺服器 VAD 會處理回音消除和語音檢測
        // 當用戶在 AI 播放時說話，伺服器會發送 input_audio_buffer.speech_started
        // 我們在該事件處理器中執行 barge-in
        sendAudioBuffer(data)
    }

    // MARK: - Audio Playback (Streaming with AVAudioEngine)

    /// 確保播放設置已完成（現在由 startAudioCapture 統一處理）
    private func ensurePlaybackReady() {
        // 播放設置現在在 startAudioCapture 中與捕獲一起初始化
        // 這確保輸入和輸出在同一個 engine 上，以便回音消除正常工作
        guard isPlaybackSetup, playerNode != nil else {
            voiceNSLog("⚠️ Playback not ready - audio capture may not have started")
            return
        }
    }

    private func handleAudioDelta(_ audioData: Data) {
        // 確保播放已準備好（應該在 startAudioCapture 中已設置）
        if !isPlaybackSetup {
            ensurePlaybackReady()
        }

        // 累積音頻數據到輸出緩衝區
        outputBuffer.append(audioData)

        if isPreBuffering {
            // 預緩衝階段：累積足夠數據後才開始播放，防止網路抖動
            if outputBuffer.count >= preBufferThreshold {
                isPreBuffering = false
                voiceNSLog("🎵 Pre-buffer complete (\(outputBuffer.count) bytes), starting playback")
                scheduleBufferedAudio()
            }
        } else {
            // 已開始播放：當累積達到最小排程大小時排程
            if outputBuffer.count >= minScheduleSize {
                scheduleBufferedAudio()
            }
        }

        delegate?.grokVoiceDidReceiveAudio(audioData)
    }

    /// 排程累積的音頻緩衝區
    private func scheduleBufferedAudio() {
        guard !outputBuffer.isEmpty else { return }

        // 取出所有累積的數據
        let dataToSchedule = outputBuffer
        outputBuffer = Data()

        // 排程播放
        scheduleAudioBuffer(dataToSchedule)
    }

    private func scheduleAudioBuffer(_ data: Data) {
        guard let format = playbackFormat,
              let player = playerNode,
              player.engine != nil else { return }

        // 計算幀數: data.count / 2 (因為是 16-bit = 2 bytes per sample)
        let frameCount = AVAudioFrameCount(data.count / 2)
        let sampleCount = Int(frameCount)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return
        }

        buffer.frameLength = frameCount

        // 複製 PCM16 數據到 buffer
        data.withUnsafeBytes { rawBuffer in
            if let src = rawBuffer.baseAddress {
                memcpy(buffer.int16ChannelData?[0], src, data.count)
            }
        }

        // 增加待播放緩衝區計數
        pendingAudioBuffers += 1

        // 排程到 player node，並追蹤播放完成
        player.scheduleBuffer(buffer) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.pendingAudioBuffers -= 1

                // 追蹤已播放的音訊樣本數 (用於 barge-in truncate)
                self.playedAudioSamples += sampleCount

                // 當所有緩衝區播放完畢且回應已完成，恢復麥克風
                if self.pendingAudioBuffers == 0 && !self.isPlayingResponse {
                    self.resumeMicrophoneAfterPlayback()
                }
            }
        }
    }

    private func resumeMicrophoneAfterPlayback() {
        guard !isMuted, isConnected else { return }

        // 麥克風現在保持運行（支援 barge-in），只需重置播放狀態
        voiceNSLog("🎤 Playback complete, mic already running for barge-in")

        // 確保音訊捕獲仍在運行（以防萬一）
        if !isCapturingAudio {
            startAudioCapture()
            voiceNSLog("🎤 Restarted mic (was stopped)")
        }
    }

    private func stopAudioPlayback() {
        playerNode?.stop()
        // 不需要停止 engine，因為它與 capture 共用
        // audioEngine 會在 stopAudioCapture 中停止
        playerNode = nil
        isPlaybackSetup = false
        pendingAudioBuffers = 0

        // 重置預緩衝狀態
        outputBuffer = Data()
        isPreBuffering = true

        voiceNSLog("🔇 Playback stopped")
    }

    // MARK: - State Management

    private func updateState(_ newState: GrokVoiceChatState) {
        state = newState
        isConnected = newState.isActive
        delegate?.grokVoiceStateDidChange(newState)
    }
}
