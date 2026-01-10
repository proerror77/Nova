import SwiftUI
import PhotosUI
import AVFoundation

struct NewPostView: View {
    @Binding var showNewPost: Bool
    var initialMediaItems: [PostMediaItem]? = nil  // Live Photo items from PhotosPicker
    var initialImage: UIImage? = nil  // 从PhotoOptionsModal传入的图片
    var onPostSuccess: ((Post) -> Void)? = nil  // 成功发布后的回调，传递创建的Post对象

    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var viewModel = NewPostViewModel()
    @State private var isBottomSwitchOn = false  // 底部开关状态
    @State private var keyboardHeight: CGFloat = 0  // 键盘高度
    @State private var capturedCameraImage: UIImage?  // Camera capture result

    // 🎯 新增：分离的照片和视频选择
    @State private var selectedPhotoItems: [PhotosPickerItem] = []  // 照片（Live Photo + 静态照片）
    @State private var selectedVideoItems: [PhotosPickerItem] = []  // 视频
    @State private var showPhotoPhotoPicker = false
    @State private var showVideoPhotoPicker = false

    // 计算当前媒体类型
    private var currentMediaType: MediaSelectionType {
        let hasPhotos = viewModel.selectedMediaItems.contains { item in
            if case .image = item { return true }
            if case .livePhoto = item { return true }
            return false
        }
        let hasVideos = viewModel.selectedMediaItems.contains { item in
            if case .video = item { return true }
            return false
        }

        if hasPhotos { return .photos }
        if hasVideos { return .video }
        return .none
    }

    enum MediaSelectionType {
        case none
        case photos  // 照片 + Live Photo
        case video   // 视频
    }

    var body: some View {
        ZStack {
            // 背景色
            Color.white

            // MARK: - 可滚动内容区域
            ScrollView {
                VStack(spacing: 0) {
                    // 顶部留白，给固定导航栏让出空间
                    Spacer()
                        .frame(height: 98.h)

                    contentView
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                viewModel.hideKeyboard()
            }

            // MARK: - 固定顶部导航栏
            VStack(spacing: 0) {
                topNavigationBar

                // MARK: - Error Messages
                if let error = viewModel.postError {
                    Text(error)
                        .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                        .foregroundColor(.red)
                        .padding(.horizontal, 16.w)
                        .padding(.vertical, 8.h)
                        .background(Color.white)
                }

                if let enhanceError = viewModel.enhanceError {
                    Text(enhanceError)
                        .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 16.w)
                        .padding(.vertical, 8.h)
                        .background(Color.white)
                }

                Spacer()
            }

            // MARK: - 底部白色背景模块
            VStack {
                Spacer()
                VStack(spacing: 0) {
                    // 底部 icon 区域
                    HStack(spacing: 20.s) {
                        // 📸 照片按钮（Live Photo + 静态照片）
                        Button(action: {
                            showPhotoPhotoPicker = true
                        }) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 16.f))
                                .foregroundColor(currentMediaType == .video ? .gray : .black)
                        }
                        .disabled(currentMediaType == .video || viewModel.totalMediaCount >= 5)

                        // 🎥 视频按钮
                        Button(action: {
                            showVideoPhotoPicker = true
                        }) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 16.f))
                                .foregroundColor(currentMediaType == .photos ? .gray : .black)
                        }
                        .disabled(currentMediaType == .photos || viewModel.totalMediaCount >= 1)

                        // Alice icon - Enhance with Alice 功能
                        Button(action: {
                            viewModel.requestEnhancement()
                        }) {
                            if viewModel.isEnhancing {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .frame(width: 16.s, height: 16.s)
                            } else {
                                Image("Alice-icon-B")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 16.s, height: 16.s)
                            }
                        }
                        .disabled(viewModel.isEnhancing)

                        // Location icon
                        Button(action: {
                            viewModel.showLocationPicker = true
                        }) {
                            Image("Location-icon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 11.w, height: 14.h)
                        }

                        Spacer()
                    }
                    .padding(.leading, 16.w)
                    .padding(.top, keyboardHeight > 0 ? 10.h : 16.h)

                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .frame(height: keyboardHeight > 0 ? 36.h : 70.h)
                .background(.white)
            }
            .padding(.bottom, keyboardHeight)
            .animation(.easeOut(duration: 0.25), value: keyboardHeight)
        }
        .ignoresSafeArea(edges: [.top, .bottom])
        .sheet(isPresented: $viewModel.showCamera) {
            ImagePicker(
                sourceType: .camera,
                selectedImage: $capturedCameraImage,
                onVideoSelected: { videoURL in
                    handleCapturedVideo(url: videoURL)
                },
                allowsVideo: true
            )
        }
        .onChange(of: capturedCameraImage) { _, newImage in
            if let image = newImage, viewModel.selectedMediaItems.count < 5 {
                viewModel.selectedMediaItems.append(.image(image, .empty))
                viewModel.analyzeImageWithVLM()
                capturedCameraImage = nil  // Reset for next capture
            }
        }
        // 📸 照片选择器（Live Photo + 静态照片）
        .photosPicker(
            isPresented: $showPhotoPhotoPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: 5 - viewModel.selectedMediaItems.count,
            matching: .any(of: [.images, .livePhotos])  // ← 只选照片
        )
        .onChange(of: selectedPhotoItems) { _, newValue in
            Task {
                await processSelectedPhotos(newValue)
            }
        }

        // 🎥 视频选择器（独立）
        .photosPicker(
            isPresented: $showVideoPhotoPicker,
            selection: $selectedVideoItems,
            maxSelectionCount: 1,  // 视频只能选1个
            matching: .videos  // ← 只选视频
        )
        .onChange(of: selectedVideoItems) { _, newValue in
            Task {
                await processSelectedVideos(newValue)
            }
        }

        // 保留旧的 PhotosPicker（用于兼容性）
        .photosPicker(
            isPresented: $viewModel.showPhotoPicker,
            selection: $viewModel.selectedPhotos,
            maxSelectionCount: 5 - viewModel.selectedMediaItems.count,
            matching: .any(of: [.images, .livePhotos, .videos])
        )
        .onChange(of: viewModel.selectedPhotos) { _, newValue in
            Task {
                await viewModel.processSelectedPhotos(newValue)
            }
        }
        .onAppear {
            viewModel.configure(
                authManager: authManager,
                initialMediaItems: initialMediaItems,
                initialImage: initialImage,
                onPostSuccess: onPostSuccess,
                onDismiss: { showNewPost = false }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            guard let userInfo = notification.userInfo,
                  let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                #if DEBUG
                print("[NewPostView] Failed to extract keyboard frame from notification")
                #endif
                return
            }
            keyboardHeight = keyboardFrame.height
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
        .overlay {
            // MARK: - 名称选择弹窗
            if viewModel.showNameSelector {
                NameSelectorModal(
                    isPresented: $viewModel.showNameSelector,
                    selectedNameType: $viewModel.selectedNameType
                )
            }

            // MARK: - 保存草稿弹窗
            if viewModel.showSaveDraftModal {
                SaveDraftModal(
                    isPresented: $viewModel.showSaveDraftModal,
                    onNo: { viewModel.handleSaveDraftNo() },
                    onYes: { viewModel.handleSaveDraftYes() }
                )
            }
        }
        .sheet(isPresented: $viewModel.showLocationPicker) {
            LocationPickerView(
                selectedLocation: $viewModel.selectedLocation,
                isPresented: $viewModel.showLocationPicker
            )
        }
        .sheet(isPresented: $viewModel.showEnhanceSuggestion) {
            if let suggestion = viewModel.enhanceSuggestion {
                EnhanceSuggestionView(
                    suggestion: suggestion,
                    isPresented: $viewModel.showEnhanceSuggestion,
                    onApply: { selectedText in
                        viewModel.applyEnhancement(selectedText)
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            } else {
                // Fallback: auto-dismiss if suggestion is nil to prevent blank sheet
                Color.clear
                    .onAppear {
                        #if DEBUG
                        print("[NewPostView] Warning: showEnhanceSuggestion=true but enhanceSuggestion is nil - state synchronization issue")
                        #endif
                        viewModel.showEnhanceSuggestion = false
                    }
            }
        }
        .sheet(isPresented: $viewModel.showChannelPicker) {
            ChannelPickerView(
                selectedChannelIds: $viewModel.selectedChannelIds,
                isPresented: $viewModel.showChannelPicker
            )
        }
    }

    // MARK: - Helper Methods

    /// 处理选中的照片（Live Photo + 静态照片）
    private func processSelectedPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else {
            selectedPhotoItems = []
            return
        }

        let maxToAdd = 5 - viewModel.selectedMediaItems.count
        guard maxToAdd > 0 else {
            selectedPhotoItems = []
            return
        }

        viewModel.isProcessingMedia = true

        do {
            let newMedia = try await LivePhotoManager.shared.loadMedia(from: items, maxCount: maxToAdd)

            // 只保留照片类型（过滤掉视频）
            let filteredMedia = newMedia.filter { item in
                if case .video = item {
                    return false
                }
                return true
            }

            await MainActor.run {
                viewModel.selectedMediaItems.append(contentsOf: filteredMedia)
                selectedPhotoItems = []  // 清空以便下次选择
                viewModel.isProcessingMedia = false

                // 触发 VLM 分析
                if !filteredMedia.isEmpty {
                    viewModel.analyzeImageWithVLM()
                }
            }

            #if DEBUG
            print("[NewPostView] Loaded \(filteredMedia.count) photos")
            #endif
        } catch {
            await MainActor.run {
                viewModel.isProcessingMedia = false
                selectedPhotoItems = []
                viewModel.postError = "Failed to load photos: \(error.localizedDescription)"
            }
            #if DEBUG
            print("[NewPostView] Failed to load photos: \(error)")
            #endif
        }
    }

    /// 处理选中的视频
    private func processSelectedVideos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else {
            selectedVideoItems = []
            return
        }

        viewModel.isProcessingMedia = true

        do {
            let newMedia = try await LivePhotoManager.shared.loadMedia(from: items, maxCount: 1)

            // 只保留视频类型
            let filteredMedia = newMedia.filter { item in
                if case .video = item {
                    return true
                }
                return false
            }

            await MainActor.run {
                viewModel.selectedMediaItems.append(contentsOf: filteredMedia)
                selectedVideoItems = []  // 清空以便下次选择
                viewModel.isProcessingMedia = false
            }

            #if DEBUG
            print("[NewPostView] Loaded \(filteredMedia.count) videos")
            #endif
        } catch {
            await MainActor.run {
                viewModel.isProcessingMedia = false
                selectedVideoItems = []
                viewModel.postError = "Failed to load video: \(error.localizedDescription)"
            }
            #if DEBUG
            print("[NewPostView] Failed to load video: \(error)")
            #endif
        }
    }

    /// Handle video captured from camera
    private func handleCapturedVideo(url: URL) {
        guard viewModel.selectedMediaItems.count < 5 else { return }

        Task {
            // Generate thumbnail
            let asset = AVURLAsset(url: url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true

            var thumbnail: UIImage
            var duration: TimeInterval

            do {
                let (cgImage, _) = try await imageGenerator.image(at: .zero)
                thumbnail = UIImage(cgImage: cgImage)
            } catch {
                thumbnail = UIImage(systemName: "video.fill") ?? UIImage()
            }

            do {
                let durationCM = try await asset.load(.duration)
                duration = durationCM.seconds
            } catch {
                duration = 0
            }

            let videoData = VideoData(url: url, thumbnail: thumbnail, duration: duration)
            await MainActor.run {
                viewModel.selectedMediaItems.append(.video(videoData, .empty))
            }
        }
    }

    // MARK: - Top Navigation Bar
    private var topNavigationBar: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                // 标题 - 居中摆放
                Text("NewPost")
                    .font(Font.custom("SFProDisplay-Medium", size: 18.f))
                    .foregroundColor(.black)

                // 两侧按钮
                HStack {
                    // Cancel 按钮
                    Button(action: {
                        viewModel.handleCancelTapped()
                    }) {
                        Text("Cancel")
                            .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                            .tracking(0.28)
                            .foregroundColor(.black)
                    }
                    .frame(height: 24.h)

                    Spacer()

                    // Post 按钮
                    Button(action: {
                        Task {
                            await viewModel.submitPost()
                        }
                    }) {
                        if viewModel.isPosting {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(Color(red: 0.87, green: 0.11, blue: 0.26))
                        } else {
                            Text("Post")
                                .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                                .tracking(0.28)
                                .foregroundColor(viewModel.canPost ? Color(red: 0.87, green: 0.11, blue: 0.26) : Color(red: 0.53, green: 0.53, blue: 0.53))
                        }
                    }
                    .disabled(!viewModel.canPost || viewModel.isPosting)
                    .frame(height: 24.h)  // 移除宽度限制，让按钮自适应内容
                }
            }
            .padding(.horizontal, 16.w)

            Spacer()
                .frame(height: 18.h)

            // 底部灰线
            Rectangle()
                .fill(DesignTokens.borderColor)
                .frame(height: 0.5)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 98.h)
        .background(
            Rectangle()
                .foregroundColor(.clear)
                .background(.white)
        )
    }

    // MARK: - Content View
    private var contentView: some View {
        VStack(spacing: 0) {
            postAsSection
            imagePreviewSection
            vlmTagsSection  // VLM-generated tags
            textInputSection
            channelsAndEnhanceSection

            // Invite alice 区域 + 开关
            HStack(spacing: 10.s) {
                Image("alice-center-icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16.s, height: 16.s)

                VStack(alignment: .leading, spacing: 4.s) {
                    Text("Invite alice")
                        .font(Font.custom("SFProDisplay-Medium", size: 14.f))
                        .foregroundColor(.black)

                    Text("Add AI in this conversation")
                        .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                        .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                }

                Spacer()

                // 开关按钮
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isBottomSwitchOn.toggle()
                    }
                }) {
                    Image(isBottomSwitchOn ? "Switch-on" : "Switch-off")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 37.w, height: 20.h)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16.w)
            .padding(.top, 20.h)

            // 底部留白，避免被底部白色模块遮挡
            Spacer()
                .frame(height: 120.h)
        }
    }

    // MARK: - Post As Section
    private var postAsSection: some View {
        HStack(spacing: 13.s) {
            // 头像 - 优先显示 AvatarManager 的头像
            ZStack {
                if let pendingAvatar = AvatarManager.shared.pendingAvatar {
                    Image(uiImage: pendingAvatar)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 30.s, height: 30.s)
                        .clipShape(Circle())
                } else if let avatarUrl = authManager.currentUser?.avatarUrl,
                          let url = URL(string: avatarUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        DefaultAvatarView(size: 30.s)
                    }
                    .frame(width: 30.s, height: 30.s)
                    .clipShape(Circle())
                } else {
                    DefaultAvatarView(size: 30.s)
                }
            }
            .overlay(
                Circle()
                    .stroke(Color(red: 0.81, green: 0.13, blue: 0.25), lineWidth: 0.50)
            )

            // 显示名称 + 箭头（保持 6pt 间距）
            HStack(spacing: 6.s) {
                Text(viewModel.displayedName)
                    .font(Font.custom("SFProDisplay-Medium", size: 14.f))
                    .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

                Image(systemName: "chevron.down")
                    .font(.system(size: 10.f))
                    .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))
            }

            Spacer()
        }
        .padding(.leading, 16.w)
        .padding(.top, 12.h)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.showNameSelector = true
        }
    }

    // MARK: - Image Preview Section (with Live Photo support)
    private var imagePreviewSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12.s) {
                // Processing indicator
                if viewModel.isProcessingMedia {
                    ZStack {
                        Rectangle()
                            .foregroundColor(.clear)
                            .frame(width: 239.w, height: 290.h)
                            .background(Color(red: 0.91, green: 0.91, blue: 0.91))
                            .cornerRadius(10.s)

                        VStack(spacing: 12.s) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Processing...")
                                .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                                .foregroundColor(.gray)
                        }
                    }
                }

                // Display all selected media (images and Live Photos)
                ForEach(Array(viewModel.selectedMediaItems.enumerated()), id: \.element.id) { index, mediaItem in
                    ZStack {
                        // Top-right alignment for delete button
                        ZStack(alignment: .topTrailing) {
                            switch mediaItem {
                            case .image(let image, _):
                                // Regular image preview
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 239.w, height: 290.h)
                                    .clipShape(RoundedRectangle(cornerRadius: 10.s))

                            case .livePhoto(let livePhotoData, _):
                                // Live Photo preview with play capability
                                LivePhotoPreviewCard(
                                    livePhotoData: livePhotoData,
                                    onDelete: {
                                        viewModel.removeMediaItem(at: index)
                                    }
                                )

                            case .video(let videoData, _):
                                // Video preview with thumbnail and duration
                                ZStack(alignment: .bottomTrailing) {
                                    Image(uiImage: videoData.thumbnail)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 239.w, height: 290.h)
                                        .clipShape(RoundedRectangle(cornerRadius: 10.s))

                                    // Video duration badge
                                    Text(viewModel.formatDuration(videoData.duration))
                                        .font(Font.custom("SFProDisplay-Medium", size: 12.f))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8.w)
                                        .padding(.vertical, 4.h)
                                        .background(Color.black.opacity(0.6))
                                        .cornerRadius(4.s)
                                        .padding(8.s)

                                    // Play icon overlay
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 40.f))
                                        .foregroundColor(.white.opacity(0.9))
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }

                            // Delete button (for images and videos, Live Photo has its own)
                            if !mediaItem.isLivePhoto {
                                Button(action: {
                                    viewModel.removeMediaItem(at: index)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 20.f))
                                        .foregroundColor(.white)
                                        .background(
                                            Circle()
                                                .fill(Color.black.opacity(0.5))
                                                .frame(width: 20.s, height: 20.s)
                                        )
                                }
                                .padding(4.s)
                            }
                        }
                    }
                }

                // Add more media button (max 5) - always shown on the right
                if viewModel.totalMediaCount < 5 && !viewModel.isProcessingMedia {
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 239.w, height: 290.h)
                        .background(Color(red: 0.91, green: 0.91, blue: 0.91))
                        .cornerRadius(10.s)
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: currentMediaType == .video ? "video.fill" : "photo.on.rectangle.angled")
                                    .font(.system(size: 32))
                                    .foregroundColor(.gray)
                                Text(currentMediaType == .video ? "Add Video" : "Add Photos")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        )
                        .onTapGesture {
                            // 根据当前媒体类型打开相应的选择器
                            if currentMediaType == .video {
                                showVideoPhotoPicker = true
                            } else {
                                showPhotoPhotoPicker = true
                            }
                        }
                }
            }
            .padding(.horizontal, 16.w)
        }
        .padding(.top, 12.h)
    }

    // MARK: - VLM Tags Section
    @ViewBuilder
    private var vlmTagsSection: some View {
        if viewModel.isAnalyzingImage || !viewModel.vlmTags.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("AI Suggested Tags")
                        .font(Font.custom("SFProDisplay-Medium", size: 14.f))
                        .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))

                    if viewModel.isAnalyzingImage {
                        ProgressView()
                            .scaleEffect(0.7)
                    }

                    Spacer()

                    if !viewModel.vlmTags.isEmpty {
                        Text("\(viewModel.selectedVLMTags.count) selected")
                            .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                            .foregroundColor(DesignTokens.textMuted)
                    }
                }

                if !viewModel.vlmTags.isEmpty {
                    // Flow layout for tags
                    FlowLayout(spacing: 8) {
                        ForEach(viewModel.vlmTags) { tagSuggestion in
                            VLMTagChip(
                                tag: tagSuggestion.tag,
                                confidence: tagSuggestion.confidence,
                                isSelected: viewModel.selectedVLMTags.contains(tagSuggestion.tag),
                                onTap: { viewModel.toggleVLMTag(tagSuggestion.tag) }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)
        }
    }


    // MARK: - Text Input Section
    private var textInputSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                // Enhance with alice 浮动气泡 (仿 AutoFill 样式)
                if viewModel.isTextEditorFocused {
                    Button(action: {
                        // TODO: 后续添加 AI 功能
                    }) {
                        HStack(spacing: 6) {
                            Image("alice-center-icon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)

                            Text("Enhance with alice")
                                .font(Font.custom("SFProDisplay-Medium", size: 14.f))
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
                    text: $viewModel.postText,
                    placeholder: "Enter text...",
                    textColor: UIColor(red: 0.38, green: 0.37, blue: 0.37, alpha: 1),
                    placeholderColor: UIColor(red: 0.38, green: 0.37, blue: 0.37, alpha: 1),
                    font: .systemFont(ofSize: 14),
                    onFocusChange: { focused in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            viewModel.isTextEditorFocused = focused
                        }
                        // Trigger on-device AI tag generation when user finishes typing
                        if !focused {
                            viewModel.generateTextBasedTags()
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                // Channel selection button
                Button(action: {
                    viewModel.showChannelPicker = true
                }) {
                    HStack(spacing: 6) {
                        Text("#")
                            .font(Font.custom("SFProDisplay-Medium", size: 16.f))
                            .foregroundColor(viewModel.selectedChannelIds.isEmpty
                                ? Color(red: 0.27, green: 0.27, blue: 0.27)
                                : Color(red: 0.82, green: 0.13, blue: 0.25))

                        if viewModel.selectedChannelIds.isEmpty {
                            Text("Add Channels")
                                .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                                .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
                        } else {
                            Text("\(viewModel.selectedChannelIds.count) selected")
                                .font(Font.custom("SFProDisplay-Medium", size: 12.f))
                                .foregroundColor(Color(red: 0.82, green: 0.13, blue: 0.25))
                        }

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10.f))
                            .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(viewModel.selectedChannelIds.isEmpty
                        ? Color(red: 0.91, green: 0.91, blue: 0.91)
                        : Color(red: 0.98, green: 0.95, blue: 0.96))
                    .cornerRadius(24)
                }

                Spacer()
            }

            // AI-suggested channels (show when available and no manual selection)
            if !viewModel.suggestedChannels.isEmpty && viewModel.selectedChannelIds.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11.f))
                            .foregroundColor(Color(red: 0.82, green: 0.13, blue: 0.25))
                        Text("Suggested by Alice")
                            .font(Font.custom("SFProDisplay-Medium", size: 11.f))
                            .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                    }

                    HStack(spacing: 8) {
                        ForEach(viewModel.suggestedChannels) { suggestion in
                            Button(action: {
                                // Add suggested channel to selection
                                if !viewModel.selectedChannelIds.contains(suggestion.id) && viewModel.selectedChannelIds.count < 3 {
                                    viewModel.selectedChannelIds.append(suggestion.id)
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Text("#\(suggestion.name)")
                                        .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                                        .foregroundColor(Color(red: 0.82, green: 0.13, blue: 0.25))
                                    Text("\(Int(suggestion.confidence * 100))%")
                                        .font(Font.custom("SFProDisplay-Regular", size: 10.f))
                                        .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(red: 0.98, green: 0.95, blue: 0.96))
                                .cornerRadius(16)
                            }
                        }

                        // Accept all button
                        if viewModel.suggestedChannels.count > 1 {
                            Button(action: {
                                // Add all suggestions (up to 3)
                                for suggestion in viewModel.suggestedChannels.prefix(3) {
                                    if !viewModel.selectedChannelIds.contains(suggestion.id) {
                                        viewModel.selectedChannelIds.append(suggestion.id)
                                    }
                                }
                            }) {
                                Text("Use All")
                                    .font(Font.custom("SFProDisplay-Medium", size: 11.f))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(red: 0.82, green: 0.13, blue: 0.25))
                                    .cornerRadius(16)
                            }
                        }
                    }
                }
            } else if viewModel.isLoadingSuggestions {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Getting suggestions...")
                        .font(Font.custom("SFProDisplay-Regular", size: 11.f))
                        .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
    }
}

#Preview {
    @Previewable @State var showNewPost = true
    NewPostView(showNewPost: $showNewPost)
        .environmentObject(AuthenticationManager.shared)
}
