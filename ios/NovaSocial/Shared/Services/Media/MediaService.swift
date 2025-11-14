import Foundation

// MARK: - Media Service

/// Manages media uploads using media-service backend
/// Handles image/video uploads and CDN integration
class MediaService {
    private let client = APIClient.shared

    func uploadImage(image: Data, userId: String, contentType: String = "image/jpeg") async throws -> String {
        struct StartUploadRequest: Codable {
            let user_id: String
            let file_name: String
            let file_size: Int64
            let content_type: String
        }

        struct StartUploadResponse: Codable {
            struct Upload: Codable {
                let id: String
            }
            let upload: Upload
        }

        // Start upload
        let startRequest = StartUploadRequest(
            user_id: userId,
            file_name: "avatar_\(UUID().uuidString).jpg",
            file_size: Int64(image.count),
            content_type: contentType
        )

        let startResponse: StartUploadResponse = try await client.request(
            endpoint: APIConfig.Media.uploadStart,
            body: startRequest
        )

        let uploadId = startResponse.upload.id

        // TODO: Implement actual file upload to S3/CDN
        // For now, return mock URL
        return "https://cdn.nova.social/avatars/\(uploadId).jpg"
    }
}
