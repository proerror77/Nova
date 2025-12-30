import SwiftUI
import PhotosUI
import Photos
import AVFoundation
import UniformTypeIdentifiers
import CoreLocation

// MARK: - Photo Metadata Model

/// Metadata extracted from photo's PHAsset
struct PhotoMetadata: Sendable {
    /// GPS location where photo was taken
    let location: CLLocation?
    /// When the photo was taken
    let creationDate: Date?
    /// When the photo was last modified
    let modificationDate: Date?
    /// Reverse geocoded location name (populated async)
    var locationName: String?

    /// Check if location data is available
    var hasLocation: Bool { location != nil }

    /// Check if any metadata is available
    var hasAnyMetadata: Bool { location != nil || creationDate != nil }

    /// Format creation date for display
    var formattedDate: String? {
        guard let date = creationDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// Format location for display (coordinates or name)
    var formattedLocation: String? {
        if let name = locationName {
            return name
        }
        guard let loc = location else { return nil }
        return String(format: "%.4f, %.4f", loc.coordinate.latitude, loc.coordinate.longitude)
    }

    static let empty = PhotoMetadata(location: nil, creationDate: nil, modificationDate: nil, locationName: nil)
}

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
/// Now includes extracted photo metadata (location, timestamp)
enum PostMediaItem: Identifiable {
    case image(UIImage, PhotoMetadata)
    case livePhoto(LivePhotoData, PhotoMetadata)
    case video(VideoData, PhotoMetadata)

    var id: String {
        switch self {
        case .image(let image, _):
            return "image-\(ObjectIdentifier(image).hashValue)"
        case .livePhoto(let data, _):
            return data.id.uuidString
        case .video(let data, _):
            return data.id.uuidString
        }
    }

    /// Get the display image (still image for Live Photo, thumbnail for video)
    var displayImage: UIImage {
        switch self {
        case .image(let image, _):
            return image
        case .livePhoto(let data, _):
            return data.stillImage
        case .video(let data, _):
            return data.thumbnail
        }
    }

    /// Get the associated photo metadata
    var metadata: PhotoMetadata {
        switch self {
        case .image(_, let meta):
            return meta
        case .livePhoto(_, let meta):
            return meta
        case .video(_, let meta):
            return meta
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

    /// Check if location metadata is available
    var hasLocation: Bool {
        metadata.hasLocation
    }

    /// Get location name if available
    var locationName: String? {
        metadata.locationName ?? metadata.formattedLocation
    }

    /// Get creation date if available
    var creationDate: Date? {
        metadata.creationDate
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
    
    // MARK: - Metadata Extraction

    /// Extract metadata from a PHAsset
    private func extractMetadata(from asset: PHAsset) async -> PhotoMetadata {
        var metadata = PhotoMetadata(
            location: asset.location,
            creationDate: asset.creationDate,
            modificationDate: asset.modificationDate,
            locationName: nil
        )

        // Reverse geocode location to get human-readable name
        if let location = asset.location {
            metadata.locationName = await reverseGeocode(location: location)
        }

        return metadata
    }

    /// Reverse geocode a location to get city/country name
    private func reverseGeocode(location: CLLocation) async -> String? {
        let geocoder = CLGeocoder()

        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }

            // Build location string: City, Country
            var components: [String] = []
            if let city = placemark.locality {
                components.append(city)
            } else if let area = placemark.administrativeArea {
                components.append(area)
            }
            if let country = placemark.country {
                components.append(country)
            }

            return components.isEmpty ? nil : components.joined(separator: ", ")
        } catch {
            #if DEBUG
            print("[LivePhotoManager] Reverse geocoding failed: \(error)")
            #endif
            return nil
        }
    }

    /// Get PHAsset from PhotosPickerItem identifier
    private func getPHAsset(from item: PhotosPickerItem) -> PHAsset? {
        guard let assetId = item.itemIdentifier else { return nil }
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        return fetchResult.firstObject
    }

    // MARK: - Load from PhotosPickerItem

    /// Load media from PhotosPickerItem - supports images, Live Photos, and videos
    /// Now includes metadata extraction (location, timestamp)
    func loadMedia(from item: PhotosPickerItem) async throws -> PostMediaItem {
        isProcessing = true
        defer { isProcessing = false }

        // Extract metadata from PHAsset if available
        let metadata: PhotoMetadata
        if let asset = getPHAsset(from: item) {
            metadata = await extractMetadata(from: asset)
            #if DEBUG
            if metadata.hasAnyMetadata {
                print("[LivePhotoManager] Extracted metadata - Location: \(metadata.locationName ?? "N/A"), Date: \(metadata.formattedDate ?? "N/A")")
            }
            #endif
        } else {
            metadata = .empty
        }

        let supportedTypes = item.supportedContentTypes

        // Check if it's a video
        let videoTypes = supportedTypes.filter { $0.conforms(to: .movie) || $0.conforms(to: .video) }
        if !videoTypes.isEmpty {
            if let videoData = try await loadVideo(from: item) {
                return .video(videoData, metadata)
            }
        }

        // Check if it's a Live Photo (has both image and video components)
        let hasLivePhotoType = supportedTypes.contains { $0.identifier == "com.apple.live-photo" }
        if hasLivePhotoType {
            if let livePhotoData = try await loadLivePhoto(from: item) {
                return .livePhoto(livePhotoData, metadata)
            }
        }

        // Fall back to regular image
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            return .image(image, metadata)
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

        // Generate thumbnail using async API (iOS 18+ compatible)
        let asset = AVURLAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true

        let thumbnail: UIImage
        do {
            let (cgImage, _) = try await imageGenerator.image(at: .zero)
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

        // Request Live Photo - use fastFormat for speed, we'll get full quality on upload
        return try await withCheckedThrowingContinuation { continuation in
            let options = PHLivePhotoRequestOptions()
            options.deliveryMode = .fastFormat  // Fast loading for display
            options.isNetworkAccessAllowed = true

            // Use a reasonable target size instead of maximum
            let targetSize = CGSize(width: 1920, height: 1920)

            PHImageManager.default().requestLivePhoto(
                for: asset,
                targetSize: targetSize,
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

                // Accept even degraded version for fast display
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
    
    /// Load multiple media items from PhotosPickerItems - PARALLEL processing for speed
    func loadMedia(from items: [PhotosPickerItem], maxCount: Int = 5) async throws -> [PostMediaItem] {
        let itemsToProcess = Array(items.prefix(maxCount))
        guard !itemsToProcess.isEmpty else { return [] }

        isProcessing = true
        defer { isProcessing = false }

        #if DEBUG
        let startTime = CFAbsoluteTimeGetCurrent()
        print("[LivePhotoManager] Starting parallel load of \(itemsToProcess.count) items")
        #endif

        // Process all items in parallel using TaskGroup
        let results = await withTaskGroup(of: (Int, PostMediaItem?).self) { group in
            for (index, item) in itemsToProcess.enumerated() {
                group.addTask {
                    do {
                        let media = try await self.loadMediaItem(from: item)
                        return (index, media)
                    } catch {
                        #if DEBUG
                        print("[LivePhotoManager] Failed to load item \(index): \(error)")
                        #endif
                        return (index, nil)
                    }
                }
            }

            var indexedResults: [(Int, PostMediaItem)] = []
            var completed = 0

            for await (index, media) in group {
                completed += 1
                processingProgress = Double(completed) / Double(itemsToProcess.count)

                if let media = media {
                    indexedResults.append((index, media))
                }
            }

            // Sort by original index to maintain order
            return indexedResults.sorted { $0.0 < $1.0 }.map { $0.1 }
        }

        processingProgress = 1.0

        #if DEBUG
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        print("[LivePhotoManager] Loaded \(results.count) items in \(String(format: "%.2f", elapsed))s")
        #endif

        return results
    }

    /// Load single media item without setting isProcessing (for parallel use)
    /// Includes metadata extraction for location-aware AI tagging
    private func loadMediaItem(from item: PhotosPickerItem) async throws -> PostMediaItem {
        // Extract metadata from PHAsset if available
        let metadata: PhotoMetadata
        if let asset = getPHAsset(from: item) {
            metadata = await extractMetadata(from: asset)
        } else {
            metadata = .empty
        }

        let supportedTypes = item.supportedContentTypes

        // Check if it's a video
        let videoTypes = supportedTypes.filter { $0.conforms(to: .movie) || $0.conforms(to: .video) }
        if !videoTypes.isEmpty {
            if let videoData = try await loadVideo(from: item) {
                return .video(videoData, metadata)
            }
        }

        // Check if it's a Live Photo (has both image and video components)
        let hasLivePhotoType = supportedTypes.contains { $0.identifier == "com.apple.live-photo" }
        if hasLivePhotoType {
            if let livePhotoData = try await loadLivePhoto(from: item) {
                return .livePhoto(livePhotoData, metadata)
            }
        }

        // Fall back to regular image - use faster loading
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            return .image(image, metadata)
        }

        throw LivePhotoError.loadFailed
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
            case .livePhoto(let data, _):
                try? FileManager.default.removeItem(at: data.videoURL)
            case .video(let data, _):
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
