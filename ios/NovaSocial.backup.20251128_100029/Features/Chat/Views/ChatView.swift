import SwiftUI
import PhotosUI
import CoreLocation
import MapKit
import Combine

// MARK: - 消息模型
struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isFromMe: Bool
    let timestamp: Date
    var image: UIImage?
    var location: CLLocationCoordinate2D?

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - 聊天位置管理器
class ChatLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var location: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

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
    @Binding var showChat: Bool
    var userName: String = "User"
    var initialMessages: [ChatMessage] = []
    @State private var messageText = ""
    @State private var showUserProfile = false
    @State private var messages: [ChatMessage] = []
    @State private var showAttachmentOptions = false
    @FocusState private var isInputFocused: Bool

    // 相册相关
    @State private var selectedPhotoItem: PhotosPickerItem?

    // 相机相关
    @State private var showCamera = false
    @State private var cameraImage: UIImage?

    // 位置相关
    @StateObject private var locationManager = ChatLocationManager()
    @State private var showLocationAlert = false

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
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
        .onAppear {
            // 加载初始消息
            if messages.isEmpty && !initialMessages.isEmpty {
                messages = initialMessages
            }
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
                    Text(currentDateString())
                        .font(Font.custom("Helvetica Neue", size: 12))
                        .foregroundColor(Color(red: 0.59, green: 0.59, blue: 0.59))
                        .padding(.top, 16)

                    ForEach(messages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
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
                    showCamera = true
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
            if let data = try? await newItem?.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    sendImageMessage(image: image)
                }
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

    // MARK: - 发送文字消息
    private func sendMessage() {
        let trimmedText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let myMessage = ChatMessage(text: trimmedText, isFromMe: true, timestamp: Date())
        messages.append(myMessage)

        messageText = ""
        showAttachmentOptions = false
    }

    // MARK: - 发送图片消息
    private func sendImageMessage(image: UIImage) {
        var message = ChatMessage(text: "", isFromMe: true, timestamp: Date())
        message.image = image
        messages.append(message)
    }

    // MARK: - 发送位置消息
    private func sendLocationMessage(location: CLLocationCoordinate2D) {
        var message = ChatMessage(text: "", isFromMe: true, timestamp: Date())
        message.location = location
        messages.append(message)
    }

    // MARK: - 获取当前日期字符串
    private func currentDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd  HH:mm"
        return formatter.string(from: Date())
    }
}

#Preview {
    ChatView(showChat: .constant(true), userName: "alice")
}
