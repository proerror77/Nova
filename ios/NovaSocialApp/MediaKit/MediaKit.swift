import Foundation
import SwiftUI

/// MediaKit - Nova 社交应用的媒体处理工具集
///
/// 核心功能：
/// - 高效图片加载和缓存
/// - 智能图片上传
/// - 视频播放和处理
/// - 网络优化
/// - 性能监控

// MARK: - Public Exports

// Core
public typealias ImageManager = ImageManager
public typealias MediaMetrics = MediaMetrics
public typealias VideoManager = VideoManager

// Image
public typealias ImageUploadManager = ImageUploadManager
public typealias ImageViewerView = ImageViewerView
public typealias KFImageView = KFImageView
public typealias ImagePickerWrapper = ImagePickerWrapper

// Video
public typealias VideoPlayerView = VideoPlayerView
public typealias CustomVideoPlayerView = CustomVideoPlayerView

// Utils
public typealias ImageCompressor = ImageCompressor
public typealias MediaNetworkOptimizer = MediaNetworkOptimizer

// Debug
public typealias MediaPerformanceDebugView = MediaPerformanceDebugView

// MARK: - MediaKit Configuration

public struct MediaKitConfig {
    /// 图片缓存配置
    public var imageCache: ImageManager.Config = .init()

    /// 压缩配置
    public var compression: ImageCompressor.CompressionConfig = .init()

    /// 是否启用性能监控
    public var enableMetrics: Bool = true

    public init() {}
}

// MARK: - MediaKit Main Class

@MainActor
public final class MediaKit: ObservableObject {
    public static let shared = MediaKit()

    // MARK: - Managers

    public let imageManager = ImageManager.shared
    public let uploadManager = ImageUploadManager.shared
    public let videoManager = VideoManager.shared
    public let networkOptimizer = MediaNetworkOptimizer.shared
    public let metrics = MediaMetrics.shared

    // MARK: - Configuration

    private(set) var config: MediaKitConfig

    private init(config: MediaKitConfig = MediaKitConfig()) {
        self.config = config

        if config.enableMetrics {
            metrics.startMonitoring()
        }
    }

    // MARK: - Setup

    /// 配置 MediaKit
    public static func configure(with config: MediaKitConfig) {
        // 应用配置
        shared.config = config
    }

    // MARK: - Quick Actions

    /// 快速加载图片
    public func loadImage(url: String) async throws -> UIImage {
        try await imageManager.loadImage(url: url)
    }

    /// 快速上传图片
    @discardableResult
    public func uploadImage(_ image: UIImage, to url: URL) -> String {
        uploadManager.uploadImage(image, to: url)
    }

    /// 生成视频缩略图
    public func generateThumbnail(videoURL: URL) async throws -> UIImage {
        try await videoManager.generateThumbnail(from: videoURL)
    }

    /// 获取性能报告
    public func getPerformanceReport() -> PerformanceReport {
        metrics.getPerformanceReport()
    }

    /// 清空所有缓存
    public func clearAllCaches() async {
        await imageManager.clearCache()
        videoManager.clearVideoCache()
        videoManager.clearThumbnailCache()
    }
}

// MARK: - SwiftUI Environment

private struct MediaKitKey: EnvironmentKey {
    static let defaultValue = MediaKit.shared
}

extension EnvironmentValues {
    public var mediaKit: MediaKit {
        get { self[MediaKitKey.self] }
        set { self[MediaKitKey.self] = newValue }
    }
}

// MARK: - Convenience Extensions

extension View {
    /// 注入 MediaKit 到环境
    public func mediaKit(_ mediaKit: MediaKit = .shared) -> some View {
        environment(\.mediaKit, mediaKit)
    }
}
