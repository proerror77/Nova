import SwiftUI
import AVFoundation

// MARK: - Voice Chat View
struct VoiceChatView: View {
    @Binding var isPresented: Bool
    
    @State private var voiceChatService = VoiceChatService.shared
    @State private var state: VoiceChatState = .disconnected
    @State private var transcript: String = ""
    @State private var aiResponse: String = ""
    @State private var audioLevel: Float = 0
    @State private var isMuted: Bool = false
    @State private var showEndConfirmation: Bool = false
    
    // 動畫相關
    @State private var pulseAnimation: Bool = false
    @State private var wavePhase: Double = 0
    
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
        .alert("結束對話", isPresented: $showEndConfirmation) {
            Button("取消", role: .cancel) { }
            Button("結束", role: .destructive) {
                endVoiceChat()
                isPresented = false
            }
        } message: {
            Text("確定要結束與 Alice 的語音對話嗎？")
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
                    .font(.system(size: 20, weight: .medium))
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
                    .font(.system(size: 14, weight: .medium))
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
        case .connected, .speaking, .listening, .processing: return .green
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
            // 波紋動畫 (當說話或聆聽時)
            if state == .speaking || state == .listening {
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
            
            // 音量波形 (當說話時)
            if state == .speaking {
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
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
            
            Text(stateSubtitle)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
        }
    }
    
    private var stateTitle: String {
        switch state {
        case .disconnected: return "未連線"
        case .connecting: return "連線中..."
        case .connected: return "已連線"
        case .speaking: return "正在聆聽你說話"
        case .listening: return "Alice 正在回覆"
        case .processing: return "Alice 正在思考..."
        case .error: return "連線錯誤"
        }
    }
    
    private var stateSubtitle: String {
        switch state {
        case .disconnected: return "點擊下方按鈕開始對話"
        case .connecting: return "正在連接到 Alice..."
        case .connected: return "準備就緒"
        case .speaking: return "說完後會自動處理"
        case .listening: return "請聆聽回覆"
        case .processing: return "正在生成回覆..."
        case .error(let msg): return msg
        }
    }
    
    // MARK: - Transcript View
    private var transcriptView: some View {
        VStack(spacing: 16) {
            // 用戶說的話
            if !transcript.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("你說：")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    Text(transcript)
                        .font(.system(size: 16))
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
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.purple.opacity(0.8))
                    Text(aiResponse)
                        .font(.system(size: 16))
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
                            .font(.system(size: 28))
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
            Text("點擊紅色按鈕結束對話")
                .font(.system(size: 12))
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
                    .font(.system(size: 24))
                    .foregroundColor(isActive ? .white : .white.opacity(0.5))
            }
        }
    }
    
    // MARK: - Actions
    private func startVoiceChat() {
        voiceChatService.delegate = VoiceChatDelegateHandler(
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
        
        voiceChatService.startVoiceChat()
    }
    
    private func endVoiceChat() {
        voiceChatService.endVoiceChat()
    }
    
    private func toggleMute() {
        isMuted.toggle()
        voiceChatService.toggleMute()
    }
    
    private func toggleSpeaker() {
        voiceChatService.toggleSpeaker()
    }
}

// MARK: - Delegate Handler
private class VoiceChatDelegateHandler: VoiceChatServiceDelegate {
    let onStateChange: (VoiceChatState) -> Void
    let onTranscript: (String, Bool) -> Void
    let onAIResponse: (String) -> Void
    let onAudioLevel: (Float) -> Void
    
    init(
        onStateChange: @escaping (VoiceChatState) -> Void,
        onTranscript: @escaping (String, Bool) -> Void,
        onAIResponse: @escaping (String) -> Void,
        onAudioLevel: @escaping (Float) -> Void
    ) {
        self.onStateChange = onStateChange
        self.onTranscript = onTranscript
        self.onAIResponse = onAIResponse
        self.onAudioLevel = onAudioLevel
    }
    
    func voiceChatStateDidChange(_ state: VoiceChatState) {
        DispatchQueue.main.async {
            self.onStateChange(state)
        }
    }
    
    func voiceChatDidReceiveTranscript(_ text: String, isFinal: Bool) {
        DispatchQueue.main.async {
            self.onTranscript(text, isFinal)
        }
    }
    
    func voiceChatDidReceiveAIResponse(_ text: String) {
        DispatchQueue.main.async {
            self.onAIResponse(text)
        }
    }
    
    func voiceChatAudioLevelDidChange(_ level: Float) {
        DispatchQueue.main.async {
            self.onAudioLevel(level)
        }
    }
}

// MARK: - Preview
#Preview {
    VoiceChatView(isPresented: .constant(true))
}
