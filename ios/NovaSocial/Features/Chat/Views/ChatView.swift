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

    // MARK: - ViewModel
    @StateObject private var viewModel: ChatViewModel

    // MARK: - Required Properties
    @Binding var showChat: Bool

    // MARK: - UI State (kept in View)
    @State private var showUserProfile = false
    @State private var showAttachmentOptions = false
    @FocusState private var isInputFocused: Bool

    // Photo/Camera related
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var cameraImage: UIImage?
    @State private var showCameraPermissionAlert = false

    // Location related
    @StateObject private var locationManager = ChatLocationManager()
    @State private var showLocationAlert = false

    // Voice recording related
    @State private var audioRecorder = AudioRecorderService()
    @State private var audioPlayer = AudioPlayerService()
    @State private var isRecordingVoice = false
    @State private var showMicrophonePermissionAlert = false

    // MARK: - Init
    init(showChat: Binding<Bool>, conversationId: String, userName: String, otherUserId: String = "") {
        self._showChat = showChat
        self._viewModel = StateObject(wrappedValue: ChatViewModel(
            conversationId: conversationId,
            userName: userName,
            otherUserId: otherUserId
        ))
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
            UserProfileView(showUserProfile: $showUserProfile, userId: viewModel.otherUserId)
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
            await viewModel.loadChatData()
        }
        .onDisappear {
            viewModel.cleanup()
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
                if viewModel.userName.lowercased() == "alice" {
                    Image("alice-avatar")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                } else {
                    DefaultAvatarView(size: 50)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.userName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(DesignTokens.textPrimary)

                    // Matrix E2EE 狀態指示器
                    if viewModel.isMatrixE2EEEnabled {
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
                    // 加载状态指示器
                    if viewModel.isLoadingHistory {
                        ProgressView("Loading messages...")
                            .padding()
                    }

                    // 错误提示
                    if let error = viewModel.error {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 30))
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Retry") {
                                Task { await viewModel.loadChatData() }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                    }

                    Text(currentDateString())
                        .font(.system(size: 12))
                        .foregroundColor(DesignTokens.textMuted)
                        .padding(.top, 16)

                    ForEach(viewModel.messages) { message in
                        MessageBubbleView(message: message, audioPlayer: audioPlayer)
                            .id(message.id)
                    }

                    // Sending indicator
                    if viewModel.isSending {
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
                    if viewModel.isOtherUserTyping {
                        HStack(spacing: 6) {
                            DefaultAvatarView(size: 30)

                            HStack(spacing: 4) {
                                Text("\(viewModel.typingUserName.isEmpty ? viewModel.userName : viewModel.typingUserName) is typing")
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
                        .animation(.easeInOut(duration: 0.2), value: viewModel.isOtherUserTyping)
                    }
                }
                .padding(.bottom, 16)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let lastMessage = viewModel.messages.last {
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

                        TextField("Type a message...", text: $viewModel.messageText)
                            .font(Font.custom("Helvetica Neue", size: 16))
                            .foregroundColor(DesignTokens.textPrimary)
                            .focused($isInputFocused)
                            .onSubmit {
                                Task {
                                    await viewModel.sendMessage()
                                }
                            }
                            .onChange(of: viewModel.messageText) { oldValue, newValue in
                                // Send typing indicator when user starts typing
                                if oldValue.isEmpty && !newValue.isEmpty {
                                    viewModel.sendTypingStart()
                                }
                                // Send typing stop when text is cleared
                                if !oldValue.isEmpty && newValue.isEmpty {
                                    viewModel.sendTypingStop()
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
                        Task {
                            await viewModel.sendMessage()
                        }
                    }
                }) {
                    Circle()
                        .fill(isRecordingVoice ? Color.red : (viewModel.messageText.isEmpty ? Color.gray : Color(red: 0.91, green: 0.18, blue: 0.30)))
                        .frame(width: 33, height: 33)
                        .overlay(
                            Image(systemName: isRecordingVoice ? "stop.fill" : "paperplane.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        )
                }
                .disabled(!isRecordingVoice && viewModel.messageText.isEmpty)
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
                    await viewModel.sendImageMessage(image)
                    showAttachmentOptions = false
                }
            } catch {
                print("Failed to load photo: \(error.localizedDescription)")
                // Consider showing user-facing error in future
            }
        }
    }

    private func handleCameraImage(_ newImage: UIImage?) {
        if let image = newImage {
            Task {
                await viewModel.sendImageMessage(image)
            }
            cameraImage = nil
        }
    }

    private func handleLocationUpdate(_ newLocation: CLLocationCoordinate2D?) {
        if let location = newLocation, showLocationAlert {
            Task {
                await viewModel.sendLocationMessage(location)
            }
            showLocationAlert = false
        }
    }

    // MARK: - Helper Methods

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
                    viewModel.error = errorMsg
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
            viewModel.error = "Failed to save recording"
            return
        }

        isRecordingVoice = false

        // 检查录音时长（太短的录音不发送）
        guard result.duration >= 1.0 else {
            #if DEBUG
            print("[ChatView] Recording too short: \(result.duration)s")
            #endif
            viewModel.error = "Recording too short"
            audioRecorder.cleanupTempFiles()
            return
        }

        Task {
            await viewModel.sendVoiceMessage(audioData: result.data, duration: result.duration, url: result.url)
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
