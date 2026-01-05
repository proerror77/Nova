import SwiftUI
import AVFoundation

// MARK: - Voice Chat View
/// 語音對話視圖 - 使用 xAI Grok Voice Agent API
struct VoiceChatView: View {
    @Binding var isPresented: Bool
    
    @State private var grokVoiceService = GrokVoiceService.shared
    @State private var state: GrokVoiceChatState = .disconnected
    @State private var selectedVoice: GrokVoiceConfig.Voice = .ara
    @State private var transcript: String = ""
    @State private var aiResponse: String = ""
    @State private var audioLevel: Float = 0
    @State private var isMuted: Bool = false
    @State private var showEndConfirmation: Bool = false
    
    // 動畫相關
    @State private var pulseAnimation: Bool = false
    @State private var wavePhase: Double = 0
    @State private var delegateHandler: GrokVoiceDelegateHandler?
    
    var body: some View {
        ZStack {
            // 背景
            backgroundGradient
            
            VStack(spacing: 0) {
                // 頂部導航
                topBar
                
                Spacer()
                
                // 主要內容區域
                mainContent
                
                Spacer()
                
                // 底部控制區
                bottomControls
            }
        }
        .onAppear {
            startVoiceChat()
        }
        .onDisappear {
            endVoiceChat()
        }
        .alert("End Conversation", isPresented: $showEndConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("End", role: .destructive) {
                endVoiceChat()
                isPresented = false
            }
        } message: {
            Text("Are you sure you want to end the voice conversation with Alice?")
        }
    }
    
    // MARK: - Background
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.05, blue: 0.15),
                Color(red: 0.1, green: 0.1, blue: 0.25),
                Color(red: 0.05, green: 0.05, blue: 0.15)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            Button(action: { showEndConfirmation = true }) {
                Image(systemName: "xmark")
                    .font(.system(size: 20.f))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 44, height: 44)
            }
            
            Spacer()
            
            // 連線狀態
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(state.description)
                    .font(Font.custom("SFProDisplay-Medium", size: 14.f))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            Spacer()
            
            // 佔位符保持對稱
            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    private var statusColor: Color {
        switch state {
        case .disconnected, .error: return .red
        case .connecting: return .yellow
        case .connected, .listening, .processing, .responding: return .green
        }
    }
    
    // MARK: - Main Content
    private var mainContent: some View {
        VStack(spacing: 40) {
            // Alice 頭像和波紋動畫
            aliceAvatarWithWaves
            
            // 狀態文字
            stateIndicator
            
            // 轉錄/回覆文字
            transcriptView
        }
        .padding(.horizontal, 32)
    }
    
    // MARK: - Alice Avatar with Waves
    private var aliceAvatarWithWaves: some View {
        ZStack {
            // 波紋動畫 (當聆聽或回應時)
            if state == .listening || state == .responding {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.purple.opacity(0.6), .blue.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 160 + CGFloat(index * 40), height: 160 + CGFloat(index * 40))
                        .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                        .opacity(pulseAnimation ? 0 : 0.6)
                        .animation(
                            .easeOut(duration: 1.5)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) * 0.3),
                            value: pulseAnimation
                        )
                }
            }
            
            // 音量波形 (當聆聽或回應時)
            if state == .listening || state == .responding {
                audioWaveform
            }
            
            // Alice 頭像
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)
                
                Image("alice-center-icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
            }
            .shadow(color: .purple.opacity(0.5), radius: 20, x: 0, y: 10)
        }
        .frame(height: 280)
        .onAppear {
            pulseAnimation = true
        }
    }
    
    // MARK: - Audio Waveform
    private var audioWaveform: some View {
        HStack(spacing: 4) {
            ForEach(0..<12, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 4, height: waveHeight(for: index))
                    .animation(
                        .easeInOut(duration: 0.15)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.05),
                        value: audioLevel
                    )
            }
        }
        .frame(height: 60)
        .offset(y: 100)
    }
    
    private func waveHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 10
        let maxHeight: CGFloat = 50
        let variation = sin(Double(index) * 0.5 + wavePhase) * 0.5 + 0.5
        return baseHeight + (maxHeight - baseHeight) * CGFloat(audioLevel) * CGFloat(variation)
    }
    
    // MARK: - State Indicator
    private var stateIndicator: some View {
        VStack(spacing: 8) {
            Text(stateTitle)
                .font(Font.custom("SFProDisplay-Semibold", size: 24.f))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text(stateSubtitle)
                .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var stateTitle: String {
        switch state {
        case .disconnected: return "Not Connected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .listening: return "Listening to you"
        case .responding: return "Alice is responding"
        case .processing: return "Alice is thinking..."
        case .error: return "Connection Error"
        }
    }
    
    private var stateSubtitle: String {
        switch state {
        case .disconnected: return "Tap the button below to start the conversation"
        case .connecting: return "Connecting to Grok Voice..."
        case .connected: return "Ready, start speaking"
        case .listening: return "Auto-processes when done"
        case .responding: return "Please listen to the response"
        case .processing: return "Generating response..."
        case .error(let msg): return msg
        }
    }
    
    // MARK: - Transcript View
    private var transcriptView: some View {
        VStack(spacing: 16) {
            // 用戶說的話
            if !transcript.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("You said:")
                        .font(Font.custom("SFProDisplay-Medium", size: 12.f))
                        .foregroundColor(.white.opacity(0.5))
                    Text(transcript)
                        .font(Font.custom("SFProDisplay-Regular", size: 16.f))
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.white.opacity(0.1))
                .cornerRadius(16)
            }
            
            // AI 回覆
            if !aiResponse.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Alice：")
                        .font(Font.custom("SFProDisplay-Medium", size: 12.f))
                        .foregroundColor(.purple.opacity(0.8))
                    Text(aiResponse)
                        .font(Font.custom("SFProDisplay-Regular", size: 16.f))
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    LinearGradient(
                        colors: [.purple.opacity(0.2), .blue.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(16)
            }
        }
        .frame(minHeight: 100)
    }
    
    // MARK: - Bottom Controls
    private var bottomControls: some View {
        VStack(spacing: 24) {
            // 主要控制按鈕
            HStack(spacing: 60) {
                // 靜音按鈕
                controlButton(
                    icon: isMuted ? "mic.slash.fill" : "mic.fill",
                    isActive: !isMuted,
                    action: toggleMute
                )
                
                // 結束通話按鈕
                Button(action: { showEndConfirmation = true }) {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 72, height: 72)
                        
                        Image(systemName: "phone.down.fill")
                            .font(.system(size: 28.f))
                            .foregroundColor(.white)
                    }
                }
                .shadow(color: .red.opacity(0.4), radius: 10, x: 0, y: 5)
                
                // 揚聲器按鈕
                controlButton(
                    icon: "speaker.wave.2.fill",
                    isActive: true,
                    action: toggleSpeaker
                )
            }
            
            // 提示文字
            Text("Tap the red button to end the conversation")
                .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.bottom, 50)
    }
    
    private func controlButton(icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(isActive ? 0.2 : 0.1))
                    .frame(width: 56, height: 56)
                
                Image(systemName: icon)
                    .font(Font.custom("SFProDisplay-Regular", size: 24.f))
                    .foregroundColor(isActive ? .white : .white.opacity(0.5))
            }
        }
    }
    
    // MARK: - Actions
    private func startVoiceChat() {
        print("[VoiceChatView] 🚀 startVoiceChat called!")
        let handler = GrokVoiceDelegateHandler(
            onStateChange: { newState in
                withAnimation(.easeInOut(duration: 0.3)) {
                    state = newState
                }
            },
            onTranscript: { text, isFinal in
                transcript = text
            },
            onAIResponse: { text in
                aiResponse = text
            },
            onAudioLevel: { level in
                audioLevel = level
                wavePhase += 0.1
            }
        )
        delegateHandler = handler
        grokVoiceService.delegate = handler

        grokVoiceService.startVoiceChat(voice: selectedVoice)
    }
    
    private func endVoiceChat() {
        grokVoiceService.endVoiceChat()
    }
    
    private func toggleMute() {
        isMuted.toggle()
        grokVoiceService.toggleMute()
    }
    
    private func toggleSpeaker() {
        // Grok Voice 使用 AVAudioSession 管理揚聲器
        // 切換由系統自動處理
    }
}

// MARK: - Grok Voice Delegate Handler
private class GrokVoiceDelegateHandler: GrokVoiceServiceDelegate {
    let onStateChange: (GrokVoiceChatState) -> Void
    let onTranscript: (String, Bool) -> Void
    let onAIResponse: (String) -> Void
    let onAudioLevel: (Float) -> Void
    
    init(
        onStateChange: @escaping (GrokVoiceChatState) -> Void,
        onTranscript: @escaping (String, Bool) -> Void,
        onAIResponse: @escaping (String) -> Void,
        onAudioLevel: @escaping (Float) -> Void
    ) {
        self.onStateChange = onStateChange
        self.onTranscript = onTranscript
        self.onAIResponse = onAIResponse
        self.onAudioLevel = onAudioLevel
    }
    
    func grokVoiceStateDidChange(_ state: GrokVoiceChatState) {
        DispatchQueue.main.async {
            self.onStateChange(state)
        }
    }
    
    func grokVoiceDidReceiveTranscript(_ text: String, isFinal: Bool) {
        DispatchQueue.main.async {
            self.onTranscript(text, isFinal)
        }
    }
    
    func grokVoiceDidReceiveResponse(_ text: String) {
        DispatchQueue.main.async {
            self.onAIResponse(text)
        }
    }
    
    func grokVoiceAudioLevelDidChange(_ level: Float) {
        DispatchQueue.main.async {
            self.onAudioLevel(level)
        }
    }
    
    func grokVoiceDidReceiveAudio(_ audioData: Data) {
        // 音訊播放由 GrokVoiceService 內部處理
    }

    func grokVoiceDidReceiveFunctionCall(_ call: GrokFunctionCall) async -> String? {
        // 處理函數調用
        #if DEBUG
        print("[VoiceChat] Function call received: \(call.name)")
        print("[VoiceChat] Arguments: \(call.arguments)")
        #endif

        // TODO: 實現 ICERED 平台函數
        switch call.name {
        case "get_user_profile":
            if let username = call.arguments["username"] as? String {
                // TODO: 調用 API 獲取用戶資料
                return """
                {"status": "success", "message": "User profile lookup for '\(username)' - feature coming soon"}
                """
            }
        case "create_post":
            if let content = call.arguments["content"] as? String {
                // TODO: 調用 API 創建貼文
                return """
                {"status": "success", "message": "Post creation with content - feature coming soon", "content_preview": "\(content.prefix(50))..."}
                """
            }
        case "search_posts":
            if let query = call.arguments["query"] as? String {
                // TODO: 調用搜索 API
                return """
                {"status": "success", "message": "Search for '\(query)' - feature coming soon", "results": []}
                """
            }
        case "get_trending_topics":
            // TODO: 調用熱門話題 API
            return """
            {"status": "success", "topics": ["Technology", "Fashion", "Travel", "Fitness", "Entertainment"]}
            """
        default:
            return """
            {"status": "error", "message": "Unknown function: \(call.name)"}
            """
        }

        return nil
    }
}

// MARK: - Previews

#Preview("VoiceChat - Default") {
    VoiceChatView(isPresented: .constant(true))
}

#Preview("VoiceChat - Dark Mode") {
    VoiceChatView(isPresented: .constant(true))
        .preferredColorScheme(.dark)
}
