import Foundation
import UIKit
import os.log

private let draftLogger = Logger(subsystem: "com.libruce.icered", category: "DraftManager")

// MARK: - Draft Media Item (File-based)

/// Represents a media item saved to disk as part of a draft
enum DraftMediaItem: Codable {
    case imageFile(relativePath: String)
    case videoFile(relativePath: String, thumbnailPath: String, duration: TimeInterval)
    case livePhotoFile(imagePath: String, videoPath: String)

    enum CodingKeys: String, CodingKey {
        case type
        case imagePath
        case videoPath
        case thumbnailPath
        case duration
    }

    private enum MediaType: String, Codable {
        case image
        case video
        case livePhoto
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .imageFile(let path):
            try container.encode(MediaType.image, forKey: .type)
            try container.encode(path, forKey: .imagePath)
        case .videoFile(let videoPath, let thumbnailPath, let duration):
            try container.encode(MediaType.video, forKey: .type)
            try container.encode(videoPath, forKey: .videoPath)
            try container.encode(thumbnailPath, forKey: .thumbnailPath)
            try container.encode(duration, forKey: .duration)
        case .livePhotoFile(let imagePath, let videoPath):
            try container.encode(MediaType.livePhoto, forKey: .type)
            try container.encode(imagePath, forKey: .imagePath)
            try container.encode(videoPath, forKey: .videoPath)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(MediaType.self, forKey: .type)
        switch type {
        case .image:
            let path = try container.decode(String.self, forKey: .imagePath)
            self = .imageFile(relativePath: path)
        case .video:
            let videoPath = try container.decode(String.self, forKey: .videoPath)
            let thumbnailPath = try container.decode(String.self, forKey: .thumbnailPath)
            let duration = try container.decode(TimeInterval.self, forKey: .duration)
            self = .videoFile(relativePath: videoPath, thumbnailPath: thumbnailPath, duration: duration)
        case .livePhoto:
            let imagePath = try container.decode(String.self, forKey: .imagePath)
            let videoPath = try container.decode(String.self, forKey: .videoPath)
            self = .livePhotoFile(imagePath: imagePath, videoPath: videoPath)
        }
    }
}

// MARK: - Draft Model

/// Represents a saved post draft
struct Draft: Codable {
    let id: UUID
    let text: String
    let mediaItems: [DraftMediaItem]
    let channelIds: [String]
    let timestamp: Date

    init(text: String, mediaItems: [DraftMediaItem], channelIds: [String]) {
        self.id = UUID()
        self.text = text
        self.mediaItems = mediaItems
        self.channelIds = channelIds
        self.timestamp = Date()
    }
}

// MARK: - Draft Manager

/// Actor-based manager for saving and loading post drafts to the file system
/// Uses file system storage instead of UserDefaults for better memory efficiency
actor PostDraftManager {
    static let shared = PostDraftManager()

    // MARK: - Properties

    private let fileManager = FileManager.default
    private var draftDirectory: URL?
    private let draftMetadataFilename = "draft_metadata.json"

    // MARK: - Initialization

    private init() {
        setupDraftDirectory()
    }

    private func setupDraftDirectory() {
        if let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            draftDirectory = cachesDir.appendingPathComponent("Drafts", isDirectory: true)
            if let dir = draftDirectory {
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: - Save Draft

    /// Save a draft with media items to the file system
    /// - Parameters:
    ///   - text: The post text content
    ///   - mediaItems: Array of PostMediaItem to save
    ///   - channelIds: Selected channel IDs
    func saveDraft(text: String, mediaItems: [PostMediaItem], channelIds: [String]) async throws {
        guard let draftDir = draftDirectory else {
            throw DraftError.directoryNotAvailable
        }

        // Clear any existing draft first
        await clearDraft()

        // Create draft ID for this session
        let draftId = UUID()
        let draftMediaDir = draftDir.appendingPathComponent(draftId.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: draftMediaDir, withIntermediateDirectories: true)

        // Save each media item to disk
        var savedItems: [DraftMediaItem] = []

        for (index, item) in mediaItems.enumerated() {
            switch item {
            case .image(let image):
                let filename = "image_\(index).jpg"
                let imagePath = draftMediaDir.appendingPathComponent(filename)
                if let data = image.jpegData(compressionQuality: 0.8) {
                    try data.write(to: imagePath)
                    savedItems.append(.imageFile(relativePath: "\(draftId.uuidString)/\(filename)"))
                    draftLogger.debug("Saved draft image: \(filename)")
                }

            case .livePhoto(let data):
                // Save still image
                let imageFilename = "livephoto_\(index)_still.jpg"
                let imagePath = draftMediaDir.appendingPathComponent(imageFilename)
                if let imageData = data.stillImage.jpegData(compressionQuality: 0.8) {
                    try imageData.write(to: imagePath)
                }

                // Copy video file
                let videoFilename = "livephoto_\(index)_video.mov"
                let videoPath = draftMediaDir.appendingPathComponent(videoFilename)
                try fileManager.copyItem(at: data.videoURL, to: videoPath)

                savedItems.append(.livePhotoFile(
                    imagePath: "\(draftId.uuidString)/\(imageFilename)",
                    videoPath: "\(draftId.uuidString)/\(videoFilename)"
                ))
                draftLogger.debug("Saved draft Live Photo: \(index)")

            case .video(let data):
                // Save thumbnail
                let thumbnailFilename = "video_\(index)_thumb.jpg"
                let thumbnailPath = draftMediaDir.appendingPathComponent(thumbnailFilename)
                if let thumbData = data.thumbnail.jpegData(compressionQuality: 0.8) {
                    try thumbData.write(to: thumbnailPath)
                }

                // Copy video file
                let videoFilename = "video_\(index).mp4"
                let videoPath = draftMediaDir.appendingPathComponent(videoFilename)
                try fileManager.copyItem(at: data.url, to: videoPath)

                savedItems.append(.videoFile(
                    relativePath: "\(draftId.uuidString)/\(videoFilename)",
                    thumbnailPath: "\(draftId.uuidString)/\(thumbnailFilename)",
                    duration: data.duration
                ))
                draftLogger.debug("Saved draft video: \(index)")
            }
        }

        // Save draft metadata
        let draft = Draft(text: text, mediaItems: savedItems, channelIds: channelIds)
        let metadataPath = draftDir.appendingPathComponent(draftMetadataFilename)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(draft)
        try data.write(to: metadataPath)

        draftLogger.info("Draft saved: \(savedItems.count) media items")
    }

    // MARK: - Load Draft

    /// Load the saved draft metadata (does not load media into memory)
    /// - Returns: The draft metadata if one exists
    func loadDraft() async throws -> Draft? {
        guard let draftDir = draftDirectory else { return nil }

        let metadataPath = draftDir.appendingPathComponent(draftMetadataFilename)
        guard fileManager.fileExists(atPath: metadataPath.path) else { return nil }

        let data = try Data(contentsOf: metadataPath)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let draft = try decoder.decode(Draft.self, from: data)

        draftLogger.debug("Draft loaded: \(draft.mediaItems.count) media items")
        return draft
    }

    /// Load media items from a draft back into PostMediaItem format
    /// - Parameter draft: The draft to load media from
    /// - Returns: Array of PostMediaItem loaded from disk
    func loadMediaForDraft(_ draft: Draft) async -> [PostMediaItem] {
        guard let draftDir = draftDirectory else { return [] }

        var mediaItems: [PostMediaItem] = []

        for item in draft.mediaItems {
            switch item {
            case .imageFile(let relativePath):
                let imagePath = draftDir.appendingPathComponent(relativePath)
                if let image = UIImage(contentsOfFile: imagePath.path) {
                    mediaItems.append(.image(image))
                }

            case .livePhotoFile(let imagePath, let videoPath):
                let fullImagePath = draftDir.appendingPathComponent(imagePath)
                let fullVideoPath = draftDir.appendingPathComponent(videoPath)

                if let image = UIImage(contentsOfFile: fullImagePath.path),
                   fileManager.fileExists(atPath: fullVideoPath.path) {
                    let livePhotoData = LivePhotoData(
                        stillImage: image,
                        videoURL: fullVideoPath,
                        phLivePhoto: nil
                    )
                    mediaItems.append(.livePhoto(livePhotoData))
                }

            case .videoFile(let videoPath, let thumbnailPath, let duration):
                let fullVideoPath = draftDir.appendingPathComponent(videoPath)
                let fullThumbnailPath = draftDir.appendingPathComponent(thumbnailPath)

                if fileManager.fileExists(atPath: fullVideoPath.path),
                   let thumbnail = UIImage(contentsOfFile: fullThumbnailPath.path) {
                    let videoData = VideoData(
                        url: fullVideoPath,
                        thumbnail: thumbnail,
                        duration: duration
                    )
                    mediaItems.append(.video(videoData))
                }
            }
        }

        draftLogger.debug("Loaded \(mediaItems.count) media items from draft")
        return mediaItems
    }

    // MARK: - Clear Draft

    /// Clear the saved draft and delete all associated files
    func clearDraft() async {
        guard let draftDir = draftDirectory else { return }

        // Remove metadata file
        let metadataPath = draftDir.appendingPathComponent(draftMetadataFilename)
        try? fileManager.removeItem(at: metadataPath)

        // Remove all subdirectories (draft media folders)
        if let contents = try? fileManager.contentsOfDirectory(
            at: draftDir,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) {
            for item in contents {
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    try? fileManager.removeItem(at: item)
                }
            }
        }

        draftLogger.info("Draft cleared")
    }

    // MARK: - Check for Draft

    /// Check if a draft exists without loading it
    /// - Returns: True if a draft exists
    func hasDraft() async -> Bool {
        guard let draftDir = draftDirectory else { return false }
        let metadataPath = draftDir.appendingPathComponent(draftMetadataFilename)
        return fileManager.fileExists(atPath: metadataPath.path)
    }

    // MARK: - Draft Statistics

    /// Get the total size of the draft on disk
    /// - Returns: Size in bytes
    func getDraftSize() async -> Int64 {
        guard let draftDir = draftDirectory else { return 0 }

        var totalSize: Int64 = 0

        if let enumerator = fileManager.enumerator(
            at: draftDir,
            includingPropertiesForKeys: [.fileSizeKey]
        ) {
            for case let file as URL in enumerator {
                if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(size)
                }
            }
        }

        return totalSize
    }
}

// MARK: - Draft Errors

enum DraftError: LocalizedError {
    case directoryNotAvailable
    case saveFailed(Error)
    case loadFailed(Error)

    var errorDescription: String? {
        switch self {
        case .directoryNotAvailable:
            return "Draft directory is not available"
        case .saveFailed(let error):
            return "Failed to save draft: \(error.localizedDescription)"
        case .loadFailed(let error):
            return "Failed to load draft: \(error.localizedDescription)"
        }
    }
}
