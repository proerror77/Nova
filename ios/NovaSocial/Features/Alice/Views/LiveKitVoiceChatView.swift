import SwiftUI
import AVFoundation

// MARK: - LiveKit Voice Chat View
/// 使用 LiveKit + xAI Grok Voice Agent 的語音對話視圖
/// 提供可靠的 WebRTC 回音消除和 barge-in 支援
struct LiveKitVoiceChatView: View {
    @Binding var isPresented: Bool

    @State private var voiceService = LiveKitVoiceService.shared
    @State private var state: LiveKitVoiceChatState = .disconnected
    @State private var transcript: String = ""
    @State private var aiResponse: String = ""
    @State private var audioLevel: Float = 0
    @State private var isMuted: Bool = false
    @State private var showEndConfirmation: Bool = false

    // 動畫
    @State private var pulseAnimation: Bool = false
    @State private var wavePhase: Double = 0
    @State private var delegateHandler: LiveKitVoiceDelegateHandler?

    var body: some View {
        ZStack {
            backgroundGradient

            VStack(spacing: 0) {
                topBar
                Spacer()
                mainContent
                Spacer()
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

            // 連線狀態 + LiveKit 標記
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(state.description)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))

                // LiveKit 標記
                Text("LiveKit")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(4)
            }

            Spacer()

            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var statusColor: Color {
        switch state {
        case .disconnected, .error: return .red
        case .connecting: return .yellow
        case .connected, .listening, .aiSpeaking: return .green
        }
    }

    // MARK: - Main Content
    private var mainContent: some View {
        VStack(spacing: 40) {
            aliceAvatarWithWaves
            stateIndicator
            transcriptView
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Alice Avatar
    private var aliceAvatarWithWaves: some View {
        ZStack {
            // 波紋動畫
            if state == .listening || state == .aiSpeaking {
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

            // 音量波形
            if state == .listening || state == .aiSpeaking {
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
        case .listening: return "正在聆聽你說話"
        case .aiSpeaking: return "Alice 正在回覆"
        case .error: return "連線錯誤"
        }
    }

    private var stateSubtitle: String {
        switch state {
        case .disconnected: return "點擊下方按鈕開始對話"
        case .connecting: return "正在連接到 LiveKit..."
        case .connected: return "準備就緒，開始說話吧"
        case .listening: return "說完後會自動處理 • 支援打斷"
        case .aiSpeaking: return "你可以隨時打斷 Alice"
        case .error(let msg): return msg
        }
    }

    // MARK: - Transcript View
    private var transcriptView: some View {
        VStack(spacing: 16) {
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
            HStack(spacing: 60) {
                // 靜音
                controlButton(
                    icon: isMuted ? "mic.slash.fill" : "mic.fill",
                    isActive: !isMuted,
                    action: toggleMute
                )

                // 結束
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

                // 揚聲器
                controlButton(
                    icon: "speaker.wave.2.fill",
                    isActive: true,
                    action: { }
                )
            }

            Text("LiveKit WebRTC • 支援語音打斷")
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
        print("[LiveKitVoiceChatView] 🚀 Starting LiveKit voice chat")

        let handler = LiveKitVoiceDelegateHandler(
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
        voiceService.delegate = handler

        voiceService.startVoiceChat()
    }

    private func endVoiceChat() {
        voiceService.endVoiceChat()
    }

    private func toggleMute() {
        isMuted.toggle()
        voiceService.toggleMute()
    }
}

// MARK: - Delegate Handler
private class LiveKitVoiceDelegateHandler: LiveKitVoiceServiceDelegate {
    let onStateChange: (LiveKitVoiceChatState) -> Void
    let onTranscript: (String, Bool) -> Void
    let onAIResponse: (String) -> Void
    let onAudioLevel: (Float) -> Void

    init(
        onStateChange: @escaping (LiveKitVoiceChatState) -> Void,
        onTranscript: @escaping (String, Bool) -> Void,
        onAIResponse: @escaping (String) -> Void,
        onAudioLevel: @escaping (Float) -> Void
    ) {
        self.onStateChange = onStateChange
        self.onTranscript = onTranscript
        self.onAIResponse = onAIResponse
        self.onAudioLevel = onAudioLevel
    }

    func liveKitVoiceStateDidChange(_ state: LiveKitVoiceChatState) {
        DispatchQueue.main.async {
            self.onStateChange(state)
        }
    }

    func liveKitVoiceDidReceiveTranscript(_ text: String, isFinal: Bool) {
        DispatchQueue.main.async {
            self.onTranscript(text, isFinal)
        }
    }

    func liveKitVoiceDidReceiveResponse(_ text: String) {
        DispatchQueue.main.async {
            self.onAIResponse(text)
        }
    }

    func liveKitVoiceAudioLevelDidChange(_ level: Float) {
        DispatchQueue.main.async {
            self.onAudioLevel(level)
        }
    }
}

// MARK: - Feature Flag
enum VoiceServiceType {
    case grok       // 直接 WebSocket 連接 xAI
    case liveKit    // LiveKit + xAI (推薦，支援 barge-in)

    static var current: VoiceServiceType {
        // 可以根據需要切換
        // 推薦使用 LiveKit 以獲得更好的 barge-in 支援
        #if DEBUG
        return .liveKit
        #else
        return .liveKit
        #endif
    }
}

// MARK: - Preview
#Preview("LiveKit Voice Chat") {
    LiveKitVoiceChatView(isPresented: .constant(true))
}
