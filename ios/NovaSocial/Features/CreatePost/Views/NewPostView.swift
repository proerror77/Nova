import SwiftUI
import PhotosUI

struct NewPostView: View {
    @Binding var showNewPost: Bool
    var initialMediaItems: [PostMediaItem]? = nil  // Live Photo items from PhotosPicker
    var initialImage: UIImage? = nil  // 从PhotoOptionsModal传入的图片
    var onPostSuccess: ((Post) -> Void)? = nil  // 成功发布后的回调，传递创建的Post对象
    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var postText: String = ""
    @State private var inviteAlice: Bool = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var selectedMediaItems: [PostMediaItem] = []  // Unified media items (images, videos, live photos)
    @State private var isProcessingMedia = false  // Live Photo processing indicator
    @State private var isPosting = false
    @State private var uploadProgress: Double = 0.0  // Upload progress (0.0 to 1.0)
    @State private var uploadStatus: String = ""  // Upload status message
    @State private var postError: String?
    @State private var showNameSelector = false  // 控制名称选择弹窗
    @State private var selectedNameType: NameDisplayType = .realName  // 选择的名称类型
    @State private var showLocationPicker = false  // 控制位置选择弹窗
    @State private var selectedLocation = ""  // 选择的位置
    @State private var isTextEditorFocused: Bool = false  // 用于自定义 TextView 的焦点状态
    @State private var showSaveDraftModal: Bool = false  // 控制保存草稿弹窗

    // Enhance with Alice states
    @State private var isEnhancing: Bool = false  // 正在獲取 AI 建議
    @State private var showEnhanceSuggestion: Bool = false  // 顯示建議彈窗
    @State private var enhanceSuggestion: PostEnhancementSuggestion?  // AI 建議結果
    @State private var enhanceError: String?  // 增強錯誤訊息

    // Channel selection states
    @State private var showChannelPicker: Bool = false
    @State private var selectedChannelIds: [String] = []
    @State private var suggestedChannels: [ChannelSuggestion] = []
    @State private var isLoadingSuggestions: Bool = false

    // VLM (Vision Language Model) states - TODO: Add VLMService.swift to project
    // @State private var vlmTags: [TagSuggestion] = []
    // @State private var selectedVLMTags: Set<String> = []
    @State private var isAnalyzingImage: Bool = false
    // @State private var vlmChannelSuggestions: [ChannelSuggestion] = []

    // Services
    private let mediaService = MediaService()
    private let contentService = ContentService()
    private let livePhotoManager = LivePhotoManager.shared
    private let aliceService = AliceService.shared
    private let feedService = FeedService()
    // private let vlmService = VLMService.shared  // TODO: Add to project
    // WebP image compression (25-35% smaller than JPEG)
    private let imageCompressor = ImageCompressor.shared
    // Background upload manager for non-blocking uploads
    private let uploadManager = BackgroundUploadManager.shared

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
                        .padding(.vertical, 8)
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera, selectedImage: .constant(nil))
        }
        // PhotosPicker with Live Photo and video support
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotos,
            maxSelectionCount: 5 - selectedMediaItems.count,
            matching: .any(of: [.images, .livePhotos, .videos])  // Support images, Live Photos, and videos
        )
        .onChange(of: selectedPhotos) { oldValue, newValue in
            Task {
                await processSelectedPhotos(newValue)
            }
        }
        .onAppear {
            // 如果有初始媒体项目（来自 PhotosPicker），添加到 selectedMediaItems
            if let mediaItems = initialMediaItems, !mediaItems.isEmpty, selectedMediaItems.isEmpty {
                selectedMediaItems = mediaItems
                // Trigger VLM analysis for initial media - TODO: re-enable
                // analyzeImageWithVLM()
            }
            // 如果有初始图片，添加到 selectedMediaItems
            else if let image = initialImage, selectedMediaItems.isEmpty {
                selectedMediaItems = [.image(image)]
                // Trigger VLM analysis for initial image - TODO: re-enable
                // analyzeImageWithVLM()
            } else if initialMediaItems == nil && initialImage == nil {
                // 没有初始媒体时，尝试加载草稿
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
        .sheet(isPresented: $showEnhanceSuggestion) {
            if let suggestion = enhanceSuggestion {
                EnhanceSuggestionView(
                    suggestion: suggestion,
                    isPresented: $showEnhanceSuggestion,
                    onApply: { selectedText in
                        postText = selectedText
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showChannelPicker) {
            ChannelPickerView(
                selectedChannelIds: $selectedChannelIds,
                isPresented: $showChannelPicker
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
                    .font(.system(size: 14))
                    .lineSpacing(20)
                    .foregroundColor(.black)
            }

            Spacer()

            // 标题
            Text("Newpost")
                .font(.system(size: 18, weight: .medium))
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
                        .scaleEffect(0.8)
                        .tint(Color(red: 0.87, green: 0.11, blue: 0.26))
                } else {
                    Text("Post")
                        .font(.system(size: 14))
                        .lineSpacing(20)
                        .foregroundColor(canPost ? Color(red: 0.87, green: 0.11, blue: 0.26) : Color(red: 0.53, green: 0.53, blue: 0.53))
                }
            }
            .disabled(!canPost || isPosting)
            .frame(minWidth: 36)
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
            // vlmTagsSection  // VLM-generated tags - TODO: re-enable
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
                .font(.system(size: 14, weight: .medium))
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

    // MARK: - Image Preview Section (with Live Photo support)
    private var imagePreviewSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                // Processing indicator
                if isProcessingMedia {
                    ZStack {
                        Rectangle()
                            .foregroundColor(.clear)
                            .frame(width: 239, height: 290)
                            .background(Color(red: 0.91, green: 0.91, blue: 0.91))
                            .cornerRadius(10)
                        
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Processing...")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                // Display all selected media (images and Live Photos)
                ForEach(Array(selectedMediaItems.enumerated()), id: \.element.id) { index, mediaItem in
                    ZStack {
                        // Top-right alignment for delete button
                        ZStack(alignment: .topTrailing) {
                            switch mediaItem {
                            case .image(let image):
                                // Regular image preview
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 239, height: 290)
                                    .cornerRadius(10)
                                    .clipped()

                            case .livePhoto(let livePhotoData):
                                // Live Photo preview with play capability
                                LivePhotoPreviewCard(
                                    livePhotoData: livePhotoData,
                                    onDelete: {
                                        removeMediaItem(at: index)
                                    }
                                )

                            case .video(let videoData):
                                // Video preview with thumbnail and duration
                                ZStack(alignment: .bottomTrailing) {
                                    Image(uiImage: videoData.thumbnail)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 239, height: 290)
                                        .cornerRadius(10)
                                        .clipped()

                                    // Video duration badge
                                    Text(formatDuration(videoData.duration))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.black.opacity(0.6))
                                        .cornerRadius(4)
                                        .padding(8)

                                    // Play icon overlay
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(.white.opacity(0.9))
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }

                            // Delete button (for images and videos, Live Photo has its own)
                            if !mediaItem.isLivePhoto {
                                Button(action: {
                                    removeMediaItem(at: index)
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

                        // Enhance with Alice button (only on first image)
                        if index == 0 {
                            VStack {
                                Spacer()
                                HStack {
                                    enhanceWithAliceButton
                                        .padding(.leading, 8)
                                        .padding(.bottom, 8)
                                    Spacer()
                                }
                            }
                            .frame(width: 239, height: 290)
                        }
                    }
                }
                
                // Add more media button (max 5) - always shown on the right
                if totalMediaCount < 5 && !isProcessingMedia {
                    ZStack {
                        Rectangle()
                            .foregroundColor(.clear)
                            .frame(width: totalMediaCount == 0 ? 239 : 100, height: totalMediaCount == 0 ? 290 : 210)
                            .background(Color(red: 0.91, green: 0.91, blue: 0.91))
                            .cornerRadius(10)

                        VStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 30, weight: .light))
                                .foregroundColor(.white)

                            if totalMediaCount > 0 {
                                Text("\(totalMediaCount)/5")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                            }
                            
                            // Hint for Live Photo support
                            if totalMediaCount == 0 {
                                Text("Photos & Live Photos")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.8))
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

    // MARK: - VLM Tags Section (disabled - TODO: Add VLMService.swift to project)
    @ViewBuilder
    private var vlmTagsSection: some View {
        EmptyView()
    }

    // MARK: - Total media count
    private var totalMediaCount: Int {
        selectedMediaItems.count
    }

    // MARK: - Enhance with Alice Button
    private var enhanceWithAliceButton: some View {
        Button(action: {
            requestEnhancement()
        }) {
            HStack(spacing: 6) {
                if isEnhancing {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 14, height: 14)
                } else {
                    Image("alice-center-icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                }

                Text(isEnhancing ? "Analyzing..." : "Enhance with alice")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.black)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
            )
        }
        .disabled(isEnhancing)
    }

    // MARK: - Request Enhancement from Alice
    private func requestEnhancement() {
        // Get the first image for analysis
        guard let firstImage = getFirstImage() else { return }

        isEnhancing = true
        enhanceError = nil

        Task {
            do {
                let suggestion = try await aliceService.enhancePost(
                    image: firstImage,
                    existingText: postText.isEmpty ? nil : postText,
                    includeTrending: true
                )

                await MainActor.run {
                    // Use suggestion directly - it's already PostEnhancementSuggestion type
                    enhanceSuggestion = suggestion
                    showEnhanceSuggestion = true
                    isEnhancing = false
                }

                // Also fetch channel suggestions based on Alice's analysis
                await fetchChannelSuggestions(
                    content: suggestion.description,
                    hashtags: suggestion.hashtags
                )
            } catch {
                await MainActor.run {
                    enhanceError = error.localizedDescription
                    isEnhancing = false
                }
                #if DEBUG
                print("[NewPost] Enhancement failed: \(error)")
                #endif
            }
        }
    }

    // MARK: - Fetch Channel Suggestions
    private func fetchChannelSuggestions(content: String, hashtags: [String]) async {
        await MainActor.run {
            isLoadingSuggestions = true
        }

        do {
            let suggestions = try await feedService.suggestChannels(
                content: content,
                hashtags: hashtags.map { "#\($0)" }
            )

            await MainActor.run {
                suggestedChannels = suggestions
                isLoadingSuggestions = false
                #if DEBUG
                print("[NewPost] Got \(suggestions.count) channel suggestions")
                #endif
            }
        } catch {
            await MainActor.run {
                isLoadingSuggestions = false
            }
            #if DEBUG
            print("[NewPost] Channel suggestion failed: \(error)")
            #endif
        }
    }

    // MARK: - Get First Image for Enhancement
    private func getFirstImage() -> UIImage? {
        selectedMediaItems.first?.displayImage
    }

    // MARK: - VLM Image Analysis (disabled - TODO: Add VLMService.swift to project)
    /*
    private func analyzeImageWithVLM() {
        guard let firstImage = getFirstImage() else { return }
        guard !isAnalyzingImage else { return }
        isAnalyzingImage = true
        // ... VLM analysis code disabled
    }
    */

    // MARK: - Toggle VLM Tag Selection (disabled)
    /*
    private func toggleVLMTag(_ tag: String) {
        if selectedVLMTags.contains(tag) {
            selectedVLMTags.remove(tag)
        } else {
            selectedVLMTags.insert(tag)
        }
    }
    */

    // MARK: - Process Selected Photos (with Live Photo support)
    private func processSelectedPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        
        await MainActor.run {
            isProcessingMedia = true
        }
        
        defer {
            Task { @MainActor in
                isProcessingMedia = false
                selectedPhotos = []  // Clear for next selection
            }
        }
        
        do {
            let maxToAdd = 5 - selectedMediaItems.count
            let newMedia = try await livePhotoManager.loadMedia(from: items, maxCount: maxToAdd)
            
            await MainActor.run {
                selectedMediaItems.append(contentsOf: newMedia)
                // Trigger VLM analysis when first image is added - TODO: re-enable
                // if !newMedia.isEmpty {
                //     analyzeImageWithVLM()
                // }
            }
        } catch {
            #if DEBUG
            print("[NewPost] Failed to process photos: \(error)")
            #endif
            
            // Fallback to regular image loading
            for item in items {
                guard selectedMediaItems.count < 5 else { break }

                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        selectedMediaItems.append(.image(image))
                    }
                }
            }
        }
    }
    
    // MARK: - Remove media item
    private func removeMediaItem(at index: Int) {
        guard index < selectedMediaItems.count else { return }

        let item = selectedMediaItems[index]

        // Clean up temporary files for Live Photos and videos
        switch item {
        case .livePhoto(let data):
            try? FileManager.default.removeItem(at: data.videoURL)
        case .video(let data):
            try? FileManager.default.removeItem(at: data.url)
        case .image:
            break
        }

        selectedMediaItems.remove(at: index)

        // Sync selectedPhotos if applicable
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
                                .font(.system(size: 14, weight: .medium))
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                // Channel selection button
                Button(action: {
                    showChannelPicker = true
                }) {
                    HStack(spacing: 6) {
                        Text("#")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(selectedChannelIds.isEmpty
                                ? Color(red: 0.27, green: 0.27, blue: 0.27)
                                : Color(red: 0.82, green: 0.13, blue: 0.25))

                        if selectedChannelIds.isEmpty {
                            Text("Add Channels")
                                .font(.system(size: 12))
                                .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
                        } else {
                            Text("\(selectedChannelIds.count) selected")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(red: 0.82, green: 0.13, blue: 0.25))
                        }

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(selectedChannelIds.isEmpty
                        ? Color(red: 0.91, green: 0.91, blue: 0.91)
                        : Color(red: 0.98, green: 0.95, blue: 0.96))
                    .cornerRadius(24)
                }

                Spacer()
            }

            // AI-suggested channels (show when available and no manual selection)
            if !suggestedChannels.isEmpty && selectedChannelIds.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .foregroundColor(Color(red: 0.82, green: 0.13, blue: 0.25))
                        Text("Suggested by Alice")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                    }

                    HStack(spacing: 8) {
                        ForEach(suggestedChannels) { suggestion in
                            Button(action: {
                                // Add suggested channel to selection
                                if !selectedChannelIds.contains(suggestion.id) && selectedChannelIds.count < 3 {
                                    selectedChannelIds.append(suggestion.id)
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Text("#\(suggestion.name)")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color(red: 0.82, green: 0.13, blue: 0.25))
                                    Text("\(Int(suggestion.confidence * 100))%")
                                        .font(.system(size: 10))
                                        .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(red: 0.98, green: 0.95, blue: 0.96))
                                .cornerRadius(16)
                            }
                        }

                        // Accept all button
                        if suggestedChannels.count > 1 {
                            Button(action: {
                                // Add all suggestions (up to 3)
                                for suggestion in suggestedChannels.prefix(3) {
                                    if !selectedChannelIds.contains(suggestion.id) {
                                        selectedChannelIds.append(suggestion.id)
                                    }
                                }
                            }) {
                                Text("Use All")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(red: 0.82, green: 0.13, blue: 0.25))
                                    .cornerRadius(16)
                            }
                        }
                    }
                }
            } else if isLoadingSuggestions {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Getting suggestions...")
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                }
            }
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
                .font(.system(size: 16))
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

            VStack(alignment: .leading, spacing: 6) {
                Text("Invite alice")
                    .font(.system(size: 16))
                    .lineSpacing(40.94)
                    .foregroundColor(.black)

                Text("add AI insight to this conversation")
                    .font(.system(size: 12))
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
                .font(.system(size: 12, weight: .medium))
                .lineSpacing(20)
                .foregroundColor(Color(red: 0.82, green: 0.13, blue: 0.25))

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
    }

    // MARK: - 是否可以发布
    private var canPost: Bool {
        !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedMediaItems.isEmpty
    }

    // MARK: - 是否有内容（用于判断是否显示保存弹窗）
    private var hasContent: Bool {
        !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedMediaItems.isEmpty
    }

    // MARK: - 保存草稿 (uses PostDraftManager for file-based storage)
    private func saveDraft() {
        Task {
            do {
                try await PostDraftManager.shared.saveDraft(
                    text: postText,
                    mediaItems: selectedMediaItems,
                    channelIds: selectedChannelIds
                )
            } catch {
                #if DEBUG
                print("[NewPost] Failed to save draft: \(error)")
                #endif
            }
        }
    }

    // MARK: - 清除草稿
    private func clearDraft() {
        Task {
            await PostDraftManager.shared.clearDraft()
        }
    }

    // MARK: - 加载草稿
    private func loadDraft() {
        Task {
            do {
                if let draft = try await PostDraftManager.shared.loadDraft() {
                    await MainActor.run {
                        postText = draft.text
                        selectedChannelIds = draft.channelIds
                    }
                    // Load media items from disk
                    let mediaItems = await PostDraftManager.shared.loadMediaForDraft(draft)
                    await MainActor.run {
                        selectedMediaItems = mediaItems
                    }
                }
            } catch {
                #if DEBUG
                print("[NewPost] Failed to load draft: \(error)")
                #endif
            }
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
    
    // MARK: - 异步调整图片大小（在背景线程执行）
    private func resizeImageForUploadAsync(_ image: UIImage, maxDimension: CGFloat = 1024) async -> UIImage {
        // Run image processing on a background thread to avoid blocking UI
        return await Task.detached(priority: .userInitiated) {
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
        }.value
    }

    // MARK: - Format video duration
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - 提交帖子
    private func submitPost() async {
        guard canPost else { return }

        // Try to get userId from currentUser first, fallback to storedUserId from Keychain
        guard let userId = authManager.currentUser?.id ?? authManager.storedUserId else {
            postError = "Please login first"
            return
        }

        let itemsToUpload: [PostMediaItem] = selectedMediaItems

        // For posts WITH media: Use background upload (user can continue using app)
        if !itemsToUpload.isEmpty {
            #if DEBUG
            print("[NewPost] Starting background upload for \(itemsToUpload.count) media item(s)")
            #endif

            // VLM tags disabled - TODO: re-enable
            // let tagsToSave = Array(selectedVLMTags)
            let channelsToSave = selectedChannelIds

            // Start background upload
            uploadManager.startUpload(
                mediaItems: itemsToUpload,
                postText: postText,
                channelIds: selectedChannelIds,
                nameType: selectedNameType,
                userId: userId,
                onSuccess: { [onPostSuccess] post in
                    // VLM tags update disabled - TODO: re-enable
                    onPostSuccess?(post)
                }
            )

            // Clear draft and dismiss immediately - upload continues in background
            clearDraft()
            showNewPost = false
            return
        }

        // For posts WITHOUT media: Create immediately (fast, no background needed)
        isPosting = true
        postError = nil

        do {
            let content = postText.trimmingCharacters(in: .whitespacesAndNewlines)
            var post: Post?
            var lastError: Error?

            for attempt in 1...3 {
                do {
                    post = try await contentService.createPost(
                        creatorId: userId,
                        content: content.isEmpty ? " " : content,
                        mediaUrls: nil,
                        channelIds: selectedChannelIds.isEmpty ? nil : selectedChannelIds
                    )
                    break
                } catch let error as APIError {
                    lastError = error
                    if case .serverError(let statusCode, _) = error, statusCode == 503 {
                        if attempt < 3 {
                            try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                            continue
                        }
                    }
                    throw error
                }
            }

            guard let createdPost = post else {
                throw lastError ?? APIError.serverError(statusCode: 503, message: "Service unavailable")
            }

            isPosting = false
            clearDraft()
            showNewPost = false
            onPostSuccess?(createdPost)

        } catch {
            isPosting = false
            postError = error.localizedDescription
            #if DEBUG
            print("[NewPost] Text-only post failed: \(error)")
            #endif
        }
    }

    // MARK: - Legacy inline upload (kept for reference/fallback)
    private func submitPostInline() async {
        guard canPost else { return }

        guard let userId = authManager.currentUser?.id ?? authManager.storedUserId else {
            postError = "Please login first"
            return
        }

        isPosting = true
        postError = nil
        uploadProgress = 0.0
        uploadStatus = "Preparing..."

        do {
            let itemsToUpload: [PostMediaItem] = selectedMediaItems

            guard !itemsToUpload.isEmpty else {
                // No media - handled by submitPost now
                return
            }

            // Separate regular images, Live Photos, and videos for different handling
            var regularImages: [(data: Data, filename: String, index: Int)] = []
            var livePhotos: [(data: LivePhotoData, index: Int)] = []
            var videos: [(data: VideoData, index: Int)] = []

            await MainActor.run {
                uploadStatus = "Processing media..."
            }

            var imagesToProcess: [(image: UIImage, index: Int)] = []
            for (index, item) in itemsToUpload.enumerated() {
                switch item {
                case .image(let image):
                    imagesToProcess.append((image: image, index: index))
                case .livePhoto(let livePhotoData):
                    livePhotos.append((data: livePhotoData, index: index))
                case .video(let videoData):
                    videos.append((data: videoData, index: index))
                }
            }

            if !imagesToProcess.isEmpty {
                #if DEBUG
                print("[NewPost] Compressing \(imagesToProcess.count) image(s)...")
                #endif

                await withTaskGroup(of: (data: Data, filename: String, index: Int)?.self) { group in
                    for imageInfo in imagesToProcess {
                        group.addTask {
                            // Use ImageCompressor for WebP format (25-35% smaller than JPEG)
                            let result = await self.imageCompressor.compressImage(
                                imageInfo.image,
                                quality: .low,  // 50% quality, max 1080px
                                format: .webp,
                                stripMetadata: false  // Preserve EXIF, GPS, and other metadata
                            )
                            #if DEBUG
                            print("[NewPost] WebP compressed: \(result.compressedSize / 1024) KB (saved \(String(format: "%.0f", result.savedPercentage))%)")
                            #endif
                            return (data: result.data, filename: result.filename, index: imageInfo.index)
                        }
                    }

                    for await result in group {
                        if let result = result {
                            regularImages.append(result)
                        }
                    }
                }
                // Sort by original index to maintain order
                regularImages.sort { $0.index < $1.index }
            }
            
            let totalItems = regularImages.count + livePhotos.count
            var completedItems = 0
            var uploadResults: [(index: Int, urls: [String])] = []
            
            // Upload regular images in parallel
            if !regularImages.isEmpty {
                await MainActor.run {
                    uploadStatus = "Uploading images..."
                }
                
                #if DEBUG
                print("[NewPost] Starting parallel upload of \(regularImages.count) images")
                #endif
                
                let imagesToUpload = regularImages.map { (data: $0.data, filename: $0.filename) }
                let batchResult = await mediaService.uploadImagesInParallel(
                    images: imagesToUpload,
                    maxConcurrent: 5,
                    progressCallback: { [totalItems] progress in
                        Task { @MainActor in
                            // Calculate overall progress (images take 80% of progress)
                            let imageWeight = Double(regularImages.count) / Double(totalItems)
                            self.uploadProgress = progress * 0.8 * imageWeight
                        }
                    }
                )
                
                // Process results maintaining order using urlsByIndex mapping
                for (arrayIndex, imageInfo) in regularImages.enumerated() {
                    if let url = batchResult.url(for: arrayIndex) {
                        uploadResults.append((index: imageInfo.index, urls: [url]))
                    }
                }
                
                completedItems += batchResult.urlsByIndex.count
                
                // Check for failures
                if !batchResult.failedIndices.isEmpty {
                    #if DEBUG
                    print("[NewPost] \(batchResult.failedIndices.count) image(s) failed to upload")
                    #endif
                    // Continue with successful uploads rather than failing entirely
                }
            }
            
            // Upload Live Photos (these need sequential handling due to image+video pairing)
            for (livePhotoIndex, livePhotoInfo) in livePhotos.enumerated() {
                await MainActor.run {
                    uploadStatus = "Uploading Live Photo \(livePhotoIndex + 1)/\(livePhotos.count)..."
                }

                // Use WebP compression for Live Photo still image
                let compressionResult = await imageCompressor.compressImage(
                    livePhotoInfo.data.stillImage,
                    quality: .low,  // 50% quality, max 1080px
                    format: .webp,
                    stripMetadata: false  // Preserve EXIF, GPS, and other metadata
                )

                #if DEBUG
                print("[NewPost] Live Photo WebP: \(compressionResult.compressedSize / 1024) KB (saved \(String(format: "%.0f", compressionResult.savedPercentage))%)")
                #endif

                var livePhotoResult: LivePhotoUploadResult?
                var lastError: Error? = nil

                for attempt in 1...3 {
                    do {
                        livePhotoResult = try await mediaService.uploadLivePhoto(
                            imageData: compressionResult.data,
                            videoURL: livePhotoInfo.data.videoURL,
                            imageFilename: compressionResult.filename
                        )
                        break
                    } catch let error as APIError {
                        lastError = error
                        if case .serverError(let statusCode, _) = error, statusCode == 503 {
                            #if DEBUG
                            print("[NewPost] Live Photo upload attempt \(attempt) failed with 503, retrying...")
                            #endif
                            if attempt < 3 {
                                try await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)
                                continue
                            }
                        }
                        throw error
                    }
                }
                
                if let result = livePhotoResult {
                    uploadResults.append((index: livePhotoInfo.index, urls: [result.imageUrl, result.videoUrl]))
                    completedItems += 1
                    
                    await MainActor.run {
                        let progress = Double(completedItems) / Double(totalItems)
                        uploadProgress = 0.8 * progress
                    }
                    
                    #if DEBUG
                    print("[NewPost] Live Photo uploaded - Image: \(result.imageUrl), Video: \(result.videoUrl)")
                    #endif
                }
            }
            
            // Sort results by original index to maintain order
            uploadResults.sort { $0.index < $1.index }
            let mediaUrls = uploadResults.flatMap { $0.urls }

            #if DEBUG
            print("[NewPost] Upload complete: \(mediaUrls.count) URLs")
            #endif

            // Step 2: 创建帖子 (带重试逻辑处理 503 错误)
            await MainActor.run {
                uploadProgress = 0.85
                uploadStatus = "Creating post..."
            }
            
            let content = postText.trimmingCharacters(in: .whitespacesAndNewlines)
            var post: Post?
            var lastError: Error?

            for attempt in 1...3 {
                do {
                    post = try await contentService.createPost(
                        creatorId: userId,
                        content: content.isEmpty ? " " : content,  // 至少需要空格
                        mediaUrls: mediaUrls.isEmpty ? nil : mediaUrls,
                        channelIds: selectedChannelIds.isEmpty ? nil : selectedChannelIds
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
                uploadProgress = 1.0
                uploadStatus = "Done!"
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
                uploadProgress = 0.0
                uploadStatus = ""
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

// MARK: - VLM Tag Chip
struct VLMTagChip: View {
    let tag: String
    let confidence: Float
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(tag)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .white : Color(red: 0.27, green: 0.27, blue: 0.27))

                // Confidence indicator (only show for high confidence)
                if confidence >= 0.8 {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : Color(red: 0.82, green: 0.13, blue: 0.25).opacity(0.6))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected
                        ? Color(red: 0.82, green: 0.13, blue: 0.25)
                        : Color(red: 0.91, green: 0.91, blue: 0.91))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout for Tags (disabled - duplicate with EnhanceSuggestionView)
// FlowLayout removed to avoid redeclaration - use shared version from EnhanceSuggestionView

#Preview {
    @Previewable @State var showNewPost = true
    NewPostView(showNewPost: $showNewPost)
        .environmentObject(AuthenticationManager.shared)
}
