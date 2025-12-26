import Foundation

// MARK: - Upload Progress

/// Progress callback for upload operations
typealias UploadProgressCallback = (Double) -> Void

/// Result of a batch upload operation
struct BatchUploadResult {
    /// Map of original index to uploaded URL (preserves order mapping)
    let urlsByIndex: [Int: String]
    let failedIndices: [Int]
    let errors: [Int: Error]

    /// Convenience: URLs sorted by original index
    var successfulUrls: [String] {
        urlsByIndex.sorted { $0.key < $1.key }.map { $0.value }
    }

    /// Get URL for a specific original index
    func url(for index: Int) -> String? {
        urlsByIndex[index]
    }
}

// MARK: - Live Photo Upload Result

/// Result of uploading a Live Photo
struct LivePhotoUploadResult {
    let imageUrl: String
    let videoUrl: String
}

// MARK: - Media Response Models

/// Upload status information
struct UploadStatus: Codable {
    let uploadId: String
    let status: String  // "pending", "processing", "completed", "failed"
    let progress: Double  // 0.0 to 1.0
    let bytesUploaded: Int64
    let totalBytes: Int64
    let mediaUrl: String?

    enum CodingKeys: String, CodingKey {
        case uploadId = "upload_id"
        case status
        case progress
        case bytesUploaded = "bytes_uploaded"
        case totalBytes = "total_bytes"
        case mediaUrl = "media_url"
    }
}

/// Video metadata
struct VideoMetadata: Codable, Identifiable {
    let id: String
    let userId: String
    let videoUrl: String
    let thumbnailUrl: String?
    let duration: Int
    let title: String?
    let description: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case videoUrl = "video_url"
        case thumbnailUrl = "thumbnail_url"
        case duration
        case title
        case description
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Video list response
struct VideoListResponse: Codable {
    let videos: [VideoMetadata]
    let totalCount: Int
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case videos
        case totalCount = "total_count"
        case hasMore = "has_more"
    }
}

/// Reel metadata
struct ReelMetadata: Codable, Identifiable {
    let id: String
    let userId: String
    let videoUrl: String
    let thumbnailUrl: String?
    let caption: String?
    let viewCount: Int
    let likeCount: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case videoUrl = "video_url"
        case thumbnailUrl = "thumbnail_url"
        case caption
        case viewCount = "view_count"
        case likeCount = "like_count"
        case createdAt = "created_at"
    }
}

/// Reels list response
struct ReelsListResponse: Codable {
    let reels: [ReelMetadata]
    let totalCount: Int
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case reels
        case totalCount = "total_count"
        case hasMore = "has_more"
    }
}
