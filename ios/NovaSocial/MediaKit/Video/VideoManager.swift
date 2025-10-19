import AVFoundation
import UIKit

/// 视频管理器 - 处理视频缓存和缩略图生成
///
/// Linus 风格：简单清晰的数据流
/// - 视频缓存
/// - 缩略图生成
/// - 视频信息提取
@MainActor
final class VideoManager: ObservableObject {
    static let shared = VideoManager()

    // MARK: - Properties

    private let thumbnailCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default

    private lazy var cacheDirectory: URL = {
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let videoCache = cacheDir.appendingPathComponent("VideoCache", isDirectory: true)
        try? fileManager.createDirectory(at: videoCache, withIntermediateDirectories: true)
        return videoCache
    }()

    // MARK: - Thumbnail Generation

    /// 生成视频缩略图
    /// - Parameters:
    ///   - url: 视频 URL
    ///   - time: 截取时间点（秒）
    /// - Returns: 缩略图
    func generateThumbnail(from url: URL, at time: Double = 0) async throws -> UIImage {
        let cacheKey = "\(url.absoluteString)-\(time)" as NSString

        // 检查缓存
        if let cached = thumbnailCache.object(forKey: cacheKey) {
            return cached
        }

        // 生成缩略图
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true

        let timestamp = CMTime(seconds: time, preferredTimescale: 600)
        let cgImage = try await imageGenerator.image(at: timestamp).image

        let thumbnail = UIImage(cgImage: cgImage)

        // 缓存
        thumbnailCache.setObject(thumbnail, forKey: cacheKey)

        return thumbnail
    }

    /// 批量生成缩略图（用于视频预览条）
    /// - Parameters:
    ///   - url: 视频 URL
    ///   - count: 缩略图数量
    /// - Returns: 缩略图数组
    func generateThumbnails(from url: URL, count: Int = 5) async throws -> [UIImage] {
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        var thumbnails: [UIImage] = []
        let interval = durationSeconds / Double(count)

        for i in 0..<count {
            let time = interval * Double(i)
            let thumbnail = try await generateThumbnail(from: url, at: time)
            thumbnails.append(thumbnail)
        }

        return thumbnails
    }

    // MARK: - Video Info

    /// 获取视频信息
    /// - Parameter url: 视频 URL
    /// - Returns: 视频信息
    func getVideoInfo(from url: URL) async throws -> VideoInfo {
        let asset = AVAsset(url: url)

        let duration = try await asset.load(.duration)
        let tracks = try await asset.load(.tracks)

        guard let videoTrack = tracks.first(where: { $0.mediaType == .video }) else {
            throw VideoError.noVideoTrack
        }

        let size = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)

        // 计算旋转后的真实尺寸
        let actualSize = size.applying(transform)

        return VideoInfo(
            duration: CMTimeGetSeconds(duration),
            size: CGSize(
                width: abs(actualSize.width),
                height: abs(actualSize.height)
            ),
            fileSize: try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        )
    }

    // MARK: - Video Compression

    /// 压缩视频
    /// - Parameters:
    ///   - url: 源视频 URL
    ///   - quality: 压缩质量
    /// - Returns: 压缩后的视频 URL
    func compressVideo(from url: URL, quality: VideoQuality = .medium) async throws -> URL {
        let asset = AVAsset(url: url)
        let outputURL = cacheDirectory.appendingPathComponent(UUID().uuidString + ".mp4")

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: quality.preset
        ) else {
            throw VideoError.compressionFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4

        await exportSession.export()

        guard exportSession.status == .completed else {
            throw VideoError.compressionFailed
        }

        return outputURL
    }

    // MARK: - Cache Management

    /// 清空缩略图缓存
    func clearThumbnailCache() {
        thumbnailCache.removeAllObjects()
    }

    /// 清空视频缓存
    func clearVideoCache() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}

// MARK: - Video Info

struct VideoInfo {
    let duration: TimeInterval
    let size: CGSize
    let fileSize: Int

    var durationFormatted: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var fileSizeFormatted: String {
        let mb = Double(fileSize) / 1024 / 1024
        return String(format: "%.1f MB", mb)
    }
}

// MARK: - Video Quality

enum VideoQuality {
    case low
    case medium
    case high

    var preset: String {
        switch self {
        case .low:
            return AVAssetExportPresetLowQuality
        case .medium:
            return AVAssetExportPresetMediumQuality
        case .high:
            return AVAssetExportPresetHighestQuality
        }
    }
}

// MARK: - Errors

enum VideoError: LocalizedError {
    case noVideoTrack
    case compressionFailed
    case thumbnailGenerationFailed

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "No video track found"
        case .compressionFailed:
            return "Failed to compress video"
        case .thumbnailGenerationFailed:
            return "Failed to generate thumbnail"
        }
    }
}
