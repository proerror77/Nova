import SwiftUI
import PhotosUI

struct NewPostView: View {
    @Binding var showNewPost: Bool
    var initialMediaItems: [PostMediaItem]? = nil  // Live Photo items from PhotosPicker
    var initialImage: UIImage? = nil  // 从PhotoOptionsModal传入的图片
    var onPostSuccess: ((Post) -> Void)? = nil  // 成功发布后的回调，传递创建的Post对象

    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var viewModel = NewPostViewModel()

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
                    viewModel.hideKeyboard()
                }

                // MARK: - Error Message
                if let error = viewModel.postError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
            }
        }
        .sheet(isPresented: $viewModel.showCamera) {
            ImagePicker(sourceType: .camera, selectedImage: .constant(nil))
        }
        // PhotosPicker with Live Photo and video support
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
            }
        }
        .sheet(isPresented: $viewModel.showChannelPicker) {
            ChannelPickerView(
                selectedChannelIds: $viewModel.selectedChannelIds,
                isPresented: $viewModel.showChannelPicker
            )
        }
    }

    // MARK: - Top Navigation Bar
    private var topNavigationBar: some View {
        HStack {
            // Cancel 按钮
            Button(action: {
                viewModel.handleCancelTapped()
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
                    await viewModel.submitPost()
                }
            }) {
                if viewModel.isPosting {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(Color(red: 0.87, green: 0.11, blue: 0.26))
                } else {
                    Text("Post")
                        .font(.system(size: 14))
                        .lineSpacing(20)
                        .foregroundColor(viewModel.canPost ? Color(red: 0.87, green: 0.11, blue: 0.26) : Color(red: 0.53, green: 0.53, blue: 0.53))
                }
            }
            .disabled(!viewModel.canPost || viewModel.isPosting)
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
            vlmTagsSection  // VLM-generated tags
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

            if viewModel.inviteAlice {
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
            Text(viewModel.displayedName)
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
            viewModel.showNameSelector = true
        }
    }

    // MARK: - Image Preview Section (with Live Photo support)
    private var imagePreviewSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                // Processing indicator
                if viewModel.isProcessingMedia {
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
                ForEach(Array(viewModel.selectedMediaItems.enumerated()), id: \.element.id) { index, mediaItem in
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
                                        viewModel.removeMediaItem(at: index)
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
                                    Text(viewModel.formatDuration(videoData.duration))
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
                                    viewModel.removeMediaItem(at: index)
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
                if viewModel.totalMediaCount < 5 && !viewModel.isProcessingMedia {
                    ZStack {
                        Rectangle()
                            .foregroundColor(.clear)
                            .frame(width: viewModel.totalMediaCount == 0 ? 239 : 100, height: viewModel.totalMediaCount == 0 ? 290 : 210)
                            .background(Color(red: 0.91, green: 0.91, blue: 0.91))
                            .cornerRadius(10)

                        VStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 30, weight: .light))
                                .foregroundColor(.white)

                            if viewModel.totalMediaCount > 0 {
                                Text("\(viewModel.totalMediaCount)/5")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                            }

                            // Hint for Live Photo support
                            if viewModel.totalMediaCount == 0 {
                                Text("Photos & Live Photos")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                    .onTapGesture {
                        viewModel.showPhotoPicker = true
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 16)
    }

    // MARK: - VLM Tags Section
    @ViewBuilder
    private var vlmTagsSection: some View {
        if viewModel.isAnalyzingImage || !viewModel.vlmTags.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("AI Suggested Tags")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))

                    if viewModel.isAnalyzingImage {
                        ProgressView()
                            .scaleEffect(0.7)
                    }

                    Spacer()

                    if !viewModel.vlmTags.isEmpty {
                        Text("\(viewModel.selectedVLMTags.count) selected")
                            .font(.system(size: 12))
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

    // MARK: - Enhance with Alice Button
    private var enhanceWithAliceButton: some View {
        Button(action: {
            viewModel.requestEnhancement()
        }) {
            HStack(spacing: 6) {
                if viewModel.isEnhancing {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 14, height: 14)
                } else {
                    Image("alice-center-icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                }

                Text(viewModel.isEnhancing ? "Analyzing..." : "Enhance with alice")
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
        .disabled(viewModel.isEnhancing)
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
                    text: $viewModel.postText,
                    placeholder: "What do you want to talk about?",
                    textColor: UIColor(red: 0.38, green: 0.37, blue: 0.37, alpha: 1),
                    placeholderColor: UIColor(red: 0.38, green: 0.37, blue: 0.37, alpha: 1),
                    font: .systemFont(ofSize: 14),
                    onFocusChange: { focused in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            viewModel.isTextEditorFocused = focused
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
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(viewModel.selectedChannelIds.isEmpty
                                ? Color(red: 0.27, green: 0.27, blue: 0.27)
                                : Color(red: 0.82, green: 0.13, blue: 0.25))

                        if viewModel.selectedChannelIds.isEmpty {
                            Text("Add Channels")
                                .font(.system(size: 12))
                                .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
                        } else {
                            Text("\(viewModel.selectedChannelIds.count) selected")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(red: 0.82, green: 0.13, blue: 0.25))
                        }

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
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
                            .font(.system(size: 11))
                            .foregroundColor(Color(red: 0.82, green: 0.13, blue: 0.25))
                        Text("Suggested by Alice")
                            .font(.system(size: 11, weight: .medium))
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
            } else if viewModel.isLoadingSuggestions {
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

            Text(viewModel.selectedLocation.isEmpty ? "Check in" : viewModel.selectedLocation)
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
            viewModel.showLocationPicker = true
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

            Toggle("", isOn: $viewModel.inviteAlice)
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
}

// MARK: - Flow Layout for Tags (disabled - duplicate with EnhanceSuggestionView)
// FlowLayout removed to avoid redeclaration - use shared version from EnhanceSuggestionView

#Preview {
    @Previewable @State var showNewPost = true
    NewPostView(showNewPost: $showNewPost)
        .environmentObject(AuthenticationManager.shared)
}
