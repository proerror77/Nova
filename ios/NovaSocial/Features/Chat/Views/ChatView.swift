import SwiftUI
import PhotosUI
import CoreLocation
import MapKit
import Combine
import AVFoundation
import UniformTypeIdentifiers

// MARK: - 聊天位置管理器
class ChatLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var location: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var locationError: Error?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestLocation() {
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.first?.coordinate
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
        locationError = error
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }
}

// MARK: - 相機視圖
struct CameraView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        init(_ parent: CameraView) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.image = image }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

// MARK: - 位置消息預覽視圖
struct LocationMessageView: View {
    let location: CLLocationCoordinate2D
    var body: some View {
        let region = MKCoordinateRegion(center: location, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        VStack(spacing: 4) {
            Map(initialPosition: .region(region)) { }
                .frame(width: 180, height: 120)
                .cornerRadius(12)
                .disabled(true)
            Text("My Location")
                .font(.system(size: 12))
                .foregroundColor(DesignTokens.textPrimary)
        }
        .padding(8)
        .background(DesignTokens.chatBubbleOther)
        .cornerRadius(12)
    }
}

// MARK: - 語音消息視圖
struct VoiceMessageView: View {
    let message: ChatMessage
    let isFromMe: Bool
    let audioPlayer: AudioPlayerService
    @State private var isPlaying = false

    private var duration: TimeInterval { message.audioDuration ?? 0 }
    private var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: { togglePlayback() }) {
                Circle()
                    .fill(isFromMe ? Color.white.opacity(0.3) : Color(red: 0.91, green: 0.18, blue: 0.30))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: isCurrentlyPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                    )
            }
            HStack(spacing: 2) {
                ForEach(0..<12, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(isFromMe ? Color.white.opacity(0.7) : DesignTokens.textMuted)
                        .frame(width: 3, height: CGFloat.random(in: 8...20))
                }
            }.frame(height: 24)
            Text(isCurrentlyPlaying ? formatCurrentTime() : formattedDuration)
                .font(Font.custom("Helvetica Neue", size: 12).monospacedDigit())
                .foregroundColor(isFromMe ? Color.white.opacity(0.8) : DesignTokens.textMuted)
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 16))
        .background(isFromMe ? Color(red: 0.91, green: 0.18, blue: 0.30) : DesignTokens.chatBubbleOther)
        .cornerRadius(20)
    }

    private var isCurrentlyPlaying: Bool { audioPlayer.playingMessageId == message.id && audioPlayer.isPlaying }
    private func formatCurrentTime() -> String {
        let time = audioPlayer.currentTime
        return String(format: "%d:%02d", Int(time) / 60, Int(time) % 60)
    }
    private func togglePlayback() {
        if isCurrentlyPlaying { audioPlayer.pause() }
        else if audioPlayer.playingMessageId == message.id { audioPlayer.resume() }
        else if let url = message.audioUrl { audioPlayer.play(url: url, messageId: message.id) }
        else if let data = message.audioData { audioPlayer.play(data: data, messageId: message.id) }
    }
}

// MARK: - Typing Dots Animation
struct TypingDotsView: View {
    @State private var animationPhase = 0
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(DesignTokens.textMuted)
                    .frame(width: 6, height: 6)
                    .scaleEffect(animationPhase == index ? 1.2 : 0.8)
                    .animation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true).delay(Double(index) * 0.15), value: animationPhase)
            }
        }
        .onAppear { animationPhase = 2 }
    }
}

// MARK: - 消息氣泡視圖
struct MessageBubbleView: View {
    let message: ChatMessage
    var audioPlayer: AudioPlayerService? = nil
    private let myBubbleColor = Color(red: 0.91, green: 0.20, blue: 0.34)
    private let otherBubbleColor = Color(red: 0.92, green: 0.92, blue: 0.92)
    private let otherTextColor = Color(red: 0.34, green: 0.34, blue: 0.34)

    var body: some View {
        if message.isFromMe { myMessageView } else { otherMessageView }
    }

    private var myMessageView: some View {
        HStack(alignment: .top, spacing: 10) {
            Spacer()
            messageContent
            DefaultAvatarView(size: 40)
        }.padding(.horizontal, 16)
    }

    private var otherMessageView: some View {
        HStack(alignment: .top, spacing: 10) {
            DefaultAvatarView(size: 40)
            otherMessageContent
            Spacer()
        }.padding(.horizontal, 16)
    }

    @ViewBuilder private var messageContent: some View {
        if let image = message.image {
            Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 200, maxHeight: 200).cornerRadius(14)
        } else if let location = message.location {
            LocationMessageView(location: location)
        } else if message.audioData != nil || message.audioUrl != nil, let player = audioPlayer {
            VoiceMessageView(message: message, isFromMe: true, audioPlayer: player)
        } else {
            Text(message.text)
                .font(Font.custom("Helvetica Neue", size: 16)).lineSpacing(4).foregroundColor(.white)
                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                .padding(EdgeInsets(top: 11, leading: 20, bottom: 11, trailing: 20))
                .background(myBubbleColor).cornerRadius(14).frame(maxWidth: 260, alignment: .trailing)
        }
    }

    @ViewBuilder private var otherMessageContent: some View {
        if let image = message.image {
            Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 200, maxHeight: 200).cornerRadius(14)
        } else if let location = message.location {
            LocationMessageView(location: location)
        } else if message.audioData != nil || message.audioUrl != nil, let player = audioPlayer {
            VoiceMessageView(message: message, isFromMe: false, audioPlayer: player)
        } else {
            Text(message.text)
                .font(Font.custom("Helvetica Neue", size: 16)).lineSpacing(4).foregroundColor(otherTextColor)
                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                .padding(EdgeInsets(top: 11, leading: 20, bottom: 11, trailing: 20))
                .background(otherBubbleColor).cornerRadius(14).frame(maxWidth: 260, alignment: .leading)
        }
    }
}

// MARK: - 附件選項按鈕
struct AttachmentOptionButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(Color(red: 0.96, green: 0.96, blue: 0.96)).frame(width: 56, height: 56)
                Image(systemName: icon).font(.system(size: 24)).foregroundColor(DesignTokens.textPrimary)
            }
            Text(title).font(.system(size: 12)).lineSpacing(20).foregroundColor(DesignTokens.textPrimary)
        }.frame(width: 60).onTapGesture { action() }
    }
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
            DocumentPickerView(onDocumentPicked: handleDocumentPicked)
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
                VStack(spacing: 16) {
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

                    Text(currentDateString())
                        .font(Font.custom("Helvetica Neue", size: 12))
                        .lineSpacing(20)
                        .foregroundColor(Color(red: 0.59, green: 0.59, blue: 0.59))
                        .padding(.top, 16)

                    ForEach(messages) { message in
                        MessageBubbleView(message: message, audioPlayer: audioPlayer)
                            .id(message.id)
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
                            DefaultAvatarView(size: 30)
                            
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
            .onChange(of: messages.count) { _, _ in
                if let lastMessage = messages.last {
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

            // MatrixService.getRoomMessages doesn't expose a paging cursor yet
            hasMoreMessages = false
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
            print("[ChatView] ⚠️ Matrix message handler already setup, skipping duplicate setup\")")
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
                    print("[ChatView] ⚠️ Skipping duplicate message: \\(matrixMessage.id) (already exists)")
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
                    print("[ChatView] ⚠️ Skipping duplicate message: \\(newChatMessage.id) (added during conversion)")
                    #endif
                    return
                }

                // 添加到 UI
                self.messages.append(newChatMessage)
                
                #if DEBUG
                print("[ChatView] ✅ Message added to UI - ID: \\(newChatMessage.id), Sender: \\(newChatMessage.isFromMe ? \"me\" : \"other\"), Total: \\(self.messages.count)")
                #endif

                // 清除打字指示器
                self.isOtherUserTyping = false

                // Mark as read (Matrix read receipt)
                if novaMessage.senderId != self.currentUserId {
                    #if DEBUG
                    print("[ChatView] 📖 Marking message as read - ID: \\(matrixMessage.id)")
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
        guard !isLoadingHistory else { return }

        isLoadingHistory = true

        do {
            let desiredLimit = max(messages.count + 50, 50)
            let matrixMessages = try await matrixBridge.getMessages(conversationId: conversationId, limit: desiredLimit)
            let sorted = matrixMessages.sorted { $0.timestamp < $1.timestamp }
            messages = sorted.map { matrixMessage in
                let novaMessage = matrixBridge.convertToNovaMessage(matrixMessage, conversationId: conversationId)
                return ChatMessage(from: novaMessage, currentUserId: currentUserId)
            }
        } catch {
            #if DEBUG
            print("[ChatView] Load more error: \(error)")
            #endif
        }

        isLoadingHistory = false
    }

    // MARK: - Send Text Message
    /// 發送文字訊息 - 使用 Matrix E2EE（端到端加密）
    private func sendMessage() {
        let trimmedText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, !isSending else { return }

        messageText = ""
        showAttachmentOptions = false

        // 立即添加到本地 UI（樂觀更新）
        let localMessage = ChatMessage(localText: trimmedText, isFromMe: true)
        messages.append(localMessage)

        Task {
            isSending = true
            do {
                try? await matrixBridge.setTyping(conversationId: conversationId, isTyping: false)
                let eventId = try await matrixBridge.sendMessage(conversationId: conversationId, content: trimmedText)
                try? await matrixBridge.markAsRead(conversationId: conversationId)

                // 用服务器返回的消息ID更新本地消息
                if let index = messages.firstIndex(where: { $0.id == localMessage.id }) {
                    var updatedMessage = messages[index]
                    updatedMessage.id = eventId
                    messages[index] = updatedMessage
                }

                #if DEBUG
                print("[ChatView] ✅ Message sent via Matrix: room=\(conversationId), eventId=\(eventId)")
                #endif
            } catch {
                // Send failed - remove the local message and show error
                messages.removeAll { $0.id == localMessage.id }
                self.error = "Failed to send message: \(error.localizedDescription)"
                #if DEBUG
                print("[ChatView] ❌ Failed to send message: \(error)")
                #endif
            }
            isSending = false
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
                self.error = "Failed to send image"
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

    // MARK: - 檔案處理

    /// 處理選擇的檔案
    private func handleDocumentPicked(_ url: URL) {
        // 開始存取安全範圍的資源
        guard url.startAccessingSecurityScopedResource() else {
            error = "Cannot access file"
            return
        }

        defer {
            url.stopAccessingSecurityScopedResource()
        }

        Task {
            isUploadingFile = true
            isSending = true

            do {
                // 讀取檔案數據
                let fileData = try Data(contentsOf: url)
                let fileName = url.lastPathComponent
                let mimeType = getMimeType(for: url)

                // 將檔案複製到臨時目錄
                let tempDir = FileManager.default.temporaryDirectory
                let tempFileURL = tempDir.appendingPathComponent(fileName)
                try fileData.write(to: tempFileURL)

                #if DEBUG
                print("[ChatView] 📎 Sending file: \(fileName) (\(fileData.count) bytes)")
                #endif

                // 使用 Matrix SDK 發送檔案
                let eventId = try await MatrixBridgeService.shared.sendMessage(
                    conversationId: conversationId,
                    content: fileName,
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
                self.error = "Failed to send file: \(error.localizedDescription)"
            }

            isUploadingFile = false
            isSending = false
        }
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

// MARK: - Document Picker View

/// 檔案選擇器視圖
struct DocumentPickerView: UIViewControllerRepresentable {
    let onDocumentPicked: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [
            .pdf,
            .plainText,
            .image,
            .audio,
            .video,
            .data,
            .spreadsheet,
            .presentation,
            .item
        ])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerView

        init(_ parent: DocumentPickerView) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onDocumentPicked(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            // User cancelled - no action needed
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
