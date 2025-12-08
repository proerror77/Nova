import SwiftUI
import PhotosUI

struct NewPostView: View {
    @Binding var showNewPost: Bool
    var initialImage: UIImage? = nil  // 从PhotoOptionsModal传入的图片
    var onPostSuccess: ((Post) -> Void)? = nil  // 成功发布后的回调，传递创建的Post对象
    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var postText: String = ""
    @State private var inviteAlice: Bool = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var isPosting = false
    @State private var postError: String?
    @State private var showNameSelector = false  // 控制名称选择弹窗
    @State private var selectedNameType: NameDisplayType = .realName  // 选择的名称类型
    @State private var showLocationPicker = false  // 控制位置选择弹窗
    @State private var selectedLocation = ""  // 选择的位置
    @FocusState private var isTextFieldFocused: Bool

    // Services
    private let mediaService = MediaService()
    private let contentService = ContentService()

    var body: some View {
        ZStack {
            // 背景色
            Color(red: 0.97, green: 0.97, blue: 0.97)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topNavigationBar

                ScrollView {
                    contentView
                }
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture {
                    // 点击 ScrollView 区域收起键盘
                    hideKeyboard()
                }

                // MARK: - Error Message
                if let error = postError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                postButton
            }
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera, selectedImage: .constant(nil))
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotos, maxSelectionCount: 5 - selectedImages.count, matching: .images)
        .onChange(of: selectedPhotos) { oldValue, newValue in
            Task {
                // 将新选择的照片添加到已有照片中（不清空）
                for item in newValue {
                    // 检查是否已达到最大数量
                    guard selectedImages.count < 5 else { break }

                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        selectedImages.append(image)
                    }
                }
                // 清空 selectedPhotos 以便下次继续选择
                selectedPhotos = []
            }
        }
        .onAppear {
            // 如果有初始图片，添加到selectedImages
            if let image = initialImage, selectedImages.isEmpty {
                selectedImages = [image]
            }
        }
        .overlay {
            // MARK: - 名称选择弹窗
            if showNameSelector {
                NameSelectorModal(
                    isPresented: $showNameSelector,
                    selectedNameType: $selectedNameType
                )
            }
        }
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerView(
                selectedLocation: $selectedLocation,
                isPresented: $showLocationPicker
            )
        }
    }

    // MARK: - Top Navigation Bar
    private var topNavigationBar: some View {
        HStack {
            // Cancel 按钮
            Button(action: {
                showNewPost = false
            }) {
                Text("Cancel")
                    .font(Font.custom("Helvetica Neue", size: 14))
                    .lineSpacing(20)
                    .foregroundColor(.black)
            }

            Spacer()

            // 标题
            Text("Newpost")
                .font(Font.custom("Helvetica Neue", size: 18).weight(.medium))
                .lineSpacing(20)
                .foregroundColor(.black)

            Spacer()

            // Draft 按钮
            Button(action: {
                // Draft action
            }) {
                Text("Draft")
                    .font(Font.custom("Helvetica Neue", size: 14))
                    .lineSpacing(20)
                    .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
            }
        }
        .frame(height: DesignTokens.topBarHeight)
        .padding(.horizontal, 16)
        .background(Color.white)
    }

    // MARK: - Content View
    private var contentView: some View {
        VStack(spacing: 0) {
            postAsSection
            imagePreviewSection
            textInputSection
            channelsAndEnhanceSection

            Rectangle()
                .foregroundColor(.clear)
                .frame(height: 0)
                .overlay(
                    Rectangle()
                        .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.20)
                )
                .padding(.top, 20)

            checkInSection

            Rectangle()
                .foregroundColor(.clear)
                .frame(height: 0)
                .overlay(
                    Rectangle()
                        .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.20)
                )

            inviteAliceSection

            if inviteAlice {
                inviteAlicePrompt
            }
        }
    }

    // MARK: - Post As Section
    private var postAsSection: some View {
        HStack(spacing: 13) {
            // 头像 - 优先显示 AvatarManager 的头像
            ZStack {
                if let pendingAvatar = AvatarManager.shared.pendingAvatar {
                    Image(uiImage: pendingAvatar)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 30, height: 30)
                        .clipShape(Circle())
                } else if let avatarUrl = authManager.currentUser?.avatarUrl,
                          let url = URL(string: avatarUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        DefaultAvatarView(size: 30)
                    }
                    .frame(width: 30, height: 30)
                    .clipShape(Circle())
                } else {
                    DefaultAvatarView(size: 30)
                }
            }
            .overlay(
                Circle()
                    .stroke(Color(red: 0.81, green: 0.13, blue: 0.25), lineWidth: 0.50)
            )

            // 显示名称 - 根据选择的类型显示真实名称或别名
            Text(displayedName)
                .font(Font.custom("Helvetica Neue", size: 14).weight(.medium))
                .lineSpacing(20)
                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

            ZStack {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))
            }
            .frame(width: 16, height: 16)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .contentShape(Rectangle())
        .onTapGesture {
            showNameSelector = true
        }
    }

    // MARK: - 显示的名称
    private var displayedName: String {
        if selectedNameType == .realName {
            // 真实名称：优先使用 displayName，否则使用 username
            return authManager.currentUser?.displayName ?? authManager.currentUser?.username ?? "User"
        } else {
            // 别名
            return "Dreamer"
        }
    }

    // MARK: - Image Preview Section
    private var imagePreviewSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                // 显示所有选中的图片
                ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 255, height: 300)
                            .cornerRadius(10)
                            .clipped()

                        // 删除按钮
                        Button(action: {
                            removeImage(at: index)
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.5))
                                        .frame(width: 20, height: 20)
                                )
                        }
                        .padding(4)
                    }
                }

                // 添加更多图片按钮（最多5张）- 始终显示在最右边
                if selectedImages.count < 5 {
                    ZStack {
                        Rectangle()
                            .foregroundColor(.clear)
                            .frame(width: 255, height: 300)
                            .background(Color(red: 0.91, green: 0.91, blue: 0.91))
                            .cornerRadius(10)

                        VStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 30, weight: .light))
                                .foregroundColor(.white)

                            if selectedImages.count > 0 {
                                Text("\(selectedImages.count)/5")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .onTapGesture {
                        showPhotoPicker = true
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 16)
    }

    // MARK: - 删除图片
    private func removeImage(at index: Int) {
        guard index < selectedImages.count else { return }
        selectedImages.remove(at: index)

        // 同步更新 selectedPhotos
        if index < selectedPhotos.count {
            selectedPhotos.remove(at: index)
        }
    }

    // MARK: - Text Input Section
    private var textInputSection: some View {
        ZStack(alignment: .topLeading) {
            if postText.isEmpty {
                Text("What do you want to talk about?")
                    .font(Font.custom("Helvetica Neue", size: 14))
                    .lineSpacing(20)
                    .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))
                    .padding(.leading, 5)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $postText)
                .font(Font.custom("Helvetica Neue", size: 14))
                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))
                .frame(height: 150)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .focused($isTextFieldFocused)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: - Channels and Enhance Section
    private var channelsAndEnhanceSection: some View {
        HStack(spacing: 10) {
            HStack(spacing: 3) {
                Text("#")
                    .font(Font.custom("Helvetica Neue", size: 16))
                    .lineSpacing(20)
                    .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))

                Text("Channels")
                    .font(Font.custom("Helvetica Neue", size: 10))
                    .lineSpacing(20)
                    .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
            }
            .padding(.horizontal, 16)
            .frame(height: 26)
            .background(Color(red: 0.91, green: 0.91, blue: 0.91))
            .cornerRadius(24)

            HStack(spacing: 3) {
                Image("alice-center-icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 11, height: 11)
                    .colorMultiply(Color(red: 0.87, green: 0.11, blue: 0.26))

                Text("Enhance with alice")
                    .font(Font.custom("Helvetica Neue", size: 10))
                    .lineSpacing(20)
                    .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
            }
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Color(red: 0.97, green: 0.92, blue: 0.92))
            .cornerRadius(24)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
    }

    // MARK: - Check In Section
    private var checkInSection: some View {
        HStack(spacing: 10) {
            Image("Location-icon")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)

            Text(selectedLocation.isEmpty ? "Check in" : selectedLocation)
                .font(Font.custom("Helvetica Neue", size: 16))
                .lineSpacing(40.94)
                .foregroundColor(.black)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
        .contentShape(Rectangle())
        .onTapGesture {
            showLocationPicker = true
        }
    }

    // MARK: - Invite Alice Section
    private var inviteAliceSection: some View {
        HStack(spacing: 10) {
            Image("alice-center-icon")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .colorMultiply(.black)

            Text("Invite alice")
                .font(Font.custom("Helvetica Neue", size: 16))
                .lineSpacing(40.94)
                .foregroundColor(.black)

            Spacer()

            Toggle("", isOn: $inviteAlice)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.82, green: 0.13, blue: 0.25)))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
    }

    // MARK: - Invite Alice Prompt
    private var inviteAlicePrompt: some View {
        HStack(spacing: 5) {
            ZStack {
                Ellipse()
                    .foregroundColor(.clear)
                    .frame(width: 9.60, height: 9.60)
                    .background(.white)
                    .overlay(
                        Ellipse()
                            .inset(by: 0.24)
                            .stroke(Color(red: 0.82, green: 0.13, blue: 0.25), lineWidth: 0.24)
                    )

                Ellipse()
                    .foregroundColor(.clear)
                    .frame(width: 5.28, height: 5.28)
                    .background(Color(red: 0.82, green: 0.13, blue: 0.25))
            }
            .frame(width: 9.60, height: 9.60)

            Text("Invite Alice to join the discussion")
                .font(Font.custom("Helvetica Neue", size: 12).weight(.medium))
                .lineSpacing(20)
                .foregroundColor(Color(red: 0.82, green: 0.13, blue: 0.25))

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
    }

    // MARK: - Post Button
    private var postButton: some View {
        Button(action: {
            Task {
                await submitPost()
            }
        }) {
            HStack {
                if isPosting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                }
                Text(isPosting ? "Posting..." : "Post")
                    .font(Font.custom("Helvetica Neue", size: 16).weight(.medium))
                    .lineSpacing(20)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(canPost ? Color(red: 0.87, green: 0.11, blue: 0.26) : Color.gray)
            .cornerRadius(31.50)
        }
        .disabled(!canPost || isPosting)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(red: 0.97, green: 0.97, blue: 0.97))
    }

    // MARK: - 是否可以发布
    private var canPost: Bool {
        !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedImages.isEmpty
    }

    // MARK: - 收起键盘
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: - 调整图片大小以优化上传
    private func resizeImageForUpload(_ image: UIImage, maxDimension: CGFloat = 1024) -> UIImage {
        let size = image.size

        // 如果图片已经足够小，直接返回
        if size.width <= maxDimension && size.height <= maxDimension {
            return image
        }

        // 计算缩放比例
        let ratio = min(maxDimension / size.width, maxDimension / size.height)
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)

        // 使用 UIGraphicsImageRenderer 进行高质量缩放
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - 提交帖子
    private func submitPost() async {
        guard canPost else { return }

        // Try to get userId from currentUser first, fallback to storedUserId from Keychain
        guard let userId = authManager.currentUser?.id ?? authManager.storedUserId else {
            postError = "Please login first"
            return
        }

        isPosting = true
        postError = nil

        do {
            // Step 1: 上传图片 (如果有，带重试逻辑)
            var mediaUrls: [String] = []
            for image in selectedImages {
                // 先调整图片大小再压缩，避免上传过大的文件
                let resizedImage = resizeImageForUpload(image)
                if let imageData = resizedImage.jpegData(compressionQuality: 0.3) {
                    #if DEBUG
                    print("[NewPost] Uploading image: \(imageData.count / 1024) KB")
                    #endif

                    // 重试逻辑处理 503 错误
                    var mediaUrl: String?
                    var lastError: Error?

                    for attempt in 1...3 {
                        do {
                            mediaUrl = try await mediaService.uploadImage(
                                imageData: imageData,
                                filename: "post_\(UUID().uuidString).jpg"
                            )
                            break  // 成功则跳出循环
                        } catch let error as APIError {
                            lastError = error
                            if case .serverError(let statusCode, _) = error, statusCode == 503 {
                                #if DEBUG
                                print("[NewPost] Image upload attempt \(attempt) failed with 503, retrying in \(attempt * 2)s...")
                                #endif
                                if attempt < 3 {
                                    try await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)  // 2s, 4s delay
                                    continue
                                }
                            }
                            throw error
                        }
                    }

                    guard let uploadedUrl = mediaUrl else {
                        throw lastError ?? APIError.serverError(statusCode: 503, message: "Image upload failed")
                    }

                    mediaUrls.append(uploadedUrl)
                    #if DEBUG
                    print("[NewPost] Uploaded image: \(uploadedUrl)")
                    #endif
                }
            }

            // Step 2: 创建帖子 (带重试逻辑处理 503 错误)
            let content = postText.trimmingCharacters(in: .whitespacesAndNewlines)
            var post: Post?
            var lastError: Error?

            for attempt in 1...3 {
                do {
                    post = try await contentService.createPost(
                        creatorId: userId,
                        content: content.isEmpty ? " " : content,  // 至少需要空格
                        mediaUrls: mediaUrls.isEmpty ? nil : mediaUrls
                    )
                    break  // 成功则跳出循环
                } catch let error as APIError {
                    lastError = error
                    if case .serverError(let statusCode, _) = error, statusCode == 503 {
                        #if DEBUG
                        print("[NewPost] Attempt \(attempt) failed with 503, retrying...")
                        #endif
                        if attempt < 3 {
                            try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)  // 1s, 2s delay
                            continue
                        }
                    }
                    throw error
                }
            }

            guard let createdPost = post else {
                throw lastError ?? APIError.serverError(statusCode: 503, message: "Service unavailable")
            }

            // Step 3: 成功后关闭页面并触发刷新回调
            await MainActor.run {
                isPosting = false
                showNewPost = false
                // 调用成功回调，将创建的Post传递给 HomeView
                onPostSuccess?(createdPost)
            }

        } catch {
            await MainActor.run {
                isPosting = false
                postError = "Failed to create post: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Image Picker for Camera
struct ImagePicker: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType
    @Binding var selectedImage: UIImage?
    @Environment(\.presentationMode) private var presentationMode

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.presentationMode.wrappedValue.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

#Preview {
    @Previewable @State var showNewPost = true
    NewPostView(showNewPost: $showNewPost)
        .environmentObject(AuthenticationManager.shared)
}
