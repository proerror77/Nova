import SwiftUI
import PhotosUI
import CoreLocation
import MapKit
import Combine
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Message Send Error
enum MessageSendError: Error {
    case timeout
}

// MARK: - ChatView
struct ChatView: View {
    // MARK: - Static Properties
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd  HH:mm"
        return formatter
    }()

    // MARK: - 预览模式配置 (开发调试用)
    // 🎨 在模拟器上运行时启用预览模式，方便调试UI
    #if DEBUG
    private static var useChatPreviewMode: Bool {
        #if targetEnvironment(simulator)
        return false  // 关闭模拟器预览模式，使用真实API
        #else
        return false
        #endif
    }
    #else
    private static let useChatPreviewMode = false
    #endif

    // MARK: - Mock Data for UI Preview
    private static var mockMessages: [ChatMessage] {
        let calendar = Calendar.current
        let now = Date()
        _ = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now) ?? now

        return [
            ChatMessage(localText: "Hello, how are you bro~", isFromMe: false),
            ChatMessage(localText: "Have you been busy recently?", isFromMe: false),
            ChatMessage(localText: "Not bad. There's a new project recently and I'm extremely busy", isFromMe: true),
            ChatMessage(localText: "Is there dinner time tonight? There is a project that you might be interested in", isFromMe: false),
        ]
    }

    // MARK: - Services
    private let matrixBridge = MatrixBridgeService.shared

    /// 必需参数
    @Binding var showChat: Bool
    let conversationId: String  // ← 从上级View传入，标识当前聊天对象
    var userName: String = "User"
    var otherUserAvatarUrl: String? = nil  // 對方用戶頭像URL（從父視圖傳入）

    // MARK: - State
    @State private var messageText = ""
    @State private var showUserProfile = false
    @State private var messages: [ChatMessage] = []
    @State private var showAttachmentOptions = false
    @FocusState private var isInputFocused: Bool

    // Loading states
    @State private var isLoadingHistory = false
    @State private var isSending = false
    @State private var isUploadingImage = false
    @State private var error: String?
    @State private var isPreviewMode = false  // 追踪预览模式状态

    // Matrix E2EE status
    @State private var isMatrixE2EEEnabled = false
    
    // Typing indicator state
    @State private var isOtherUserTyping = false
    @State private var typingUserName: String = ""
    @State private var typingTimer: Timer?
    
    // Pagination
    @State private var hasMoreMessages = true
    @State private var nextCursor: String?


    // 相册相关
    @State private var selectedPhotoItem: PhotosPickerItem?

    // 相机相关
    @State private var showCamera = false
    @State private var cameraImage: UIImage?
    @State private var showCameraPermissionAlert = false

    // 位置相关
    @StateObject private var locationManager = ChatLocationManager()

    // 语音录制相关
    @State private var audioRecorder = AudioRecorderService()
    @State private var audioPlayer = AudioPlayerService()
    @State private var isRecordingVoice = false
    @State private var showMicrophonePermissionAlert = false
    @State private var showLocationAlert = false

    // 通話相關
    @State private var showVoiceCall = false
    @State private var showVideoCall = false

    // 檔案分享相關
    @State private var showFilePicker = false
    @State private var isUploadingFile = false

    // 当前用户ID（从Keychain获取）
    private var currentUserId: String {
        KeychainService.shared.get(.userId) ?? "unknown"
    }

    // 當前用戶頭像URL（從AuthenticationManager獲取）
    private var currentUserAvatarUrl: String? {
        AuthenticationManager.shared.currentUser?.avatarUrl
    }
    
    // Matrix 消息处理器状态（防止重复设置）
    @State private var matrixMessageHandlerSetup = false


    var body: some View {
        ZStack {
            DesignTokens.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                navigationBar

                Divider()
                    .frame(height: 0.5)
                    .background(DesignTokens.borderColor)

                messageListView

                inputAreaView
            }
        }
        .fullScreenCover(isPresented: $showUserProfile) {
            UserProfileView(
                showUserProfile: $showUserProfile,
                userId: conversationId  // 使用会话ID（实际项目中应传入对方用户ID）
            )
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView(image: $cameraImage)
        }
        .fullScreenCover(isPresented: $showVoiceCall) {
            CallView(
                roomId: conversationId,
                roomName: userName,
                isVideoCall: false,
                intent: .startCallDM
            )
        }
        .fullScreenCover(isPresented: $showVideoCall) {
            CallView(
                roomId: conversationId,
                roomName: userName,
                isVideoCall: true,
                intent: .startCallDM
            )
        }
        .sheet(isPresented: $showFilePicker) {
            DocumentPickerView(
                onDocumentPicked: { data, filename, mimeType in
                    handleDocumentPicked(data: data, filename: filename, mimeType: mimeType)
                },
                onError: { error in
                    self.error = "Cannot access file: \(error.localizedDescription)"
                }
            )
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            handlePhotoSelection(newItem)
        }
        .onChange(of: cameraImage) { _, newImage in
            handleCameraImage(newImage)
        }
        .onReceive(locationManager.$location) { newLocation in
            handleLocationUpdate(newLocation)
        }
        .alert("Share Location", isPresented: $showLocationAlert) {
            Button("Share") {
                if let location = locationManager.location {
                    sendLocationMessage(location: location)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Share your current location?")
        }
        .alert("Camera Access Required", isPresented: $showCameraPermissionAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
        } message: {
            Text("Please enable camera access in Settings to take photos.")
        }
        .alert("Microphone Access Required", isPresented: $showMicrophonePermissionAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
        } message: {
            Text("Please enable microphone access in Settings to record voice messages.")
        }
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
        .task {
            // ✅ 使用.task而非.onAppear - 自动处理取消
            await loadChatData()
        }
        .onDisappear {
            // Clear Matrix callbacks and reset handler setup flag
            MatrixBridgeService.shared.onMatrixMessage = nil
            MatrixBridgeService.shared.onTypingIndicator = nil
            matrixMessageHandlerSetup = false

            Task {
                await matrixBridge.stopListening(conversationId: conversationId)
                try? await matrixBridge.setTyping(conversationId: conversationId, isTyping: false)
            }
            
            // Clean up timer
            typingTimer?.invalidate()
            
            #if DEBUG
            print("[ChatView] Cleanup completed for conversation \(conversationId)")
            #endif
        }
    }

    // MARK: - 导航栏
    private var navigationBar: some View {
        HStack(spacing: 13) {
            Button(action: {
                showChat = false
            }) {
                Image(systemName: "chevron.left")
                    .frame(width: 24, height: 24)
                    .foregroundColor(DesignTokens.textPrimary)
            }

            HStack(spacing: 13) {
                // 头像 - alice 使用自定义图片，其他用户使用默认头像
                if userName.lowercased() == "alice" {
                    Image("alice-avatar")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                } else {
                    DefaultAvatarView(size: 40)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(userName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(DesignTokens.textPrimary)

                    // Matrix E2EE 狀態指示器
                    if isMatrixE2EEEnabled {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                            Text("End-to-end encrypted")
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    showUserProfile = true
                }
            }

            Spacer()
        }
        .frame(height: DesignTokens.topBarHeight)
        .padding(.horizontal, 16)
        .background(DesignTokens.surface)
    }

    // MARK: - 消息列表
    private var messageListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    // MARK: - 加載更多歷史消息按鈕
                    if hasMoreMessages && !isLoadingHistory {
                        Button(action: {
                            Task { await loadMoreMessages() }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.up.circle")
                                    .font(.system(size: 14))
                                Text("載入更多歷史消息")
                                    .font(.system(size: 13))
                            }
                            .foregroundColor(DesignTokens.accentColor)
                            .padding(.vertical, 10)
                        }
                    }
                    
                    // MARK: - 预览模式提示（仅在DEBUG模式显示）
                    #if DEBUG
                    if isPreviewMode {
                        HStack(spacing: 8) {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 12))
                            Text("Preview Mode - Mock Data (Simulator)")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.1))
                    }
                    #endif

                    // 加载状态指示器
                    if isLoadingHistory {
                        ProgressView("Loading messages...")
                            .padding()
                    }

                    // 错误提示
                    if let error = error {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 30))
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Retry") {
                                Task { await loadChatData() }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                    }

                    // 日期分隔符
                    Text(currentDateString())
                        .font(Font.custom("Helvetica Neue", size: 12))
                        .lineSpacing(20)
                        .foregroundColor(Color(red: 0.59, green: 0.59, blue: 0.59))
                        .padding(.top, 16)

                    // 消息列表
                    ForEach(messages) { message in
                        MessageBubbleView(
                            message: message,
                            audioPlayer: audioPlayer,
                            senderAvatarUrl: otherUserAvatarUrl,
                            myAvatarUrl: currentUserAvatarUrl,
                            onLongPress: { msg in
                                handleMessageLongPress(msg)
                            },
                            onRetry: { msg in
                                retryFailedMessage(msg)
                            }
                        )
                        .id(message.id)
                        // 首條消息出現時嘗試加載更多
                        .onAppear {
                            if message.id == messages.first?.id && hasMoreMessages && !isLoadingHistory {
                                Task { await loadMoreMessages() }
                            }
                        }
                    }

                    // Sending indicator
                    if isSending {
                        HStack {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Sending...")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                    
                    // Typing indicator
                    if isOtherUserTyping {
                        HStack(spacing: 6) {
                            AvatarView(image: nil, url: otherUserAvatarUrl, size: 30)
                            
                            HStack(spacing: 4) {
                                Text("\(typingUserName.isEmpty ? userName : typingUserName) is typing")
                                    .font(Font.custom("Helvetica Neue", size: 14))
                                    .foregroundColor(DesignTokens.textMuted)
                                    .italic()
                                
                                // Animated dots
                                TypingDotsView()
                            }
                            .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                            .background(DesignTokens.chatBubbleOther.opacity(0.5))
                            .cornerRadius(16)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: isOtherUserTyping)
                    }
                }
                .padding(.bottom, 16)
            }
            .refreshable {
                await loadMoreMessages()
            }
            .onChange(of: messages.count) { oldCount, newCount in
                // 只有新消息添加時才滾動到底部（不是加載歷史）
                if newCount > oldCount, let lastMessage = messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                if showAttachmentOptions {
                    showAttachmentOptions = false
                }
            }
        }
    }

    // MARK: - 输入区域
    private var inputAreaView: some View {
        VStack(spacing: 0) {
            Divider()
                .frame(height: 0.5)
                .background(DesignTokens.borderColor)

            HStack(spacing: 12) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAttachmentOptions.toggle()
                    }
                }) {
                    ZStack {
                        Circle()
                            .stroke(Color(red: 0.91, green: 0.18, blue: 0.30), lineWidth: 2)
                            .frame(width: 26, height: 26)

                        Image(systemName: showAttachmentOptions ? "xmark" : "plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(red: 0.91, green: 0.18, blue: 0.30))
                    }
                }

                // Text Input (voice recording is handled by the mic button)
                    HStack(spacing: 8) {
                        TextField("Type a message...", text: $messageText)
                            .font(Font.custom("Helvetica Neue", size: 16))
                            .foregroundColor(DesignTokens.textPrimary)
                            .focused($isInputFocused)
                            .onSubmit {
                                sendMessage()
                            }
                            .onChange(of: messageText) { oldValue, newValue in
                                // Send typing indicator when user starts typing
                                if oldValue.isEmpty && !newValue.isEmpty {
                                    Task { try? await matrixBridge.setTyping(conversationId: conversationId, isTyping: true) }
                                }
                                // Send typing stop when text is cleared
                                if !oldValue.isEmpty && newValue.isEmpty {
                                    Task { try? await matrixBridge.setTyping(conversationId: conversationId, isTyping: false) }
                                }
                            }
                    }
                    .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .background(DesignTokens.inputBackground)
                    .cornerRadius(26)
                    .onChange(of: isInputFocused) { _, focused in
                        if focused && showAttachmentOptions {
                            showAttachmentOptions = false
                        }
                    }

                // Send button or Voice Record button
                if messageText.isEmpty {
                    // Press-and-hold voice record button
                    voiceRecordButton
                } else {
                    // Send text message button
                    Button(action: {
                        sendMessage()
                    }) {
                        Circle()
                            .fill(Color(red: 0.91, green: 0.18, blue: 0.30))
                            .frame(width: 33, height: 33)
                            .overlay(
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                            )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(DesignTokens.surface)

            if showAttachmentOptions {
                attachmentOptionsView
                    .transition(.move(edge: .bottom))
            }
        }
    }

    // MARK: - 附件选项视图
    private var attachmentOptionsView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 15) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    VStack(spacing: 4) {
                        Rectangle()
                            .foregroundColor(.clear)
                            .frame(width: 60, height: 60)
                            .background(DesignTokens.surface)
                            .cornerRadius(10)
                            .overlay(
                                Image(systemName: "photo.on.rectangle")
                                    .font(.system(size: 24))
                                    .foregroundColor(DesignTokens.textPrimary)
                            )
                        Text("Album")
                            .font(.system(size: 12))
                            .lineSpacing(20)
                            .foregroundColor(DesignTokens.textPrimary)
                    }
                    .frame(width: 60)
                }

                AttachmentOptionButton(icon: "camera", title: "Camera") {
                    showAttachmentOptions = false
                    checkCameraPermissionAndOpen()
                }

                AttachmentOptionButton(icon: "video.fill", title: "Video Call") {
                    showAttachmentOptions = false
                    showVideoCall = true
                }

                AttachmentOptionButton(icon: "phone.fill", title: "Voice Call") {
                    showAttachmentOptions = false
                    showVoiceCall = true
                }

                AttachmentOptionButton(icon: "location.fill", title: "Location") {
                    showAttachmentOptions = false
                    locationManager.requestLocation()
                    showLocationAlert = true
                }

                AttachmentOptionButton(icon: "doc.fill", title: "File") {
                    showAttachmentOptions = false
                    showFilePicker = true
                }
            }
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity)
        .background(DesignTokens.attachmentBackground)
    }

    // MARK: - 按住录音按钮
    /// 按住錄音、放開發送、向上滑動取消
    @State private var voiceRecordDragOffset: CGFloat = 0
    private let voiceCancelThreshold: CGFloat = -60

    private var voiceRecordButton: some View {
        ZStack {
            // 錄音中的背景脈衝動畫
            if isRecordingVoice {
                Circle()
                    .fill(Color.red.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .scaleEffect(audioRecorder.audioLevel > 0.3 ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: audioRecorder.audioLevel)
            }

            // 主按鈕
            Circle()
                .fill(isRecordingVoice ? Color.red : Color.gray.opacity(0.3))
                .frame(width: 33, height: 33)
                .overlay(
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14))
                        .foregroundColor(isRecordingVoice ? .white : DesignTokens.textMuted)
                )
                .scaleEffect(isRecordingVoice ? 1.2 : 1.0)
                .offset(y: voiceRecordDragOffset)
                .animation(.spring(response: 0.3), value: isRecordingVoice)

            // 取消提示
            if isRecordingVoice && voiceRecordDragOffset < voiceCancelThreshold {
                VStack {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.red)
                    Text("Release to Cancel")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .offset(y: -70)
                .transition(.opacity)
            }

            // 錄音時間顯示
            if isRecordingVoice {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)

                    Text(formatDuration(audioRecorder.recordingDuration))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.red)
                }
                .offset(x: -80)
                .transition(.opacity)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    handleVoiceRecordDragChanged(value)
                }
                .onEnded { value in
                    handleVoiceRecordDragEnded(value)
                }
        )
    }

    private func handleVoiceRecordDragChanged(_ value: DragGesture.Value) {
        // 開始錄音
        if !isRecordingVoice {
            startVoiceRecording()
        }

        // 追蹤拖動以支持取消手勢
        voiceRecordDragOffset = min(0, value.translation.height)
    }

    private func handleVoiceRecordDragEnded(_ value: DragGesture.Value) {
        // 檢查是否應該取消
        if voiceRecordDragOffset < voiceCancelThreshold {
            cancelVoiceRecording()
        } else if isRecordingVoice {
            stopAndSendVoiceMessage()
        }

        voiceRecordDragOffset = 0
    }

    // MARK: - 事件处理
    private func handlePhotoSelection(_ newItem: PhotosPickerItem?) {
        Task {
            do {
                if let data = try await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        sendImageMessage(image: image)
                    }
                }
            } catch {
                print("Failed to load photo: \(error.localizedDescription)")
                // Consider showing user-facing error in future
            }
        }
    }

    private func handleCameraImage(_ newImage: UIImage?) {
        if let image = newImage {
            sendImageMessage(image: image)
            cameraImage = nil
        }
    }

    private func handleLocationUpdate(_ newLocation: CLLocationCoordinate2D?) {
        if let location = newLocation, showLocationAlert {
            sendLocationMessage(location: location)
            showLocationAlert = false
        }
    }

    // MARK: - API Calls

    /// Load chat data via Matrix timeline/sync (Matrix-first)
    /// - Parameter retryCount: Number of retry attempts made (for automatic recovery)
    private func loadChatData(retryCount: Int = 0) async {
        // 🎨 预览模式：使用模拟数据进行UI调试
        if Self.useChatPreviewMode {
            print("🎨 [ChatView] Preview Mode enabled - using mock data")
            await MainActor.run {
                self.messages = Self.mockMessages
                self.isLoadingHistory = false
                self.error = nil
                self.isPreviewMode = true
            }
            return
        }

        await MainActor.run {
            self.isPreviewMode = false
        }

        isLoadingHistory = true
        error = nil

        do {
            if !matrixBridge.isInitialized {
                try await matrixBridge.initialize()
            }

            isMatrixE2EEEnabled = matrixBridge.isInitialized

            setupMatrixMessageHandler()

            let matrixMessages = try await matrixBridge.getMessages(conversationId: conversationId, limit: 50)
            let sorted = matrixMessages.sorted { $0.timestamp < $1.timestamp }
            messages = sorted.map { matrixMessage in
                let novaMessage = matrixBridge.convertToNovaMessage(matrixMessage, conversationId: conversationId)
                return ChatMessage(from: novaMessage, currentUserId: currentUserId)
            }

            // 如果返回了請求的消息數量，可能還有更多歷史消息
            hasMoreMessages = matrixMessages.count >= 50
            nextCursor = nil

            try? await matrixBridge.markAsRead(conversationId: conversationId)

            #if DEBUG
            print("[ChatView] Loaded \(messages.count) Matrix messages for room \(conversationId)")
            #endif
        } catch {
            // Check if this is a recoverable database corruption error
            if matrixBridge.handleMatrixError(error) && retryCount < 1 {
                #if DEBUG
                print("[ChatView] Database corruption detected, retrying with fresh session...")
                #endif
                // Re-initialize Matrix bridge after clearing session
                try? await matrixBridge.initialize()
                await loadChatData(retryCount: retryCount + 1)
                return
            }

            self.error = "Failed to load messages: \(error.localizedDescription)"
            #if DEBUG
            print("[ChatView] Load error: \(error)")
            #endif
        }

        isLoadingHistory = false
    }

    /// Setup Matrix Bridge message handler for E2EE messages
    private func setupMatrixMessageHandler() {
        // 防止重复设置处理器 - 只设置一次
        guard !matrixMessageHandlerSetup else {
            #if DEBUG
            print("[ChatView] ⚠️ Matrix message handler already setup, skipping duplicate setup")
            #endif
            return
        }
        
        matrixMessageHandlerSetup = true
        
        MatrixBridgeService.shared.onMatrixMessage = { [self] conversationId, matrixMessage in
            Task { @MainActor in
                // 只處理當前會話的訊息
                guard conversationId == self.conversationId else { return }

                // 跳過自己發送的訊息（避免與 optimistic update 重複）
                // 自己發的訊息已經通過 sendMessage() 的 optimistic update 添加
                if let myMatrixId = MatrixBridgeService.shared.matrixUserId,
                   matrixMessage.senderId == myMatrixId {
                    #if DEBUG
                    print("[ChatView] ✅ Skipping own message from Matrix sync: \(matrixMessage.id)")
                    #endif
                    return
                }

                // 避免重複
                if self.messages.contains(where: { $0.id == matrixMessage.id }) {
                    #if DEBUG
                    print("[ChatView] ⚠️ Skipping duplicate message: \(matrixMessage.id) (already exists)")
                    #endif
                    return
                }

                // 轉換 Matrix 訊息為 Nova 訊息格式
                let novaMessage = MatrixBridgeService.shared.convertToNovaMessage(
                    matrixMessage,
                    conversationId: conversationId
                )
                
                let newChatMessage = ChatMessage(from: novaMessage, currentUserId: self.currentUserId)
                
                // 再次檢查 - 防止競態條件（消息可能在轉換期間被添加）
                if self.messages.contains(where: { $0.id == newChatMessage.id }) {
                    #if DEBUG
                    print("[ChatView] ⚠️ Skipping duplicate message: \(newChatMessage.id) (added during conversion)")
                    #endif
                    return
                }

                // 添加到 UI
                self.messages.append(newChatMessage)
                
                #if DEBUG
                print("[ChatView] ✅ Message added to UI - ID: \(newChatMessage.id), Sender: \(newChatMessage.isFromMe ? "me" : "other"), Total: \(self.messages.count)")
                #endif

                // 清除打字指示器
                self.isOtherUserTyping = false

                // Mark as read (Matrix read receipt)
                if novaMessage.senderId != self.currentUserId {
                    #if DEBUG
                    print("[ChatView] 📖 Marking message as read - ID: \(matrixMessage.id)")
                    #endif
                    try? await self.matrixBridge.markAsRead(conversationId: self.conversationId)
                }
            }
        }

        // Matrix 打字指示器
        MatrixBridgeService.shared.onTypingIndicator = { [self] conversationId, userIds in
            Task { @MainActor in
                guard conversationId == self.conversationId else { return }
                guard !userIds.contains(self.currentUserId) else { return }

                self.isOtherUserTyping = !userIds.isEmpty

                // 3 秒後自動隱藏
                if !userIds.isEmpty {
                    self.typingTimer?.invalidate()
                    self.typingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                        Task { @MainActor in
                            self.isOtherUserTyping = false
                        }
                    }
                }
            }
        }

        #if DEBUG
        print("[ChatView] Matrix message handler setup complete")
        #endif
    }
    
    /// Load more messages (pagination)
    private func loadMoreMessages() async {
        guard !isLoadingHistory, hasMoreMessages else { return }

        isLoadingHistory = true
        let previousCount = messages.count

        do {
            // 請求比當前更多的消息來實現分頁
            let desiredLimit = messages.count + 50
            let matrixMessages = try await matrixBridge.getMessages(conversationId: conversationId, limit: desiredLimit)
            let sorted = matrixMessages.sorted { $0.timestamp < $1.timestamp }
            
            // 記錄第一條消息 ID 以保持滾動位置
            let firstMessageId = messages.first?.id
            
            messages = sorted.map { matrixMessage in
                let novaMessage = matrixBridge.convertToNovaMessage(matrixMessage, conversationId: conversationId)
                return ChatMessage(from: novaMessage, currentUserId: currentUserId)
            }
            
            // 檢查是否還有更多消息
            hasMoreMessages = messages.count > previousCount && matrixMessages.count >= desiredLimit
            
            #if DEBUG
            print("[ChatView] Loaded more messages: \(previousCount) -> \(messages.count), hasMore: \(hasMoreMessages)")
            #endif
        } catch {
            #if DEBUG
            print("[ChatView] Load more error: \(error)")
            #endif
        }

        isLoadingHistory = false
    }
    
    /// 處理消息長按操作
    private func handleMessageLongPress(_ message: ChatMessage) {
        // 刪除消息
        Task {
            do {
                try await matrixBridge.deleteMessage(
                    conversationId: conversationId,
                    messageId: message.id,
                    reason: nil
                )
                // 從本地列表移除
                await MainActor.run {
                    messages.removeAll { $0.id == message.id }
                }
                #if DEBUG
                print("[ChatView] Message deleted: \(message.id)")
                #endif
            } catch {
                #if DEBUG
                print("[ChatView] Failed to delete message: \(error)")
                #endif
                self.error = "無法刪除消息"
            }
        }
    }

    // MARK: - Send Text Message
    /// 發送文字訊息 - 使用 Matrix E2EE（端到端加密）
    private func sendMessage() {
        let trimmedText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, !isSending else { return }

        messageText = ""
        showAttachmentOptions = false

        // 立即添加到本地 UI（樂觀更新）
        var localMessage = ChatMessage(localText: trimmedText, isFromMe: true)
        messages.append(localMessage)
        let localMessageId = localMessage.id

        Task {
            isSending = true
            do {
                try? await matrixBridge.setTyping(conversationId: conversationId, isTyping: false)

                // 使用超時機制發送訊息（30秒）
                let eventId = try await withTimeout(seconds: 30) {
                    try await matrixBridge.sendMessage(conversationId: conversationId, content: trimmedText)
                }

                try? await matrixBridge.markAsRead(conversationId: conversationId)

                // 更新本地消息：ID 和狀態
                await MainActor.run {
                    if let index = messages.firstIndex(where: { $0.id == localMessageId }) {
                        messages[index].id = eventId
                        messages[index].status = .sent
                    }
                }

                #if DEBUG
                print("[ChatView] ✅ Message sent via Matrix: room=\(conversationId), eventId=\(eventId)")
                #endif
            } catch {
                // 發送失敗 - 更新狀態為 failed（保留訊息以便重試）
                await MainActor.run {
                    if let index = messages.firstIndex(where: { $0.id == localMessageId }) {
                        messages[index].status = .failed
                    }
                    self.error = getMessageSendErrorMessage(for: error)
                }
                #if DEBUG
                print("[ChatView] ❌ Failed to send message: \(error)")
                #endif
            }
            await MainActor.run {
                isSending = false
            }
        }
    }

    /// 帶超時的異步操作
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw MessageSendError.timeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    /// 獲取訊息發送錯誤訊息
    private func getMessageSendErrorMessage(for error: Error) -> String {
        if let sendError = error as? MessageSendError {
            switch sendError {
            case .timeout:
                return "Message sending timed out. Tap to retry."
            }
        }

        if let matrixError = error as? MatrixBridgeError {
            switch matrixError {
            case .notInitialized:
                return "Connection not ready. Tap to retry."
            case .notAuthenticated:
                return "Please sign in again."
            case .sessionExpired:
                return "Session expired. Please restart the app."
            case .roomMappingFailed:
                return "Chat room not found."
            case .messageSendFailed(let reason):
                return "Failed to send: \(reason)"
            case .bridgeDisabled:
                return "Messaging is temporarily unavailable."
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return "No internet connection. Tap to retry."
            case NSURLErrorTimedOut:
                return "Request timed out. Tap to retry."
            default:
                return "Network error. Tap to retry."
            }
        }

        return "Failed to send message. Tap to retry."
    }

    /// 重試發送失敗的訊息
    private func retryFailedMessage(_ message: ChatMessage) {
        guard message.status == .failed else { return }

        // 找到訊息索引並更新狀態為 sending
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages[index].status = .sending

        let messageId = message.id
        let messageText = message.text

        Task {
            do {
                // 使用超時機制重新發送
                let eventId = try await withTimeout(seconds: 30) {
                    try await matrixBridge.sendMessage(conversationId: conversationId, content: messageText)
                }

                // 更新成功
                await MainActor.run {
                    if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                        messages[idx].id = eventId
                        messages[idx].status = .sent
                    }
                }

                #if DEBUG
                print("[ChatView] ✅ Message retry succeeded: \(eventId)")
                #endif
            } catch {
                // 重試失敗
                await MainActor.run {
                    if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                        messages[idx].status = .failed
                    }
                    self.error = getMessageSendErrorMessage(for: error)
                }

                #if DEBUG
                print("[ChatView] ❌ Message retry failed: \(error)")
                #endif
            }
        }
    }

    // MARK: - 發送圖片訊息
    /// 使用 Matrix SDK 發送圖片訊息
    private func sendImageMessage(image: UIImage) {
        // 壓縮圖片
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            #if DEBUG
            print("[ChatView] ❌ Failed to compress image")
            #endif
            error = "Failed to compress image"
            return
        }

        // 立即添加到本地 UI（樂觀更新）
        let localMessage = ChatMessage(localText: "", isFromMe: true, image: image)
        messages.append(localMessage)
        showAttachmentOptions = false

        Task {
            isUploadingImage = true

            do {
                // 確保 Matrix 已初始化
                guard MatrixBridgeService.shared.isInitialized else {
                    throw NSError(domain: "ChatView", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Matrix service not initialized"
                    ])
                }

                #if DEBUG
                print("[ChatView] 📤 Sending image via Matrix SDK")
                #endif

                // 將圖片數據保存到臨時文件
                let tempDir = FileManager.default.temporaryDirectory
                let filename = "chat_image_\(UUID().uuidString).jpg"
                let tempFileURL = tempDir.appendingPathComponent(filename)
                try imageData.write(to: tempFileURL)

                // 使用 Matrix SDK 發送圖片
                let eventId = try await MatrixBridgeService.shared.sendMessage(
                    conversationId: conversationId,
                    content: "",
                    mediaURL: tempFileURL,
                    mimeType: "image/jpeg"
                )

                // 清理臨時文件
                try? FileManager.default.removeItem(at: tempFileURL)

                let senderId = KeychainService.shared.get(.userId) ?? ""
                let sentMessage = Message(
                    id: eventId,
                    conversationId: conversationId,
                    senderId: senderId,
                    content: "",
                    type: .image,
                    createdAt: Date(),
                    status: .sent,
                    encryptionVersion: 3  // Matrix E2EE
                )

                #if DEBUG
                print("[ChatView] ✅ Image sent via Matrix: \(eventId)")
                #endif

                // 替換本地訊息為伺服器返回的訊息
                if let index = messages.firstIndex(where: { $0.id == localMessage.id }) {
                    var updatedMessage = ChatMessage(from: sentMessage, currentUserId: currentUserId)
                    updatedMessage.image = image  // 保留本地圖片用於顯示
                    messages[index] = updatedMessage
                }

            } catch {
                #if DEBUG
                print("[ChatView] ❌ Failed to send image: \(error)")
                #endif
                // 提供更具體的錯誤訊息
                self.error = getImageSendErrorMessage(for: error)
                // 移除失敗的本地訊息
                messages.removeAll { $0.id == localMessage.id }
            }

            isUploadingImage = false
        }
    }

    // MARK: - 發送位置訊息
    /// 發送位置訊息 - 使用 Matrix SDK
    private func sendLocationMessage(location: CLLocationCoordinate2D) {
        // 立即添加到本地 UI（樂觀更新）
        let localMessage = ChatMessage(localText: "", isFromMe: true, location: location)
        messages.append(localMessage)
        showAttachmentOptions = false

        Task {
            isSending = true

            do {
                // 確保 Matrix 已初始化
                guard MatrixBridgeService.shared.isInitialized else {
                    throw NSError(domain: "ChatView", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Matrix service not initialized"
                    ])
                }

                #if DEBUG
                print("[ChatView] 📍 Sending location via Matrix SDK")
                #endif

                // 使用 Matrix SDK 發送位置訊息
                let eventId = try await MatrixBridgeService.shared.sendLocation(
                    conversationId: conversationId,
                    latitude: location.latitude,
                    longitude: location.longitude
                )

                let senderId = KeychainService.shared.get(.userId) ?? ""
                let sentMessage = Message(
                    id: eventId,
                    conversationId: conversationId,
                    senderId: senderId,
                    content: "geo:\(location.latitude),\(location.longitude)",
                    type: .location,
                    createdAt: Date(),
                    status: .sent,
                    encryptionVersion: 3  // Matrix E2EE
                )

                #if DEBUG
                print("[ChatView] ✅ Location sent via Matrix: \(eventId)")
                #endif

                // 替換本地訊息為伺服器返回的訊息
                if let index = messages.firstIndex(where: { $0.id == localMessage.id }) {
                    var updatedMessage = ChatMessage(from: sentMessage, currentUserId: currentUserId)
                    updatedMessage.location = location
                    messages[index] = updatedMessage
                }

            } catch {
                #if DEBUG
                print("[ChatView] ❌ Failed to send location: \(error)")
                #endif
                self.error = "Failed to share location"
                // 移除失敗的本地訊息
                messages.removeAll { $0.id == localMessage.id }
            }

            isSending = false
        }
    }

    // MARK: - 获取当前日期字符串
    private func currentDateString() -> String {
        return Self.dateFormatter.string(from: Date())
    }

    // MARK: - 检查相机权限
    private func checkCameraPermissionAndOpen() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // Already authorized - open camera
            showCamera = true
        case .notDetermined:
            // Request permission
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showCamera = true
                    } else {
                        showCameraPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            // Permission denied - show alert to open settings
            showCameraPermissionAlert = true
        @unknown default:
            showCameraPermissionAlert = true
        }
    }

    // MARK: - 语音录制功能

    /// 开始录制语音消息
    private func startVoiceRecording() {
        Task {
            let started = await audioRecorder.startRecording()
            if started {
                isRecordingVoice = true
                #if DEBUG
                print("[ChatView] Voice recording started")
                #endif
            } else {
                // Show permission alert if needed
                if !audioRecorder.permissionGranted {
                    showMicrophonePermissionAlert = true
                } else if let errorMsg = audioRecorder.errorMessage {
                    error = errorMsg
                }
            }
        }
    }

    /// 取消录制
    private func cancelVoiceRecording() {
        audioRecorder.cancelRecording()
        isRecordingVoice = false
        #if DEBUG
        print("[ChatView] Voice recording cancelled")
        #endif
    }

    /// 停止录制并发送语音消息
    private func stopAndSendVoiceMessage() {
        guard let result = audioRecorder.stopRecording() else {
            isRecordingVoice = false
            error = "Failed to save recording"
            return
        }

        isRecordingVoice = false

        // 检查录音时长（太短的录音不发送）
        guard result.duration >= 1.0 else {
            #if DEBUG
            print("[ChatView] Recording too short: \(result.duration)s")
            #endif
            error = "Recording too short"
            audioRecorder.cleanupTempFiles()
            return
        }

        sendVoiceMessage(audioData: result.data, duration: result.duration, url: result.url)
    }

    /// 發送語音訊息 - 使用 Matrix SDK
    private func sendVoiceMessage(audioData: Data, duration: TimeInterval, url: URL) {
        // 立即添加到本地 UI（樂觀更新）
        let localMessage = ChatMessage(
            localText: "",
            isFromMe: true,
            audioData: audioData,
            audioDuration: duration,
            audioUrl: url
        )
        messages.append(localMessage)
        showAttachmentOptions = false

        Task {
            isSending = true

            do {
                // 確保 Matrix 已初始化
                guard MatrixBridgeService.shared.isInitialized else {
                    throw NSError(domain: "ChatView", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Matrix service not initialized"
                    ])
                }

                #if DEBUG
                print("[ChatView] 📤 Sending voice via Matrix SDK: \(url)")
                #endif

                // 使用 Matrix SDK 發送語音訊息
                let eventId = try await MatrixBridgeService.shared.sendMessage(
                    conversationId: conversationId,
                    content: String(format: "%.1f", duration),
                    mediaURL: url,
                    mimeType: "audio/mp4"
                )

                let senderId = KeychainService.shared.get(.userId) ?? ""
                let sentMessage = Message(
                    id: eventId,
                    conversationId: conversationId,
                    senderId: senderId,
                    content: String(format: "%.1f", duration),
                    type: .audio,
                    createdAt: Date(),
                    status: .sent,
                    encryptionVersion: 3  // Matrix E2EE
                )

                #if DEBUG
                print("[ChatView] ✅ Voice sent via Matrix: \(eventId)")
                #endif

                // 替換本地訊息為伺服器返回的訊息
                if let index = messages.firstIndex(where: { $0.id == localMessage.id }) {
                    var updatedMessage = ChatMessage(from: sentMessage, currentUserId: currentUserId)
                    updatedMessage.audioData = audioData
                    updatedMessage.audioDuration = duration
                    updatedMessage.audioUrl = url
                    messages[index] = updatedMessage
                }

            } catch {
                #if DEBUG
                print("[ChatView] ❌ Failed to send voice: \(error)")
                #endif
                self.error = "Failed to send voice message"
                // 移除失敗的本地訊息
                messages.removeAll { $0.id == localMessage.id }
            }

            isSending = false
            audioRecorder.cleanupTempFiles()
        }
    }

    /// 格式化时长显示
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// 根據錯誤類型返回用戶友好的錯誤訊息
    private func getImageSendErrorMessage(for error: Error) -> String {
        // 檢查是否是 Matrix 錯誤
        if let matrixError = error as? MatrixBridgeError {
            switch matrixError {
            case .notInitialized:
                return "Connection not ready. Please try again."
            case .notAuthenticated:
                return "Please sign in again to send images."
            case .sessionExpired:
                return "Session expired. Please restart the app."
            case .roomMappingFailed:
                return "Chat room not found. Please reopen the chat."
            case .messageSendFailed(let reason):
                return "Failed to send: \(reason)"
            case .bridgeDisabled:
                return "Messaging is temporarily unavailable."
            }
        }

        // 檢查網路錯誤
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return "No internet connection. Please check your network."
            case NSURLErrorTimedOut:
                return "Request timed out. Please try again."
            case NSURLErrorNetworkConnectionLost:
                return "Connection lost. Please try again."
            case NSURLErrorCannotConnectToHost:
                return "Cannot connect to server. Please try later."
            default:
                return "Network error. Please check your connection."
            }
        }

        // 檢查檔案相關錯誤
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
                return "Image file not found. Please try selecting again."
            case NSFileReadNoPermissionError:
                return "Cannot access image. Please check permissions."
            case NSFileWriteOutOfSpaceError:
                return "Storage full. Please free up space."
            default:
                break
            }
        }

        // 預設錯誤訊息，包含原始錯誤描述
        let description = error.localizedDescription
        if description.isEmpty || description == "The operation couldn't be completed." {
            return "Failed to send image. Please try again."
        }
        return "Failed to send image: \(description)"
    }

    // MARK: - 檔案處理

    /// 處理選擇的檔案（數據已在 DocumentPicker 回調中讀取）
    private func handleDocumentPicked(data: Data, filename: String, mimeType: String) {
        Task {
            isUploadingFile = true
            isSending = true

            do {
                // 將檔案數據複製到臨時目錄
                let tempDir = FileManager.default.temporaryDirectory
                let tempFileURL = tempDir.appendingPathComponent(filename)
                try data.write(to: tempFileURL)

                #if DEBUG
                print("[ChatView] 📎 Sending file: \(filename) (\(data.count) bytes)")
                #endif

                // 使用 Matrix SDK 發送檔案
                let eventId = try await MatrixBridgeService.shared.sendMessage(
                    conversationId: conversationId,
                    content: filename,
                    mediaURL: tempFileURL,
                    mimeType: mimeType
                )

                // 清理臨時檔案
                try? FileManager.default.removeItem(at: tempFileURL)

                #if DEBUG
                print("[ChatView] ✅ File sent via Matrix: \(eventId)")
                #endif

            } catch {
                #if DEBUG
                print("[ChatView] ❌ Failed to send file: \(error)")
                #endif
                // 提供更具體的錯誤訊息
                self.error = getFileSendErrorMessage(for: error, filename: filename)
            }

            isUploadingFile = false
            isSending = false
        }
    }

    /// 根據錯誤類型返回用戶友好的檔案發送錯誤訊息
    private func getFileSendErrorMessage(for error: Error, filename: String) -> String {
        // 檢查是否是 Matrix 錯誤
        if let matrixError = error as? MatrixBridgeError {
            switch matrixError {
            case .notInitialized:
                return "Connection not ready. Please try again."
            case .notAuthenticated:
                return "Please sign in again to send files."
            case .sessionExpired:
                return "Session expired. Please restart the app."
            case .roomMappingFailed:
                return "Chat room not found. Please reopen the chat."
            case .messageSendFailed(let reason):
                return "Failed to send \(filename): \(reason)"
            case .bridgeDisabled:
                return "Messaging is temporarily unavailable."
            }
        }

        // 檢查網路錯誤
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return "No internet connection. Please check your network."
            case NSURLErrorTimedOut:
                return "Upload timed out. Please try again."
            case NSURLErrorNetworkConnectionLost:
                return "Connection lost during upload. Please try again."
            default:
                return "Network error. Please check your connection."
            }
        }

        // 預設錯誤訊息
        let description = error.localizedDescription
        if description.isEmpty || description == "The operation couldn't be completed." {
            return "Failed to send \(filename). Please try again."
        }
        return "Failed to send file: \(description)"
    }

    /// 獲取檔案的 MIME 類型
    private func getMimeType(for url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        switch pathExtension {
        case "pdf":
            return "application/pdf"
        case "doc":
            return "application/msword"
        case "docx":
            return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls":
            return "application/vnd.ms-excel"
        case "xlsx":
            return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "ppt":
            return "application/vnd.ms-powerpoint"
        case "pptx":
            return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "txt":
            return "text/plain"
        case "zip":
            return "application/zip"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "mp3":
            return "audio/mpeg"
        case "mp4":
            return "video/mp4"
        case "mov":
            return "video/quicktime"
        default:
            return "application/octet-stream"
        }
    }
}

// MARK: - Previews

#Preview("Chat - Default") {
    ChatView(
        showChat: .constant(true),
        conversationId: "preview_conversation_123",
        userName: "Alice AI"
    )
}

#Preview("Chat - Dark Mode") {
    ChatView(
        showChat: .constant(true),
        conversationId: "preview_conversation_123",
        userName: "Alice AI"
    )
    .preferredColorScheme(.dark)
}
