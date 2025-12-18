import SwiftUI
import PhotosUI
import Photos
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Movie Transferable for Video Loading

struct Movie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "video_\(UUID().uuidString).mov"
            let destURL = tempDir.appendingPathComponent(fileName)
            try FileManager.default.copyItem(at: received.file, to: destURL)
            return Self(url: destURL)
        }
    }
}

// MARK: - Live Photo Data Model

/// Represents a Live Photo with its still image and video components
struct LivePhotoData: Identifiable {
    let id = UUID()
    let stillImage: UIImage
    let videoURL: URL
    let phLivePhoto: PHLivePhoto?
    
    /// Duration of the Live Photo video (typically ~3 seconds)
    func getVideoDuration() async -> TimeInterval? {
        let asset = AVURLAsset(url: videoURL)
        do {
            let duration = try await asset.load(.duration)
            return duration.seconds
        } catch {
            return nil
        }
    }
}

/// Video data model
struct VideoData: Identifiable {
    let id = UUID()
    let url: URL
    let thumbnail: UIImage
    let duration: TimeInterval
}

/// Media item that can be either a regular image, Live Photo, or video
enum PostMediaItem: Identifiable {
    case image(UIImage)
    case livePhoto(LivePhotoData)
    case video(VideoData)

    var id: String {
        switch self {
        case .image(let image):
            return "image-\(ObjectIdentifier(image).hashValue)"
        case .livePhoto(let data):
            return data.id.uuidString
        case .video(let data):
            return data.id.uuidString
        }
    }

    /// Get the display image (still image for Live Photo, thumbnail for video)
    var displayImage: UIImage {
        switch self {
        case .image(let image):
            return image
        case .livePhoto(let data):
            return data.stillImage
        case .video(let data):
            return data.thumbnail
        }
    }

    /// Check if this is a Live Photo
    var isLivePhoto: Bool {
        if case .livePhoto = self { return true }
        return false
    }

    /// Check if this is a video
    var isVideo: Bool {
        if case .video = self { return true }
        return false
    }
}

// MARK: - Live Photo Manager

/// Handles extraction and processing of Live Photos
@MainActor
class LivePhotoManager: ObservableObject {
    static let shared = LivePhotoManager()
    
    @Published private(set) var isProcessing = false
    @Published private(set) var processingProgress: Double = 0
    
    private init() {}
    
    // MARK: - Load from PhotosPickerItem

    /// Load media from PhotosPickerItem - supports images, Live Photos, and videos
    func loadMedia(from item: PhotosPickerItem) async throws -> PostMediaItem {
        isProcessing = true
        defer { isProcessing = false }

        let supportedTypes = item.supportedContentTypes

        // Check if it's a video
        let videoTypes = supportedTypes.filter { $0.conforms(to: .movie) || $0.conforms(to: .video) }
        if !videoTypes.isEmpty {
            if let videoData = try await loadVideo(from: item) {
                return .video(videoData)
            }
        }

        // Check if it's a Live Photo (has both image and video components)
        let hasLivePhotoType = supportedTypes.contains { $0.identifier == "com.apple.live-photo" }
        if hasLivePhotoType {
            if let livePhotoData = try await loadLivePhoto(from: item) {
                return .livePhoto(livePhotoData)
            }
        }

        // Fall back to regular image
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            return .image(image)
        }

        throw LivePhotoError.loadFailed
    }

    /// Load video from PhotosPickerItem
    private func loadVideo(from item: PhotosPickerItem) async throws -> VideoData? {
        // Load video as Movie transferable
        guard let movie = try? await item.loadTransferable(type: Movie.self) else {
            return nil
        }

        let url = movie.url

        // Generate thumbnail
        let asset = AVURLAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true

        let thumbnail: UIImage
        do {
            let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
            thumbnail = UIImage(cgImage: cgImage)
        } catch {
            thumbnail = UIImage(systemName: "video.fill") ?? UIImage()
        }

        // Get duration
        let duration: TimeInterval
        do {
            let durationCM = try await asset.load(.duration)
            duration = durationCM.seconds
        } catch {
            duration = 0
        }

        return VideoData(url: url, thumbnail: thumbnail, duration: duration)
    }

    /// Load Live Photo from PhotosPickerItem using Photos framework
    private func loadLivePhoto(from item: PhotosPickerItem) async throws -> LivePhotoData? {
        // Get the PHAsset using the item identifier
        guard let assetId = item.itemIdentifier else { return nil }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = fetchResult.firstObject, asset.mediaSubtypes.contains(.photoLive) else {
            return nil
        }

        // Request Live Photo
        return try await withCheckedThrowingContinuation { continuation in
            let options = PHLivePhotoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestLivePhoto(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { livePhoto, info in
                guard let livePhoto = livePhoto else {
                    if let error = info?[PHImageErrorKey] as? Error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(throwing: LivePhotoError.loadFailed)
                    }
                    return
                }

                // Check if this is the final result
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded { return }

                Task {
                    do {
                        if let data = try await self.extractLivePhotoComponents(from: livePhoto) {
                            continuation.resume(returning: data)
                        } else {
                            continuation.resume(throwing: LivePhotoError.extractionFailed)
                        }
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    /// Load multiple media items from PhotosPickerItems
    func loadMedia(from items: [PhotosPickerItem], maxCount: Int = 5) async throws -> [PostMediaItem] {
        var results: [PostMediaItem] = []
        let itemsToProcess = Array(items.prefix(maxCount))
        
        for (index, item) in itemsToProcess.enumerated() {
            processingProgress = Double(index) / Double(itemsToProcess.count)
            
            do {
                let media = try await loadMedia(from: item)
                results.append(media)
            } catch {
                // Log error but continue processing other items
                print("[LivePhotoManager] Failed to load item \(index): \(error)")
            }
        }
        
        processingProgress = 1.0
        return results
    }
    
    // MARK: - Extract Live Photo Components
    
    /// Extract still image and video from PHLivePhoto
    private func extractLivePhotoComponents(from livePhoto: PHLivePhoto) async throws -> LivePhotoData? {
        // Get the asset resources
        let resources = PHAssetResource.assetResources(for: livePhoto)
        
        var stillImageData: Data?
        var videoURL: URL?
        
        // Create temporary directory for video
        let tempDir = FileManager.default.temporaryDirectory
        let videoFileName = "livephoto_\(UUID().uuidString).mov"
        let tempVideoURL = tempDir.appendingPathComponent(videoFileName)
        
        for resource in resources {
            switch resource.type {
            case .photo, .fullSizePhoto:
                // Extract still image
                stillImageData = try await extractResourceData(resource)
                
            case .pairedVideo, .fullSizePairedVideo:
                // Extract video to temp file
                try await extractResourceToFile(resource, destinationURL: tempVideoURL)
                videoURL = tempVideoURL
                
            default:
                break
            }
        }
        
        // Create LivePhotoData if we have both components
        guard let imageData = stillImageData,
              let image = UIImage(data: imageData),
              let video = videoURL,
              FileManager.default.fileExists(atPath: video.path) else {
            return nil
        }
        
        return LivePhotoData(
            stillImage: image,
            videoURL: video,
            phLivePhoto: livePhoto
        )
    }
    
    /// Extract data from PHAssetResource
    private func extractResourceData(_ resource: PHAssetResource) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            var data = Data()
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            
            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { chunk in
                    data.append(chunk)
                },
                completionHandler: { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: data)
                    }
                }
            )
        }
    }
    
    /// Extract resource to a file URL
    private func extractResourceToFile(_ resource: PHAssetResource, destinationURL: URL) async throws {
        // Remove existing file if any
        try? FileManager.default.removeItem(at: destinationURL)
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            
            PHAssetResourceManager.default().writeData(
                for: resource,
                toFile: destinationURL,
                options: options
            ) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - Cleanup

    /// Clean up temporary video files for Live Photos and videos
    func cleanupTemporaryFiles(for items: [PostMediaItem]) {
        for item in items {
            switch item {
            case .livePhoto(let data):
                try? FileManager.default.removeItem(at: data.videoURL)
            case .video(let data):
                try? FileManager.default.removeItem(at: data.url)
            case .image:
                break
            }
        }
    }
}

// MARK: - Live Photo Errors

enum LivePhotoError: LocalizedError {
    case loadFailed
    case extractionFailed
    case videoNotFound
    case imageNotFound
    case directTransferNotSupported
    
    var errorDescription: String? {
        switch self {
        case .loadFailed:
            return "Failed to load Live Photo"
        case .extractionFailed:
            return "Failed to extract Live Photo components"
        case .videoNotFound:
            return "Live Photo video component not found"
        case .imageNotFound:
            return "Live Photo image component not found"
        case .directTransferNotSupported:
            return "Direct transfer not supported for Live Photos"
        }
    }
}

// MARK: - Live Photo Picker Filter

extension PHPickerFilter {
    /// Filter that includes both images and Live Photos
    static var imagesAndLivePhotos: PHPickerFilter {
        .any(of: [.images, .livePhotos])
    }
}
