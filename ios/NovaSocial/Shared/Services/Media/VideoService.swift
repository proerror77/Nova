import Foundation

// MARK: - Video Service
/// Handles video-related API operations
/// Extracted from MediaService for better separation of concerns

final class VideoService {
    private let client = APIClient.shared

    // MARK: - Video Management

    /// Get list of user's videos
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
        print("[Video] Video deleted: \(videoId)")
        #endif
    }
}
