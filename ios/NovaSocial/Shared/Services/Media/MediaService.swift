import Foundation

// MARK: - Media Service

/// Manages media uploads using media-service backend
/// Handles image/video uploads via multipart/form-data
class MediaService {
    private let client = APIClient.shared

    // MARK: - Upload Response

    /// Response from /api/v2/media/upload endpoint
    struct UploadResponse: Codable {
        let uploadId: String
        let presignedUrl: String?
        let mediaUrl: String?

        enum CodingKeys: String, CodingKey {
            case uploadId = "upload_id"
            case presignedUrl = "presigned_url"
            case mediaUrl = "media_url"
        }
    }

    // MARK: - Upload Methods

    /// Dedicated URLSession for media uploads with longer timeout
    private lazy var uploadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120  // 2 minutes for upload requests
        config.timeoutIntervalForResource = 300 // 5 minutes for total upload
        return URLSession(configuration: config)
    }()

    /// Upload image using multipart/form-data
    /// - Parameters:
    ///   - imageData: Image data to upload
    ///   - filename: Original filename (e.g., "photo.jpg")
    /// - Returns: Media URL or upload ID for the uploaded image
    func uploadImage(imageData: Data, filename: String = "image.jpg") async throws -> String {
        let url = URL(string: "\(APIConfig.current.baseURL)\(APIConfig.Media.uploadStart)")!

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120  // 2 minutes timeout for individual request

        // Add auth token
        if let token = client.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Build multipart body
        var body = Data()

        // Add file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        #if DEBUG
        print("[Media] Starting upload: \(imageData.count / 1024) KB to \(url.absoluteString)")
        #endif

        let (data, response) = try await uploadSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        #if DEBUG
        print("[Media] Upload response - Status: \(httpResponse.statusCode), Size: \(data.count) bytes")
        if let responseStr = String(data: data, encoding: .utf8) {
            print("[Media] Upload response body: \(responseStr)")
        }
        #endif

        switch httpResponse.statusCode {
        case 200...299:
            // Note: Don't use .convertFromSnakeCase when CodingKeys already define snake_case mappings
            let decoder = JSONDecoder()
            let uploadResponse = try decoder.decode(UploadResponse.self, from: data)

            // Return media URL if available, otherwise presigned URL
            if let mediaUrl = uploadResponse.mediaUrl, !mediaUrl.isEmpty {
                return mediaUrl
            } else if let presignedUrl = uploadResponse.presignedUrl, !presignedUrl.isEmpty {
                // If we got a presigned URL, we need to PUT the file there
                // Content-Type must match what was used when generating the presigned URL
                try await uploadToPresignedUrl(presignedUrl, data: imageData, contentType: "image/jpeg")
                return presignedUrl.components(separatedBy: "?").first ?? presignedUrl
            }
            return uploadResponse.uploadId
        case 401:
            throw APIError.unauthorized
        case 413:
            throw APIError.serverError(statusCode: 413, message: "File too large (max 20MB)")
        default:
            let message = String(data: data, encoding: .utf8) ?? "Upload failed"
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: message)
        }
    }

    /// Upload video using multipart/form-data
    func uploadVideo(videoData: Data, filename: String = "video.mp4") async throws -> String {
        let url = URL(string: "\(APIConfig.current.baseURL)\(APIConfig.Media.uploadStart)")!

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300  // 5 minutes timeout for video uploads

        if let token = client.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(videoData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        #if DEBUG
        print("[Media] Starting video upload: \(videoData.count / 1024) KB")
        #endif

        let (data, response) = try await uploadSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            // Note: Don't use .convertFromSnakeCase when CodingKeys already define snake_case mappings
            let decoder = JSONDecoder()
            let uploadResponse = try decoder.decode(UploadResponse.self, from: data)

            if let mediaUrl = uploadResponse.mediaUrl, !mediaUrl.isEmpty {
                return mediaUrl
            } else if let presignedUrl = uploadResponse.presignedUrl, !presignedUrl.isEmpty {
                // Content-Type must match what was used when generating the presigned URL
                try await uploadToPresignedUrl(presignedUrl, data: videoData, contentType: "video/mp4")
                return presignedUrl.components(separatedBy: "?").first ?? presignedUrl
            }
            return uploadResponse.uploadId
        case 401:
            throw APIError.unauthorized
        case 413:
            throw APIError.serverError(statusCode: 413, message: "File too large (max 20MB)")
        default:
            let message = String(data: data, encoding: .utf8) ?? "Upload failed"
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: message)
        }
    }

    // MARK: - Private Methods

    /// Upload data to S3/GCS presigned URL
    /// - Parameters:
    ///   - presignedUrl: The presigned URL from the server
    ///   - data: The file data to upload
    ///   - contentType: MIME type (must match what was used when generating presigned URL)
    private func uploadToPresignedUrl(_ presignedUrl: String, data: Data, contentType: String = "image/jpeg") async throws {
        guard let url = URL(string: presignedUrl) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = data
        // Content-Type MUST match what was specified when generating the presigned URL
        // Otherwise S3/GCS will reject with signature mismatch
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        request.timeoutInterval = 120  // 2 minutes for upload

        #if DEBUG
        print("[Media] Uploading to presigned URL: \(data.count / 1024) KB, Content-Type: \(contentType)")
        #endif

        let (responseData, response) = try await uploadSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        #if DEBUG
        print("[Media] Presigned URL upload response: \(httpResponse.statusCode)")
        if let responseStr = String(data: responseData, encoding: .utf8), !responseStr.isEmpty {
            print("[Media] Response body: \(responseStr)")
        }
        #endif

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: responseData, encoding: .utf8) ?? "Failed to upload to storage"
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
    }

    // MARK: - Upload Progress Tracking

    /// Get upload status and progress
    /// - Parameter uploadId: Upload ID from initial upload
    /// - Returns: Upload status information
    func getUploadStatus(uploadId: String) async throws -> UploadStatus {
        let url = URL(string: "\(APIConfig.current.baseURL)\(APIConfig.Media.uploadProgress)?upload_id=\(uploadId)")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let token = client.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        // Note: Don't use .convertFromSnakeCase when CodingKeys already define snake_case mappings
        let decoder = JSONDecoder()
        return try decoder.decode(UploadStatus.self, from: data)
    }

    /// Update upload progress (for resumable uploads)
    /// - Parameters:
    ///   - uploadId: Upload ID
    ///   - bytesUploaded: Number of bytes uploaded so far
    func updateUploadProgress(uploadId: String, bytesUploaded: Int64) async throws {
        struct Request: Codable {
            let uploadId: String
            let bytesUploaded: Int64

            enum CodingKeys: String, CodingKey {
                case uploadId = "upload_id"
                case bytesUploaded = "bytes_uploaded"
            }
        }

        let url = URL(string: "\(APIConfig.current.baseURL)\(APIConfig.Media.uploadProgress)")!

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = client.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let requestBody = Request(uploadId: uploadId, bytesUploaded: bytesUploaded)
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
    }

    /// Mark upload as complete
    /// - Parameter uploadId: Upload ID
    /// - Returns: Final media URL
    func completeUpload(uploadId: String) async throws -> String {
        struct Request: Codable {
            let uploadId: String

            enum CodingKeys: String, CodingKey {
                case uploadId = "upload_id"
            }
        }

        struct Response: Codable {
            let mediaUrl: String

            enum CodingKeys: String, CodingKey {
                case mediaUrl = "media_url"
            }
        }

        let url = URL(string: "\(APIConfig.current.baseURL)\(APIConfig.Media.uploadComplete)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = client.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let requestBody = Request(uploadId: uploadId)
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        // Note: Don't use .convertFromSnakeCase when CodingKeys already define snake_case mappings
        let decoder = JSONDecoder()
        let uploadResponse = try decoder.decode(Response.self, from: data)

        return uploadResponse.mediaUrl
    }

    /// Cancel an ongoing upload
    /// - Parameter uploadId: Upload ID to cancel
    func cancelUpload(uploadId: String) async throws {
        let url = URL(string: "\(APIConfig.current.baseURL)\(APIConfig.Media.uploadStart)/\(uploadId)")!

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        if let token = client.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        #if DEBUG
        print("[Media] Upload cancelled: \(uploadId)")
        #endif
    }

    // MARK: - Video Management

    /// Get list of user's videos
    /// - Parameters:
    ///   - limit: Maximum number of videos to return
    ///   - offset: Pagination offset
    /// - Returns: List of video metadata
    func getVideos(limit: Int = 20, offset: Int = 0) async throws -> VideoListResponse {
        let url = URL(string: "\(APIConfig.current.baseURL)\(APIConfig.Media.videos)?limit=\(limit)&offset=\(offset)")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let token = client.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(VideoListResponse.self, from: data)
    }

    /// Create video record
    /// - Parameters:
    ///   - videoUrl: URL of uploaded video
    ///   - thumbnailUrl: URL of video thumbnail
    ///   - duration: Video duration in seconds
    ///   - title: Video title
    ///   - description: Video description
    /// - Returns: Created video metadata
    func createVideo(
        videoUrl: String,
        thumbnailUrl: String?,
        duration: Int,
        title: String?,
        description: String?
    ) async throws -> VideoMetadata {
        struct Request: Codable {
            let videoUrl: String
            let thumbnailUrl: String?
            let duration: Int
            let title: String?
            let description: String?

            enum CodingKeys: String, CodingKey {
                case videoUrl = "video_url"
                case thumbnailUrl = "thumbnail_url"
                case duration
                case title
                case description
            }
        }

        let url = URL(string: "\(APIConfig.current.baseURL)\(APIConfig.Media.videos)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = client.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let requestBody = Request(
            videoUrl: videoUrl,
            thumbnailUrl: thumbnailUrl,
            duration: duration,
            title: title,
            description: description
        )
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(VideoMetadata.self, from: data)
    }

    /// Get specific video metadata
    /// - Parameter videoId: Video ID
    /// - Returns: Video metadata
    func getVideo(videoId: String) async throws -> VideoMetadata {
        let url = URL(string: "\(APIConfig.current.baseURL)\(APIConfig.Media.videos)/\(videoId)")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let token = client.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(VideoMetadata.self, from: data)
    }

    /// Update video metadata
    /// - Parameters:
    ///   - videoId: Video ID
    ///   - title: New title
    ///   - description: New description
    /// - Returns: Updated video metadata
    func updateVideo(
        videoId: String,
        title: String?,
        description: String?
    ) async throws -> VideoMetadata {
        struct Request: Codable {
            let title: String?
            let description: String?
        }

        let url = URL(string: "\(APIConfig.current.baseURL)\(APIConfig.Media.videos)/\(videoId)")!

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = client.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let requestBody = Request(title: title, description: description)
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(VideoMetadata.self, from: data)
    }

    /// Delete video
    /// - Parameter videoId: Video ID to delete
    func deleteVideo(videoId: String) async throws {
        let url = URL(string: "\(APIConfig.current.baseURL)\(APIConfig.Media.videos)/\(videoId)")!

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        if let token = client.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        #if DEBUG
        print("[Media] Video deleted: \(videoId)")
        #endif
    }

    // MARK: - Reels Management

    /// Get list of reels
    /// - Parameters:
    ///   - limit: Maximum number of reels to return
    ///   - offset: Pagination offset
    /// - Returns: List of reels
    func getReels(limit: Int = 20, offset: Int = 0) async throws -> ReelsListResponse {
        let url = URL(string: "\(APIConfig.current.baseURL)\(APIConfig.Media.reels)?limit=\(limit)&offset=\(offset)")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let token = client.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ReelsListResponse.self, from: data)
    }

    /// Create reel
    /// - Parameters:
    ///   - videoUrl: URL of uploaded reel video
    ///   - thumbnailUrl: URL of reel thumbnail
    ///   - caption: Reel caption
    /// - Returns: Created reel metadata
    func createReel(
        videoUrl: String,
        thumbnailUrl: String?,
        caption: String?
    ) async throws -> ReelMetadata {
        struct Request: Codable {
            let videoUrl: String
            let thumbnailUrl: String?
            let caption: String?

            enum CodingKeys: String, CodingKey {
                case videoUrl = "video_url"
                case thumbnailUrl = "thumbnail_url"
                case caption
            }
        }

        let url = URL(string: "\(APIConfig.current.baseURL)\(APIConfig.Media.reels)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = client.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let requestBody = Request(
            videoUrl: videoUrl,
            thumbnailUrl: thumbnailUrl,
            caption: caption
        )
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ReelMetadata.self, from: data)
    }

    /// Get specific reel
    /// - Parameter reelId: Reel ID
    /// - Returns: Reel metadata
    func getReel(reelId: String) async throws -> ReelMetadata {
        let url = URL(string: "\(APIConfig.current.baseURL)\(APIConfig.Media.reels)/\(reelId)")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let token = client.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ReelMetadata.self, from: data)
    }

    /// Delete reel
    /// - Parameter reelId: Reel ID to delete
    func deleteReel(reelId: String) async throws {
        let url = URL(string: "\(APIConfig.current.baseURL)\(APIConfig.Media.reels)/\(reelId)")!

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        if let token = client.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        #if DEBUG
        print("[Media] Reel deleted: \(reelId)")
        #endif
    }

    // MARK: - Legacy Support

    /// Legacy method for backward compatibility
    func uploadImage(image: Data, userId: String, contentType: String = "image/jpeg") async throws -> String {
        return try await uploadImage(imageData: image, filename: "avatar_\(UUID().uuidString).jpg")
    }
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
