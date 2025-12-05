import SwiftUI
import PhotosUI

struct NewPostView: View {
    @Binding var showNewPost: Bool
    var initialImage: UIImage? = nil  // 从PhotoOptionsModal传入的图片
    var onPostSuccess: (() -> Void)? = nil  // 成功发布后的回调
    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var postText: String = ""
    @State private var inviteAlice: Bool = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var isPosting = false
    @State private var postError: String?
    @FocusState private var isTextFieldFocused: Bool

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
                // MARK: - 顶部导航栏（与其他页面一致）
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

                ScrollView {
                    VStack(spacing: 0) {
                        // MARK: - Post as 部分
                        HStack(spacing: 13) {
                            Circle()
                                .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle()
                                        .stroke(Color(red: 0.81, green: 0.13, blue: 0.25), lineWidth: 0.50)
                                )

                            Text("Kent Peng")
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

                        // MARK: - 图片预览区 (4:3 竖图比例)
                        HStack(alignment: .top, spacing: 20) {
                            if selectedImages.count > 0 {
                                // 显示选中的图片 - 4:3竖图比例 (width:height = 3:4)
                                Image(uiImage: selectedImages[0])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 133) // 3:4 比例
                                    .cornerRadius(10)
                                    .clipped()

                                // 第二个位置：灰色加号框（添加更多图片）
                                ZStack {
                                    Rectangle()
                                        .foregroundColor(.clear)
                                        .frame(width: 100, height: 133)
                                        .background(Color(red: 0.91, green: 0.91, blue: 0.91))
                                        .cornerRadius(10)

                                    // 加号
                                    Image(systemName: "plus")
                                        .font(.system(size: 30, weight: .light))
                                        .foregroundColor(.white)
                                }
                            } else {
                                // 占位图片1 - 黑色半透明 + Preview 标签 (4:3竖图)
                                ZStack {
                                    Rectangle()
                                        .foregroundColor(.clear)
                                        .frame(width: 100, height: 133)
                                        .background(Color(red: 0, green: 0, blue: 0).opacity(0.20))
                                        .cornerRadius(10)

                                    VStack {
                                        Spacer()
                                        HStack {
                                            Text("Preview")
                                                .font(Font.custom("Helvetica Neue", size: 10).weight(.medium))
                                                .lineSpacing(20)
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 2)
                                                .background(Color(red: 0.82, green: 0.13, blue: 0.25))
                                                .cornerRadius(45)
                                            Spacer()
                                        }
                                        .padding(6)
                                    }
                                }

                                // 占位图片2 - 灰色 + 加号 (4:3竖图)
                                ZStack {
                                    Rectangle()
                                        .foregroundColor(.clear)
                                        .frame(width: 100, height: 133)
                                        .background(Color(red: 0.91, green: 0.91, blue: 0.91))
                                        .cornerRadius(10)

                                    // 加号
                                    Image(systemName: "plus")
                                        .font(.system(size: 30, weight: .light))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                        // MARK: - 文本输入区域
                        ZStack(alignment: .topLeading) {
                            // 占位文字
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

                        // MARK: - Channels 和 Enhance 按钮
                        HStack(spacing: 10) {
                            // #Channels 按钮
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

                            // Enhance with alice 按钮
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

                        Rectangle()
                            .foregroundColor(.clear)
                            .frame(height: 0)
                            .overlay(
                                Rectangle()
                                    .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.20)
                            )
                            .padding(.top, 20)

                        // MARK: - Check in 按钮
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

                        Rectangle()
                            .foregroundColor(.clear)
                            .frame(height: 0)
                            .overlay(
                                Rectangle()
                                    .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.20)
                            )

                        // MARK: - Invite alice 切换
                        HStack {
                            Circle()
                                .stroke(Color.gray, lineWidth: 1)
                                .frame(width: 20.86, height: 20.86)

                            Text("Invite alice")
                                .font(Font.custom("Helvetica Neue", size: 16))
                                .lineSpacing(40.94)
                                .foregroundColor(.black)

                            Spacer()

                            // Toggle 开关
                            Toggle("", isOn: $inviteAlice)
                                .labelsHidden()
                                .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.82, green: 0.13, blue: 0.25)))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)

                        // MARK: - Invite Alice 提示
                        if inviteAlice {
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
                    }
                }
                .scrollDismissesKeyboard(.interactively) // 滑动时自动收起键盘
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

                // MARK: - Post 按钮
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
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera, selectedImage: .constant(nil))
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotos, maxSelectionCount: 10, matching: .images)
        .onChange(of: selectedPhotos) { oldValue, newValue in
            Task {
                selectedImages = []
                for item in newValue {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        selectedImages.append(image)
                    }
                }
            }
        }
        .onAppear {
            // 如果有初始图片，添加到selectedImages
            if let image = initialImage, selectedImages.isEmpty {
                selectedImages = [image]
            }
        }
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
        guard let userId = authManager.currentUser?.id else {
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

            #if DEBUG
            print("[NewPost] Created post: \(createdPost.id)")
            #endif

            // Step 3: 成功后关闭页面并触发刷新回调
            await MainActor.run {
                isPosting = false
                showNewPost = false
                // 调用成功回调，通知 HomeView 刷新 Feed
                onPostSuccess?()
            }

        } catch {
            #if DEBUG
            print("[NewPost] Error: \(error)")
            #endif
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
