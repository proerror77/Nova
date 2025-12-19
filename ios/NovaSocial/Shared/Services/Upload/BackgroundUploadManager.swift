import SwiftUI
import Combine
import UIKit

// MARK: - Upload Task Model

struct UploadTask: Identifiable {
    let id: UUID
    let mediaItems: [PostMediaItem]
    let postText: String
    let channelIds: [String]
    let nameType: NameDisplayType
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
        onSuccess: ((Post) -> Void)?
    ) {
        self.id = UUID()
        self.mediaItems = mediaItems
        self.postText = postText
        self.channelIds = channelIds
        self.nameType = nameType
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

    // MARK: - Services
    private let mediaService = MediaService()
    private let contentService = ContentService()
    private let imageCompressor = ImageCompressor.shared

    // MARK: - Private Properties
    private var uploadCancellable: Task<Void, Never>?

    private init() {}

    // MARK: - Public Methods

    /// Start a background upload task
    func startUpload(
        mediaItems: [PostMediaItem],
        postText: String,
        channelIds: [String],
        nameType: NameDisplayType,
        userId: String,
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
            let post = try await createPostWithRetry(
                userId: userId,
                content: content.isEmpty ? " " : content,
                mediaUrls: mediaUrls.isEmpty ? nil : mediaUrls,
                channelIds: task.channelIds.isEmpty ? nil : task.channelIds
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
            showCompletionBanner = true

            // Call success callback
            task.onSuccess?(post)

            // Auto-dismiss banner after 3 seconds
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                dismissCompletionBanner()
            }

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
            case .image(let image):
                imagesToProcess.append((image: image, index: index))
            case .livePhoto(let data):
                livePhotos.append((data: data, index: index))
            case .video(let data):
                videos.append((data: data, index: index))
            }
        }

        var processedCount = 0

        // Process regular images with WebP compression
        if !imagesToProcess.isEmpty {
            onProgress(0.1, "Compressing images...")

            var compressedImages: [(data: Data, filename: String, index: Int)] = []

            await withTaskGroup(of: (data: Data, filename: String, index: Int)?.self) { group in
                for imageInfo in imagesToProcess {
                    group.addTask {
                        let result = await self.imageCompressor.compressImage(
                            imageInfo.image,
                            quality: .low,
                            format: .webp,
                            stripMetadata: true
                        )
                        #if DEBUG
                        print("[BackgroundUpload] WebP: \(result.compressedSize / 1024) KB (saved \(String(format: "%.0f", result.savedPercentage))%)")
                        #endif
                        return (data: result.data, filename: result.filename, index: imageInfo.index)
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
                maxConcurrent: 5,
                progressCallback: { progress in
                    let overallProgress = 0.3 + (progress * 0.4)
                    onProgress(overallProgress, "Uploading images...")
                }
            )

            for (arrayIndex, imageInfo) in compressedImages.enumerated() {
                if let url = batchResult.url(for: arrayIndex) {
                    allUrls.append((index: imageInfo.index, urls: [url]))
                    processedCount += 1
                }
            }
        }

        // Process Live Photos
        for (livePhotoIndex, livePhotoInfo) in livePhotos.enumerated() {
            onProgress(0.7 + Double(livePhotoIndex) / Double(totalItems) * 0.15, "Uploading Live Photo...")

            let compressionResult = await imageCompressor.compressImage(
                livePhotoInfo.data.stillImage,
                quality: .low,
                format: .webp,
                stripMetadata: true
            )

            do {
                let result = try await mediaService.uploadLivePhoto(
                    imageData: compressionResult.data,
                    videoURL: livePhotoInfo.data.videoURL,
                    imageFilename: compressionResult.filename
                )
                allUrls.append((index: livePhotoInfo.index, urls: [result.imageUrl, result.videoUrl]))
                processedCount += 1
            } catch {
                #if DEBUG
                print("[BackgroundUpload] Live Photo upload failed: \(error)")
                #endif
            }
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

    // MARK: - Post Creation with Retry

    private func createPostWithRetry(
        userId: String,
        content: String,
        mediaUrls: [String]?,
        channelIds: [String]?
    ) async throws -> Post {
        var lastError: Error?

        for attempt in 1...3 {
            do {
                let post = try await contentService.createPost(
                    creatorId: userId,
                    content: content,
                    mediaUrls: mediaUrls,
                    channelIds: channelIds
                )
                return post
            } catch let error as APIError {
                lastError = error
                if case .serverError(let statusCode, _) = error, statusCode == 503 {
                    #if DEBUG
                    print("[BackgroundUpload] Post creation attempt \(attempt) failed with 503, retrying...")
                    #endif
                    if attempt < 3 {
                        try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                        continue
                    }
                }
                throw error
            } catch {
                throw error
            }
        }

        throw lastError ?? APIError.serverError(statusCode: 503, message: "Service unavailable")
    }
}
