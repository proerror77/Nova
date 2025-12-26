import SwiftUI
import AVFoundation

// MARK: - Conversation Message Model
struct VoiceChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: MessageRole
    let text: String
    let timestamp: Date

    enum MessageRole {
        case user
        case assistant
    }
}

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
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""

    // 對話歷史
    @State private var messages: [VoiceChatMessage] = []
    @State private var pendingUserText: String = ""
    @State private var pendingAIText: String = ""

    // 文字輸入模式
    @State private var isTextInputMode: Bool = false
    @State private var textInput: String = ""
    @FocusState private var isTextFieldFocused: Bool

    // 動畫
    @State private var pulseAnimation: Bool = false
    @State private var wavePhase: Double = 0
    @State private var delegateHandler: LiveKitVoiceDelegateHandler?

    // 重連邏輯
    @State private var reconnectAttempts: Int = 0
    private let maxReconnectAttempts: Int = 3

    // 動畫計時器
    @State private var waveAnimationTimer: Timer?

    var body: some View {
        ZStack {
            backgroundGradient

            VStack(spacing: 0) {
                topBar

                if isTextInputMode {
                    // 文字輸入模式：顯示對話歷史 + 輸入框
                    conversationHistoryView
                    textInputBar
                } else {
                    // 語音模式：顯示 Avatar + 當前對話
                    Spacer()
                    mainContent
                    Spacer()
                    bottomControls
                }
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
        .alert("連線錯誤", isPresented: $showErrorAlert) {
            Button("重試") {
                attemptReconnect()
            }
            Button("關閉", role: .cancel) {
                endVoiceChat()
                isPresented = false
            }
        } message: {
            Text(errorMessage)
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

                Text("LiveKit")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(4)
            }

            Spacer()

            // 切換文字/語音模式
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    isTextInputMode.toggle()
                    if isTextInputMode {
                        isTextFieldFocused = true
                    }
                }
                triggerHaptic(.light)
            }) {
                Image(systemName: isTextInputMode ? "waveform" : "keyboard")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var statusColor: Color {
        switch state {
        case .disconnected, .error: return .red
        case .connecting: return .yellow
        case .connected, .listening: return .green
        case .userSpeaking: return .cyan
        case .aiSpeaking: return .purple
        }
    }

    // MARK: - Conversation History View
    private var conversationHistoryView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }

                    // 顯示正在進行的對話
                    if !pendingUserText.isEmpty {
                        pendingMessageBubble(text: pendingUserText, isUser: true)
                    }
                    if !pendingAIText.isEmpty {
                        pendingMessageBubble(text: pendingAIText, isUser: false)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: messages.count) { _, _ in
                if let lastMessage = messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func messageBubble(_ message: VoiceChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.role == .user ? "你" : "Alice")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(message.role == .user ? .cyan.opacity(0.7) : .purple.opacity(0.7))

                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.95))
                    .multilineTextAlignment(message.role == .user ? .trailing : .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.role == .user
                            ? AnyShapeStyle(Color.cyan.opacity(0.2))
                            : AnyShapeStyle(LinearGradient(
                                colors: [.purple.opacity(0.25), .blue.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                    )
                    .cornerRadius(16)
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }

    private func pendingMessageBubble(text: String, isUser: Bool) -> some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(isUser ? "你" : "Alice")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isUser ? .cyan.opacity(0.7) : .purple.opacity(0.7))

                    // 打字指示器
                    Text("...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }

                Text(text)
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.7))
                    .italic()
                    .multilineTextAlignment(isUser ? .trailing : .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(16)
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }

    // MARK: - Text Input Bar
    private var textInputBar: some View {
        HStack(spacing: 12) {
            TextField("輸入訊息...", text: $textInput)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.1))
                .cornerRadius(24)
                .focused($isTextFieldFocused)
                .onSubmit {
                    sendTextMessage()
                }

            Button(action: sendTextMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(textInput.isEmpty ? .white.opacity(0.3) : .purple)
            }
            .disabled(textInput.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.3))
    }

    // MARK: - Main Content (Voice Mode)
    private var mainContent: some View {
        VStack(spacing: 30) {
            aliceAvatarWithWaves

            stateIndicator

            // 當前對話顯示（簡化版）
            currentTranscriptView

            // 顯示歷史對話數量提示
            if !messages.isEmpty {
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        isTextInputMode = true
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 12))
                        Text("查看 \(messages.count) 則對話")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(20)
                }
            }
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Alice Avatar
    private var aliceAvatarWithWaves: some View {
        ZStack {
            // 波紋動畫
            if state == .userSpeaking || state == .listening || state == .aiSpeaking {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: state == .userSpeaking
                                    ? [.cyan.opacity(0.8), .blue.opacity(0.4)]
                                    : [.purple.opacity(0.6), .blue.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: state == .userSpeaking ? 3 : 2
                        )
                        .frame(width: 140 + CGFloat(index * 35), height: 140 + CGFloat(index * 35))
                        .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                        .opacity(pulseAnimation ? 0 : (state == .userSpeaking ? 0.8 : 0.6))
                        .animation(
                            .easeOut(duration: state == .userSpeaking ? 0.8 : 1.5)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) * 0.3),
                            value: pulseAnimation
                        )
                }
            }

            // 音量波形
            if state == .userSpeaking || state == .listening || state == .aiSpeaking {
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
                    .frame(width: 120, height: 120)

                Image("alice-center-icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 85, height: 85)
            }
            .shadow(color: .purple.opacity(0.5), radius: 20, x: 0, y: 10)
        }
        .frame(height: 240)
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
        .frame(height: 50)
        .offset(y: 85)
    }

    private func waveHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 8
        let maxHeight: CGFloat = 40
        let variation = sin(Double(index) * 0.5 + wavePhase) * 0.5 + 0.5
        return baseHeight + (maxHeight - baseHeight) * CGFloat(audioLevel) * CGFloat(variation)
    }

    // MARK: - State Indicator
    private var stateIndicator: some View {
        VStack(spacing: 6) {
            Text(stateTitle)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)

            Text(stateSubtitle)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    private var stateTitle: String {
        switch state {
        case .disconnected: return "未連線"
        case .connecting: return "連線中..."
        case .connected: return "已連線"
        case .listening: return "正在聆聽..."
        case .userSpeaking: return "你正在說話"
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
        case .userSpeaking: return "正在識別你的語音..."
        case .aiSpeaking: return "你可以隨時打斷 Alice"
        case .error(let msg): return msg
        }
    }

    // MARK: - Current Transcript View
    private var currentTranscriptView: some View {
        VStack(spacing: 12) {
            if !pendingUserText.isEmpty || !transcript.isEmpty {
                HStack {
                    Text(pendingUserText.isEmpty ? transcript : pendingUserText)
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.cyan.opacity(0.15))
                .cornerRadius(16)
            }

            if !pendingAIText.isEmpty || !aiResponse.isEmpty {
                HStack {
                    Text(pendingAIText.isEmpty ? aiResponse : pendingAIText)
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
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
        .frame(minHeight: 80)
    }

    // MARK: - Bottom Controls
    private var bottomControls: some View {
        VStack(spacing: 20) {
            HStack(spacing: 50) {
                // 靜音
                controlButton(
                    icon: isMuted ? "mic.slash.fill" : "mic.fill",
                    isActive: !isMuted,
                    color: isMuted ? .red : .white,
                    action: toggleMute
                )

                // 結束
                Button(action: { showEndConfirmation = true }) {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 68, height: 68)

                        Image(systemName: "phone.down.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.white)
                    }
                }
                .shadow(color: .red.opacity(0.4), radius: 10, x: 0, y: 5)

                // 鍵盤切換
                controlButton(
                    icon: "keyboard",
                    isActive: true,
                    color: .white,
                    action: {
                        withAnimation(.spring(response: 0.3)) {
                            isTextInputMode = true
                            isTextFieldFocused = true
                        }
                    }
                )
            }

            Text("LiveKit WebRTC • 支援語音打斷")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.bottom, 40)
    }

    private func controlButton(icon: String, isActive: Bool, color: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: {
            action()
            triggerHaptic(.light)
        }) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(isActive ? 0.2 : 0.1))
                    .frame(width: 52, height: 52)

                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(isActive ? color : color.opacity(0.5))
            }
        }
    }

    // MARK: - Haptic Feedback
    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    // MARK: - Actions
    private func startVoiceChat() {
        print("[LiveKitVoiceChatView] Starting LiveKit voice chat")
        reconnectAttempts = 0

        // 啟動波形動畫計時器（每 0.1 秒更新一次，而非每個音頻回調）
        waveAnimationTimer?.invalidate()
        waveAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            wavePhase += 0.1
        }

        let handler = LiveKitVoiceDelegateHandler(
            onStateChange: { newState in
                let oldState = state
                withAnimation(.easeInOut(duration: 0.3)) {
                    state = newState
                }

                // Haptic feedback on state changes
                if oldState != newState {
                    switch newState {
                    case .connected:
                        triggerHaptic(.medium)
                    case .aiSpeaking:
                        triggerHaptic(.light)
                    case .error:
                        triggerHaptic(.heavy)
                    default:
                        break
                    }
                }
            },
            onTranscript: { text, isFinal in
                if isFinal {
                    // 最終結果：加入歷史記錄
                    if !text.isEmpty {
                        // 檢查是否已存在相同內容（避免重複）
                        let isDuplicate = messages.last?.text == text && messages.last?.role == .user
                        if !isDuplicate {
                            let message = VoiceChatMessage(role: .user, text: text, timestamp: Date())
                            messages.append(message)
                        }
                        pendingUserText = ""
                        transcript = text
                    }
                } else {
                    // 暫時結果：顯示 pending
                    pendingUserText = text
                    transcript = text
                }
            },
            onAIResponse: { text in
                // AI 回覆完成：加入歷史記錄
                if !text.isEmpty {
                    // 檢查是否已存在相同內容（避免重複）
                    if messages.last?.text != text || messages.last?.role != .assistant {
                        let message = VoiceChatMessage(role: .assistant, text: text, timestamp: Date())
                        messages.append(message)
                    }
                    pendingAIText = ""
                    aiResponse = text
                }
            },
            onAudioLevel: { level in
                // 只有當音量變化超過閾值時才更新，減少不必要的 UI 重繪
                if abs(audioLevel - level) > 0.05 {
                    audioLevel = level
                }
                // 使用 Timer 控制動畫而非每次回調都更新
            },
            onError: { code, message in
                print("[LiveKitVoiceChatView] Error: \(code) - \(message)")
                errorMessage = message
                showErrorAlert = true
                triggerHaptic(.heavy)
            }
        )
        delegateHandler = handler
        voiceService.delegate = handler

        voiceService.startVoiceChat()
    }

    private func attemptReconnect() {
        reconnectAttempts += 1
        if reconnectAttempts <= maxReconnectAttempts {
            print("[LiveKitVoiceChatView] Reconnect attempt \(reconnectAttempts)/\(maxReconnectAttempts)")
            endVoiceChat()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                startVoiceChat()
            }
        } else {
            print("[LiveKitVoiceChatView] Max reconnect attempts reached")
            errorMessage = "多次連線失敗，請稍後再試"
            showErrorAlert = true
        }
    }

    private func endVoiceChat() {
        // 停止動畫計時器
        waveAnimationTimer?.invalidate()
        waveAnimationTimer = nil
        voiceService.endVoiceChat()
    }

    private func toggleMute() {
        isMuted.toggle()
        voiceService.toggleMute()
        triggerHaptic(.light)
    }

    private func sendTextMessage() {
        guard !textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let messageText = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        textInput = ""

        // 加入用戶訊息到歷史
        let userMessage = VoiceChatMessage(role: .user, text: messageText, timestamp: Date())
        messages.append(userMessage)

        // TODO: 發送文字到 LiveKit Agent（需要後端支援）
        // 目前 LiveKit Agent 只支援語音輸入，未來可以添加 data channel 文字支援
        print("[LiveKitVoiceChatView] Text message (not yet supported): \(messageText)")

        // 暫時顯示提示
        let systemMessage = VoiceChatMessage(
            role: .assistant,
            text: "文字輸入功能開發中，請使用語音對話",
            timestamp: Date()
        )
        messages.append(systemMessage)

        triggerHaptic(.light)
    }
}

// MARK: - Delegate Handler
private class LiveKitVoiceDelegateHandler: LiveKitVoiceServiceDelegate {
    let onStateChange: (LiveKitVoiceChatState) -> Void
    let onTranscript: (String, Bool) -> Void
    let onAIResponse: (String) -> Void
    let onAudioLevel: (Float) -> Void
    let onError: (String, String) -> Void

    init(
        onStateChange: @escaping (LiveKitVoiceChatState) -> Void,
        onTranscript: @escaping (String, Bool) -> Void,
        onAIResponse: @escaping (String) -> Void,
        onAudioLevel: @escaping (Float) -> Void,
        onError: @escaping (String, String) -> Void
    ) {
        self.onStateChange = onStateChange
        self.onTranscript = onTranscript
        self.onAIResponse = onAIResponse
        self.onAudioLevel = onAudioLevel
        self.onError = onError
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

    func liveKitVoiceDidReceiveError(_ code: String, message: String) {
        DispatchQueue.main.async {
            self.onError(code, message)
        }
    }
}

// MARK: - Feature Flag
enum VoiceServiceType {
    case grok
    case liveKit

    static var current: VoiceServiceType {
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
