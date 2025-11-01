import Foundation

/// Service for managing voice message sending and receiving
@Observable
final class VoiceMessageService: Sendable {
    private let apiClient: APIClient
    private let interceptor: RequestInterceptor
    private let cache: CacheManager
    private nonisolated let uploadQueue = OperationQueue()

    init(
        apiClient: APIClient = APIClient(baseURL: APIConfig.baseURL),
        cache: CacheManager = CacheManager()
    ) {
        self.apiClient = apiClient
        self.interceptor = RequestInterceptor(apiClient: apiClient)
        self.cache = cache
        uploadQueue.maxConcurrentOperationCount = 1
    }

    /// Sends a voice message to a conversation
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - audioURL: Local URL of the recorded audio file
    ///   - duration: Duration of the audio in seconds
    /// - Returns: The created message response
    func sendVoiceMessage(
        conversationId: String,
        audioURL: URL,
        duration: TimeInterval
    ) async throws -> SendMessageResponse {
        // 1. Read audio file
        let audioData = try Data(contentsOf: audioURL)

        // 2. Get presigned URL from backend
        let presignedURLResponse = try await requestPresignedURL(
            conversationId: conversationId,
            fileName: audioURL.lastPathComponent,
            fileSize: audioData.count,
            mimeType: "audio/mp4"
        )

        // 3. Upload to S3
        try await uploadAudioToS3(
            data: audioData,
            presignedURL: presignedURLResponse.url,
            headers: presignedURLResponse.headers ?? [:]
        )

        // 4. Send message metadata to backend
        let messageResponse = try await sendAudioMessageMetadata(
            conversationId: conversationId,
            audioURL: presignedURLResponse.url,
            duration: duration,
            fileSize: audioData.count
        )

        // Clean up temporary file
        try? FileManager.default.removeItem(at: audioURL)

        // Clear message cache
        cache.clear(for: "messages_\(conversationId)")

        return messageResponse
    }

    /// Requests a presigned URL for uploading audio to S3
    private func requestPresignedURL(
        conversationId: String,
        fileName: String,
        fileSize: Int,
        mimeType: String
    ) async throws -> PresignedURLResponse {
        let request = AudioPresignedUrlRequest(
            fileName: fileName,
            contentType: mimeType
        )

        let endpoint = APIEndpoint(
            path: "/api/v1/conversations/\(conversationId)/messages/audio/presigned-url",
            method: .post,
            body: request
        )

        let response: AudioPresignedUrlApiResponse = try await interceptor.executeWithRetry(endpoint)

        return PresignedURLResponse(
            url: URL(string: response.presignedUrl)!,
            headers: nil,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiration)),
            s3Key: response.s3Key
        )
    }

    /// Uploads audio file to S3 using presigned URL
    private func uploadAudioToS3(
        data: Data,
        presignedURL: URL,
        headers: [String: String]
    ) async throws {
        var request = URLRequest(url: presignedURL)
        request.httpMethod = "PUT"
        request.httpBody = data

        // Add custom headers
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Add content type if not already set
        if request.value(forHTTPHeaderField: "Content-Type") == nil {
            request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
        }

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VoiceMessageError.uploadFailed(reason: "Invalid response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw VoiceMessageError.uploadFailed(
                reason: "HTTP \(httpResponse.statusCode)"
            )
        }
    }

    /// Sends audio message metadata to backend
    private func sendAudioMessageMetadata(
        conversationId: String,
        audioURL: URL,
        duration: TimeInterval,
        fileSize: Int
    ) async throws -> SendMessageResponse {
        // Convert duration to milliseconds
        let durationMs = Int64(duration * 1000)

        let request = SendAudioMessageApiRequest(
            audioUrl: audioURL.absoluteString,
            durationMs: durationMs,
            audioCodec: "aac",  // iOS records in AAC/M4A format
            idempotencyKey: UUID().uuidString
        )

        let endpoint = APIEndpoint(
            path: "/api/v1/conversations/\(conversationId)/messages/audio",
            method: .post,
            body: request
        )

        let response: AudioMessageDto = try await interceptor.executeWithRetry(endpoint)

        return SendMessageResponse(
            id: response.id,
            sequenceNumber: Int(response.sequenceNumber),
            createdAt: response.createdAt
        )
    }

    /// Clears all voice message related caches
    func clearCache() {
        cache.clearAll()
    }
}

// MARK: - Request/Response Models

/// Request for presigned upload URL (matches backend AudioPresignedUrlRequest)
struct AudioPresignedUrlRequest: Codable, Sendable {
    let fileName: String
    let contentType: String

    enum CodingKeys: String, CodingKey {
        case fileName = "file_name"
        case contentType = "content_type"
    }
}

/// Response from presigned URL endpoint (matches backend AudioPresignedUrlResponse)
struct AudioPresignedUrlApiResponse: Codable, Sendable {
    let presignedUrl: String
    let expiration: Int64
    let s3Key: String

    enum CodingKeys: String, CodingKey {
        case presignedUrl = "presigned_url"
        case expiration
        case s3Key = "s3_key"
    }
}

/// Internal response model with additional fields
struct PresignedURLResponse: Codable, Sendable {
    let url: URL
    let headers: [String: String]?
    let expiresAt: Date
    let s3Key: String?

    enum CodingKeys: String, CodingKey {
        case url
        case headers
        case expiresAt = "expires_at"
        case s3Key = "s3_key"
    }
}

/// Request to send audio message (matches backend SendAudioMessageRequest)
struct SendAudioMessageApiRequest: Codable, Sendable {
    let audioUrl: String
    let durationMs: Int64
    let audioCodec: String
    let idempotencyKey: String

    enum CodingKeys: String, CodingKey {
        case audioUrl = "audio_url"
        case durationMs = "duration_ms"
        case audioCodec = "audio_codec"
        case idempotencyKey = "idempotency_key"
    }
}

/// Response from audio message endpoint (matches backend AudioMessageDto)
struct AudioMessageDto: Codable, Sendable {
    let id: String
    let senderId: String
    let sequenceNumber: Int64
    let createdAt: String
    let audioUrl: String
    let durationMs: Int64
    let audioCodec: String
    let transcription: String?
    let transcriptionLanguage: String?

    enum CodingKeys: String, CodingKey {
        case id
        case senderId = "sender_id"
        case sequenceNumber = "sequence_number"
        case createdAt = "created_at"
        case audioUrl = "audio_url"
        case durationMs = "duration_ms"
        case audioCodec = "audio_codec"
        case transcription
        case transcriptionLanguage = "transcription_language"
    }
}

/// Response from sending a message
struct SendMessageResponse: Codable, Sendable {
    let id: String
    let sequenceNumber: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case sequenceNumber = "sequence_number"
        case createdAt = "created_at"
    }
}

// MARK: - Error Types

enum VoiceMessageError: LocalizedError {
    case invalidAudioFile
    case uploadFailed(reason: String)
    case invalidPresignedURL
    case networkError(Error)
    case serverError

    var errorDescription: String? {
        switch self {
        case .invalidAudioFile:
            return "The audio file is invalid or corrupted"
        case .uploadFailed(let reason):
            return "Failed to upload audio: \(reason)"
        case .invalidPresignedURL:
            return "Could not get presigned upload URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError:
            return "Server error. Please try again later"
        }
    }
}
