import SwiftUI

/// 高性能异步图像加载组件
///
/// 性能优化：
/// - 双层缓存（内存 + 磁盘）
/// - 图像压缩和尺寸优化
/// - 取消机制（滚动时自动取消未完成的加载）
/// - 占位图和错误处理
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let size: ImageSize
    let content: (UIImage) -> Content
    let placeholder: () -> Placeholder

    @State private var loadedImage: UIImage?
    @State private var isLoading = false
    @State private var loadError: Error?

    @StateObject private var cacheManager = ImageCacheManager.shared

    init(
        url: URL?,
        size: ImageSize = .medium,
        @ViewBuilder content: @escaping (UIImage) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.size = size
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image = loadedImage {
                content(image)
            } else if isLoading {
                placeholder()
            } else if loadError != nil {
                errorView
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private var errorView: some View {
        Color.gray.opacity(0.2)
            .overlay(
                Image(systemName: "photo")
                    .foregroundColor(.gray)
            )
    }

    private func loadImage() async {
        guard let url = url else { return }

        isLoading = true
        loadError = nil

        do {
            let image = try await cacheManager.image(for: url, size: size)
            loadedImage = image
        } catch {
            loadError = error
            print("❌ Image load error: \(error)")
        }

        isLoading = false
    }
}

// MARK: - Convenience Initializers
extension CachedAsyncImage where Content == Image, Placeholder == Color {
    init(url: URL?, size: ImageSize = .medium) {
        self.init(
            url: url,
            size: size,
            content: { uiImage in
                Image(uiImage: uiImage)
                    .resizable()
            },
            placeholder: {
                Color.gray.opacity(0.1)
            }
        )
    }
}

extension CachedAsyncImage where Placeholder == SkeletonView {
    init(
        url: URL?,
        size: ImageSize = .medium,
        @ViewBuilder content: @escaping (UIImage) -> Content
    ) {
        self.init(
            url: url,
            size: size,
            content: content,
            placeholder: { SkeletonView() }
        )
    }
}
