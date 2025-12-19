import AVFoundation
import UIKit

// MARK: - Video Compression Quality

enum VideoCompressionQuality {
    case low        // 480p, high compression
    case medium     // 720p, balanced
    case high       // 1080p, low compression
    case original   // No compression

    var preset: String {
        switch self {
        case .low:
            return AVAssetExportPresetMediumQuality
        case .medium:
            return AVAssetExportPreset1280x720
        case .high:
            return AVAssetExportPreset1920x1080
        case .original:
            return AVAssetExportPresetPassthrough
        }
    }

    var maxBitrate: Int {
        switch self {
        case .low:
            return 1_500_000      // 1.5 Mbps
        case .medium:
            return 3_000_000      // 3 Mbps
        case .high:
            return 6_000_000      // 6 Mbps
        case .original:
            return Int.max
        }
    }

    var maxDimension: CGFloat {
        switch self {
        case .low:
            return 480
        case .medium:
            return 720
        case .high:
            return 1080
        case .original:
            return CGFloat.greatestFiniteMagnitude
        }
    }
}

// MARK: - Compression Result

struct VideoCompressionResult {
    let outputURL: URL
    let originalSize: Int64
    let compressedSize: Int64
    let compressionRatio: Double
    let duration: TimeInterval

    var savedBytes: Int64 {
        originalSize - compressedSize
    }

    var savedPercentage: Double {
        guard originalSize > 0 else { return 0 }
        return Double(savedBytes) / Double(originalSize) * 100
    }
}

// MARK: - Video Compressor

actor VideoCompressor {

    static let shared = VideoCompressor()

    private init() {}

    // MARK: - Compression Progress Callback

    typealias ProgressCallback = @Sendable (Double) -> Void

    // MARK: - Compress Video

    /// Compresses a video file with the specified quality
    /// - Parameters:
    ///   - inputURL: URL of the source video
    ///   - quality: Compression quality preset
    ///   - progressCallback: Optional callback for compression progress
    /// - Returns: Compression result with output URL and statistics
    func compressVideo(
        inputURL: URL,
        quality: VideoCompressionQuality = .medium,
        progressCallback: ProgressCallback? = nil
    ) async throws -> VideoCompressionResult {

        // Get original file size
        let originalSize = try getFileSize(url: inputURL)

        // Skip compression if quality is original or file is already small
        if quality == .original || originalSize < 1_000_000 { // < 1MB
            #if DEBUG
            print("[VideoCompressor] Skipping compression - file already small or original quality requested")
            #endif
            let duration = try await getVideoDuration(url: inputURL)
            return VideoCompressionResult(
                outputURL: inputURL,
                originalSize: originalSize,
                compressedSize: originalSize,
                compressionRatio: 1.0,
                duration: duration
            )
        }

        let asset = AVURLAsset(url: inputURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

        // Check if video needs compression based on resolution
        let needsCompression = try await checkIfNeedsCompression(asset: asset, quality: quality)
        if !needsCompression {
            #if DEBUG
            print("[VideoCompressor] Video resolution already within limits")
            #endif
            let duration = try await getVideoDuration(url: inputURL)
            return VideoCompressionResult(
                outputURL: inputURL,
                originalSize: originalSize,
                compressedSize: originalSize,
                compressionRatio: 1.0,
                duration: duration
            )
        }

        // Create output URL
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("compressed_\(UUID().uuidString).mp4")

        // Get export session
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: quality.preset) else {
            throw VideoCompressionError.exportSessionCreationFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        // Start progress monitoring
        let progressTask = Task {
            while !Task.isCancelled {
                let progress = Double(exportSession.progress)
                progressCallback?(progress)

                if exportSession.status == .completed || exportSession.status == .failed || exportSession.status == .cancelled {
                    break
                }

                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }

        defer {
            progressTask.cancel()
        }

        #if DEBUG
        let startTime = CFAbsoluteTimeGetCurrent()
        print("[VideoCompressor] Starting compression with quality: \(quality)")
        print("[VideoCompressor] Original size: \(ByteCountFormatter.string(fromByteCount: originalSize, countStyle: .file))")
        #endif

        // Export
        await exportSession.export()

        // Check result
        switch exportSession.status {
        case .completed:
            let compressedSize = try getFileSize(url: outputURL)
            let duration = try await getVideoDuration(url: inputURL)
            let ratio = Double(compressedSize) / Double(originalSize)

            #if DEBUG
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            print("[VideoCompressor] Compression completed in \(String(format: "%.2f", elapsed))s")
            print("[VideoCompressor] Compressed size: \(ByteCountFormatter.string(fromByteCount: compressedSize, countStyle: .file))")
            print("[VideoCompressor] Compression ratio: \(String(format: "%.1f", ratio * 100))%")
            #endif

            progressCallback?(1.0)

            return VideoCompressionResult(
                outputURL: outputURL,
                originalSize: originalSize,
                compressedSize: compressedSize,
                compressionRatio: ratio,
                duration: duration
            )

        case .failed:
            throw exportSession.error ?? VideoCompressionError.exportFailed

        case .cancelled:
            throw VideoCompressionError.exportCancelled

        default:
            throw VideoCompressionError.unknownError
        }
    }

    /// Compresses multiple videos in parallel
    /// - Parameters:
    ///   - urls: Array of video URLs to compress
    ///   - quality: Compression quality preset
    ///   - maxConcurrent: Maximum number of concurrent compressions
    ///   - progressCallback: Callback for overall progress
    /// - Returns: Array of compression results
    func compressVideosInParallel(
        urls: [URL],
        quality: VideoCompressionQuality = .medium,
        maxConcurrent: Int = 2,
        progressCallback: ProgressCallback? = nil
    ) async throws -> [VideoCompressionResult] {

        guard !urls.isEmpty else { return [] }

        var results: [VideoCompressionResult] = []
        var completedCount = 0
        let totalCount = urls.count

        // Process in batches for controlled parallelism
        for batch in urls.chunked(into: maxConcurrent) {
            let batchResults = try await withThrowingTaskGroup(of: VideoCompressionResult.self) { group in
                for url in batch {
                    group.addTask {
                        try await self.compressVideo(inputURL: url, quality: quality)
                    }
                }

                var batchResults: [VideoCompressionResult] = []
                for try await result in group {
                    batchResults.append(result)
                    completedCount += 1
                    progressCallback?(Double(completedCount) / Double(totalCount))
                }
                return batchResults
            }
            results.append(contentsOf: batchResults)
        }

        return results
    }

    // MARK: - Helper Methods

    private func getFileSize(url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }

    private func getVideoDuration(url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return duration.seconds
    }

    private func checkIfNeedsCompression(asset: AVURLAsset, quality: VideoCompressionQuality) async throws -> Bool {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            return false
        }

        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)

        // Apply transform to get actual dimensions
        let transformedSize = size.applying(transform)
        let width = abs(transformedSize.width)
        let height = abs(transformedSize.height)
        let maxDimension = max(width, height)

        return maxDimension > quality.maxDimension
    }

    /// Generates a thumbnail from a video
    func generateThumbnail(from url: URL, at time: TimeInterval = 0) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 600, height: 600)

        let cmTime = CMTime(seconds: time, preferredTimescale: 600)

        do {
            let (cgImage, _) = try await imageGenerator.image(at: cmTime)
            return UIImage(cgImage: cgImage)
        } catch {
            #if DEBUG
            print("[VideoCompressor] Thumbnail generation failed: \(error)")
            #endif
            return nil
        }
    }
}

// MARK: - Errors

enum VideoCompressionError: LocalizedError {
    case exportSessionCreationFailed
    case exportFailed
    case exportCancelled
    case unknownError

    var errorDescription: String? {
        switch self {
        case .exportSessionCreationFailed:
            return "Failed to create video export session"
        case .exportFailed:
            return "Video compression failed"
        case .exportCancelled:
            return "Video compression was cancelled"
        case .unknownError:
            return "Unknown video compression error"
        }
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
