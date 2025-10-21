import SwiftUI
import UIKit

// MARK: - Image Cache Manager
/// 图片缓存管理器
/// 数据结构：简单的内存 + 磁盘两层缓存
final class ImageCacheManager {
    static let shared = ImageCacheManager()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    // 缓存统计
    private(set) var hitCount: Int = 0
    private(set) var missCount: Int = 0

    private init() {
        // 设置内存缓存限制（100MB）
        memoryCache.totalCostLimit = 100 * 1024 * 1024
        memoryCache.countLimit = 100 // 最多缓存 100 张图片

        // 获取磁盘缓存目录
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("ImageCache")

        // 创建缓存目录
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // 监听内存警告
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearMemoryCache),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    // MARK: - Public Methods

    func getImage(for key: String) -> UIImage? {
        // 1. 先查内存缓存
        if let cachedImage = memoryCache.object(forKey: key as NSString) {
            hitCount += 1
            return cachedImage
        }

        // 2. 再查磁盘缓存
        let fileURL = cacheDirectory.appendingPathComponent(key.sha256)
        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            missCount += 1
            return nil
        }

        // 加载到内存缓存
        hitCount += 1
        memoryCache.setObject(image, forKey: key as NSString)
        return image
    }

    func setImage(_ image: UIImage, for key: String) {
        // 计算图片大小（字节）
        let cost = image.jpegData(compressionQuality: 0.8)?.count ?? 0

        // 1. 保存到内存缓存（带大小信息）
        memoryCache.setObject(image, forKey: key as NSString, cost: cost)

        // 2. 异步保存到磁盘缓存（不阻塞主线程）
        Task.detached(priority: .background) {
            let fileURL = self.cacheDirectory.appendingPathComponent(key.sha256)
            if let data = image.jpegData(compressionQuality: 0.8) {
                try? data.write(to: fileURL)
            }
        }
    }

    @objc func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }

    func clearCache() {
        memoryCache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        hitCount = 0
        missCount = 0
    }

    /// 获取缓存命中率
    var hitRate: Double {
        let total = hitCount + missCount
        guard total > 0 else { return 0 }
        return Double(hitCount) / Double(total)
    }
}

// MARK: - Lazy Image View
/// 懒加载图片视图 - 支持缓存、占位符、重试
/// 核心思想：消除特殊情况，统一状态管理
struct LazyImageView: View {
    let url: String?
    var contentMode: ContentMode = .fill
    var placeholder: Image = Image(systemName: "photo")
    var retryCount: Int = 3
    var enablePrefetch: Bool = true // 启用预加载

    @State private var loadedImage: UIImage?
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var currentRetry = 0
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else if isLoading {
                ZStack {
                    Color.gray.opacity(0.1)
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .gray))
                }
            } else if loadFailed {
                ZStack {
                    Color.gray.opacity(0.1)
                    VStack(spacing: 8) {
                        placeholder
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .foregroundColor(.gray)

                        if currentRetry < retryCount {
                            Button {
                                resetAndLoad()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Retry")
                                }
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(8)
                            }
                        }
                    }
                }
            } else {
                ZStack {
                    Color.gray.opacity(0.1)
                    placeholder
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .foregroundColor(.gray)
                }
            }
        }
        .onAppear {
            if enablePrefetch {
                loadImage()
            }
        }
        .onChange(of: url) { _, newURL in
            if newURL != nil {
                resetAndLoad()
            }
        }
        .onDisappear {
            // 取消加载任务（节省资源）
            loadTask?.cancel()
        }
    }

    private func resetAndLoad() {
        loadTask?.cancel()
        currentRetry = 0
        loadFailed = false
        loadImage()
    }

    private func loadImage() {
        guard let urlString = url,
              let imageURL = URL(string: urlString) else {
            loadFailed = true
            return
        }

        // 先检查缓存（快速路径）
        if let cachedImage = ImageCacheManager.shared.getImage(for: urlString) {
            loadedImage = cachedImage
            return
        }

        // 从网络加载
        isLoading = true
        loadFailed = false

        loadTask = Task {
            do {
                // 添加超时机制（10秒）
                let (data, response) = try await withTimeout(seconds: 10) {
                    try await URLSession.shared.data(from: imageURL)
                }

                // 检查 HTTP 响应状态
                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    await handleLoadFailure()
                    return
                }

                guard let image = UIImage(data: data) else {
                    await handleLoadFailure()
                    return
                }

                // 保存到缓存（异步）
                ImageCacheManager.shared.setImage(image, for: urlString)

                // 平滑过渡动画
                await MainActor.run {
                    withAnimation(.easeIn(duration: 0.3)) {
                        self.loadedImage = image
                        self.isLoading = false
                    }
                }
            } catch {
                await handleLoadFailure()
            }
        }
    }

    @MainActor
    private func handleLoadFailure() {
        isLoading = false
        currentRetry += 1

        if currentRetry < retryCount {
            // 指数退避重试
            Task {
                let delay = UInt64(pow(2.0, Double(currentRetry)) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
                loadImage()
            }
        } else {
            loadFailed = true
        }
    }

    /// 带超时的网络请求
    private func withTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw URLError(.timedOut)
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Post Image View
/// Post 专用图片视图 - 针对 Feed 优化
struct PostImageView: View {
    let imageUrl: String?
    let thumbnailUrl: String?

    @State private var useFullImage = false

    var body: some View {
        GeometryReader { geometry in
            LazyImageView(
                url: useFullImage ? imageUrl : (thumbnailUrl ?? imageUrl),
                contentMode: .fill
            )
            .frame(width: geometry.size.width, height: geometry.size.width)
            .clipped()
            .onAppear {
                // 如果缩略图存在，先加载缩略图
                if thumbnailUrl != nil {
                    // 延迟加载高清图
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                        useFullImage = true
                    }
                } else {
                    useFullImage = true
                }
            }
        }
        .aspectRatio(1, contentMode: .fill)
    }
}

// MARK: - String Extension for Cache Key
extension String {
    /// 简单的 hash 生成文件名（避免特殊字符）
    var sha256: String {
        // 简化版：使用 hashValue
        // 生产环境建议使用真正的 SHA256
        return "\(abs(self.hashValue)).jpg"
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 20) {
        LazyImageView(url: "https://picsum.photos/400/400")
            .frame(width: 200, height: 200)
            .cornerRadius(12)

        PostImageView(
            imageUrl: "https://picsum.photos/800/800",
            thumbnailUrl: "https://picsum.photos/200/200"
        )
        .frame(height: 300)
    }
}
