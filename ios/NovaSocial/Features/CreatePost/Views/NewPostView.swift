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
    @FocusState private var isTextFieldFocused: Bool

    // 名称显示类型
    enum NameDisplayType {
        case realName
        case alias
    }

    // Services
    private let mediaService = MediaService()
    private let contentService = ContentService()

    var body: some View {
        ZStack {
            // 背景色 - 点击可收起键盘
            Color(red: 0.97, green: 0.97, blue: 0.97)
                .ignoresSafeArea()
                .onTapGesture {
                    hideKeyboard()
                }

            VStack(spacing: 0) {
                topNavigationBar

                ScrollView {
                    contentView
                }
                .scrollDismissesKeyboard(.interactively)
                .contentShape(Rectangle())
                .onTapGesture {
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
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotos, maxSelectionCount: 10 - selectedImages.count, matching: .images)
        .onChange(of: selectedPhotos) { oldValue, newValue in
            Task {
                // 将新选择的照片添加到已有照片中（不清空）
                for item in newValue {
                    // 检查是否已达到最大数量
                    guard selectedImages.count < 10 else { break }

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
            if let pendingAvatar = AvatarManager.shared.pendingAvatar {
                Image(uiImage: pendingAvatar)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 30, height: 30)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color(red: 0.81, green: 0.13, blue: 0.25), lineWidth: 0.50)
                    )
            } else if let avatarUrl = authManager.currentUser?.avatarUrl,
                      let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                }
                .frame(width: 30, height: 30)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color(red: 0.81, green: 0.13, blue: 0.25), lineWidth: 0.50)
                )
            } else {
                Circle()
                    .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                    .frame(width: 30, height: 30)
                    .overlay(
                        Circle()
                            .stroke(Color(red: 0.81, green: 0.13, blue: 0.25), lineWidth: 0.50)
                    )
            }

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
            HStack(alignment: .top, spacing: 20) {
                if selectedImages.isEmpty {
                    // 预览占位符（无文字）
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 100, height: 133)
                        .background(Color(red: 0, green: 0, blue: 0).opacity(0.20))
                        .cornerRadius(10)
                }

                // 显示所有选中的图片
                ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 133)
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

                // 添加更多图片按钮（最多10张）
                if selectedImages.count < 10 {
                    ZStack {
                        Rectangle()
                            .foregroundColor(.clear)
                            .frame(width: 100, height: 133)
                            .background(Color(red: 0.91, green: 0.91, blue: 0.91))
                            .cornerRadius(10)

                        VStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 30, weight: .light))
                                .foregroundColor(.white)

                            if selectedImages.count > 0 {
                                Text("\(selectedImages.count)/10")
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
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
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
        .onTapGesture {
            isTextFieldFocused = true
        }
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
                Circle()
                    .frame(width: 11, height: 11)
                    .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))

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
        HStack(spacing: 6.14) {
            Circle()
                .stroke(Color.gray, lineWidth: 1)
                .frame(width: 28.65, height: 28.65)

            Text("Check in")
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
    }

    // MARK: - Invite Alice Section
    private var inviteAliceSection: some View {
        HStack {
            Circle()
                .stroke(Color.gray, lineWidth: 1)
                .frame(width: 20.86, height: 20.86)

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

        // 检查登录状态
        guard authManager.isAuthenticated else {
            postError = "Please login first"
            return
        }

        // 获取用户ID - 优先使用 currentUser，如果为 nil 则使用 storedUserId
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

// MARK: - 名称选择弹窗组件
struct NameSelectorModal: View {
    @Binding var isPresented: Bool
    @Binding var selectedNameType: NewPostView.NameDisplayType
    @EnvironmentObject private var authManager: AuthenticationManager

    var body: some View {
        ZStack {
            // 半透明背景
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            // 弹窗内容
            VStack {
                Spacer()

                ZStack {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 11,
                        topTrailingRadius: 11
                    )
                    .fill(.white)
                    .frame(maxWidth: .infinity, maxHeight: 405)
                    .offset(x: 0, y: 60)

                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 56, height: 7)
                        .background(Color(red: 0.82, green: 0.11, blue: 0.26))
                        .cornerRadius(3.50)
                        .offset(x: 0.50, y: -128)

                    Text("Preferred name display")
                        .font(Font.custom("Helvetica Neue", size: 20).weight(.medium))
                        .lineSpacing(20)
                        .foregroundColor(Color(red: 0.18, green: 0.18, blue: 0.18))
                        .offset(x: -64.50, y: -101.50)

                    Text("Choose how your name will appear when posting")
                        .font(Font.custom("Helvetica Neue", size: 12))
                        .lineSpacing(20)
                        .foregroundColor(Color(red: 0.68, green: 0.68, blue: 0.68))
                        .offset(x: -39, y: -74.50)

                    ZStack {
                        // 真实名称选项
                        ZStack {
                            HStack(spacing: 18) {
                                // 头像 - 优先显示 AvatarManager 的头像
                                if let pendingAvatar = AvatarManager.shared.pendingAvatar {
                                    Image(uiImage: pendingAvatar)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 67, height: 67)
                                        .clipShape(Ellipse())
                                        .overlay(
                                            Ellipse()
                                                .inset(by: 1)
                                                .stroke(selectedNameType == .realName ? Color(red: 0.82, green: 0.11, blue: 0.26) : Color(red: 0.37, green: 0.37, blue: 0.37), lineWidth: 1)
                                        )
                                } else if let avatarUrl = authManager.currentUser?.avatarUrl,
                                          let url = URL(string: avatarUrl) {
                                    AsyncImage(url: url) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } placeholder: {
                                        Ellipse()
                                            .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                                    }
                                    .frame(width: 67, height: 67)
                                    .clipShape(Ellipse())
                                    .overlay(
                                        Ellipse()
                                            .inset(by: 1)
                                            .stroke(selectedNameType == .realName ? Color(red: 0.82, green: 0.11, blue: 0.26) : Color(red: 0.37, green: 0.37, blue: 0.37), lineWidth: 1)
                                    )
                                } else {
                                    Ellipse()
                                        .foregroundColor(.clear)
                                        .frame(width: 67, height: 67)
                                        .background(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                                        .overlay(
                                            Ellipse()
                                                .inset(by: 1)
                                                .stroke(selectedNameType == .realName ? Color(red: 0.82, green: 0.11, blue: 0.26) : Color(red: 0.37, green: 0.37, blue: 0.37), lineWidth: 1)
                                        )
                                }

                                VStack(alignment: .leading, spacing: 5) {
                                    // 显示名称
                                    Text(authManager.currentUser?.displayName ?? authManager.currentUser?.username ?? "User")
                                        .font(Font.custom("Helvetica Neue", size: 19).weight(.bold))
                                        .lineSpacing(20)
                                        .foregroundColor(.black)

                                    // 用户名
                                    Text(authManager.currentUser?.username ?? "username")
                                        .font(Font.custom("Helvetica Neue", size: 15))
                                        .lineSpacing(20)
                                        .foregroundColor(Color(red: 0.54, green: 0.54, blue: 0.54))
                                }
                                .frame(width: 161, height: 46)
                            }
                            .frame(width: 246, height: 67)
                            .offset(x: -48.50, y: 0)
                        }
                        .frame(maxWidth: .infinity, maxHeight: 97)
                        .offset(x: 0, y: -48)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedNameType = .realName
                            isPresented = false
                        }

                        // 别名选项
                        ZStack {
                            Rectangle()
                                .foregroundColor(.clear)
                                .frame(maxWidth: .infinity, maxHeight: 97)
                                .background(.white)
                                .offset(x: 0, y: 0)

                            HStack(spacing: 18) {
                                // 头像 - 优先显示 AvatarManager 的头像
                                if let pendingAvatar = AvatarManager.shared.pendingAvatar {
                                    Image(uiImage: pendingAvatar)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 67, height: 67)
                                        .clipShape(Ellipse())
                                        .overlay(
                                            Ellipse()
                                                .inset(by: 1)
                                                .stroke(selectedNameType == .alias ? Color(red: 0.82, green: 0.11, blue: 0.26) : Color(red: 0.37, green: 0.37, blue: 0.37), lineWidth: 1)
                                        )
                                } else if let avatarUrl = authManager.currentUser?.avatarUrl,
                                          let url = URL(string: avatarUrl) {
                                    AsyncImage(url: url) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } placeholder: {
                                        Ellipse()
                                            .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                                    }
                                    .frame(width: 67, height: 67)
                                    .clipShape(Ellipse())
                                    .overlay(
                                        Ellipse()
                                            .inset(by: 1)
                                            .stroke(selectedNameType == .alias ? Color(red: 0.82, green: 0.11, blue: 0.26) : Color(red: 0.37, green: 0.37, blue: 0.37), lineWidth: 1)
                                    )
                                } else {
                                    Ellipse()
                                        .foregroundColor(.clear)
                                        .frame(width: 67, height: 67)
                                        .background(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                                        .overlay(
                                            Ellipse()
                                                .inset(by: 1)
                                                .stroke(selectedNameType == .alias ? Color(red: 0.82, green: 0.11, blue: 0.26) : Color(red: 0.37, green: 0.37, blue: 0.37), lineWidth: 1)
                                        )
                                }

                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Dreamer")
                                        .font(Font.custom("Helvetica Neue", size: 19).weight(.bold))
                                        .lineSpacing(20)
                                        .foregroundColor(.black)

                                    Text("Alias name")
                                        .font(Font.custom("Helvetica Neue", size: 15))
                                        .lineSpacing(20)
                                        .foregroundColor(Color(red: 0.54, green: 0.54, blue: 0.54))
                                }
                                .frame(width: 161, height: 46)
                            }
                            .offset(x: -48.50, y: 0)
                        }
                        .frame(maxWidth: .infinity, maxHeight: 97)
                        .offset(x: 0, y: 49)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedNameType = .alias
                            isPresented = false
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: 193)
                    .offset(x: 0, y: 46)

                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(maxWidth: .infinity, maxHeight: 0)
                        .overlay(
                            Rectangle()
                                .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.20)
                        )
                        .offset(x: 0, y: -51.50)

                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(maxWidth: .infinity, maxHeight: 0)
                        .overlay(
                            Rectangle()
                                .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.20)
                        )
                        .offset(x: 0, y: 47.50)

                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(maxWidth: .infinity, maxHeight: 0)
                        .overlay(
                            Rectangle()
                                .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.20)
                        )
                        .offset(x: 0, y: 142.50)
                }
                .frame(maxWidth: .infinity, maxHeight: 285)
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPresented)
    }
}

#Preview {
    @Previewable @State var showNewPost = true
    NewPostView(showNewPost: $showNewPost)
        .environmentObject(AuthenticationManager.shared)
}
