import UIKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Image Output Format

enum ImageOutputFormat {
    case jpeg
    case webp
    case heic

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .webp: return "webp"
        case .heic: return "heic"
        }
    }

    var mimeType: String {
        switch self {
        case .jpeg: return "image/jpeg"
        case .webp: return "image/webp"
        case .heic: return "image/heic"
        }
    }

    var utType: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .webp: return .webP
        case .heic: return .heic
        }
    }
}

// MARK: - Image Compression Quality

enum ImageCompressionQuality: CaseIterable {
    case low        // 50% quality, max 1080px - optimized for fast uploads
    case medium     // 70% quality, max 1440px
    case high       // 85% quality, max 2048px
    case original   // 100% quality, no resize

    var quality: CGFloat {
        switch self {
        case .low:
            return 0.50
        case .medium:
            return 0.70
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
            return 1440
        case .high:
            return 2048
        case .original:
            return CGFloat.greatestFiniteMagnitude
        }
    }

    /// Target file size in bytes (approximate)
    var targetSizeBytes: Int {
        switch self {
        case .low:
            return 100_000      // ~100 KB for WebP
        case .medium:
            return 300_000      // ~300 KB
        case .high:
            return 600_000      // ~600 KB
        case .original:
            return Int.max
        }
    }

    // Legacy compatibility
    var jpegQuality: CGFloat { quality }
}

// MARK: - Compression Result

struct ImageCompressionResult {
    let data: Data
    let originalSize: Int
    let compressedSize: Int
    let width: Int
    let height: Int
    let compressionRatio: Double
    let format: ImageOutputFormat
    let filename: String

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

    /// Preferred output format (WebP for best compression)
    var preferredFormat: ImageOutputFormat = .webp

    // MARK: - Compress Single Image

    /// Compresses a UIImage with the specified quality and format
    func compressImage(
        _ image: UIImage,
        quality: ImageCompressionQuality = .low,
        format: ImageOutputFormat? = nil,
        stripMetadata: Bool = true
    ) async -> ImageCompressionResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        let outputFormat = format ?? preferredFormat

        // Calculate original size (approximate)
        let originalData = image.jpegData(compressionQuality: 1.0) ?? Data()
        let originalSize = originalData.count

        // Skip compression if original quality requested
        if quality == .original {
            let data = encodeImage(image, format: outputFormat, quality: 1.0, stripMetadata: stripMetadata)
            let filename = "image_\(UUID().uuidString).\(outputFormat.fileExtension)"
            return ImageCompressionResult(
                data: data,
                originalSize: originalSize,
                compressedSize: data.count,
                width: Int(image.size.width * image.scale),
                height: Int(image.size.height * image.scale),
                compressionRatio: 1.0,
                format: outputFormat,
                filename: filename
            )
        }

        // Resize if needed
        let resizedImage = resizeImageIfNeeded(image, maxDimension: quality.maxDimension)

        // Compress with target quality
        var compressedData = encodeImage(resizedImage, format: outputFormat, quality: quality.quality, stripMetadata: stripMetadata)

        // If still too large, progressively reduce quality
        var currentQuality = quality.quality
        while compressedData.count > quality.targetSizeBytes && currentQuality > 0.2 {
            currentQuality -= 0.1
            compressedData = encodeImage(resizedImage, format: outputFormat, quality: currentQuality, stripMetadata: stripMetadata)
        }

        let compressionRatio = originalSize > 0 ? Double(compressedData.count) / Double(originalSize) : 1.0
        let filename = "image_\(UUID().uuidString).\(outputFormat.fileExtension)"

        #if DEBUG
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        print("[ImageCompressor] Format: \(outputFormat.fileExtension.uppercased()), Time: \(String(format: "%.0f", elapsed * 1000))ms")
        print("[ImageCompressor] Size: \(originalSize / 1024) KB -> \(compressedData.count / 1024) KB (saved \(String(format: "%.0f", (1 - compressionRatio) * 100))%)")
        #endif

        return ImageCompressionResult(
            data: compressedData,
            originalSize: originalSize,
            compressedSize: compressedData.count,
            width: Int(resizedImage.size.width * resizedImage.scale),
            height: Int(resizedImage.size.height * resizedImage.scale),
            compressionRatio: compressionRatio,
            format: outputFormat,
            filename: filename
        )
    }

    // MARK: - Encode Image to Format

    private func encodeImage(
        _ image: UIImage,
        format: ImageOutputFormat,
        quality: CGFloat,
        stripMetadata: Bool
    ) -> Data {
        switch format {
        case .webp:
            return encodeToWebP(image, quality: quality, stripMetadata: stripMetadata)
        case .heic:
            return encodeToHEIC(image, quality: quality, stripMetadata: stripMetadata)
        case .jpeg:
            return encodeToJPEG(image, quality: quality, stripMetadata: stripMetadata)
        }
    }

    /// Encode to WebP format (25-35% smaller than JPEG)
    private func encodeToWebP(_ image: UIImage, quality: CGFloat, stripMetadata: Bool) -> Data {
        guard let cgImage = image.cgImage else {
            return encodeToJPEG(image, quality: quality, stripMetadata: stripMetadata)
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.webP.identifier as CFString, 1, nil) else {
            // Fallback to JPEG if WebP not supported
            return encodeToJPEG(image, quality: quality, stripMetadata: stripMetadata)
        }

        var options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]

        if stripMetadata {
            options[kCGImageDestinationMetadata] = nil
            options[kCGImagePropertyExifDictionary] = nil
            options[kCGImagePropertyGPSDictionary] = nil
        }

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return encodeToJPEG(image, quality: quality, stripMetadata: stripMetadata)
        }

        return data as Data
    }

    /// Encode to HEIC format (most efficient, needs iOS 11+)
    private func encodeToHEIC(_ image: UIImage, quality: CGFloat, stripMetadata: Bool) -> Data {
        guard let cgImage = image.cgImage else {
            return encodeToJPEG(image, quality: quality, stripMetadata: stripMetadata)
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.heic.identifier as CFString, 1, nil) else {
            return encodeToJPEG(image, quality: quality, stripMetadata: stripMetadata)
        }

        var options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]

        if stripMetadata {
            options[kCGImageDestinationMetadata] = nil
        }

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return encodeToJPEG(image, quality: quality, stripMetadata: stripMetadata)
        }

        return data as Data
    }

    /// Encode to JPEG format with optional metadata stripping
    private func encodeToJPEG(_ image: UIImage, quality: CGFloat, stripMetadata: Bool) -> Data {
        if stripMetadata {
            // Use ImageIO to strip metadata
            guard let cgImage = image.cgImage else {
                return image.jpegData(compressionQuality: quality) ?? Data()
            }

            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
                return image.jpegData(compressionQuality: quality) ?? Data()
            }

            let options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: quality,
                kCGImageDestinationMetadata: NSNull(),
                kCGImagePropertyExifDictionary: NSNull(),
                kCGImagePropertyGPSDictionary: NSNull()
            ]

            CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
            CGImageDestinationFinalize(destination)

            return data as Data
        } else {
            return image.jpegData(compressionQuality: quality) ?? Data()
        }
    }

    // MARK: - Batch Compression with Pipeline

    /// Compresses multiple images in parallel with pipeline support
    /// Each image is compressed and returned as soon as ready (for streaming upload)
    func compressImagesWithPipeline(
        images: [UIImage],
        quality: ImageCompressionQuality = .low,
        format: ImageOutputFormat? = nil,
        onImageReady: @escaping @Sendable (Int, ImageCompressionResult) async -> Void
    ) async {
        guard !images.isEmpty else { return }

        let outputFormat = format ?? preferredFormat

        await withTaskGroup(of: (Int, ImageCompressionResult).self) { group in
            for (index, image) in images.enumerated() {
                group.addTask {
                    let result = await self.compressImage(image, quality: quality, format: outputFormat)
                    return (index, result)
                }
            }

            for await (index, result) in group {
                await onImageReady(index, result)
            }
        }
    }

    /// Compresses multiple images in parallel (legacy method)
    func compressImagesInParallel(
        images: [UIImage],
        quality: ImageCompressionQuality = .low,
        maxConcurrent: Int = 4,
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async -> [ImageCompressionResult] {
        guard !images.isEmpty else { return [] }

        let totalCount = images.count
        var completedCount = 0
        var results = [(Int, ImageCompressionResult)]()

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

        return results.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    // MARK: - Helper Methods

    private func resizeImageIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let originalWidth = image.size.width * image.scale
        let originalHeight = image.size.height * image.scale
        let maxOriginalDimension = max(originalWidth, originalHeight)

        guard maxOriginalDimension > maxDimension else {
            return image
        }

        let scaleFactor = maxDimension / maxOriginalDimension
        let newWidth = originalWidth * scaleFactor
        let newHeight = originalHeight * scaleFactor
        let newSize = CGSize(width: newWidth, height: newHeight)

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
