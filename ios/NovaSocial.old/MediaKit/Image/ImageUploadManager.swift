import UIKit
import Foundation

/// 图片上传管理器 - Linus 风格：简单的队列，清晰的状态
///
/// 核心设计：
/// 1. 上传任务队列（待上传 -> 上传中 -> 完成/失败）
/// 2. 自动压缩和重试
/// 3. 批量上传支持
@MainActor
final class ImageUploadManager: ObservableObject {
    static let shared = ImageUploadManager()

    // MARK: - Published Properties

    @Published private(set) var uploadQueue: [UploadTask] = []
    @Published private(set) var metrics = UploadMetrics()

    // MARK: - Private Properties

    private let compressor: ImageCompressor
    private let maxConcurrentUploads = 3
    private let maxRetries = 3

    // MARK: - Initialization

    init(compressor: ImageCompressor = .default) {
        self.compressor = compressor
    }

    // MARK: - Public API

    /// 上传单张图片
    /// - Parameters:
    ///   - image: 原始图片
    ///   - uploadURL: 上传地址（从后端获取）
    /// - Returns: 上传任务 ID
    @discardableResult
    func uploadImage(
        _ image: UIImage,
        to uploadURL: URL,
        metadata: [String: String] = [:]
    ) -> String {
        let task = UploadTask(
            id: UUID().uuidString,
            image: image,
            uploadURL: uploadURL,
            metadata: metadata
        )

        uploadQueue.append(task)
        processQueue()

        return task.id
    }

    /// 批量上传图片
    /// - Parameters:
    ///   - images: 图片数组
    ///   - getUploadURL: 获取上传 URL 的闭包
    /// - Returns: 任务 ID 数组
    func uploadBatch(
        _ images: [UIImage],
        getUploadURL: @escaping () async throws -> URL
    ) async throws -> [String] {
        var taskIds: [String] = []

        for image in images {
            let uploadURL = try await getUploadURL()
            let taskId = uploadImage(image, to: uploadURL)
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
    func getTaskStatus(taskId: String) -> UploadTask.State? {
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

    private func startUpload(_ task: UploadTask) {
        guard let index = uploadQueue.firstIndex(where: { $0.id == task.id }) else { return }

        uploadQueue[index].state = .uploading

        Task {
            do {
                // 1. 压缩图片
                guard let compressedData = compressor.compress(task.image) else {
                    throw UploadError.compressionFailed
                }

                uploadQueue[index].compressedSize = compressedData.count

                // 2. 上传
                try await performUpload(
                    data: compressedData,
                    to: task.uploadURL,
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

    private func performUpload(data: Data, to url: URL, taskId: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")

        guard let index = uploadQueue.firstIndex(where: { $0.id == taskId }) else {
            throw UploadError.taskNotFound
        }

        // 使用 URLSession delegate 以支持进度追踪
        let delegate = UploadProgressDelegate(taskId: taskId, manager: self)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let task = session.uploadTask(with: request, from: data)
        uploadQueue[index].uploadTask = task

        task.resume()

        // 等待上传完成
        return try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
        }
    }

    // MARK: - Progress Delegate

    private class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
        let taskId: String
        weak var manager: ImageUploadManager?
        var continuation: CheckedContinuation<Void, Error>?

        init(taskId: String, manager: ImageUploadManager) {
            self.taskId = taskId
            self.manager = manager
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
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
                continuation?.resume(throwing: UploadError.serverError)
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

// MARK: - Upload Task

class UploadTask: Identifiable, ObservableObject {
    let id: String
    let image: UIImage
    let uploadURL: URL
    let metadata: [String: String]

    @Published var state: State = .pending
    @Published var progress: Double = 0
    @Published var error: String?
    @Published var compressedSize: Int = 0

    var retryCount: Int = 0
    var uploadTask: URLSessionUploadTask?

    init(id: String, image: UIImage, uploadURL: URL, metadata: [String: String] = [:]) {
        self.id = id
        self.image = image
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

struct UploadMetrics {
    var totalUploads: Int = 0
    var successfulUploads: Int = 0
    var failedUploads: Int = 0

    var successRate: Double {
        guard totalUploads > 0 else { return 0 }
        return Double(successfulUploads) / Double(totalUploads)
    }
}

// MARK: - Errors

enum UploadError: LocalizedError {
    case compressionFailed
    case taskNotFound
    case serverError
    case networkError

    var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return "Failed to compress image"
        case .taskNotFound:
            return "Upload task not found"
        case .serverError:
            return "Server error"
        case .networkError:
            return "Network error"
        }
    }
}
