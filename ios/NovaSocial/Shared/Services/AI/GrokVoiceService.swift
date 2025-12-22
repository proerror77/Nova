import Foundation
import AVFoundation

// MARK: - Grok Voice Service Delegate
protocol GrokVoiceServiceDelegate: AnyObject {
    func grokVoiceStateDidChange(_ state: GrokVoiceChatState)
    func grokVoiceDidReceiveTranscript(_ text: String, isFinal: Bool)
    func grokVoiceDidReceiveResponse(_ text: String)
    func grokVoiceAudioLevelDidChange(_ level: Float)
    func grokVoiceDidReceiveAudio(_ audioData: Data)
}

// MARK: - Grok Voice Service
/// xAI Grok Voice Agent API 整合服務
/// 使用 WebSocket 直接連接到 wss://api.x.ai/v1/realtime
@Observable
@MainActor
final class GrokVoiceService: NSObject {
    
    // MARK: - Singleton
    static let shared = GrokVoiceService()
    
    // MARK: - Properties
    private(set) var state: GrokVoiceChatState = .disconnected
    private(set) var isConnected: Bool = false
    private(set) var isMuted: Bool = false
    private(set) var currentTranscript: String = ""
    private(set) var aiResponse: String = ""
    private(set) var selectedVoice: GrokVoiceConfig.Voice = .ara
    
    weak var delegate: GrokVoiceServiceDelegate?
    
    // WebSocket
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var pingTimer: Timer?
    private var reconnectAttempts = 0
    
    // Audio
    private var audioEngine: AVAudioEngine?
    private var audioPlayer: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?
    private let audioSession = AVAudioSession.sharedInstance()
    private var inputNode: AVAudioInputNode?
    private var audioBuffer: Data = Data()
    private var isCapturingAudio = false
    
    // Audio playback buffer
    private var playbackBuffer: Data = Data()
    private var isPlaying = false
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = GrokVoiceConfig.connectionTimeout
        urlSession = URLSession(configuration: config, delegate: nil, delegateQueue: .main)
    }
    
    // Note: deinit cleanup removed - this is a singleton that lives for app lifetime
    // The disconnect() method is MainActor-isolated and cannot be called from deinit
    
    // MARK: - Public Methods
    
    /// 開始語音對話
    func startVoiceChat(voice: GrokVoiceConfig.Voice = .ara) {
        guard state == .disconnected || state.description.contains("錯誤") else {
            #if DEBUG
            print("[GrokVoice] Already connected or connecting")
            #endif
            return
        }
        
        guard GrokVoiceConfig.isConfigured else {
            updateState(.error(GrokVoiceConfig.configurationError ?? "未配置"))
            return
        }
        
        selectedVoice = voice
        updateState(.connecting)
        
        Task {
            await setupAudioSession()
            await connect()
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
    
    private func connect() async {
        guard let url = URL(string: GrokVoiceConfig.webSocketURL) else {
            updateState(.error("無效的 URL"))
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(GrokVoiceConfig.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        
        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()
        
        #if DEBUG
        print("[GrokVoice] Connecting to \(url)")
        #endif
        
        // 開始接收訊息
        receiveMessage()
        
        // 等待連線確認
        try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5s
        
        if webSocketTask?.state == .running {
            sendSessionUpdate()
            startPingTimer()
        }
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
            await connect()
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
                    await self?.handleDisconnection(error: error)
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
        case "session.created", "session.updated":
            handleSessionCreated(json)
            
        case "input_audio_buffer.speech_started":
            updateState(.listening)
            
        case "input_audio_buffer.speech_stopped":
            updateState(.processing)
            
        case "conversation.item.input_audio_transcription.completed":
            if let transcript = json["transcript"] as? String {
                currentTranscript = transcript
                delegate?.grokVoiceDidReceiveTranscript(transcript, isFinal: true)
            }
            
        case "response.audio_transcript.delta":
            if let delta = json["delta"] as? String {
                aiResponse += delta
                delegate?.grokVoiceDidReceiveResponse(aiResponse)
            }
            
        case "response.audio.delta":
            if let deltaBase64 = json["delta"] as? String,
               let audioData = Data(base64Encoded: deltaBase64) {
                handleAudioDelta(audioData)
            }
            updateState(.responding)
            
        case "response.audio.done":
            // 音訊播放完成
            break
            
        case "response.done":
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
    
    private func handleSessionCreated(_ json: [String: Any]) {
        isConnected = true
        reconnectAttempts = 0
        updateState(.connected)
        
        // 開始音訊捕獲
        if !isMuted {
            startAudioCapture()
        }
        
        #if DEBUG
        if let session = json["session"] as? [String: Any],
           let id = session["id"] as? String {
            print("[GrokVoice] Session created: \(id)")
        }
        #endif
    }
    
    private func handleResponseDone(_ json: [String: Any]) {
        if let response = json["response"] as? [String: Any],
           let status = response["status"] as? String {
            #if DEBUG
            print("[GrokVoice] Response done: \(status)")
            #endif
            
            if status == "completed" {
                // 清空回應，準備下一輪
                aiResponse = ""
                updateState(.connected)
            }
        }
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
    
    private func sendAudioBuffer(_ audioData: Data) {
        let base64Audio = audioData.base64EncodedString()
        let message: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": base64Audio
        ]
        sendJSON(message)
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
        
        // 使用 16kHz PCM 格式
        let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(GrokVoiceConfig.defaultSampleRate.rawValue),
            channels: 1,
            interleaved: true
        )
        
        guard let format = recordingFormat else { return }
        audioFormat = format
        
        // 安裝 tap 來捕獲音訊
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputNode.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }
        
        do {
            try audioEngine.start()
            isCapturingAudio = true
            
            #if DEBUG
            print("[GrokVoice] Audio capture started")
            #endif
        } catch {
            #if DEBUG
            print("[GrokVoice] Failed to start audio engine: \(error)")
            #endif
        }
    }
    
    private func stopAudioCapture() {
        guard isCapturingAudio else { return }
        
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        isCapturingAudio = false
        
        #if DEBUG
        print("[GrokVoice] Audio capture stopped")
        #endif
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isConnected, !isMuted else { return }
        
        // 轉換為目標格式 (16kHz PCM16)
        guard let channelData = buffer.int16ChannelData else { return }
        
        let frameCount = Int(buffer.frameLength)
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
        
        // 發送到服務器
        sendAudioBuffer(data)
    }
    
    // MARK: - Audio Playback
    
    private func handleAudioDelta(_ audioData: Data) {
        playbackBuffer.append(audioData)
        
        // 當緩衝區足夠大時開始播放
        if !isPlaying && playbackBuffer.count > 4800 {  // ~0.15秒 @ 16kHz
            playBufferedAudio()
        }
        
        delegate?.grokVoiceDidReceiveAudio(audioData)
    }
    
    private func playBufferedAudio() {
        guard !playbackBuffer.isEmpty else { return }
        
        isPlaying = true
        
        // 使用 AVAudioPlayer 播放 PCM 音訊
        // 注意：這是簡化版本，生產環境可能需要更複雜的音訊處理
        let audioData = playbackBuffer
        playbackBuffer = Data()
        
        Task {
            await playPCMAudio(audioData)
            isPlaying = false
        }
    }
    
    private func playPCMAudio(_ data: Data) async {
        // 創建 WAV 標頭
        let wavData = createWAVData(from: data, sampleRate: GrokVoiceConfig.defaultSampleRate.rawValue)
        
        do {
            let player = try AVAudioPlayer(data: wavData)
            player.prepareToPlay()
            player.play()
            
            // 等待播放完成
            while player.isPlaying {
                try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
            }
        } catch {
            #if DEBUG
            print("[GrokVoice] Playback error: \(error)")
            #endif
        }
    }
    
    private func createWAVData(from pcmData: Data, sampleRate: Int) -> Data {
        var wavData = Data()
        
        // RIFF header
        wavData.append(contentsOf: "RIFF".utf8)
        let fileSize = UInt32(36 + pcmData.count)
        wavData.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        wavData.append(contentsOf: "WAVE".utf8)
        
        // fmt chunk
        wavData.append(contentsOf: "fmt ".utf8)
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })  // chunk size
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })   // PCM
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })   // mono
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate * 2).littleEndian) { Array($0) })  // byte rate
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Array($0) })   // block align
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) })  // bits per sample
        
        // data chunk
        wavData.append(contentsOf: "data".utf8)
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(pcmData.count).littleEndian) { Array($0) })
        wavData.append(pcmData)
        
        return wavData
    }
    
    private func stopAudioPlayback() {
        playbackBuffer = Data()
        isPlaying = false
    }
    
    // MARK: - State Management
    
    private func updateState(_ newState: GrokVoiceChatState) {
        state = newState
        isConnected = newState.isActive
        delegate?.grokVoiceStateDidChange(newState)
    }
}
