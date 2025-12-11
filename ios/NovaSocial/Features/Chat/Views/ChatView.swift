import SwiftUI
import PhotosUI
import CoreLocation
import MapKit
import Combine
import AVFoundation

// MARK: - 消息UI模型
/// UI层的消息模型，包含后端Message + UI特定字段（图片、位置、语音）
struct ChatMessage: Identifiable, Equatable {
    let id: String  // 改为String以匹配后端Message.id
    let backendMessage: Message?  // 后端消息对象（可选，本地消息可能还没发送）
    let text: String
    let isFromMe: Bool
    let timestamp: Date
    var image: UIImage?
    var location: CLLocationCoordinate2D?
    var audioData: Data?  // 语音消息数据
    var audioDuration: TimeInterval?  // 语音时长（秒）
    var audioUrl: URL?  // 语音文件 URL

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }

    /// 从后端Message创建ChatMessage
    init(from message: Message, currentUserId: String) {
        self.id = message.id
        self.backendMessage = message
        self.text = message.content
        self.isFromMe = message.senderId == currentUserId
        self.timestamp = message.createdAt
        self.image = nil  // 图片需要单独加载
        self.location = nil  // TODO: 解析location类型消息
        self.audioData = nil
        self.audioDuration = nil
        self.audioUrl = nil
    }

    /// 创建本地消息（发送前）
    init(localText: String, isFromMe: Bool = true, image: UIImage? = nil, location: CLLocationCoordinate2D? = nil, audioData: Data? = nil, audioDuration: TimeInterval? = nil, audioUrl: URL? = nil) {
        self.id = UUID().uuidString
        self.backendMessage = nil
        self.text = localText
        self.isFromMe = isFromMe
        self.timestamp = Date()
        self.image = image
        self.location = location
        self.audioData = audioData
        self.audioDuration = audioDuration
        self.audioUrl = audioUrl
    }
}

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

// MARK: - 相机视图
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

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView

        init(_ parent: CameraView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - 位置标注
struct LocationAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

// MARK: - 位置消息预览视图
struct LocationMessageView: View {
    let location: CLLocationCoordinate2D

    var body: some View {
        let region = MKCoordinateRegion(
            center: location,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )

        VStack(spacing: 4) {
            // iOS 17+ new Map initializer with content builder (no annotations needed here)
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

// MARK: - 语音消息视图
struct VoiceMessageView: View {
    let message: ChatMessage
    let isFromMe: Bool
    let audioPlayer: AudioPlayerService

    @State private var isPlaying = false

    private var duration: TimeInterval {
        message.audioDuration ?? 0
    }

    private var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Play/Pause button
            Button(action: {
                togglePlayback()
            }) {
                Circle()
                    .fill(isFromMe ? Color.white.opacity(0.3) : Color(red: 0.91, green: 0.18, blue: 0.30))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: isCurrentlyPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14))
                            .foregroundColor(isFromMe ? .white : .white)
                    )
            }

            // Waveform visualization (static)
            HStack(spacing: 2) {
                ForEach(0..<12, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(isFromMe ? Color.white.opacity(0.7) : DesignTokens.textMuted)
                        .frame(width: 3, height: CGFloat.random(in: 8...20))
                }
            }
            .frame(height: 24)

            // Duration
            Text(isCurrentlyPlaying ? formatCurrentTime() : formattedDuration)
                .font(Font.custom("Helvetica Neue", size: 12).monospacedDigit())
                .foregroundColor(isFromMe ? Color.white.opacity(0.8) : DesignTokens.textMuted)
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 16))
        .background(isFromMe ? Color(red: 0.91, green: 0.18, blue: 0.30) : DesignTokens.chatBubbleOther)
        .cornerRadius(20)
    }

    private var isCurrentlyPlaying: Bool {
        audioPlayer.playingMessageId == message.id && audioPlayer.isPlaying
    }

    private func formatCurrentTime() -> String {
        let time = audioPlayer.currentTime
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func togglePlayback() {
        if isCurrentlyPlaying {
            audioPlayer.pause()
        } else if audioPlayer.playingMessageId == message.id {
            audioPlayer.resume()
        } else {
            // Start new playback
            if let url = message.audioUrl {
                audioPlayer.play(url: url, messageId: message.id)
            } else if let data = message.audioData {
                audioPlayer.play(data: data, messageId: message.id)
            }
        }
    }
}

// MARK: - 消息气泡视图
// MARK: - Typing Dots Animation
struct TypingDotsView: View {
    @State private var animationPhase = 0
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(DesignTokens.textMuted)
                    .frame(width: 6, height: 6)
                    .scaleEffect(animationPhase == index ? 1.2 : 0.8)
                    .animation(
                        .easeInOut(duration: 0.4)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.15),
                        value: animationPhase
                    )
            }
        }
        .onAppear {
            animationPhase = 2
        }
    }
}

struct MessageBubbleView: View {
    let message: ChatMessage
    var audioPlayer: AudioPlayerService? = nil

    var body: some View {
        if message.isFromMe {
            myMessageView
        } else {
            otherMessageView
        }
    }

    private var myMessageView: some View {
        HStack(spacing: 6) {
            Spacer()

            messageContent

            DefaultAvatarView(size: 50)
        }
        .padding(.horizontal, 16)
    }

    private var otherMessageView: some View {
        HStack(spacing: 6) {
            DefaultAvatarView(size: 50)

            otherMessageContent

            Spacer()
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var messageContent: some View {
        if let image = message.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 200, maxHeight: 200)
                .cornerRadius(12)
        } else if let location = message.location {
            LocationMessageView(location: location)
        } else if message.audioData != nil || message.audioUrl != nil, let player = audioPlayer {
            VoiceMessageView(message: message, isFromMe: true, audioPlayer: player)
        } else {
            Text(message.text)
                .font(Font.custom("Helvetica Neue", size: 18))
                .foregroundColor(DesignTokens.textPrimary)
                .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                .background(DesignTokens.chatBubbleOther)
                .cornerRadius(23)
        }
    }

    @ViewBuilder
    private var otherMessageContent: some View {
        if let image = message.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 200, maxHeight: 200)
                .cornerRadius(12)
        } else if let location = message.location {
            LocationMessageView(location: location)
        } else if message.audioData != nil || message.audioUrl != nil, let player = audioPlayer {
            VoiceMessageView(message: message, isFromMe: false, audioPlayer: player)
        } else {
            Text(message.text)
                .font(.system(size: 18))
                .foregroundColor(DesignTokens.textPrimary)
                .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                .background(DesignTokens.chatBubbleOther)
                .cornerRadius(23)
        }
    }
}

// MARK: - 附件选项按钮
struct AttachmentOptionButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Rectangle()
                .foregroundColor(.clear)
                .frame(width: 60, height: 60)
                .background(DesignTokens.surface)
                .cornerRadius(10)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundColor(DesignTokens.textPrimary)
                )
            Text(title)
                .font(.system(size: 12))
                .lineSpacing(20)
                .foregroundColor(DesignTokens.textPrimary)
        }
        .frame(width: 60)
        .onTapGesture {
            action()
        }
    }
}

struct ChatView: View {
    // MARK: - Static Properties
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd  HH:mm"
        return formatter
    }()

    // MARK: - Dependencies & Required Properties
    /// 聊天服务 - 负责发送/接收消息、WebSocket连接
    /// ⚠️ 这是连接后端API的关键，不要替换成其他Service
    @State private var chatService = ChatService()

    /// 媒体服务 - 负责图片/视频上传
    private let mediaService = MediaService()

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

    // 当前用户ID（从Keychain获取）
    private var currentUserId: String {
        KeychainService.shared.get(.userId) ?? "unknown"
    }


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
            UserProfileView(showUserProfile: $showUserProfile)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView(image: $cameraImage)
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
            // 断开WebSocket连接
            chatService.disconnectWebSocket()
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
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                } else {
                    DefaultAvatarView(size: 50)
                }

                Text(userName)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(DesignTokens.textPrimary)
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
                        .font(.system(size: 12))
                        .foregroundColor(DesignTokens.textMuted)
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

                // Voice Recording UI or Text Input
                if isRecordingVoice {
                    // Recording indicator
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                            .opacity(audioRecorder.isRecording ? 1.0 : 0.3)
                            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: audioRecorder.isRecording)

                        Text(formatDuration(audioRecorder.recordingDuration))
                            .font(Font.custom("Helvetica Neue", size: 16).monospacedDigit())
                            .foregroundColor(DesignTokens.textPrimary)

                        // Audio level visualization
                        HStack(spacing: 2) {
                            ForEach(0..<8, id: \.self) { index in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.red.opacity(0.7))
                                    .frame(width: 3, height: max(4, CGFloat(audioRecorder.audioLevel) * 20 * CGFloat.random(in: 0.5...1.5)))
                                    .animation(.easeInOut(duration: 0.1), value: audioRecorder.audioLevel)
                            }
                        }
                        .frame(height: 20)

                        Spacer()

                        // Cancel recording button
                        Button(action: {
                            cancelVoiceRecording()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(DesignTokens.textMuted)
                        }
                    }
                    .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(26)
                } else {
                    HStack(spacing: 8) {
                        // Microphone button for voice recording
                        Button(action: {
                            startVoiceRecording()
                        }) {
                            Image(systemName: "waveform")
                                .font(.system(size: 14))
                                .foregroundColor(DesignTokens.textMuted)
                        }

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
                                    chatService.sendTypingStart(conversationId: conversationId)
                                }
                                // Send typing stop when text is cleared
                                if !oldValue.isEmpty && newValue.isEmpty {
                                    chatService.sendTypingStop(conversationId: conversationId)
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
                }

                // Send button (text message or voice message)
                Button(action: {
                    if isRecordingVoice {
                        stopAndSendVoiceMessage()
                    } else {
                        sendMessage()
                    }
                }) {
                    Circle()
                        .fill(isRecordingVoice ? Color.red : (messageText.isEmpty ? Color.gray : Color(red: 0.91, green: 0.18, blue: 0.30)))
                        .frame(width: 33, height: 33)
                        .overlay(
                            Image(systemName: isRecordingVoice ? "stop.fill" : "paperplane.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        )
                }
                .disabled(!isRecordingVoice && messageText.isEmpty)
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
                }

                AttachmentOptionButton(icon: "phone.fill", title: "Voice Call") {
                    showAttachmentOptions = false
                }

                AttachmentOptionButton(icon: "location.fill", title: "Location") {
                    showAttachmentOptions = false
                    locationManager.requestLocation()
                    showLocationAlert = true
                }
            }
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity)
        .background(DesignTokens.attachmentBackground)
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

    /// Load chat data (message history + WebSocket connection)
    private func loadChatData() async {
        isLoadingHistory = true
        error = nil

        do {
            // 1. Get message history
            let response = try await chatService.getMessages(conversationId: conversationId, limit: 50)

            // 2. Convert to UI messages
            messages = response.messages.map { ChatMessage(from: $0, currentUserId: currentUserId) }
            
            // 3. Store pagination info
            hasMoreMessages = response.hasMore
            nextCursor = response.nextCursor

            // 4. Setup WebSocket callbacks
            setupWebSocketCallbacks()
            
            // 5. Connect WebSocket
            chatService.connectWebSocket()
            
            // 6. Mark messages as read
            if let lastMessage = messages.last {
                try? await chatService.markAsRead(conversationId: conversationId, messageId: lastMessage.id)
            }

            #if DEBUG
            print("[ChatView] Loaded \(messages.count) messages for conversation \(conversationId)")
            #endif

        } catch {
            self.error = "Failed to load messages: \(error.localizedDescription)"
            #if DEBUG
            print("[ChatView] Load error: \(error)")
            #endif
        }

        isLoadingHistory = false
    }
    
    /// Setup WebSocket event callbacks
    private func setupWebSocketCallbacks() {
        // New message received
        chatService.onMessageReceived = { newMessage in
            Task { @MainActor in
                // Avoid duplicates
                guard !self.messages.contains(where: { $0.id == newMessage.id }) else { return }
                self.messages.append(ChatMessage(from: newMessage, currentUserId: self.currentUserId))
                
                // Clear typing indicator when message is received
                self.isOtherUserTyping = false
                
                // Mark as read
                try? await self.chatService.markAsRead(
                    conversationId: self.conversationId,
                    messageId: newMessage.id
                )
            }
        }
        
        // Typing indicator received
        chatService.onTypingIndicator = { typingData in
            Task { @MainActor in
                // Only show if it's for this conversation and not from me
                guard typingData.conversationId == self.conversationId,
                      typingData.userId != self.currentUserId else { return }
                
                self.isOtherUserTyping = typingData.isTyping
                self.typingUserName = typingData.username
                
                // Auto-hide typing indicator after 3 seconds (server TTL)
                if typingData.isTyping {
                    self.typingTimer?.invalidate()
                    self.typingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                        Task { @MainActor in
                            self.isOtherUserTyping = false
                        }
                    }
                }
            }
        }
        
        // Read receipt received
        chatService.onReadReceipt = { readData in
            Task { @MainActor in
                guard readData.conversationId == self.conversationId else { return }
                
                // Update message status to "read" for messages up to lastReadMessageId
                // This enables showing double checkmarks in the UI
                #if DEBUG
                print("[ChatView] Read receipt: \(readData.userId) read up to \(readData.lastReadMessageId)")
                #endif
            }
        }
    }
    
    /// Load more messages (pagination)
    private func loadMoreMessages() async {
        guard hasMoreMessages, let cursor = nextCursor, !isLoadingHistory else { return }
        
        isLoadingHistory = true
        
        do {
            let response = try await chatService.getMessages(
                conversationId: conversationId,
                limit: 50,
                cursor: cursor
            )
            
            // Prepend older messages
            let olderMessages = response.messages.map { ChatMessage(from: $0, currentUserId: currentUserId) }
            messages.insert(contentsOf: olderMessages, at: 0)
            
            hasMoreMessages = response.hasMore
            nextCursor = response.nextCursor
            
        } catch {
            #if DEBUG
            print("[ChatView] Load more error: \(error)")
            #endif
        }
        
        isLoadingHistory = false
    }

    // MARK: - Send Text Message
    private func sendMessage() {
        let trimmedText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, !isSending else { return }

        // Stop typing indicator
        chatService.sendTypingStop(conversationId: conversationId)
        
        // Add to UI immediately (optimistic update)
        let localMessage = ChatMessage(localText: trimmedText, isFromMe: true)
        messages.append(localMessage)

        messageText = ""
        showAttachmentOptions = false

        // Send to server asynchronously
        Task {
            isSending = true
            do {
                let sentMessage = try await chatService.sendMessage(
                    conversationId: conversationId,
                    content: trimmedText,
                    type: .text
                )

                // Replace local message with server response
                if let index = messages.firstIndex(where: { $0.id == localMessage.id }) {
                    messages[index] = ChatMessage(from: sentMessage, currentUserId: currentUserId)
                }

                #if DEBUG
                print("[ChatView] Message sent successfully: \(sentMessage.id)")
                #endif

            } catch {
                // Send failed - mark message as failed (TODO: add retry UI)
                #if DEBUG
                print("[ChatView] Failed to send message: \(error)")
                #endif
                // Could remove failed message or add retry button here
            }
            isSending = false
        }
    }

    // MARK: - 发送图片消息
    /// 完整图片上传流程：压缩 → 上传到 MediaService → 发送消息
    private func sendImageMessage(image: UIImage) {
        // 压缩图片
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            #if DEBUG
            print("[ChatView] Failed to compress image")
            #endif
            error = "Failed to compress image"
            return
        }

        // 立即添加到本地 UI（乐观更新）
        let localMessage = ChatMessage(localText: "", isFromMe: true, image: image)
        messages.append(localMessage)
        showAttachmentOptions = false

        // 异步上传并发送
        Task {
            isUploadingImage = true

            do {
                // 1. 上传图片到 MediaService
                let filename = "chat_image_\(UUID().uuidString).jpg"
                let mediaUrl = try await mediaService.uploadImage(imageData: imageData, filename: filename)

                #if DEBUG
                print("[ChatView] Image uploaded: \(mediaUrl)")
                #endif

                // 2. 发送带 mediaUrl 的消息到聊天服务
                let sentMessage = try await chatService.sendMessage(
                    conversationId: conversationId,
                    content: mediaUrl,  // 图片 URL 作为内容
                    type: .image,
                    mediaUrl: mediaUrl
                )

                // 3. 替换本地消息为服务器返回的消息
                if let index = messages.firstIndex(where: { $0.id == localMessage.id }) {
                    // 保留本地图片用于显示，同时更新消息 ID
                    var updatedMessage = ChatMessage(from: sentMessage, currentUserId: currentUserId)
                    updatedMessage.image = image  // 保留本地图片
                    messages[index] = updatedMessage
                }

                #if DEBUG
                print("[ChatView] Image message sent: \(sentMessage.id)")
                #endif

            } catch {
                #if DEBUG
                print("[ChatView] Failed to send image: \(error)")
                #endif

                // 上传失败 - 标记消息为失败状态
                self.error = "Failed to send image"

                // 可选：移除失败的消息或添加重试按钮
                // messages.removeAll { $0.id == localMessage.id }
            }

            isUploadingImage = false
        }
    }

    // MARK: - 发送位置消息
    /// 发送位置消息到会话
    private func sendLocationMessage(location: CLLocationCoordinate2D) {
        // 立即添加到本地 UI（乐观更新）
        let localMessage = ChatMessage(localText: "", isFromMe: true, location: location)
        messages.append(localMessage)
        showAttachmentOptions = false

        Task {
            isSending = true

            do {
                // 使用 ChatService 的位置分享 API
                try await chatService.shareLocation(
                    conversationId: conversationId,
                    latitude: location.latitude,
                    longitude: location.longitude,
                    accuracy: nil
                )

                #if DEBUG
                print("[ChatView] Location shared: \(location.latitude), \(location.longitude)")
                #endif

            } catch {
                #if DEBUG
                print("[ChatView] Failed to share location: \(error)")
                #endif
                self.error = "Failed to share location"
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

    /// 发送语音消息
    private func sendVoiceMessage(audioData: Data, duration: TimeInterval, url: URL) {
        // 立即添加到本地 UI（乐观更新）
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
                // 1. 上传音频到 MediaService
                let filename = "voice_\(UUID().uuidString).m4a"
                let mediaUrl = try await mediaService.uploadAudio(audioData: audioData, filename: filename)

                #if DEBUG
                print("[ChatView] Voice uploaded: \(mediaUrl)")
                #endif

                // 2. 发送带 mediaUrl 的消息到聊天服务
                let sentMessage = try await chatService.sendMessage(
                    conversationId: conversationId,
                    content: String(format: "%.1f", duration),  // 时长作为内容（用于预览）
                    type: .audio,
                    mediaUrl: mediaUrl
                )

                // 3. 替换本地消息为服务器返回的消息
                if let index = messages.firstIndex(where: { $0.id == localMessage.id }) {
                    var updatedMessage = ChatMessage(from: sentMessage, currentUserId: currentUserId)
                    updatedMessage.audioData = audioData
                    updatedMessage.audioDuration = duration
                    updatedMessage.audioUrl = url
                    messages[index] = updatedMessage
                }

                #if DEBUG
                print("[ChatView] Voice message sent: \(sentMessage.id)")
                #endif

            } catch {
                #if DEBUG
                print("[ChatView] Failed to send voice: \(error)")
                #endif
                self.error = "Failed to send voice message"
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
}

#Preview {
    ChatView(
        showChat: .constant(true),
        conversationId: "preview_conversation_123",
        userName: "Alice AI"
    )
}
