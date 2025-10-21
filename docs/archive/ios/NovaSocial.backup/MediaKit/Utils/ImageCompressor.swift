import UIKit
import Foundation

/// 图片压缩器 - Linus 风格：简单直接，没有废话
///
/// 核心思想：
/// 1. 自动检测并调整尺寸
/// 2. 智能质量压缩
/// 3. 一次性处理，没有特殊情况
struct ImageCompressor {

    // MARK: - Configuration

    struct CompressionConfig {
        var maxFileSize: Int = 500 * 1024  // 500KB
        var maxDimension: CGFloat = 2048    // 最大边长
        var initialQuality: CGFloat = 0.8   // 初始质量
        var minQuality: CGFloat = 0.3       // 最低质量
        var qualityStep: CGFloat = 0.1      // 质量递减步长
    }

    static let `default` = ImageCompressor()

    private let config: CompressionConfig

    init(config: CompressionConfig = CompressionConfig()) {
        self.config = config
    }

    // MARK: - Public API

    /// 压缩图片 - 统一入口
    /// - Parameter image: 原始图片
    /// - Returns: 压缩后的数据
    func compress(_ image: UIImage) -> Data? {
        // 1. 调整尺寸
        let resizedImage = resize(image)

        // 2. 压缩质量
        return compressQuality(resizedImage)
    }

    /// 批量压缩
    /// - Parameter images: 图片数组
    /// - Returns: 压缩后的数据数组
    func compressBatch(_ images: [UIImage]) async -> [Data] {
        await withTaskGroup(of: Data?.self) { group in
            for image in images {
                group.addTask {
                    self.compress(image)
                }
            }

            var results: [Data] = []
            for await data in group {
                if let data = data {
                    results.append(data)
                }
            }
            return results
        }
    }

    /// 生成缩略图
    /// - Parameters:
    ///   - image: 原始图片
    ///   - size: 目标尺寸
    /// - Returns: 缩略图
    func generateThumbnail(_ image: UIImage, size: CGSize) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - Private Helpers

    /// 调整图片尺寸
    private func resize(_ image: UIImage) -> UIImage {
        let size = image.size
        let maxDim = max(size.width, size.height)

        // 如果已经足够小，直接返回
        guard maxDim > config.maxDimension else {
            return image
        }

        // 计算新尺寸（保持比例）
        let scale = config.maxDimension / maxDim
        let newSize = CGSize(
            width: size.width * scale,
            height: size.height * scale
        )

        // 渲染新图片
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// 压缩质量
    private func compressQuality(_ image: UIImage) -> Data? {
        var quality = config.initialQuality
        var data = image.jpegData(compressionQuality: quality)

        // 逐步降低质量直到满足大小要求
        while let currentData = data,
              currentData.count > config.maxFileSize,
              quality > config.minQuality {
            quality -= config.qualityStep
            data = image.jpegData(compressionQuality: quality)
        }

        return data
    }
}

// MARK: - Image Processing Extensions

extension UIImage {
    /// 生成圆角图片
    func withRoundedCorners(radius: CGFloat) -> UIImage? {
        let rect = CGRect(origin: .zero, size: size)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
            path.addClip()
            draw(in: rect)
        }
    }

    /// 应用滤镜
    func withFilter(_ filterName: String, parameters: [String: Any] = [:]) -> UIImage? {
        guard let ciImage = CIImage(image: self) else { return nil }
        guard let filter = CIFilter(name: filterName) else { return nil }

        filter.setValue(ciImage, forKey: kCIInputImageKey)
        for (key, value) in parameters {
            filter.setValue(value, forKey: key)
        }

        guard let outputImage = filter.outputImage else { return nil }

        let context = CIContext()
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    /// 生成模糊效果
    func withBlur(radius: CGFloat = 10) -> UIImage? {
        withFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
    }
}
