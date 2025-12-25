import SwiftUI
import PhotosUI

// MARK: - NewPostViewModel
/// ViewModel for NewPostView - handles all state and business logic for creating posts

@MainActor
@Observable
final class NewPostViewModel {

    // MARK: - Published State

    // Core post content
    var postText: String = ""
    var inviteAlice: Bool = false
    var selectedMediaItems: [PostMediaItem] = []
    var selectedPhotos: [PhotosPickerItem] = []

    // UI State
    var showPhotoPicker = false
    var showCamera = false
    var showNameSelector = false
    var showLocationPicker = false
    var showSaveDraftModal = false
    var showChannelPicker = false
    var showEnhanceSuggestion = false
    var isTextEditorFocused = false

    // Loading States
    var isProcessingMedia = false
    var isPosting = false
    var isEnhancing = false
    var isLoadingSuggestions = false
    var isAnalyzingImage = false

    // Progress & Status
    var uploadProgress: Double = 0.0
    var uploadStatus: String = ""
    var postError: String?
    var enhanceError: String?

    // Selections
    var selectedNameType: NameDisplayType = .realName
    var selectedLocation: String = ""
    var selectedChannelIds: [String] = []
    var selectedVLMTags: Set<String> = []

    // Suggestions
    var suggestedChannels: [ChannelSuggestion] = []
    var vlmTags: [TagSuggestion] = []
    var vlmChannelSuggestions: [ChannelSuggestion] = []
    var enhanceSuggestion: PostEnhancementSuggestion?

    // MARK: - Services

    private let mediaService = MediaService()
    private let contentService = ContentService()
    private let livePhotoManager = LivePhotoManager.shared
    private let aliceService = AliceService.shared
    private let feedService = FeedService()
    let vlmService = VLMService.shared
    private let imageCompressor = ImageCompressor.shared
    let uploadManager = BackgroundUploadManager.shared

    // MARK: - Dependencies

    private weak var authManager: AuthenticationManager?

    // MARK: - Callbacks

    var onPostSuccess: ((Post) -> Void)?
    var onDismiss: (() -> Void)?

    // MARK: - Computed Properties

    var totalMediaCount: Int {
        selectedMediaItems.count
    }

    var canPost: Bool {
        let hasTextContent = !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasMedia = !selectedMediaItems.isEmpty
        return (hasTextContent || hasMedia) && !isPosting
    }

    var hasContent: Bool {
        !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedMediaItems.isEmpty
    }

    var displayedName: String {
        if selectedNameType == .realName {
            return authManager?.currentUser?.displayName ?? authManager?.currentUser?.username ?? "User"
        } else {
            return "Dreamer"
        }
    }

    // MARK: - Initialization

    init() {}

    func configure(
        authManager: AuthenticationManager,
        initialMediaItems: [PostMediaItem]? = nil,
        initialImage: UIImage? = nil,
        onPostSuccess: ((Post) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.authManager = authManager
        self.onPostSuccess = onPostSuccess
        self.onDismiss = onDismiss

        // Handle initial media items (from PhotosPicker)
        if let mediaItems = initialMediaItems, !mediaItems.isEmpty, selectedMediaItems.isEmpty {
            selectedMediaItems = mediaItems
            analyzeImageWithVLM()
        }
        // Handle initial image (from PhotoOptionsModal)
        else if let image = initialImage, selectedMediaItems.isEmpty {
            selectedMediaItems = [.image(image)]
            analyzeImageWithVLM()
        }
        // No initial media - try to load draft
        else if initialMediaItems == nil && initialImage == nil {
            loadDraft()
        }
    }

    // MARK: - Media Management

    func processSelectedPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }

        isProcessingMedia = true

        defer {
            Task { @MainActor in
                isProcessingMedia = false
                selectedPhotos = []  // Clear for next selection
            }
        }

        do {
            let maxToAdd = 5 - selectedMediaItems.count
            let newMedia = try await livePhotoManager.loadMedia(from: items, maxCount: maxToAdd)

            selectedMediaItems.append(contentsOf: newMedia)
            // Trigger VLM analysis when first image is added
            if !newMedia.isEmpty && vlmTags.isEmpty {
                analyzeImageWithVLM()
            }
        } catch {
            #if DEBUG
            print("[NewPostViewModel] Failed to process photos: \(error)")
            #endif

            // Fallback to regular image loading
            for item in items {
                guard selectedMediaItems.count < 5 else { break }

                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedMediaItems.append(.image(image))
                }
            }
        }
    }

    func removeMediaItem(at index: Int) {
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

        // Clear VLM tags if no media left
        if selectedMediaItems.isEmpty {
            vlmTags = []
            selectedVLMTags = []
            vlmChannelSuggestions = []
        }
    }

    func getFirstImage() -> UIImage? {
        selectedMediaItems.first?.displayImage
    }

    // MARK: - VLM Analysis

    func analyzeImageWithVLM() {
        guard let firstImage = getFirstImage() else { return }
        guard !isAnalyzingImage else { return }

        isAnalyzingImage = true
        vlmTags = []
        vlmChannelSuggestions = []

        Task {
            do {
                // Compress image for upload
                let compressionResult = await imageCompressor.compressImage(firstImage, quality: .low)
                let imageData = compressionResult.data
                let filename = "vlm_\(UUID().uuidString).\(compressionResult.format.fileExtension)"

                // Upload to get URL
                let imageUrl = try await mediaService.uploadImage(imageData: imageData, filename: filename)

                // Call VLM API
                let result = try await vlmService.analyzeImage(
                    imageUrl: imageUrl,
                    includeChannels: true,
                    maxTags: 15
                )

                await MainActor.run {
                    vlmTags = result.tags
                    vlmChannelSuggestions = result.channels ?? []

                    // Auto-select high confidence tags (>80%)
                    for tag in result.tags where tag.confidence >= 0.8 {
                        selectedVLMTags.insert(tag.tag)
                    }

                    // Auto-suggest channels if none selected
                    if selectedChannelIds.isEmpty, let topChannel = vlmChannelSuggestions.first {
                        selectedChannelIds = [topChannel.id]
                    }

                    isAnalyzingImage = false
                }

                #if DEBUG
                print("[NewPostViewModel] VLM analysis complete: \(result.tags.count) tags, \(result.channels?.count ?? 0) channels")
                #endif
            } catch {
                #if DEBUG
                print("[NewPostViewModel] VLM analysis failed: \(error)")
                #endif
                await MainActor.run {
                    isAnalyzingImage = false
                }
            }
        }
    }

    func toggleVLMTag(_ tag: String) {
        if selectedVLMTags.contains(tag) {
            selectedVLMTags.remove(tag)
        } else {
            selectedVLMTags.insert(tag)
        }
    }

    // MARK: - AI Enhancement

    func requestEnhancement() {
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
                print("[NewPostViewModel] Enhancement failed: \(error)")
                #endif
            }
        }
    }

    func applyEnhancement(_ selectedText: String) {
        postText = selectedText
        showEnhanceSuggestion = false
    }

    // MARK: - Channel Suggestions

    func fetchChannelSuggestions(content: String, hashtags: [String]) async {
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
                print("[NewPostViewModel] Got \(suggestions.count) channel suggestions")
                #endif
            }
        } catch {
            await MainActor.run {
                isLoadingSuggestions = false
            }
            #if DEBUG
            print("[NewPostViewModel] Channel suggestion failed: \(error)")
            #endif
        }
    }

    // MARK: - Post Submission

    func submitPost() async {
        guard canPost else { return }

        // Try to get userId from currentUser first, fallback to storedUserId from Keychain
        guard let userId = authManager?.currentUser?.id ?? authManager?.storedUserId else {
            postError = "Please login first"
            return
        }

        let itemsToUpload: [PostMediaItem] = selectedMediaItems

        // For posts WITH media: Use background upload (user can continue using app)
        if !itemsToUpload.isEmpty {
            #if DEBUG
            print("[NewPostViewModel] Starting background upload for \(itemsToUpload.count) media item(s)")
            #endif

            // VLM tags to save after post creation
            let tagsToSave = Array(selectedVLMTags)
            let channelsToSave = selectedChannelIds

            // Start background upload
            uploadManager.startUpload(
                mediaItems: itemsToUpload,
                postText: postText,
                channelIds: selectedChannelIds,
                nameType: selectedNameType,
                userId: userId,
                onSuccess: { [onPostSuccess, vlmService] post in
                    // Update VLM tags after post is created
                    if !tagsToSave.isEmpty {
                        Task {
                            do {
                                _ = try await vlmService.updatePostTags(
                                    postId: post.id,
                                    tags: tagsToSave,
                                    channelIds: channelsToSave
                                )
                                #if DEBUG
                                print("[NewPostViewModel] VLM tags saved: \(tagsToSave)")
                                #endif
                            } catch {
                                #if DEBUG
                                print("[NewPostViewModel] Failed to save VLM tags: \(error)")
                                #endif
                            }
                        }
                    }
                    onPostSuccess?(post)
                }
            )

            // Clear draft and dismiss immediately - upload continues in background
            clearDraft()
            onDismiss?()
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
            onDismiss?()
            onPostSuccess?(createdPost)

        } catch {
            isPosting = false
            postError = error.localizedDescription
            #if DEBUG
            print("[NewPostViewModel] Text-only post failed: \(error)")
            #endif
        }
    }

    // MARK: - Draft Management (uses PostDraftManager for file-based storage)

    func saveDraft() {
        Task {
            do {
                try await PostDraftManager.shared.saveDraft(
                    text: postText,
                    mediaItems: selectedMediaItems,
                    channelIds: selectedChannelIds
                )
            } catch {
                #if DEBUG
                print("[NewPostViewModel] Failed to save draft: \(error)")
                #endif
            }
        }
    }

    func clearDraft() {
        Task {
            await PostDraftManager.shared.clearDraft()
        }
    }

    func loadDraft() {
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
                print("[NewPostViewModel] Failed to load draft: \(error)")
                #endif
            }
        }
    }

    // MARK: - Helper Methods

    func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    func handleCancelTapped() {
        if hasContent {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showSaveDraftModal = true
            }
        } else {
            onDismiss?()
        }
    }

    func handleSaveDraftNo() {
        clearDraft()
        onDismiss?()
    }

    func handleSaveDraftYes() {
        saveDraft()
        onDismiss?()
    }

    // MARK: - Reset

    func reset() {
        postText = ""
        inviteAlice = false
        selectedMediaItems = []
        selectedPhotos = []
        selectedNameType = .realName
        selectedLocation = ""
        selectedChannelIds = []
        selectedVLMTags = []
        vlmTags = []
        vlmChannelSuggestions = []
        suggestedChannels = []
        enhanceSuggestion = nil
        postError = nil
        enhanceError = nil
        isPosting = false
        uploadProgress = 0.0
        uploadStatus = ""
    }
}
