import Foundation
import SwiftUI
import PhotosUI
import AVFoundation

/// 创建帖子的 ViewModel
/// 支持图片和视频上传
@MainActor
final class CreatePostViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var selectedImage: UIImage?
    @Published var selectedVideoURL: URL?
    @Published var selectedMediaType: MediaType?
    @Published var caption = ""
    @Published var isUploading = false
    @Published var uploadProgress: Double = 0
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var showImagePicker = false
    @Published var videoThumbnail: UIImage?
    @Published var videoDuration: String = ""
    @Published var videoFileSize: String = ""

    // MARK: - Dependencies
    private let postRepository: PostRepository
    private let mediaUploadManager: MediaUploadManager
    private let videoManager: VideoManager

    // MARK: - Computed Properties
    var canPost: Bool {
        (selectedImage != nil || selectedVideoURL != nil) && !isUploading && !caption.isEmpty
    }

    var mediaDescription: String {
        switch selectedMediaType {
        case .image:
            return "Photo"
        case .video:
            return "Video"
        case .none:
            return "No media selected"
        }
    }

    // MARK: - Initialization
    init(
        postRepository: PostRepository = PostRepository(),
        mediaUploadManager: MediaUploadManager = .shared,
        videoManager: VideoManager = .shared
    ) {
        self.postRepository = postRepository
        self.mediaUploadManager = mediaUploadManager
        self.videoManager = videoManager
    }

    // MARK: - Public Methods

    func createPost() async -> Bool {
        guard let mediaType = selectedMediaType else {
            showErrorMessage("Please select an image or video")
            return false
        }

        isUploading = true
        uploadProgress = 0
        errorMessage = nil

        do {
            let contentType = mediaType.contentType

            // 1. Get upload URL
            uploadProgress = 0.2
            let uploadInfo = try await postRepository.getUploadURL(
                contentType: contentType
            )

            // 2. Prepare and upload media
            uploadProgress = 0.4
            let mediaData: MediaData

            switch mediaType {
            case .image:
                guard let image = selectedImage else {
                    throw NSError(domain: "ImageError", code: -1)
                }
                mediaData = .image(image)

            case .video:
                guard let videoURL = selectedVideoURL else {
                    throw NSError(domain: "VideoError", code: -1)
                }
                mediaData = .video(videoURL)
            }

            // 使用 MediaUploadManager 上传
            let taskId = mediaUploadManager.uploadMedia(
                mediaData,
                to: uploadInfo.uploadUrl
            )

            // 监听上传进度
            uploadProgress = 0.7
            try await waitForUploadCompletion(taskId: taskId)

            // 3. Create post
            uploadProgress = 0.9
            _ = try await postRepository.createPost(
                fileKey: uploadInfo.fileKey,
                caption: caption.isEmpty ? nil : caption
            )

            uploadProgress = 1.0
            isUploading = false

            // Reset form
            selectedImage = nil
            selectedVideoURL = nil
            selectedMediaType = nil
            caption = ""
            videoThumbnail = nil
            videoDuration = ""
            videoFileSize = ""

            return true
        } catch {
            showErrorMessage(error.localizedDescription)
            isUploading = false
            return false
        }
    }

    func selectImage(_ image: UIImage) {
        selectedImage = image
        selectedVideoURL = nil
        selectedMediaType = .image
        videoThumbnail = nil
        videoDuration = ""
        videoFileSize = ""
    }

    func selectVideo(_ url: URL) {
        selectedVideoURL = url
        selectedImage = nil
        selectedMediaType = .video

        Task {
            await loadVideoMetadata(url)
        }
    }

    func removeMedia() {
        selectedImage = nil
        selectedVideoURL = nil
        selectedMediaType = nil
        videoThumbnail = nil
        videoDuration = ""
        videoFileSize = ""
    }

    func clearError() {
        errorMessage = nil
        showError = false
    }

    // MARK: - Private Helpers

    private func loadVideoMetadata(_ url: URL) async {
        do {
            let videoInfo = try await videoManager.getVideoInfo(from: url)
            let thumbnail = try await videoManager.generateThumbnail(from: url)

            self.videoThumbnail = thumbnail
            self.videoDuration = videoInfo.durationFormatted
            self.videoFileSize = videoInfo.fileSizeFormatted
        } catch {
            showErrorMessage("Failed to load video metadata: \(error.localizedDescription)")
        }
    }

    private func waitForUploadCompletion(taskId: String) async throws {
        // 等待上传完成（最多 5 分钟）
        let maxWaitTime: UInt64 = 5 * 60 * 1_000_000_000 // 5 分钟
        let startTime = Date()

        while true {
            let status = mediaUploadManager.getTaskStatus(taskId: taskId)

            switch status {
            case .completed:
                return
            case .failed:
                throw NSError(
                    domain: "UploadError",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Upload failed"]
                )
            case .uploading, .pending, .paused, .none:
                // 继续等待
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 秒检查一次

                let elapsed = Date().timeIntervalSince(startTime)
                uploadProgress = min(0.95, 0.7 + (elapsed / (5 * 60)) * 0.2)

                if elapsed > 300 {
                    throw NSError(
                        domain: "TimeoutError",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Upload timeout"]
                    )
                }
            }
        }
    }

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
}

// MARK: - Media Type

enum MediaType {
    case image
    case video

    var contentType: String {
        switch self {
        case .image:
            return "image/jpeg"
        case .video:
            return "video/mp4"
        }
    }
}
