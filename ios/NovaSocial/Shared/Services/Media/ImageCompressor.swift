import UIKit
import CoreGraphics

// MARK: - Image Compression Quality

enum ImageCompressionQuality: CaseIterable {
    case low        // 60% quality, max 1080px
    case medium     // 75% quality, max 1920px
    case high       // 85% quality, max 2560px
    case original   // 100% quality, no resize

    var jpegQuality: CGFloat {
        switch self {
        case .low:
            return 0.60
        case .medium:
            return 0.75
        case .high:
            return 0.85
        case .original:
            return 1.0
        }
    }

    var maxDimension: CGFloat {
        switch self {
        case .low:
            return 1080
        case .medium:
            return 1920
        case .high:
            return 2560
        case .original:
            return CGFloat.greatestFiniteMagnitude
        }
    }

    /// Target file size in bytes (approximate)
    var targetSizeBytes: Int {
        switch self {
        case .low:
            return 200_000      // ~200 KB
        case .medium:
            return 500_000      // ~500 KB
        case .high:
            return 1_000_000    // ~1 MB
        case .original:
            return Int.max
        }
    }
}

// MARK: - Compression Result

struct ImageCompressionResult {
    let data: Data
    let originalSize: Int
    let compressedSize: Int
    let width: Int
    let height: Int
    let compressionRatio: Double

    var savedBytes: Int {
        originalSize - compressedSize
    }

    var savedPercentage: Double {
        guard originalSize > 0 else { return 0 }
        return Double(savedBytes) / Double(originalSize) * 100
    }
}

// MARK: - Image Compressor

actor ImageCompressor {

    static let shared = ImageCompressor()

    private init() {}

    // MARK: - Compress Single Image

    /// Compresses a UIImage with the specified quality
    /// - Parameters:
    ///   - image: Source UIImage
    ///   - quality: Compression quality preset
    /// - Returns: Compression result with data and statistics
    func compressImage(
        _ image: UIImage,
        quality: ImageCompressionQuality = .medium
    ) async -> ImageCompressionResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Calculate original size (approximate from PNG)
        let originalData = image.pngData() ?? Data()
        let originalSize = originalData.count

        // Skip if original quality requested
        if quality == .original {
            let jpegData = image.jpegData(compressionQuality: 1.0) ?? originalData
            return ImageCompressionResult(
                data: jpegData,
                originalSize: originalSize,
                compressedSize: jpegData.count,
                width: Int(image.size.width * image.scale),
                height: Int(image.size.height * image.scale),
                compressionRatio: 1.0
            )
        }

        // Resize if needed
        let resizedImage = resizeImageIfNeeded(image, maxDimension: quality.maxDimension)

        // Compress to JPEG with target quality
        var compressedData = resizedImage.jpegData(compressionQuality: quality.jpegQuality) ?? Data()

        // If still too large, progressively reduce quality
        var currentQuality = quality.jpegQuality
        while compressedData.count > quality.targetSizeBytes && currentQuality > 0.3 {
            currentQuality -= 0.1
            if let newData = resizedImage.jpegData(compressionQuality: currentQuality) {
                compressedData = newData
            }
        }

        let compressionRatio = originalSize > 0 ? Double(compressedData.count) / Double(originalSize) : 1.0

        #if DEBUG
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        print("[ImageCompressor] Compressed in \(String(format: "%.2f", elapsed * 1000))ms")
        print("[ImageCompressor] Original: \(originalSize / 1024) KB -> Compressed: \(compressedData.count / 1024) KB")
        print("[ImageCompressor] Ratio: \(String(format: "%.1f", compressionRatio * 100))%")
        #endif

        return ImageCompressionResult(
            data: compressedData,
            originalSize: originalSize,
            compressedSize: compressedData.count,
            width: Int(resizedImage.size.width * resizedImage.scale),
            height: Int(resizedImage.size.height * resizedImage.scale),
            compressionRatio: compressionRatio
        )
    }

    /// Compresses image data (JPEG/PNG) with the specified quality
    /// - Parameters:
    ///   - data: Source image data
    ///   - quality: Compression quality preset
    /// - Returns: Compression result with data and statistics
    func compressImageData(
        _ data: Data,
        quality: ImageCompressionQuality = .medium
    ) async -> ImageCompressionResult? {
        guard let image = UIImage(data: data) else {
            return nil
        }
        return await compressImage(image, quality: quality)
    }

    // MARK: - Batch Compression

    /// Compresses multiple images in parallel
    /// - Parameters:
    ///   - images: Array of UIImages
    ///   - quality: Compression quality preset
    ///   - maxConcurrent: Maximum concurrent compressions (default: 4)
    ///   - progressCallback: Called with overall progress (0.0 to 1.0)
    /// - Returns: Array of compression results in order
    func compressImagesInParallel(
        images: [UIImage],
        quality: ImageCompressionQuality = .medium,
        maxConcurrent: Int = 4,
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async -> [ImageCompressionResult] {
        guard !images.isEmpty else { return [] }

        let totalCount = images.count
        var completedCount = 0
        var results = [(Int, ImageCompressionResult)]()

        // Process in batches for controlled parallelism
        for batch in images.enumerated().chunked(into: maxConcurrent) {
            let batchResults = await withTaskGroup(of: (Int, ImageCompressionResult).self) { group in
                for (index, image) in batch {
                    group.addTask {
                        let result = await self.compressImage(image, quality: quality)
                        return (index, result)
                    }
                }

                var batchResults = [(Int, ImageCompressionResult)]()
                for await (index, result) in group {
                    batchResults.append((index, result))
                    completedCount += 1
                    let progress = Double(completedCount) / Double(totalCount)
                    progressCallback?(progress)
                }
                return batchResults
            }
            results.append(contentsOf: batchResults)
        }

        // Sort by original index and return results
        return results.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    // MARK: - Prepare Images for Upload

    /// Prepares images for upload by compressing and converting to upload-ready format
    /// - Parameters:
    ///   - images: Array of UIImages
    ///   - quality: Compression quality preset
    ///   - progressCallback: Called with overall progress (0.0 to 1.0)
    /// - Returns: Array of (data, filename) tuples ready for upload
    func prepareImagesForUpload(
        images: [UIImage],
        quality: ImageCompressionQuality = .medium,
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async -> [(data: Data, filename: String)] {
        let results = await compressImagesInParallel(
            images: images,
            quality: quality,
            progressCallback: progressCallback
        )

        return results.enumerated().map { index, result in
            let filename = "image_\(UUID().uuidString).jpg"
            return (data: result.data, filename: filename)
        }
    }

    // MARK: - Helper Methods

    private func resizeImageIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let originalWidth = image.size.width * image.scale
        let originalHeight = image.size.height * image.scale
        let maxOriginalDimension = max(originalWidth, originalHeight)

        // No resize needed
        guard maxOriginalDimension > maxDimension else {
            return image
        }

        let scaleFactor = maxDimension / maxOriginalDimension
        let newWidth = originalWidth * scaleFactor
        let newHeight = originalHeight * scaleFactor
        let newSize = CGSize(width: newWidth, height: newHeight)

        // Use UIGraphicsImageRenderer for efficient resizing
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        #if DEBUG
        print("[ImageCompressor] Resized: \(Int(originalWidth))x\(Int(originalHeight)) -> \(Int(newWidth))x\(Int(newHeight))")
        #endif

        return resizedImage
    }
}

// MARK: - Array Extension for Chunking

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

private extension EnumeratedSequence where Base: Collection {
    func chunked(into size: Int) -> [[(offset: Int, element: Base.Element)]] {
        let array = Array(self)
        return stride(from: 0, to: array.count, by: size).map {
            Array(array[$0..<Swift.min($0 + size, array.count)])
        }
    }
}
