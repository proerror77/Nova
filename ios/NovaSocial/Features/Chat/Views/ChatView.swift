import SwiftUI
import PhotosUI
import CoreLocation
import MapKit
import Combine
import AVFoundation

// MARK: - 消息UI模型
/// UI层的消息模型，包含后端Message + UI特定字段（图片、位置）
struct ChatMessage: Identifiable, Equatable {
    let id: String  // 改为String以匹配后端Message.id
    let backendMessage: Message?  // 后端消息对象（可选，本地消息可能还没发送）
    let text: String
    let isFromMe: Bool
    let timestamp: Date
    var image: UIImage?
    var location: CLLocationCoordinate2D?

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
    }

    /// 创建本地消息（发送前）
    init(localText: String, isFromMe: Bool = true, image: UIImage? = nil, location: CLLocationCoordinate2D? = nil) {
        self.id = UUID().uuidString
        self.backendMessage = nil
        self.text = localText
        self.isFromMe = isFromMe
        self.timestamp = Date()
        self.image = image
        self.location = location
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
            Map(coordinateRegion: .constant(region))
                .frame(width: 180, height: 120)
                .cornerRadius(12)
                .disabled(true)

            Text("My Location")
                .font(Font.custom("Helvetica Neue", size: 12))
                .foregroundColor(Color(red: 0.34, green: 0.34, blue: 0.34))
        }
        .padding(8)
        .background(Color(red: 0.85, green: 0.85, blue: 0.85))
        .cornerRadius(12)
    }
}

// MARK: - 消息气泡视图
struct MessageBubbleView: View {
    let message: ChatMessage

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

            Circle()
                .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                .frame(width: 50, height: 50)
        }
        .padding(.horizontal, 16)
    }

    private var otherMessageView: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                .frame(width: 50, height: 50)

            Text(message.text)
                .font(Font.custom("Helvetica Neue", size: 18))
                .foregroundColor(Color(red: 0.34, green: 0.34, blue: 0.34))
                .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                .background(Color(red: 0.85, green: 0.85, blue: 0.85))
                .cornerRadius(23)

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
        } else {
            Text(message.text)
                .font(Font.custom("Helvetica Neue", size: 18))
                .foregroundColor(Color(red: 0.34, green: 0.34, blue: 0.34))
                .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                .background(Color(red: 0.85, green: 0.85, blue: 0.85))
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
                .background(.white)
                .cornerRadius(10)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundColor(.black)
                )
            Text(title)
                .font(Font.custom("Helvetica Neue", size: 12))
                .lineSpacing(20)
                .foregroundColor(Color(red: 0.25, green: 0.25, blue: 0.25))
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

    // 加载状态
    @State private var isLoadingHistory = false
    @State private var isSending = false
    @State private var error: String?


    // 相册相关
    @State private var selectedPhotoItem: PhotosPickerItem?

    // 相机相关
    @State private var showCamera = false
    @State private var cameraImage: UIImage?
    @State private var showCameraPermissionAlert = false

    // 位置相关
    @StateObject private var locationManager = ChatLocationManager()
    @State private var showLocationAlert = false

    // 当前用户ID（从Keychain获取）
    private var currentUserId: String {
        KeychainService.shared.get(.userId) ?? "unknown"
    }


    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.96, blue: 0.96)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                navigationBar

                Divider()
                    .frame(height: 0.5)
                    .background(Color(red: 0.74, green: 0.74, blue: 0.74))

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
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.black)
            }

            HStack(spacing: 13) {
                // 头像 - alice 使用自定义图片，其他用户使用默认圆形
                if userName.lowercased() == "alice" {
                    Image("alice-avatar")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                        .frame(width: 50, height: 50)
                }

                Text(userName)
                    .font(Font.custom("Helvetica Neue", size: 20).weight(.medium))
                    .foregroundColor(.black)
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
        .background(Color.white)
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
                        .font(Font.custom("Helvetica Neue", size: 12))
                        .foregroundColor(Color(red: 0.59, green: 0.59, blue: 0.59))
                        .padding(.top, 16)

                    ForEach(messages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                    }

                    // 发送中指示器
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
            .onTapGesture {
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
                .background(Color(red: 0.74, green: 0.74, blue: 0.74))

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

                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))

                    TextField("Type a message...", text: $messageText)
                        .font(Font.custom("Helvetica Neue", size: 16))
                        .foregroundColor(Color(red: 0.34, green: 0.34, blue: 0.34))
                        .focused($isInputFocused)
                        .onSubmit {
                            sendMessage()
                        }
                }
                .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .background(Color(red: 0.53, green: 0.53, blue: 0.53).opacity(0.20))
                .cornerRadius(26)
                .onChange(of: isInputFocused) { _, focused in
                    if focused && showAttachmentOptions {
                        showAttachmentOptions = false
                    }
                }

                Button(action: {
                    sendMessage()
                }) {
                    Circle()
                        .fill(messageText.isEmpty ? Color.gray : Color(red: 0.91, green: 0.18, blue: 0.30))
                        .frame(width: 33, height: 33)
                        .overlay(
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        )
                }
                .disabled(messageText.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)

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
                            .background(.white)
                            .cornerRadius(10)
                            .overlay(
                                Image(systemName: "photo.on.rectangle")
                                    .font(.system(size: 24))
                                    .foregroundColor(.black)
                            )
                        Text("Album")
                            .font(Font.custom("Helvetica Neue", size: 12))
                            .lineSpacing(20)
                            .foregroundColor(Color(red: 0.25, green: 0.25, blue: 0.25))
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
        .background(Color(red: 0.91, green: 0.91, blue: 0.91))
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

    // MARK: - API调用

    /// 加载聊天数据（消息历史 + WebSocket连接）
    private func loadChatData() async {
        isLoadingHistory = true
        error = nil

        do {
            // 1. 获取消息历史
            let response = try await chatService.getMessages(conversationId: conversationId, limit: 50)

            // 2. 转换为UI消息
            messages = response.messages.map { ChatMessage(from: $0, currentUserId: currentUserId) }

            // 3. 连接WebSocket接收实时消息
            chatService.onMessageReceived = { [weak chatService] newMessage in
                Task { @MainActor in
                    // 避免重复添加（如果消息已存在）
                    guard !self.messages.contains(where: { $0.id == newMessage.id }) else { return }
                    self.messages.append(ChatMessage(from: newMessage, currentUserId: self.currentUserId))
                }
            }
            chatService.connectWebSocket()

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

    // MARK: - 发送文字消息
    private func sendMessage() {
        let trimmedText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, !isSending else { return }

        // 立即添加到UI（乐观更新）
        let localMessage = ChatMessage(localText: trimmedText, isFromMe: true)
        messages.append(localMessage)

        messageText = ""
        showAttachmentOptions = false

        // 异步发送到服务器
        Task {
            isSending = true
            do {
                let sentMessage = try await chatService.sendMessage(
                    conversationId: conversationId,
                    content: trimmedText,
                    type: .text
                )

                // 替换本地消息为服务器返回的消息
                if let index = messages.firstIndex(where: { $0.id == localMessage.id }) {
                    messages[index] = ChatMessage(from: sentMessage, currentUserId: currentUserId)
                }

                #if DEBUG
                print("[ChatView] Message sent successfully: \(sentMessage.id)")
                #endif

            } catch {
                // 发送失败 - 标记消息为失败状态（TODO: 添加重试UI）
                #if DEBUG
                print("[ChatView] Failed to send message: \(error)")
                #endif
                // 可以在这里移除失败的消息或添加重试按钮
            }
            isSending = false
        }
    }

    // MARK: - 发送图片消息
    private func sendImageMessage(image: UIImage) {
        // TODO: 先上传图片到Media Service，获取URL，然后发送消息
        // 暂时只添加到本地UI
        let localMessage = ChatMessage(localText: "", isFromMe: true, image: image)
        messages.append(localMessage)

        #if DEBUG
        print("[ChatView] Image upload not yet implemented")
        #endif
    }

    // MARK: - 发送位置消息
    private func sendLocationMessage(location: CLLocationCoordinate2D) {
        // TODO: 发送location类型消息
        // 暂时只添加到本地UI
        let localMessage = ChatMessage(localText: "", isFromMe: true, location: location)
        messages.append(localMessage)

        #if DEBUG
        print("[ChatView] Location sharing not yet implemented")
        #endif
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
}

#Preview {
    ChatView(
        showChat: .constant(true),
        conversationId: "preview_conversation_123",
        userName: "Alice AI"
    )
}
