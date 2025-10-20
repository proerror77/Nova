import UIKit
import AVFoundation
import Foundation

/// 通用媒体上传管理器 - 支持图片和视频
///
/// Linus 风格：简单统一的数据流
/// - 支持图片、视频混合上传
/// - 自动压缩和重试
/// - 统一的进度追踪
@MainActor
final class MediaUploadManager: ObservableObject {
    static let shared = MediaUploadManager()

    // MARK: - Published Properties

    @Published private(set) var uploadQueue: [MediaUploadTask] = []
    @Published private(set) var metrics = MediaUploadMetrics()

    // MARK: - Private Properties

    private let imageCompressor: ImageCompressor
    private let videoManager: VideoManager
    private let maxConcurrentUploads = 3
    private let maxRetries = 3

    // MARK: - Initialization

    init(
        imageCompressor: ImageCompressor = .default,
        videoManager: VideoManager = .shared
    ) {
        self.imageCompressor = imageCompressor
        self.videoManager = videoManager
    }

    // MARK: - Public API

    /// 上传单个媒体文件
    /// - Parameters:
    ///   - media: 媒体数据（图片或视频）
    ///   - uploadURL: 上传地址
    ///   - metadata: 元数据
    /// - Returns: 上传任务 ID
    @discardableResult
    func uploadMedia(
        _ media: MediaData,
        to uploadURL: URL,
        metadata: [String: String] = [:]
    ) -> String {
        let task = MediaUploadTask(
            id: UUID().uuidString,
            media: media,
            uploadURL: uploadURL,
            metadata: metadata
        )

        uploadQueue.append(task)
        processQueue()

        return task.id
    }

    /// 批量上传媒体
    /// - Parameters:
    ///   - medias: 媒体数组
    ///   - getUploadURL: 获取上传 URL 的闭包
    /// - Returns: 任务 ID 数组
    func uploadBatch(
        _ medias: [MediaData],
        getUploadURL: @escaping () async throws -> URL
    ) async throws -> [String] {
        var taskIds: [String] = []

        for media in medias {
            let uploadURL = try await getUploadURL()
            let taskId = uploadMedia(media, to: uploadURL)
            taskIds.append(taskId)
        }

        return taskIds
    }

    /// 暂停上传
    func pauseUpload(taskId: String) {
        guard let index = uploadQueue.firstIndex(where: { $0.id == taskId }) else { return }
        uploadQueue[index].state = .paused
    }

    /// 恢复上传
    func resumeUpload(taskId: String) {
        guard let index = uploadQueue.firstIndex(where: { $0.id == taskId }) else { return }
        uploadQueue[index].state = .pending
        processQueue()
    }

    /// 取消上传
    func cancelUpload(taskId: String) {
        guard let index = uploadQueue.firstIndex(where: { $0.id == taskId }) else { return }
        uploadQueue[index].uploadTask?.cancel()
        uploadQueue.remove(at: index)
    }

    /// 清空队列
    func clearQueue() {
        uploadQueue.forEach { $0.uploadTask?.cancel() }
        uploadQueue.removeAll()
    }

    /// 获取任务状态
    func getTaskStatus(taskId: String) -> MediaUploadTask.State? {
        uploadQueue.first(where: { $0.id == taskId })?.state
    }

    // MARK: - Private Helpers

    private func processQueue() {
        let uploadingCount = uploadQueue.filter { $0.state == .uploading }.count
        let pendingTasks = uploadQueue.filter { $0.state == .pending }

        // 控制并发数
        let availableSlots = maxConcurrentUploads - uploadingCount
        guard availableSlots > 0 else { return }

        let tasksToStart = pendingTasks.prefix(availableSlots)
        for task in tasksToStart {
            startUpload(task)
        }
    }

    private func startUpload(_ task: MediaUploadTask) {
        guard let index = uploadQueue.firstIndex(where: { $0.id == task.id }) else { return }

        uploadQueue[index].state = .uploading

        Task {
            do {
                // 1. 准备媒体数据
                let data: Data
                let contentType: String

                switch task.media {
                case .image(let image):
                    guard let compressedData = imageCompressor.compress(image) else {
                        throw MediaUploadError.compressionFailed
                    }
                    data = compressedData
                    contentType = "image/jpeg"

                case .video(let url):
                    // 压缩视频
                    let compressedURL = try await videoManager.compressVideo(
                        from: url,
                        quality: .medium
                    )
                    data = try Data(contentsOf: compressedURL)
                    contentType = "video/mp4"

                    // 清理临时文件
                    try? FileManager.default.removeItem(at: compressedURL)
                }

                uploadQueue[index].compressedSize = data.count

                // 2. 上传
                try await performUpload(
                    data: data,
                    to: task.uploadURL,
                    contentType: contentType,
                    taskId: task.id
                )

                // 3. 标记完成
                uploadQueue[index].state = .completed
                updateMetrics(success: true)

                // 继续处理队列
                processQueue()

            } catch {
                // 处理失败
                await handleUploadFailure(taskId: task.id, error: error)
            }
        }
    }

    private func performUpload(
        data: Data,
        to url: URL,
        contentType: String,
        taskId: String
    ) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        guard let index = uploadQueue.firstIndex(where: { $0.id == taskId }) else {
            throw MediaUploadError.taskNotFound
        }

        // 使用 URLSession delegate 以支持进度追踪
        let delegate = UploadProgressDelegate(taskId: taskId, manager: self)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let uploadTask = session.uploadTask(with: request, from: data)
        uploadQueue[index].uploadTask = uploadTask

        uploadTask.resume()

        // 等待上传完成
        return try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
        }
    }

    // MARK: - Progress Delegate

    private class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
        let taskId: String
        weak var manager: MediaUploadManager?
        var continuation: CheckedContinuation<Void, Error>?

        init(taskId: String, manager: MediaUploadManager) {
            self.taskId = taskId
            self.manager = manager
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didSendBodyData bytesSent: Int64,
            totalBytesSent: Int64,
            totalBytesExpectedToSend: Int64
        ) {
            Task { @MainActor in
                guard let manager = self.manager,
                      let index = manager.uploadQueue.firstIndex(where: { $0.id == taskId }) else { return }

                let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
                manager.uploadQueue[index].progress = progress
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error = error {
                continuation?.resume(throwing: error)
            } else if let response = task.response as? HTTPURLResponse,
                      (200...299).contains(response.statusCode) {
                continuation?.resume()
            } else {
                continuation?.resume(throwing: MediaUploadError.serverError)
            }
        }
    }

    private func handleUploadFailure(taskId: String, error: Error) async {
        guard let index = uploadQueue.firstIndex(where: { $0.id == taskId }) else { return }

        uploadQueue[index].retryCount += 1

        if uploadQueue[index].retryCount < maxRetries {
            // 重试
            uploadQueue[index].state = .pending
            uploadQueue[index].error = error.localizedDescription

            // 延迟后重试
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 秒
            processQueue()
        } else {
            // 最终失败
            uploadQueue[index].state = .failed
            uploadQueue[index].error = error.localizedDescription
            updateMetrics(success: false)
        }
    }

    private func updateMetrics(success: Bool) {
        metrics.totalUploads += 1
        if success {
            metrics.successfulUploads += 1
        } else {
            metrics.failedUploads += 1
        }
    }
}

// MARK: - Media Data

enum MediaData {
    case image(UIImage)
    case video(URL)

    var contentType: String {
        switch self {
        case .image:
            return "image/jpeg"
        case .video:
            return "video/mp4"
        }
    }
}

// MARK: - Upload Task

class MediaUploadTask: Identifiable, ObservableObject {
    let id: String
    let media: MediaData
    let uploadURL: URL
    let metadata: [String: String]

    @Published var state: State = .pending
    @Published var progress: Double = 0
    @Published var error: String?
    @Published var compressedSize: Int = 0

    var retryCount: Int = 0
    var uploadTask: URLSessionUploadTask?

    init(
        id: String,
        media: MediaData,
        uploadURL: URL,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.media = media
        self.uploadURL = uploadURL
        self.metadata = metadata
    }

    enum State {
        case pending
        case uploading
        case paused
        case completed
        case failed
    }
}

// MARK: - Upload Metrics

struct MediaUploadMetrics {
    var totalUploads: Int = 0
    var successfulUploads: Int = 0
    var failedUploads: Int = 0

    var successRate: Double {
        guard totalUploads > 0 else { return 0 }
        return Double(successfulUploads) / Double(totalUploads)
    }
}

// MARK: - Errors

enum MediaUploadError: LocalizedError {
    case compressionFailed
    case taskNotFound
    case serverError
    case networkError
    case invalidMediaType

    var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return "Failed to compress media"
        case .taskNotFound:
            return "Upload task not found"
        case .serverError:
            return "Server error"
        case .networkError:
            return "Network error"
        case .invalidMediaType:
            return "Invalid media type"
        }
    }
}
