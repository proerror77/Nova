import SwiftUI
import Combine
import UIKit
import Network

// MARK: - Upload Error Types

enum UploadError: LocalizedError {
    case noNetwork
    case maxRetriesExceeded
    case cancelled
    case allUploadsFailed(underlying: Error?)

    var errorDescription: String? {
        switch self {
        case .noNetwork:
            return "No network connection. Will retry when online."
        case .maxRetriesExceeded:
            return "Upload failed after multiple retries."
        case .cancelled:
            return "Upload was cancelled."
        case .allUploadsFailed(let underlying):
            if let error = underlying {
                return "All uploads failed: \(error.localizedDescription)"
            }
            return "All image uploads failed."
        }
    }
}

// MARK: - Upload Task Model

struct UploadTask: Identifiable {
    let id: UUID
    let mediaItems: [PostMediaItem]
    let postText: String
    let channelIds: [String]
    let nameType: NameDisplayType
    let location: String?
    let onSuccess: ((Post) -> Void)?

    var status: PostUploadStatus = .preparing
    var progress: Double = 0.0
    var statusMessage: String = "Preparing..."
    var error: String?
    var createdPost: Post?

    init(
        mediaItems: [PostMediaItem],
        postText: String,
        channelIds: [String],
        nameType: NameDisplayType,
        location: String?,
        onSuccess: ((Post) -> Void)?
    ) {
        self.id = UUID()
        self.mediaItems = mediaItems
        self.postText = postText
        self.channelIds = channelIds
        self.nameType = nameType
        self.location = location
        self.onSuccess = onSuccess
    }
}

enum PostUploadStatus: Equatable {
    case preparing
    case compressing
    case uploading
    case creatingPost
    case completed
    case failed

    var displayText: String {
        switch self {
        case .preparing: return "Preparing..."
        case .compressing: return "Compressing..."
        case .uploading: return "Uploading..."
        case .creatingPost: return "Creating post..."
        case .completed: return "Posted!"
        case .failed: return "Failed"
        }
    }
}

// MARK: - Background Upload Manager

@MainActor
final class BackgroundUploadManager: ObservableObject {
    static let shared = BackgroundUploadManager()

    // MARK: - Published Properties
    @Published private(set) var currentTask: UploadTask?
    @Published private(set) var isUploading: Bool = false
    @Published private(set) var showCompletionBanner: Bool = false
    @Published private(set) var completedPost: Post?
    @Published private(set) var isWaitingForNetwork: Bool = false

    // MARK: - Services
    private let mediaService = MediaService()
    private let contentService = ContentService()
    private let imageCompressor = ImageCompressor.shared

    // MARK: - Network Monitoring
    private let networkMonitor = NWPathMonitor()
    private let networkMonitorQueue = DispatchQueue(label: "com.icered.networkMonitor")
    private var isNetworkConnected: Bool = true

    // MARK: - Private Properties
    private var uploadCancellable: Task<Void, Never>?

    private init() {
        setupNetworkMonitor()
    }

    // MARK: - Network Monitoring Setup

    private func setupNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            let isConnected = path.status == .satisfied
            Task { @MainActor in
                self?.isNetworkConnected = isConnected
                if isConnected && self?.isWaitingForNetwork == true {
                    self?.isWaitingForNetwork = false
                    #if DEBUG
                    print("[BackgroundUpload] Network restored, resuming upload...")
                    #endif
                }
            }
        }
        networkMonitor.start(queue: networkMonitorQueue)
    }

    /// Wait for network connection with timeout
    private func waitForNetworkConnection(timeout: TimeInterval = 60) async -> Bool {
        let startTime = Date()

        while !isNetworkConnected {
            // Check timeout
            if Date().timeIntervalSince(startTime) > timeout {
                return false
            }

            // Check cancellation
            if Task.isCancelled {
                return false
            }

            // Update UI state
            if !isWaitingForNetwork {
                isWaitingForNetwork = true
                updateTask { $0.statusMessage = "Waiting for network..." }
            }

            // Wait before checking again
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }

        isWaitingForNetwork = false
        return true
    }

    // MARK: - Public Methods

    /// Start a background upload task
    func startUpload(
        mediaItems: [PostMediaItem],
        postText: String,
        channelIds: [String],
        nameType: NameDisplayType,
        userId: String,
        location: String?,
        onSuccess: ((Post) -> Void)?
    ) {
        // Cancel any existing upload
        uploadCancellable?.cancel()

        // Create new task
        var task = UploadTask(
            mediaItems: mediaItems,
            postText: postText,
            channelIds: channelIds,
            nameType: nameType,
            location: location,
            onSuccess: onSuccess
        )

        currentTask = task
        isUploading = true
        showCompletionBanner = false
        completedPost = nil

        // Start upload in background
        uploadCancellable = Task { [weak self] in
            await self?.performUpload(task: &task, userId: userId)
        }
    }

    /// Cancel the current upload
    func cancelUpload() {
        uploadCancellable?.cancel()
        uploadCancellable = nil
        currentTask = nil
        isUploading = false
    }

    /// Dismiss the completion banner
    func dismissCompletionBanner() {
        showCompletionBanner = false
        completedPost = nil
        currentTask = nil
    }

    // MARK: - Private Methods

    private func performUpload(task: inout UploadTask, userId: String) async {
        do {
            // Phase 1: Compress media
            updateTask { $0.status = .compressing; $0.statusMessage = "Compressing media..." }

            let mediaUrls = try await compressAndUploadMedia(
                items: task.mediaItems,
                onProgress: { [weak self] progress, message in
                    self?.updateTask { task in
                        task.progress = progress
                        task.statusMessage = message
                    }
                }
            )

            // Check for cancellation
            if Task.isCancelled { return }

            // Phase 2: Create post
            updateTask { $0.status = .creatingPost; $0.progress = 0.9; $0.statusMessage = "Creating post..." }

            let content = task.postText.trimmingCharacters(in: .whitespacesAndNewlines)

            // Determine the correct media type based on items
            let mediaType = Self.determineMediaType(from: task.mediaItems)

            let post = try await createPostWithRetry(
                userId: userId,
                content: content.isEmpty ? " " : content,
                mediaUrls: mediaUrls.isEmpty ? nil : mediaUrls,
                mediaType: mediaType,
                channelIds: task.channelIds.isEmpty ? nil : task.channelIds,
                location: task.location
            )

            // Check for cancellation
            if Task.isCancelled { return }

            // Success!
            updateTask { task in
                task.status = .completed
                task.progress = 1.0
                task.statusMessage = "Posted!"
                task.createdPost = post
            }

            completedPost = post
            isUploading = false
            // Don't show completion banner - user requested no popup after posting
            // showCompletionBanner = true

            // Call success callback
            task.onSuccess?(post)

            #if DEBUG
            print("[BackgroundUpload] Post created successfully: \(post.id)")
            #endif

        } catch {
            // Handle failure
            updateTask { task in
                task.status = .failed
                task.error = error.localizedDescription
                task.statusMessage = "Upload failed"
            }
            isUploading = false

            #if DEBUG
            print("[BackgroundUpload] Upload failed: \(error)")
            #endif
        }
    }

    private func updateTask(_ update: (inout UploadTask) -> Void) {
        guard var task = currentTask else { return }
        update(&task)
        currentTask = task
    }

    // MARK: - Media Type Detection

    /// Determine the correct media type string from an array of PostMediaItem
    /// - Returns: "image", "video", "live_photo", "mixed", or nil
    static func determineMediaType(from items: [PostMediaItem]) -> String? {
        guard !items.isEmpty else { return nil }

        // Count each type
        var hasImage = false
        var hasVideo = false
        var hasLivePhoto = false

        for item in items {
            switch item {
            case .image:
                hasImage = true
            case .video:
                hasVideo = true
            case .livePhoto:
                hasLivePhoto = true
            }
        }

        // Determine the type based on combinations
        // Single Live Photo
        if hasLivePhoto && !hasImage && !hasVideo && items.count == 1 {
            return "live_photo"
        }

        // Single or multiple images only
        if hasImage && !hasVideo && !hasLivePhoto {
            return "image"
        }

        // Single or multiple videos only
        if hasVideo && !hasImage && !hasLivePhoto {
            return "video"
        }

        // Mixed content (any combination of different types)
        return "mixed"
    }

    // MARK: - Media Compression & Upload

    private func compressAndUploadMedia(
        items: [PostMediaItem],
        onProgress: @escaping (Double, String) -> Void
    ) async throws -> [String] {
        guard !items.isEmpty else { return [] }

        var allUrls: [(index: Int, urls: [String])] = []
        let totalItems = items.count

        // Separate by type
        var imagesToProcess: [(image: UIImage, index: Int)] = []
        var livePhotos: [(data: LivePhotoData, index: Int)] = []
        var videos: [(data: VideoData, index: Int)] = []

        for (index, item) in items.enumerated() {
            switch item {
            case .image(let image, _):
                imagesToProcess.append((image: image, index: index))
            case .livePhoto(let data, _):
                livePhotos.append((data: data, index: index))
            case .video(let data, _):
                videos.append((data: data, index: index))
            }
        }

        var processedCount = 0

        // Process regular images with WebP compression
        if !imagesToProcess.isEmpty {
            onProgress(0.1, "Compressing images...")

            // Store original images alongside compressed data for pre-caching
            var compressedImages: [(data: Data, filename: String, index: Int, originalImage: UIImage)] = []

            await withTaskGroup(of: (data: Data, filename: String, index: Int, originalImage: UIImage)?.self) { group in
                for imageInfo in imagesToProcess {
                    group.addTask {
                        let result = await self.imageCompressor.compressImage(
                            imageInfo.image,
                            quality: .low,
                            format: .webp,
                            stripMetadata: false  // Keep metadata for now - stripping causes encoding issues
                        )
                        #if DEBUG
                        print("[BackgroundUpload] WebP: \(result.compressedSize / 1024) KB (saved \(String(format: "%.0f", result.savedPercentage))%)")
                        #endif
                        return (data: result.data, filename: result.filename, index: imageInfo.index, originalImage: imageInfo.image)
                    }
                }

                for await result in group {
                    if let result = result {
                        compressedImages.append(result)
                    }
                }
            }

            compressedImages.sort { $0.index < $1.index }

            // Upload images
            onProgress(0.3, "Uploading images...")

            let imagesToUpload = compressedImages.map { (data: $0.data, filename: $0.filename) }
            let batchResult = await mediaService.uploadImagesInParallel(
                images: imagesToUpload,
                maxConcurrent: 8,  // Increased for faster parallel uploads
                progressCallback: { progress in
                    let overallProgress = 0.3 + (progress * 0.4)
                    onProgress(overallProgress, "Uploading images...")
                }
            )

            // Check if all uploads failed
            if !batchResult.failedIndices.isEmpty && batchResult.urlsByIndex.isEmpty {
                // All uploads failed - throw with the first underlying error
                let firstError = batchResult.errors.values.first
                throw UploadError.allUploadsFailed(underlying: firstError)
            }

            for (arrayIndex, imageInfo) in compressedImages.enumerated() {
                if let url = batchResult.url(for: arrayIndex) {
                    allUrls.append((index: imageInfo.index, urls: [url]))
                    processedCount += 1

                    // Pre-cache the uploaded image with its URL to avoid CDN propagation delay issues
                    // This ensures the image is immediately available when the feed tries to display it
                    await ImageCacheService.shared.preCacheImage(imageInfo.originalImage, for: url)
                    #if DEBUG
                    print("[BackgroundUpload] Pre-cached image for URL: \(url)")
                    #endif
                }
            }

            // Log partial failures if any
            #if DEBUG
            if !batchResult.failedIndices.isEmpty {
                print("[BackgroundUpload] Warning: \(batchResult.failedIndices.count) image(s) failed to upload")
                for (index, error) in batchResult.errors {
                    print("[BackgroundUpload] Image \(index) failed: \(error.localizedDescription)")
                }
            }
            #endif
        }

        // Process Live Photos in parallel for faster upload
        if !livePhotos.isEmpty {
            onProgress(0.7, "Uploading Live Photos...")

            // Use task group for parallel Live Photo uploads
            // Include original stillImage for pre-caching
            await withTaskGroup(of: (index: Int, urls: [String]?, originalImage: UIImage?).self) { group in
                for livePhotoInfo in livePhotos {
                    group.addTask { [imageCompressor, mediaService] in
                        // Compress still image
                        let compressionResult = await imageCompressor.compressImage(
                            livePhotoInfo.data.stillImage,
                            quality: .low,
                            format: .webp,
                            stripMetadata: false  // Keep metadata for now
                        )

                        do {
                            let result = try await mediaService.uploadLivePhoto(
                                imageData: compressionResult.data,
                                videoURL: livePhotoInfo.data.videoURL,
                                imageFilename: compressionResult.filename
                            )
                            return (index: livePhotoInfo.index, urls: [result.imageUrl, result.videoUrl], originalImage: livePhotoInfo.data.stillImage)
                        } catch {
                            #if DEBUG
                            print("[BackgroundUpload] Live Photo upload failed: \(error)")
                            #endif
                            return (index: livePhotoInfo.index, urls: nil, originalImage: nil)
                        }
                    }
                }

                // Collect results
                for await result in group {
                    if let urls = result.urls {
                        allUrls.append((index: result.index, urls: urls))
                        processedCount += 1

                        // Pre-cache the Live Photo still image with its URL
                        if let originalImage = result.originalImage, urls.count > 0 {
                            let imageUrl = urls[0]
                            await ImageCacheService.shared.preCacheImage(originalImage, for: imageUrl)
                            #if DEBUG
                            print("[BackgroundUpload] Pre-cached Live Photo still image for URL: \(imageUrl)")
                            #endif
                        }
                    }
                }
            }

            onProgress(0.85, "Live Photos uploaded")
        }

        // Process Videos
        for (videoIndex, videoInfo) in videos.enumerated() {
            onProgress(0.85 + Double(videoIndex) / Double(totalItems) * 0.1, "Uploading video...")

            do {
                // Read video data from URL
                let videoData = try Data(contentsOf: videoInfo.data.url)
                let filename = "video_\(UUID().uuidString).mp4"

                // Upload video
                let videoUrl = try await mediaService.uploadVideo(
                    videoData: videoData,
                    filename: filename
                )

                // Upload thumbnail as separate image
                let thumbnailData = videoInfo.data.thumbnail.jpegData(compressionQuality: 0.7) ?? Data()
                let thumbnailUrl = try await mediaService.uploadImage(
                    imageData: thumbnailData,
                    filename: "thumb_\(UUID().uuidString).jpg"
                )

                allUrls.append((index: videoInfo.index, urls: [videoUrl, thumbnailUrl]))
                processedCount += 1
            } catch {
                #if DEBUG
                print("[BackgroundUpload] Video upload failed: \(error)")
                #endif
            }
        }

        // Sort and flatten URLs
        allUrls.sort { $0.index < $1.index }
        return allUrls.flatMap { $0.urls }
    }

    // MARK: - Post Creation with Retry and Network Resilience

    private func createPostWithRetry(
        userId: String,
        content: String,
        mediaUrls: [String]?,
        mediaType: String?,
        channelIds: [String]?,
        location: String?
    ) async throws -> Post {
        var lastError: Error?
        let maxRetries = 5
        var backoffDelay: UInt64 = 1_000_000_000 // 1 second

        for attempt in 1...maxRetries {
            // Check for cancellation
            if Task.isCancelled {
                throw UploadError.cancelled
            }

            // Wait for network if disconnected
            if !isNetworkConnected {
                #if DEBUG
                print("[BackgroundUpload] No network, waiting for connection...")
                #endif
                updateTask { $0.statusMessage = "Waiting for network..." }

                let networkRestored = await waitForNetworkConnection(timeout: 120)
                if !networkRestored {
                    throw UploadError.noNetwork
                }

                updateTask { $0.statusMessage = "Creating post..." }
            }

            do {
                let post = try await contentService.createPost(
                    creatorId: userId,
                    content: content,
                    mediaUrls: mediaUrls,
                    mediaType: mediaType,
                    channelIds: channelIds,
                    location: location
                )
                return post
            } catch let error as APIError {
                lastError = error

                // Check if error is retryable
                let isRetryable: Bool
                switch error {
                case .networkError, .timeout, .noConnection:
                    isRetryable = true
                case .serverError(let statusCode, _):
                    isRetryable = statusCode >= 500
                default:
                    isRetryable = false
                }

                if isRetryable && attempt < maxRetries {
                    #if DEBUG
                    print("[BackgroundUpload] Post creation attempt \(attempt) failed, retrying in \(backoffDelay / 1_000_000_000)s...")
                    #endif

                    updateTask { $0.statusMessage = "Retrying... (\(attempt)/\(maxRetries))" }

                    try? await Task.sleep(nanoseconds: backoffDelay)
                    backoffDelay = min(backoffDelay * 2, 30_000_000_000) // Max 30 seconds
                    continue
                }

                throw error
            } catch {
                // Network error - wait and retry
                if attempt < maxRetries {
                    #if DEBUG
                    print("[BackgroundUpload] Network error on attempt \(attempt), waiting for connection...")
                    #endif

                    let networkRestored = await waitForNetworkConnection(timeout: 60)
                    if networkRestored {
                        continue
                    }
                }
                throw error
            }
        }

        throw lastError ?? UploadError.maxRetriesExceeded
    }

    // MARK: - Resilient Media Upload

    /// Upload media with network resilience and automatic retry
    private func uploadMediaWithRetry<T>(
        operation: @escaping () async throws -> T,
        operationName: String,
        maxRetries: Int = 5
    ) async throws -> T {
        var lastError: Error?
        var backoffDelay: UInt64 = 1_000_000_000 // 1 second

        for attempt in 1...maxRetries {
            // Check for cancellation
            if Task.isCancelled {
                throw UploadError.cancelled
            }

            // Wait for network if disconnected
            if !isNetworkConnected {
                #if DEBUG
                print("[BackgroundUpload] \(operationName): No network, waiting...")
                #endif

                let networkRestored = await waitForNetworkConnection(timeout: 120)
                if !networkRestored {
                    throw UploadError.noNetwork
                }
            }

            do {
                return try await operation()
            } catch {
                lastError = error

                // Check if we should retry
                let shouldRetry: Bool
                if let apiError = error as? APIError {
                    switch apiError {
                    case .networkError, .timeout, .noConnection:
                        shouldRetry = true
                    case .serverError(let statusCode, _):
                        shouldRetry = statusCode >= 500
                    default:
                        shouldRetry = false
                    }
                } else {
                    // Assume network-related errors are retryable
                    shouldRetry = true
                }

                if shouldRetry && attempt < maxRetries {
                    #if DEBUG
                    print("[BackgroundUpload] \(operationName) attempt \(attempt) failed: \(error.localizedDescription)")
                    #endif

                    try? await Task.sleep(nanoseconds: backoffDelay)
                    backoffDelay = min(backoffDelay * 2, 30_000_000_000) // Max 30 seconds
                    continue
                }

                throw error
            }
        }

        throw lastError ?? UploadError.maxRetriesExceeded
    }
}
