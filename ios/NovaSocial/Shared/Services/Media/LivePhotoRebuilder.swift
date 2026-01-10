import Foundation
import PhotosUI
import UIKit
import CryptoKit

// MARK: - Live Photo Rebuild Result

/// Result of rebuilding a Live Photo from downloaded resources
struct LivePhotoRebuildResult {
    let livePhoto: PHLivePhoto
    let stillImage: UIImage?
    let photoURL: URL
    let videoURL: URL
}

// MARK: - Live Photo Rebuilder Error

enum LivePhotoRebuilderError: LocalizedError {
    case downloadFailed(url: String, underlying: Error?)
    case photoDownloadFailed
    case videoDownloadFailed
    case rebuildFailed
    case invalidData
    case fileSystemError

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let url, let error):
            return "Failed to download resource from \(url): \(error?.localizedDescription ?? "unknown error")"
        case .photoDownloadFailed:
            return "Failed to download Live Photo still image"
        case .videoDownloadFailed:
            return "Failed to download Live Photo paired video"
        case .rebuildFailed:
            return "Failed to rebuild Live Photo from downloaded resources"
        case .invalidData:
            return "Invalid Live Photo data"
        case .fileSystemError:
            return "File system error while processing Live Photo"
        }
    }
}

// MARK: - Live Photo Rebuilder Service

/// Service for rebuilding PHLivePhoto objects from downloaded photo + video URLs
/// Uses PHLivePhoto.request(withResourceFileURLs:) to create native Live Photo objects
@MainActor
class LivePhotoRebuilder: ObservableObject {
    static let shared = LivePhotoRebuilder()

    // MARK: - Security
    
    /// Generate SHA256 hash for secure cache filename generation
    /// Prevents hash collisions that could lead to cross-user data leaks
    private func sha256Hash(of string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Cache

    /// In-memory cache for rebuilt Live Photos (keyed by "imageUrl|videoUrl")
    private var livePhotoCache: [String: PHLivePhoto] = [:]

    /// Disk cache directory for downloaded Live Photo resources
    private let cacheDirectory: URL

    // MARK: - URLSession

    private let urlSession: URLSession

    // MARK: - Initialization

    private init() {
        // Setup cache directory
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = cachesDir.appendingPathComponent("LivePhotos", isDirectory: true)

        // Create cache directory if needed
        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Configure URLSession with caching
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 50 * 1024 * 1024,  // 50 MB memory
            diskCapacity: 200 * 1024 * 1024,   // 200 MB disk
            diskPath: "LivePhotoDownloads"
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        self.urlSession = URLSession(configuration: config)

        #if DEBUG
        print("[LivePhotoRebuilder] Initialized with cache directory: \(cacheDirectory.path)")
        #endif
    }

    // MARK: - Public API

    /// Rebuild a Live Photo from server URLs (photo + video)
    /// Downloads resources, caches them, and uses PHLivePhoto.request to rebuild
    func rebuildLivePhoto(
        imageUrl: String,
        videoUrl: String,
        targetSize: CGSize = CGSize(width: 1920, height: 1920)
    ) async throws -> LivePhotoRebuildResult {
        let cacheKey = "\(imageUrl)|\(videoUrl)"

        // Check in-memory cache first
        if let cached = livePhotoCache[cacheKey] {
            #if DEBUG
            print("[LivePhotoRebuilder] Using cached Live Photo for: \(imageUrl)")
            #endif

            // Try to get cached file URLs
            if let urls = getCachedFileURLs(imageUrl: imageUrl, videoUrl: videoUrl),
               FileManager.default.fileExists(atPath: urls.photo.path),
               FileManager.default.fileExists(atPath: urls.video.path) {
                let stillImage = UIImage(contentsOfFile: urls.photo.path)
                return LivePhotoRebuildResult(
                    livePhoto: cached,
                    stillImage: stillImage,
                    photoURL: urls.photo,
                    videoURL: urls.video
                )
            }
        }

        // Download resources
        #if DEBUG
        print("[LivePhotoRebuilder] Downloading resources for Live Photo...")
        #endif

        let downloadResult = try await downloadLivePhotoResources(
            imageUrl: imageUrl,
            videoUrl: videoUrl
        )

        // Rebuild Live Photo using PHLivePhoto.request
        #if DEBUG
        print("[LivePhotoRebuilder] Rebuilding Live Photo from downloaded resources...")
        #endif

        let livePhoto = try await requestLivePhoto(
            photoURL: downloadResult.photoURL,
            videoURL: downloadResult.videoURL,
            targetSize: targetSize
        )

        // Cache the result
        livePhotoCache[cacheKey] = livePhoto

        #if DEBUG
        print("[LivePhotoRebuilder] Successfully rebuilt Live Photo")
        #endif

        return LivePhotoRebuildResult(
            livePhoto: livePhoto,
            stillImage: downloadResult.stillImage,
            photoURL: downloadResult.photoURL,
            videoURL: downloadResult.videoURL
        )
    }

    /// Clear in-memory cache
    func clearMemoryCache() {
        livePhotoCache.removeAll()
        #if DEBUG
        print("[LivePhotoRebuilder] Cleared in-memory cache")
        #endif
    }

    /// Clear disk cache
    func clearDiskCache() throws {
        try FileManager.default.removeItem(at: cacheDirectory)
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        #if DEBUG
        print("[LivePhotoRebuilder] Cleared disk cache")
        #endif
    }

    // MARK: - Private Methods

    /// Download both photo and video resources
    private func downloadLivePhotoResources(
        imageUrl: String,
        videoUrl: String
    ) async throws -> (photoURL: URL, videoURL: URL, stillImage: UIImage?) {
        // Check if already cached on disk
        if let cached = getCachedFileURLs(imageUrl: imageUrl, videoUrl: videoUrl),
           FileManager.default.fileExists(atPath: cached.photo.path),
           FileManager.default.fileExists(atPath: cached.video.path) {
            #if DEBUG
            print("[LivePhotoRebuilder] Using cached files from disk")
            #endif
            let stillImage = UIImage(contentsOfFile: cached.photo.path)
            return (cached.photo, cached.video, stillImage)
        }

        // Download both resources in parallel
        async let photoDownload = downloadResource(
            url: imageUrl,
            filename: "photo_\(sha256Hash(of: imageUrl)).heic"
        )
        async let videoDownload = downloadResource(
            url: videoUrl,
            filename: "video_\(sha256Hash(of: videoUrl)).mov"
        )

        let (photoURL, videoURL) = try await (photoDownload, videoDownload)

        // Load still image
        let stillImage = UIImage(contentsOfFile: photoURL.path)

        return (photoURL, videoURL, stillImage)
    }

    /// Download a single resource to cache directory
    private func downloadResource(url: String, filename: String) async throws -> URL {
        guard let downloadURL = URL(string: url) else {
            throw LivePhotoRebuilderError.downloadFailed(url: url, underlying: nil)
        }

        let destinationURL = cacheDirectory.appendingPathComponent(filename)

        // Skip if already exists
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            #if DEBUG
            print("[LivePhotoRebuilder] File already exists: \(filename)")
            #endif
            return destinationURL
        }

        do {
            let (tempURL, response) = try await urlSession.download(from: downloadURL)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw LivePhotoRebuilderError.downloadFailed(url: url, underlying: nil)
            }

            // Move to cache directory
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)

            #if DEBUG
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: destinationURL.path)[.size] as? Int) ?? 0
            print("[LivePhotoRebuilder] Downloaded \(filename): \(fileSize / 1024) KB")
            #endif

            return destinationURL
        } catch {
            throw LivePhotoRebuilderError.downloadFailed(url: url, underlying: error)
        }
    }

    /// Rebuild PHLivePhoto from local file URLs using PHLivePhoto.request
    private func requestLivePhoto(
        photoURL: URL,
        videoURL: URL,
        targetSize: CGSize
    ) async throws -> PHLivePhoto {
        var receivedDegraded: PHLivePhoto?
        
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            
            PHLivePhoto.request(
                withResourceFileURLs: [photoURL, videoURL],
                placeholderImage: nil,
                targetSize: targetSize,
                contentMode: .aspectFit
            ) { livePhoto, info in
                guard !hasResumed else { return }
                
                if let livePhoto = livePhoto {
                    let isDegraded = (info[PHLivePhotoInfoIsDegradedKey] as? Bool) ?? false
                    let isCancelled = (info[PHLivePhotoInfoCancelledKey] as? Bool) ?? false
                    
                    // Handle cancellation
                    if isCancelled {
                        hasResumed = true
                        continuation.resume(throwing: LivePhotoRebuilderError.rebuildFailed)
                        return
                    }
                    
                    if !isDegraded {
                        // Received full-quality version, return immediately
                        hasResumed = true
                        continuation.resume(returning: livePhoto)
                    } else {
                        // Save degraded version as fallback
                        receivedDegraded = livePhoto
                        
                        // Timeout fallback: if no full version arrives in 5 seconds, use degraded
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                            if !hasResumed, let degraded = receivedDegraded {
                                hasResumed = true
                                continuation.resume(returning: degraded)
                                #if DEBUG
                                print("[LivePhotoRebuilder] Using degraded version after timeout")
                                #endif
                            }
                        }
                    }
                } else if let error = info[PHLivePhotoInfoErrorKey] as? Error {
                    hasResumed = true
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Get cached file URLs if they exist
    private func getCachedFileURLs(imageUrl: String, videoUrl: String) -> (photo: URL, video: URL)? {
        let photoFilename = "photo_\(sha256Hash(of: imageUrl)).heic"
        let videoFilename = "video_\(sha256Hash(of: videoUrl)).mov"

        let photoURL = cacheDirectory.appendingPathComponent(photoFilename)
        let videoURL = cacheDirectory.appendingPathComponent(videoFilename)

        if FileManager.default.fileExists(atPath: photoURL.path) &&
           FileManager.default.fileExists(atPath: videoURL.path) {
            return (photoURL, videoURL)
        }

        return nil
    }
}

// MARK: - Live Photo Loader (ObservableObject for SwiftUI)

/// Observable loader for Live Photos in SwiftUI views
@MainActor
class LivePhotoLoader: ObservableObject {
    @Published private(set) var livePhoto: PHLivePhoto?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: Error?

    private let rebuilder = LivePhotoRebuilder.shared
    private var loadTask: Task<Void, Never>?

    /// Load and rebuild a Live Photo from server URLs
    func loadLivePhoto(imageUrl: String, videoUrl: String) async {
        // Cancel any existing load
        loadTask?.cancel()

        isLoading = true
        error = nil
        livePhoto = nil

        loadTask = Task {
            do {
                let result = try await rebuilder.rebuildLivePhoto(
                    imageUrl: imageUrl,
                    videoUrl: videoUrl
                )

                // Check if task was cancelled
                guard !Task.isCancelled else { return }

                self.livePhoto = result.livePhoto
                self.isLoading = false

                #if DEBUG
                print("[LivePhotoLoader] Successfully loaded Live Photo")
                #endif
            } catch {
                guard !Task.isCancelled else { return }

                self.error = error
                self.isLoading = false

                #if DEBUG
                print("[LivePhotoLoader] Failed to load Live Photo: \(error)")
                #endif
            }
        }

        await loadTask?.value
    }

    /// Cancel current load
    func cancel() {
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }

    deinit {
        loadTask?.cancel()
    }
}
