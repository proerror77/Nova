import SwiftUI
import PhotosUI
import Photos

// MARK: - Live Photo Data Model

/// Represents a Live Photo with its still image and video components
struct LivePhotoData: Identifiable {
    let id = UUID()
    let stillImage: UIImage
    let videoURL: URL
    let phLivePhoto: PHLivePhoto?
    
    /// Duration of the Live Photo video (typically ~3 seconds)
    var videoDuration: TimeInterval? {
        let asset = AVAsset(url: videoURL)
        return asset.duration.seconds
    }
}

/// Media item that can be either a regular image or a Live Photo
enum PostMediaItem: Identifiable {
    case image(UIImage)
    case livePhoto(LivePhotoData)
    
    var id: String {
        switch self {
        case .image(let image):
            return "image-\(ObjectIdentifier(image).hashValue)"
        case .livePhoto(let data):
            return data.id.uuidString
        }
    }
    
    /// Get the display image (still image for Live Photo)
    var displayImage: UIImage {
        switch self {
        case .image(let image):
            return image
        case .livePhoto(let data):
            return data.stillImage
        }
    }
    
    /// Check if this is a Live Photo
    var isLivePhoto: Bool {
        if case .livePhoto = self { return true }
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
    
    /// Load a Live Photo from PhotosPickerItem
    /// Returns LivePhotoData if it's a Live Photo, or just the image if not
    func loadMedia(from item: PhotosPickerItem) async throws -> PostMediaItem {
        isProcessing = true
        defer { isProcessing = false }
        
        // First, try to load as Live Photo
        if let livePhoto = try? await item.loadTransferable(type: PHLivePhoto.self) {
            // Extract components from Live Photo
            if let livePhotoData = try await extractLivePhotoComponents(from: livePhoto) {
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
    
    /// Clean up temporary video files
    func cleanupTemporaryFiles(for items: [PostMediaItem]) {
        for item in items {
            if case .livePhoto(let data) = item {
                try? FileManager.default.removeItem(at: data.videoURL)
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
