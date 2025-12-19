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
    @State private var isTextEditorFocused: Bool = false  // 用于自定义 TextView 的焦点状态
    @State private var showSaveDraftModal: Bool = false  // 控制保存草稿弹窗

    // Draft storage keys
    private let draftTextKey = "NewPostDraftText"
    private let draftImagesKey = "NewPostDraftImages"

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
                        .font(Typography.regular12)
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
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
            } else if initialImage == nil {
                // 没有初始图片时，尝试加载草稿
                loadDraft()
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

            // MARK: - 保存草稿弹窗
            if showSaveDraftModal {
                SaveDraftModal(
                    isPresented: $showSaveDraftModal,
                    onNo: {
                        // 不保存，清除草稿并关闭
                        clearDraft()
                        showNewPost = false
                    },
                    onYes: {
                        // 保存草稿并关闭
                        saveDraft()
                        showNewPost = false
                    }
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
                // 如果有内容，显示保存确认弹窗
                if hasContent {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showSaveDraftModal = true
                    }
                } else {
                    showNewPost = false
                }
            }) {
                Text("Cancel")
                    .font(Typography.regular14)
                    .lineSpacing(20)
                    .foregroundColor(.black)
            }

            Spacer()

            // 标题
            Text("Newpost")
                .font(Typography.semibold18)
                .lineSpacing(20)
                .foregroundColor(.black)

            Spacer()

            // Post 按钮
            Button(action: {
                Task {
                    await submitPost()
                }
            }) {
                if isPosting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.87, green: 0.11, blue: 0.26)))
                        .scaleEffect(0.8)
                } else {
                    Text("Post")
                        .font(Typography.regular14)
                        .lineSpacing(20)
                        .foregroundColor(canPost ? Color(red: 0.87, green: 0.11, blue: 0.26) : Color(red: 0.53, green: 0.53, blue: 0.53))
                }
            }
            .disabled(!canPost || isPosting)
            .frame(width: 36)
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
                .font(Typography.semibold14)
                .lineSpacing(20)
                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

            ZStack {
                Image(systemName: "chevron.down")
                    .font(Typography.regular10)
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
                            .frame(width: 239, height: 290)
                            .cornerRadius(10)
                            .clipped()

                        // 删除按钮
                        Button(action: {
                            removeImage(at: index)
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(Typography.regular20)
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
                            .frame(width: selectedImages.isEmpty ? 239 : 100, height: selectedImages.isEmpty ? 290 : 210)
                            .background(Color(red: 0.91, green: 0.91, blue: 0.91))
                            .cornerRadius(10)

                        VStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 30, weight: .light))
                                .foregroundColor(.white)

                            if selectedImages.count > 0 {
                                Text("\(selectedImages.count)/5")
                                    .font(Typography.regular12)
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
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                // Enhance with alice 浮动气泡 (仿 AutoFill 样式)
                if isTextEditorFocused {
                    Button(action: {
                        // TODO: 后续添加 AI 功能
                    }) {
                        HStack(spacing: 6) {
                            Image("alice-center-icon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)

                            Text("Enhance with alice")
                                .font(Typography.semibold14)
                                .foregroundColor(.black)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.white)
                                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 2)
                        )
                    }
                    .offset(y: -45)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8, anchor: .bottom).combined(with: .opacity),
                        removal: .scale(scale: 0.8, anchor: .bottom).combined(with: .opacity)
                    ))
                }

                NoAutoFillTextView(
                    text: $postText,
                    placeholder: "What do you want to talk about?",
                    textColor: UIColor(red: 0.38, green: 0.37, blue: 0.37, alpha: 1),
                    placeholderColor: UIColor(red: 0.38, green: 0.37, blue: 0.37, alpha: 1),
                    font: .systemFont(ofSize: 14),
                    onFocusChange: { focused in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isTextEditorFocused = focused
                        }
                    }
                )
                .frame(height: 150)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: - Channels and Enhance Section
    private var channelsAndEnhanceSection: some View {
        HStack(spacing: 10) {
            HStack(spacing: 3) {
                Text("#")
                    .font(Typography.regular16)
                    .lineSpacing(20)
                    .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))

                Text("Channels")
                    .font(Typography.regular10)
                    .lineSpacing(20)
                    .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
            }
            .padding(.horizontal, 16)
            .frame(height: 26)
            .background(Color(red: 0.91, green: 0.91, blue: 0.91))
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
                .font(Typography.regular16)
                .lineSpacing(40.94)
                .foregroundColor(.black)

            Spacer()

            Image(systemName: "chevron.right")
                .font(Typography.regular14)
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

            VStack(alignment: .leading, spacing: 6) {
                Text("Invite alice")
                    .font(Typography.regular16)
                    .lineSpacing(40.94)
                    .foregroundColor(.black)

                Text("add AI insight to this conversation")
                    .font(Typography.regular12)
                    .lineSpacing(40.94)
                    .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
            }

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
                .font(Typography.bold12)
                .lineSpacing(20)
                .foregroundColor(Color(red: 0.82, green: 0.13, blue: 0.25))

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
    }

    // MARK: - 是否可以发布
    private var canPost: Bool {
        !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedImages.isEmpty
    }

    // MARK: - 是否有内容（用于判断是否显示保存弹窗）
    private var hasContent: Bool {
        !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedImages.isEmpty
    }

    // MARK: - 保存草稿
    private func saveDraft() {
        // 保存文本
        UserDefaults.standard.set(postText, forKey: draftTextKey)

        // 保存图片（转为 Data 数组）
        let imageDataArray = selectedImages.compactMap { $0.jpegData(compressionQuality: 0.8) }
        UserDefaults.standard.set(imageDataArray, forKey: draftImagesKey)
    }

    // MARK: - 清除草稿
    private func clearDraft() {
        UserDefaults.standard.removeObject(forKey: draftTextKey)
        UserDefaults.standard.removeObject(forKey: draftImagesKey)
    }

    // MARK: - 加载草稿
    private func loadDraft() {
        // 加载文本
        if let savedText = UserDefaults.standard.string(forKey: draftTextKey) {
            postText = savedText
        }

        // 加载图片
        if let imageDataArray = UserDefaults.standard.array(forKey: draftImagesKey) as? [Data] {
            selectedImages = imageDataArray.compactMap { UIImage(data: $0) }
        }
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
                // 发帖成功后清除草稿
                clearDraft()
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

// MARK: - Custom TextView without AutoFill
struct NoAutoFillTextView: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var textColor: UIColor
    var placeholderColor: UIColor
    var font: UIFont
    var onFocusChange: ((Bool) -> Void)?

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = font
        textView.textColor = text.isEmpty ? placeholderColor : textColor
        textView.text = text.isEmpty ? placeholder : text
        textView.backgroundColor = .clear

        // 彻底禁用 AutoFill
        textView.textContentType = .init(rawValue: "")
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .sentences
        textView.spellCheckingType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no

        // iOS 17+ 禁用 inline predictions
        if #available(iOS 17.0, *) {
            textView.inlinePredictionType = .no
        }

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if text.isEmpty && !uiView.isFirstResponder {
            uiView.text = placeholder
            uiView.textColor = placeholderColor
        } else if !text.isEmpty {
            uiView.text = text
            uiView.textColor = textColor
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: NoAutoFillTextView

        init(_ parent: NoAutoFillTextView) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if textView.text == parent.placeholder {
                textView.text = ""
                textView.textColor = parent.textColor
            }
            parent.onFocusChange?(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if textView.text.isEmpty {
                textView.text = parent.placeholder
                textView.textColor = parent.placeholderColor
            }
            parent.onFocusChange?(false)
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text == parent.placeholder ? "" : textView.text
        }
    }
}

#Preview {
    @Previewable @State var showNewPost = true
    NewPostView(showNewPost: $showNewPost)
        .environmentObject(AuthenticationManager.shared)
}
