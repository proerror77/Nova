import SwiftUI

/// Kingfisher 图片视图包装 - 智能切换版本
///
/// Linus 哲学核心：
/// 1. "好品味" - 统一接口，无需修改调用代码即可切换实现
/// 2. "实用主义" - 未安装 Kingfisher 时使用自定义缓存，安装后自动启用
/// 3. "简洁执念" - 零配置，零边界情况
///
/// 安装 Kingfisher：
/// File > Add Package Dependencies > https://github.com/onevcat/Kingfisher.git
///
/// 功能：
/// - 自动内存和磁盘缓存
/// - 渐进式加载和占位符
/// - 图片处理（缩放、圆角、滤镜）
/// - 失败重试机制

// MARK: - 条件编译检测 Kingfisher

#if canImport(Kingfisher)
import Kingfisher

/// Kingfisher 版本 - 生产级图片加载
struct KFImageView: View {
    let url: String?
    var placeholder: Image = Image(systemName: "photo")
    var contentMode: ContentMode = .fill
    var fadeInDuration: Double = 0.25
    var retryStrategy: RetryStrategy = .default

    @StateObject private var metrics = MediaMetrics.shared

    var body: some View {
        Group {
            if let urlString = url, let imageURL = URL(string: urlString) {
                KingfisherImage(source: .network(imageURL))
                    .placeholder { _ in
                        placeholder
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.gray.opacity(0.3))
                    }
                    .retry(maxCount: retryStrategy.maxRetries, interval: .seconds(retryStrategy.retryInterval))
                    .fade(duration: fadeInDuration)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .onSuccess { result in
                        // 记录性能指标
                        let cacheHit = result.cacheType != .none
                        let imageSize = result.image.kf.imageData?.count ?? 0

                        metrics.recordImageLoad(
                            url: urlString,
                            duration: 0, // Kingfisher 不直接提供加载时长
                            cacheHit: cacheHit,
                            size: imageSize
                        )
                    }
                    .onFailure { error in
                        print("❌ Image load failed: \(error.localizedDescription)")
                    }
            } else {
                placeholder
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.gray.opacity(0.3))
            }
        }
    }
}

// MARK: - Kingfisher 配置

extension KFImageView {
    /// 配置 Kingfisher 缓存和下载器
    static func setupKingfisher() {
        // 内存缓存配置
        let cache = ImageCache.default
        cache.memoryStorage.config.totalCostLimit = 100 * 1024 * 1024  // 100MB
        cache.memoryStorage.config.countLimit = 150                     // 最多 150 张

        // 磁盘缓存配置
        cache.diskStorage.config.sizeLimit = 500 * 1024 * 1024          // 500MB
        cache.diskStorage.config.expiration = .days(7)                  // 7 天过期

        // 下载器配置
        let downloader = ImageDownloader.default
        downloader.downloadTimeout = 30.0                               // 30 秒超时
        downloader.trustedHosts = Set(["picsum.photos", "via.placeholder.com"])

        print("✅ Kingfisher configured successfully")
    }

    /// 清空所有缓存
    static func clearAllCache() {
        ImageCache.default.clearMemoryCache()
        ImageCache.default.clearDiskCache()
        print("🗑️ Kingfisher cache cleared")
    }

    /// 获取缓存大小
    static func getCacheSize() async -> (memory: UInt, disk: UInt) {
        let memoryCost = ImageCache.default.memoryStorage.totalCost
        let diskSize = await withCheckedContinuation { continuation in
            ImageCache.default.calculateDiskStorageSize { result in
                switch result {
                case .success(let size):
                    continuation.resume(returning: size)
                case .failure:
                    continuation.resume(returning: 0)
                }
            }
        }
        return (memory: memoryCost, disk: diskSize)
    }
}

// MARK: - 图片处理扩展（Kingfisher 版本）

extension KFImageView {
    /// 应用圆角
    func roundedCorners(_ radius: CGFloat) -> some View {
        self.clipShape(RoundedRectangle(cornerRadius: radius))
    }

    /// 应用圆形裁剪
    func circular() -> some View {
        self.clipShape(Circle())
    }
}

#else

// MARK: - 备用版本（使用自定义 ImageManager）

/// 自定义版本 - 无需依赖，使用 ImageManager
struct KFImageView: View {
    let url: String?
    var placeholder: Image = Image(systemName: "photo")
    var contentMode: ContentMode = .fill
    var fadeInDuration: Double = 0.25
    var retryStrategy: RetryStrategy = .default
    var processors: [ImageProcessor] = []

    @StateObject private var loader = ImageLoader()
    @State private var retryCount = 0

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity.animation(.easeInOut(duration: fadeInDuration)))
            } else if loader.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
            } else {
                placeholder
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.gray.opacity(0.3))
            }
        }
        .onAppear {
            if let url = url {
                Task {
                    await loadWithRetry(url: url)
                }
            }
        }
    }

    // MARK: - 重试逻辑

    private func loadWithRetry(url: String) async {
        while retryCount < retryStrategy.maxRetries {
            do {
                await loader.loadImage(url: url, processors: processors)
                return // 成功，退出
            } catch {
                retryCount += 1
                if retryCount < retryStrategy.maxRetries {
                    // 等待后重试
                    try? await Task.sleep(nanoseconds: UInt64(retryStrategy.retryInterval * 1_000_000_000))
                    print("🔄 Retry \(retryCount)/\(retryStrategy.maxRetries) for \(url)")
                } else {
                    print("❌ Failed after \(retryStrategy.maxRetries) retries: \(error)")
                }
            }
        }
    }
}

// MARK: - Image Loader

@MainActor
private class ImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var isLoading = false

    private let imageManager = ImageManager.shared
    private let metrics = MediaMetrics.shared

    func loadImage(url: String, processors: [ImageProcessor]) async throws {
        isLoading = true
        defer { isLoading = false }

        let startTime = Date()

        do {
            var loadedImage = try await imageManager.loadImage(url: url)

            // 应用图片处理器
            for processor in processors {
                loadedImage = processor.process(loadedImage) ?? loadedImage
            }

            self.image = loadedImage

            // 记录性能指标
            let duration = Date().timeIntervalSince(startTime)
            metrics.recordImageLoad(url: url, duration: duration, cacheHit: false, size: 0)

        } catch {
            print("Failed to load image: \(error)")
            throw error
        }
    }
}

// MARK: - 图片处理扩展（自定义版本）

extension KFImageView {
    /// 应用圆角
    func roundedCorners(_ radius: CGFloat) -> KFImageView {
        var view = self
        view.processors.append(RoundedCornerProcessor(radius: radius))
        return view
    }

    /// 调整大小
    func resize(to size: CGSize) -> KFImageView {
        var view = self
        view.processors.append(ResizeProcessor(targetSize: size))
        return view
    }

    /// 应用模糊
    func blur(radius: CGFloat) -> KFImageView {
        var view = self
        view.processors.append(BlurProcessor(radius: radius))
        return view
    }

    /// 应用圆形裁剪
    func circular() -> some View {
        self.clipShape(Circle())
    }
}

#endif

// MARK: - 共享类型（两个版本都需要）

/// 重试策略
struct RetryStrategy {
    let maxRetries: Int
    let retryInterval: TimeInterval

    static let `default` = RetryStrategy(maxRetries: 3, retryInterval: 2.0)
    static let aggressive = RetryStrategy(maxRetries: 5, retryInterval: 1.0)
    static let conservative = RetryStrategy(maxRetries: 2, retryInterval: 5.0)
    static let noRetry = RetryStrategy(maxRetries: 0, retryInterval: 0)
}

// MARK: - Image Processors（仅自定义版本需要）

#if !canImport(Kingfisher)

protocol ImageProcessor {
    func process(_ image: UIImage) -> UIImage?
}

struct RoundedCornerProcessor: ImageProcessor {
    let radius: CGFloat

    func process(_ image: UIImage) -> UIImage? {
        image.withRoundedCorners(radius: radius)
    }
}

struct ResizeProcessor: ImageProcessor {
    let targetSize: CGSize

    func process(_ image: UIImage) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

struct BlurProcessor: ImageProcessor {
    let radius: CGFloat

    func process(_ image: UIImage) -> UIImage? {
        image.withBlur(radius: radius)
    }
}

#endif

// MARK: - 便捷构造器

extension KFImageView {
    /// 创建头像图片视图
    static func avatar(url: String?, size: CGFloat = 40) -> some View {
        KFImageView(url: url)
            .frame(width: size, height: size)
            .circular()
    }

    /// 创建卡片封面图片视图
    static func cover(url: String?, aspectRatio: CGFloat = 16/9) -> some View {
        KFImageView(url: url)
            .aspectRatio(aspectRatio, contentMode: .fill)
            .clipped()
    }
}

// MARK: - Preview

#Preview("Basic Usage") {
    VStack(spacing: 20) {
        // 基础使用
        KFImageView(url: "https://picsum.photos/400/400")
            .frame(width: 200, height: 200)
            .roundedCorners(12)

        // 头像样式
        KFImageView.avatar(url: "https://picsum.photos/200/200", size: 60)

        // 封面样式
        KFImageView.cover(url: "https://picsum.photos/800/450")
            .frame(height: 200)
    }
    .padding()
}

#Preview("With Processors") {
    VStack(spacing: 20) {
        #if !canImport(Kingfisher)
        // 自定义处理器（仅在未安装 Kingfisher 时）
        KFImageView(url: "https://picsum.photos/400/400")
            .roundedCorners(20)
            .frame(width: 200, height: 200)

        KFImageView(url: "https://picsum.photos/400/400")
            .resize(to: CGSize(width: 150, height: 150))
            .frame(width: 150, height: 150)

        KFImageView(url: "https://picsum.photos/400/400")
            .blur(radius: 10)
            .frame(width: 200, height: 200)
        #else
        Text("Using Kingfisher")
            .foregroundColor(.green)
        #endif
    }
    .padding()
}
