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

        let (data, response) = try await client.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        #if DEBUG
        print("[Media] Upload response - Status: \(httpResponse.statusCode), Size: \(data.count) bytes")
        #endif

        switch httpResponse.statusCode {
        case 200...299:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let uploadResponse = try decoder.decode(UploadResponse.self, from: data)

            // Return media URL if available, otherwise presigned URL
            if let mediaUrl = uploadResponse.mediaUrl, !mediaUrl.isEmpty {
                return mediaUrl
            } else if let presignedUrl = uploadResponse.presignedUrl, !presignedUrl.isEmpty {
                // If we got a presigned URL, we need to PUT the file there
                try await uploadToPresignedUrl(presignedUrl, data: imageData)
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

        let (data, response) = try await client.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let uploadResponse = try decoder.decode(UploadResponse.self, from: data)

            if let mediaUrl = uploadResponse.mediaUrl, !mediaUrl.isEmpty {
                return mediaUrl
            } else if let presignedUrl = uploadResponse.presignedUrl, !presignedUrl.isEmpty {
                try await uploadToPresignedUrl(presignedUrl, data: videoData)
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

    /// Upload data to S3 presigned URL
    private func uploadToPresignedUrl(_ presignedUrl: String, data: Data) async throws {
        guard let url = URL(string: presignedUrl) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = data

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(statusCode: 500, message: "Failed to upload to storage")
        }
    }

    // MARK: - Legacy Support

    /// Legacy method for backward compatibility
    func uploadImage(image: Data, userId: String, contentType: String = "image/jpeg") async throws -> String {
        return try await uploadImage(imageData: image, filename: "avatar_\(UUID().uuidString).jpg")
    }
}
