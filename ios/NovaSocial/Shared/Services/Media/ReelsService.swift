import Foundation

// MARK: - Reels Service
/// Handles reels-related API operations
/// Extracted from MediaService for better separation of concerns

final class ReelsService {
    private let client = APIClient.shared

    // MARK: - Reels Management

    /// Get list of reels
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
        print("[Reels] Reel deleted: \(reelId)")
        #endif
    }
}
