import Foundation

// MARK: - Media Service

/// Manages media uploads using media-service backend
/// Handles image/video uploads via multipart/form-data
class MediaService {
    private let client = APIClient.shared

    // MARK: - Delegated Services
    private lazy var videoService = VideoService()
    private lazy var reelsService = ReelsService()

    // MARK: - Content Type Helper

    /// Determine MIME content type from filename extension
    static func contentType(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "webp":
            return "image/webp"
        case "heic", "heif":
            return "image/heic"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "mp4", "m4v":
            return "video/mp4"
        case "mov":
            return "video/quicktime"
        case "m4a":
            return "audio/mp4"
        default:
            return "application/octet-stream"
        }
    }

    // MARK: - Upload Response

    /// Response from /api/v2/media/upload endpoint
    struct UploadResponse: Codable {
        let uploadId: String?  // 可选，因为服务器可能只返回 media_url
        let presignedUrl: String?
        let mediaUrl: String?

        enum CodingKeys: String, CodingKey {
            case uploadId = "upload_id"
            case presignedUrl = "presigned_url"
            case mediaUrl = "media_url"
        }
    }

    // MARK: - Upload Methods

    /// Dedicated URLSession for media uploads with optimized settings
    private lazy var uploadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60   // 1 minute for upload requests
        config.timeoutIntervalForResource = 180 // 3 minutes for total upload
        config.httpMaximumConnectionsPerHost = 6 // More parallel connections to GCS
        config.httpShouldUsePipelining = true   // Enable HTTP pipelining
        config.urlCache = nil                   // No caching for uploads
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        // Enable HTTP/2 multiplexing
        config.multipathServiceType = .handover
        return URLSession(configuration: config)
    }()
    
    // MARK: - Parallel Upload Methods
    
    /// Upload multiple images in parallel with progress tracking
    /// - Parameters:
    ///   - images: Array of (imageData, filename) tuples
    ///   - maxConcurrent: Maximum concurrent uploads (default: 5)
    ///   - progressCallback: Called with overall progress (0.0 to 1.0)
    /// - Returns: BatchUploadResult containing successful URLs and any failures
    func uploadImagesInParallel(
        images: [(data: Data, filename: String)],
        maxConcurrent: Int = 5,
        progressCallback: UploadProgressCallback? = nil
    ) async -> BatchUploadResult {
        guard !images.isEmpty else {
            return BatchUploadResult(urlsByIndex: [:], failedIndices: [], errors: [:])
        }
        
        var urlsByIndex: [Int: String] = [:]
        var failedIndices: [Int] = []
        var errors: [Int: Error] = [:]
        var completedCount = 0
        let totalCount = images.count
        // Note: Lock removed - for await loop processes results sequentially, no concurrent access
        
        await withTaskGroup(of: (Int, Result<String, Error>).self) { group in
            var activeCount = 0
            var nextIndex = 0
            
            // Helper to add task
            func addNextTask() {
                if nextIndex < images.count {
                    let index = nextIndex
                    let image = images[index]
                    nextIndex += 1
                    activeCount += 1
                    
                    group.addTask {
                        do {
                            var lastError: Error?
                            for attempt in 1...3 {
                                do {
                                    let url = try await self.uploadImage(
                                        imageData: image.data,
                                        filename: image.filename
                                    )
                                    return (index, .success(url))
                                } catch let apiError as APIError {
                                    lastError = apiError
                                    // Retry transient backend failures (e.g., 503s from gateway/media-service).
                                    if apiError.isRetryable, attempt < 3 {
                                        try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                                        continue
                                    }
                                    throw apiError
                                } catch {
                                    lastError = error
                                    throw error
                                }
                            }
                            return (index, .failure(lastError ?? APIError.serviceUnavailable))
                        } catch {
                            return (index, .failure(error))
                        }
                    }
                }
            }
            
            // Start initial batch
            for _ in 0..<min(maxConcurrent, images.count) {
                addNextTask()
            }
            
            // Process results and add more tasks
            for await (index, result) in group {
                activeCount -= 1
                completedCount += 1

                switch result {
                case .success(let url):
                    urlsByIndex[index] = url
                case .failure(let error):
                    failedIndices.append(index)
                    errors[index] = error
                }

                // Report progress
                let progress = Double(completedCount) / Double(totalCount)
                
                await MainActor.run {
                    progressCallback?(progress)
                }
                
                // Add next task if available
                addNextTask()
            }
        }
        
        return BatchUploadResult(
            urlsByIndex: urlsByIndex,
            failedIndices: failedIndices.sorted(),
            errors: errors
        )
    }
    
    /// Upload image with progress tracking using URLSession delegate
    /// - Parameters:
    ///   - imageData: Image data to upload
    ///   - filename: Original filename
    ///   - progressCallback: Called with upload progress (0.0 to 1.0)
    /// - Returns: Media URL for the uploaded image
    func uploadImageWithProgress(
        imageData: Data,
        filename: String = "image.jpg",
        progressCallback: UploadProgressCallback? = nil
    ) async throws -> String {
        #if DEBUG
        print("[Media] Starting lightweight upload with progress: \(imageData.count / 1024) KB")
        #endif

        // Step 1: Call initiate endpoint with only metadata (no file data) - instant
        let initiateUrl = URL(string: "\(APIConfig.current.baseURL)\(APIConfig.Media.uploadInitiate)")!

        struct InitiateRequest: Codable {
            let filename: String
            let sizeBytes: Int64
            let contentType: String?

            enum CodingKeys: String, CodingKey {
                case filename
                case sizeBytes = "size_bytes"
                case contentType = "content_type"
            }
        }

        struct InitiateResponse: Codable {
            let uploadId: String
            let presignedUrl: String
            let expiresAt: Int64

            enum CodingKeys: String, CodingKey {
                case uploadId = "upload_id"
                case presignedUrl = "presigned_url"
                case expiresAt = "expires_at"
            }
        }

        var initiateRequest = URLRequest(url: initiateUrl)
        initiateRequest.httpMethod = "POST"
        initiateRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        initiateRequest.timeoutInterval = 30

        if let token = client.getAuthToken() {
            initiateRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let initiateBody = InitiateRequest(
            filename: filename,
            sizeBytes: Int64(imageData.count),
            contentType: "image/jpeg"
        )
        initiateRequest.httpBody = try JSONEncoder().encode(initiateBody)

        let (initiateData, initiateHttpResponse) = try await URLSession.shared.data(for: initiateRequest)

        guard let initiateResponse = initiateHttpResponse as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard initiateResponse.statusCode >= 200 && initiateResponse.statusCode < 300 else {
            let message = String(data: initiateData, encoding: .utf8) ?? "Initiate upload failed"
            throw APIError.serverError(statusCode: initiateResponse.statusCode, message: message)
        }

        let decoder = JSONDecoder()
        let initiateResult = try decoder.decode(InitiateResponse.self, from: initiateData)

        #if DEBUG
        print("[Media] Got presigned URL, upload_id: \(initiateResult.uploadId)")
        #endif

        // Step 2: Upload directly to GCS using presigned URL with progress tracking
        guard let gcsUrl = URL(string: initiateResult.presignedUrl) else {
            throw APIError.invalidResponse
        }

        var gcsRequest = URLRequest(url: gcsUrl)
        gcsRequest.httpMethod = "PUT"
        gcsRequest.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        gcsRequest.timeoutInterval = 120

        // Use upload task for progress tracking
        let delegate = UploadProgressDelegate(progressCallback: { progress in
            // Scale GCS upload progress to 0.1-0.9 range (initiate was 0.0-0.1, complete will be 0.9-1.0)
            let scaledProgress = 0.1 + (progress * 0.8)
            progressCallback?(scaledProgress)
        })
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        defer {
            session.finishTasksAndInvalidate()
        }

        // Report initial progress
        await MainActor.run {
            progressCallback?(0.1)
        }

        let (_, gcsResponse) = try await session.upload(for: gcsRequest, from: imageData)

        guard let gcsHttpResponse = gcsResponse as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard gcsHttpResponse.statusCode >= 200 && gcsHttpResponse.statusCode < 300 else {
            throw APIError.serverError(statusCode: gcsHttpResponse.statusCode, message: "GCS upload failed")
        }

        #if DEBUG
        print("[Media] GCS upload completed")
        #endif

        // Step 3: Complete the upload to get the final CDN URL
        await MainActor.run {
            progressCallback?(0.9)
        }

        let mediaUrl = try await completeUpload(uploadId: initiateResult.uploadId)

        await MainActor.run {
            progressCallback?(1.0)
        }

        #if DEBUG
        print("[Media] Upload complete, CDN URL: \(mediaUrl)")
        #endif

        return mediaUrl
    }

    /// Lightweight upload: only sends metadata to get presigned URL, then uploads directly to GCS
    /// This is much faster than multipart upload as it avoids sending image data twice.
    /// - Parameters:
    ///   - imageData: Image data to upload
    ///   - filename: Original filename (e.g., "photo.jpg", "image.webp", "photo.heic")
    /// - Returns: CDN URL for the uploaded image
    func uploadImage(imageData: Data, filename: String = "image.jpg") async throws -> String {
        // Determine content type based on filename extension
        let contentType = Self.contentType(for: filename)

        #if DEBUG
        print("[Media] Starting upload: \(imageData.count / 1024) KB, type: \(contentType)")
        #endif

        // Try the new lightweight initiate endpoint first, fallback to legacy multipart if not available
        let initiateResult = try await initiateUpload(filename: filename, sizeBytes: Int64(imageData.count), contentType: contentType, imageData: imageData)

        #if DEBUG
        print("[Media] Got presigned URL, upload_id: \(initiateResult.uploadId)")
        #endif

        // Step 2: Upload directly to GCS using presigned URL (this is the only time image data is sent!)
        try await uploadToPresignedUrl(initiateResult.presignedUrl, data: imageData, contentType: contentType)

        #if DEBUG
        print("[Media] Upload to GCS completed, completing upload...")
        #endif

        // Step 3: Complete the upload to get the final CDN URL
        let mediaUrl = try await completeUpload(uploadId: initiateResult.uploadId)

        #if DEBUG
        print("[Media] Upload complete, media URL: \(mediaUrl)")
        #endif

        return mediaUrl
    }


    /// Response from initiate upload (works with both new and legacy endpoints)
    private struct InitiateUploadResult {
        let uploadId: String
        let presignedUrl: String
    }

    /// Initiate upload - tries new lightweight endpoint first, falls back to legacy multipart if not available
    private func initiateUpload(filename: String, sizeBytes: Int64, contentType: String, imageData: Data) async throws -> InitiateUploadResult {
        #if DEBUG
        print("[Media] Initiating upload for: \(filename), size: \(sizeBytes) bytes")
        #endif

        // First try the new lightweight endpoint (no file data sent)
        do {
            let result = try await initiateUploadNew(filename: filename, sizeBytes: sizeBytes, contentType: contentType)
            #if DEBUG
            print("[Media] ✅ Using new lightweight initiate endpoint - upload_id: \(result.uploadId)")
            #endif
            return result
        } catch {
            #if DEBUG
            print("[Media] ⚠️ New endpoint failed: \(error.localizedDescription), falling back to legacy...")
            #endif
        }

        // Fallback to legacy multipart endpoint
        #if DEBUG
        print("[Media] 📤 Using legacy multipart upload endpoint")
        #endif

        do {
            let result = try await initiateUploadLegacy(filename: filename, imageData: imageData)
            #if DEBUG
            print("[Media] ✅ Legacy upload initiated - upload_id: \(result.uploadId)")
            #endif
            return result
        } catch {
            #if DEBUG
            print("[Media] ❌ Legacy upload also failed: \(error.localizedDescription)")
            #endif
            throw error
        }
    }

    /// New lightweight initiate endpoint (JSON body, no file data)
    private func initiateUploadNew(filename: String, sizeBytes: Int64, contentType: String) async throws -> InitiateUploadResult {
        struct InitiateRequest: Codable {
            let filename: String
            let sizeBytes: Int64
            let contentType: String?

            enum CodingKeys: String, CodingKey {
                case filename
                case sizeBytes = "size_bytes"
                case contentType = "content_type"
            }
        }

        struct InitiateResponse: Codable {
            let uploadId: String
            let presignedUrl: String
            let expiresAt: Int64

            enum CodingKeys: String, CodingKey {
                case uploadId = "upload_id"
                case presignedUrl = "presigned_url"
                case expiresAt = "expires_at"
            }
        }

        let initiateUrl = URL(string: "\(APIConfig.current.baseURL)\(APIConfig.Media.uploadInitiate)")!

        var request = URLRequest(url: initiateUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        if let token = client.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let requestBody = InitiateRequest(filename: filename, sizeBytes: sizeBytes, contentType: contentType)
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: "Initiate failed")
        }

        let initiateResponse = try JSONDecoder().decode(InitiateResponse.self, from: data)
        return InitiateUploadResult(uploadId: initiateResponse.uploadId, presignedUrl: initiateResponse.presignedUrl)
    }

    /// Legacy multipart initiate endpoint (file data is sent but drained by server)
    private func initiateUploadLegacy(filename: String, imageData: Data) async throws -> InitiateUploadResult {
        struct LegacyResponse: Codable {
            let uploadId: String
            let presignedUrl: String
            let expiresAt: Int64?

            enum CodingKeys: String, CodingKey {
                case uploadId = "upload_id"
                case presignedUrl = "presigned_url"
                case expiresAt = "expires_at"
            }
        }

        let url = URL(string: "\(APIConfig.current.baseURL)\(APIConfig.Media.uploadStart)")!
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        if let token = client.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Build multipart body
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            let message = String(data: data, encoding: .utf8) ?? "Upload failed"
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: message)
        }

        let legacyResponse = try JSONDecoder().decode(LegacyResponse.self, from: data)
        return InitiateUploadResult(uploadId: legacyResponse.uploadId, presignedUrl: legacyResponse.presignedUrl)
    }

    /// Lightweight video upload: only sends metadata to get presigned URL, then uploads directly to GCS
    /// - Parameters:
    ///   - videoData: Video data to upload
    ///   - filename: Original filename (e.g., "video.mp4")
    /// - Returns: CDN URL for the uploaded video
    func uploadVideo(videoData: Data, filename: String = "video.mp4") async throws -> String {
        #if DEBUG
        print("[Media] Starting lightweight video upload: \(videoData.count / 1024) KB")
        #endif

        // Step 1: Call initiate endpoint with only metadata (no file data)
        let initiateUrl = URL(string: "\(APIConfig.current.baseURL)\(APIConfig.Media.uploadInitiate)")!

        struct InitiateRequest: Codable {
            let filename: String
            let sizeBytes: Int64
            let contentType: String?

            enum CodingKeys: String, CodingKey {
                case filename
                case sizeBytes = "size_bytes"
                case contentType = "content_type"
            }
        }

        struct InitiateResponse: Codable {
            let uploadId: String
            let presignedUrl: String
            let expiresAt: Int64

            enum CodingKeys: String, CodingKey {
                case uploadId = "upload_id"
                case presignedUrl = "presigned_url"
                case expiresAt = "expires_at"
            }
        }

        var initiateRequest = URLRequest(url: initiateUrl)
        initiateRequest.httpMethod = "POST"
        initiateRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        initiateRequest.timeoutInterval = 30

        if let token = client.getAuthToken() {
            initiateRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let requestBody = InitiateRequest(
            filename: filename,
            sizeBytes: Int64(videoData.count),
            contentType: "video/mp4"
        )
        initiateRequest.httpBody = try JSONEncoder().encode(requestBody)

        let (initiateData, initiateResponse) = try await URLSession.shared.data(for: initiateRequest)

        guard let httpResponse = initiateResponse as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (initiateResponse as? HTTPURLResponse)?.statusCode ?? 0
            if statusCode == 401 {
                throw APIError.unauthorized
            }
            if statusCode == 413 {
                throw APIError.serverError(statusCode: 413, message: "File too large")
            }
            let message = String(data: initiateData, encoding: .utf8) ?? "Failed to initiate upload"
            throw APIError.serverError(statusCode: statusCode, message: message)
        }

        let initiateResult = try JSONDecoder().decode(InitiateResponse.self, from: initiateData)

        #if DEBUG
        print("[Media] Got presigned URL for video, upload_id: \(initiateResult.uploadId)")
        #endif

        // Step 2: Upload directly to GCS using presigned URL
        try await uploadToPresignedUrl(initiateResult.presignedUrl, data: videoData, contentType: "video/mp4")

        #if DEBUG
        print("[Media] Video upload to GCS completed, completing upload...")
        #endif

        // Step 3: Complete the upload to get the final CDN URL
        let mediaUrl = try await completeUpload(uploadId: initiateResult.uploadId)

        #if DEBUG
        print("[Media] Video upload complete, CDN URL: \(mediaUrl)")
        #endif

        return mediaUrl
    }

    /// Lightweight audio upload: only sends metadata to get presigned URL, then uploads directly to GCS
    /// - Parameters:
    ///   - audioData: Audio data to upload (M4A format)
    ///   - filename: Original filename (e.g., "voice.m4a")
    /// - Returns: CDN URL for the uploaded audio
    func uploadAudio(audioData: Data, filename: String = "voice.m4a") async throws -> String {
        #if DEBUG
        print("[Media] Starting lightweight audio upload: \(audioData.count / 1024) KB")
        #endif

        // Step 1: Call initiate endpoint with only metadata
        let initiateUrl = URL(string: "\(APIConfig.current.baseURL)\(APIConfig.Media.uploadInitiate)")!

        struct InitiateRequest: Codable {
            let filename: String
            let sizeBytes: Int64
            let contentType: String?

            enum CodingKeys: String, CodingKey {
                case filename
                case sizeBytes = "size_bytes"
                case contentType = "content_type"
            }
        }

        struct InitiateResponse: Codable {
            let uploadId: String
            let presignedUrl: String
            let expiresAt: Int64

            enum CodingKeys: String, CodingKey {
                case uploadId = "upload_id"
                case presignedUrl = "presigned_url"
                case expiresAt = "expires_at"
            }
        }

        var initiateRequest = URLRequest(url: initiateUrl)
        initiateRequest.httpMethod = "POST"
        initiateRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        initiateRequest.timeoutInterval = 30

        if let token = client.getAuthToken() {
            initiateRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let requestBody = InitiateRequest(
            filename: filename,
            sizeBytes: Int64(audioData.count),
            contentType: "audio/mp4"  // M4A is audio/mp4
        )
        initiateRequest.httpBody = try JSONEncoder().encode(requestBody)

        let (initiateData, initiateResponse) = try await URLSession.shared.data(for: initiateRequest)

        guard let httpResponse = initiateResponse as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (initiateResponse as? HTTPURLResponse)?.statusCode ?? 0
            if statusCode == 401 {
                throw APIError.unauthorized
            }
            if statusCode == 413 {
                throw APIError.serverError(statusCode: 413, message: "File too large")
            }
            let message = String(data: initiateData, encoding: .utf8) ?? "Failed to initiate upload"
            throw APIError.serverError(statusCode: statusCode, message: message)
        }

        let initiateResult = try JSONDecoder().decode(InitiateResponse.self, from: initiateData)

        #if DEBUG
        print("[Media] Got presigned URL for audio, upload_id: \(initiateResult.uploadId)")
        #endif

        // Step 2: Upload directly to GCS using presigned URL
        try await uploadToPresignedUrl(initiateResult.presignedUrl, data: audioData, contentType: "audio/mp4")

        #if DEBUG
        print("[Media] Audio upload to GCS completed, completing upload...")
        #endif

        // Step 3: Complete the upload to get the final CDN URL
        let mediaUrl = try await completeUpload(uploadId: initiateResult.uploadId)

        #if DEBUG
        print("[Media] Audio upload complete, CDN URL: \(mediaUrl)")
        #endif

        return mediaUrl
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
        // Content-Type MUST match what was specified when generating the presigned URL
        // Otherwise S3/GCS will reject with signature mismatch
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        request.timeoutInterval = 60  // 1 minute for upload

        #if DEBUG
        let startTime = CFAbsoluteTimeGetCurrent()
        print("[Media] ⬆️ Starting GCS upload: \(data.count / 1024) KB")
        #endif

        // IMPORTANT: Use upload(for:from:) instead of data(for:) because data(for:) ignores httpBody!
        let (responseData, response) = try await uploadSession.upload(for: request, from: data)

        #if DEBUG
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let speedKBps = Double(data.count) / 1024.0 / elapsed
        print("[Media] ✅ GCS upload completed: \(String(format: "%.1f", elapsed))s (\(String(format: "%.0f", speedKBps)) KB/s)")
        #endif

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
    /// - Returns: Final CDN URL for the uploaded media
    func completeUpload(uploadId: String) async throws -> String {
        // Request body for complete upload (only checksum, optional)
        struct CompleteRequest: Codable {
            let checksum: String?
        }

        // Response from complete upload endpoint - backend returns MediaResponse with cdn_url
        struct CompleteResponse: Codable {
            let id: String
            let userId: String
            let filename: String
            let mediaType: String
            let mimeType: String
            let sizeBytes: Int64
            let cdnUrl: String
            let thumbnailUrl: String
            let status: String
            let createdAt: Int64

            enum CodingKeys: String, CodingKey {
                case id
                case userId = "user_id"
                case filename
                case mediaType = "media_type"
                case mimeType = "mime_type"
                case sizeBytes = "size_bytes"
                case cdnUrl = "cdn_url"
                case thumbnailUrl = "thumbnail_url"
                case status
                case createdAt = "created_at"
            }
        }

        // Use the correct URL format with upload_id as path parameter
        let url = URL(string: "\(APIConfig.current.baseURL)\(APIConfig.Media.uploadComplete(uploadId))")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        if let token = client.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Send empty checksum (optional field)
        let requestBody = CompleteRequest(checksum: nil)
        request.httpBody = try JSONEncoder().encode(requestBody)

        #if DEBUG
        print("[Media] Completing upload: \(uploadId)")
        #endif

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        #if DEBUG
        print("[Media] Complete upload response - Status: \(httpResponse.statusCode)")
        if let responseStr = String(data: data, encoding: .utf8) {
            print("[Media] Complete upload response body: \(responseStr)")
        }
        #endif

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            let message = String(data: data, encoding: .utf8) ?? "Failed to complete upload"
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: message)
        }

        let decoder = JSONDecoder()
        let uploadResponse = try decoder.decode(CompleteResponse.self, from: data)

        #if DEBUG
        print("[Media] Upload completed - CDN URL: \(uploadResponse.cdnUrl)")
        #endif

        return uploadResponse.cdnUrl
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

    // MARK: - Video Management (delegated to VideoService)

    func getVideos(limit: Int = 20, offset: Int = 0) async throws -> VideoListResponse {
        try await videoService.getVideos(limit: limit, offset: offset)
    }

    func createVideo(
        videoUrl: String,
        thumbnailUrl: String?,
        duration: Int,
        title: String?,
        description: String?
    ) async throws -> VideoMetadata {
        try await videoService.createVideo(
            videoUrl: videoUrl,
            thumbnailUrl: thumbnailUrl,
            duration: duration,
            title: title,
            description: description
        )
    }

    func getVideo(videoId: String) async throws -> VideoMetadata {
        try await videoService.getVideo(videoId: videoId)
    }

    func updateVideo(
        videoId: String,
        title: String?,
        description: String?
    ) async throws -> VideoMetadata {
        try await videoService.updateVideo(videoId: videoId, title: title, description: description)
    }

    func deleteVideo(videoId: String) async throws {
        try await videoService.deleteVideo(videoId: videoId)
    }

    // MARK: - Reels Management (delegated to ReelsService)

    func getReels(limit: Int = 20, offset: Int = 0) async throws -> ReelsListResponse {
        try await reelsService.getReels(limit: limit, offset: offset)
    }

    func createReel(
        videoUrl: String,
        thumbnailUrl: String?,
        caption: String?
    ) async throws -> ReelMetadata {
        try await reelsService.createReel(videoUrl: videoUrl, thumbnailUrl: thumbnailUrl, caption: caption)
    }

    func getReel(reelId: String) async throws -> ReelMetadata {
        try await reelsService.getReel(reelId: reelId)
    }

    func deleteReel(reelId: String) async throws {
        try await reelsService.deleteReel(reelId: reelId)
    }

    // MARK: - Live Photo Upload

    /// Upload a Live Photo (both still image and video components)
    /// - Parameters:
    ///   - imageData: Still image data (JPEG, WebP, or HEIC)
    ///   - videoURL: URL to the video file (.mov)
    ///   - imageFilename: Optional filename for the still image (defaults to jpg)
    /// - Returns: LivePhotoUploadResult with URLs for both components
    func uploadLivePhoto(imageData: Data, videoURL: URL, imageFilename: String? = nil) async throws -> LivePhotoUploadResult {
        // Upload still image first (use provided filename or default to jpg)
        let filename = imageFilename ?? "livephoto_\(UUID().uuidString).jpg"
        let imageUrl = try await uploadImage(
            imageData: imageData,
            filename: filename
        )
        
        // Read video data
        let videoData = try Data(contentsOf: videoURL)
        
        // Upload video component
        let videoUrl = try await uploadLivePhotoVideo(
            videoData: videoData,
            filename: "livephoto_\(UUID().uuidString).mov"
        )
        
        return LivePhotoUploadResult(
            imageUrl: imageUrl,
            videoUrl: videoUrl
        )
    }
    
    /// Upload Live Photo video component (MOV format)
    private func uploadLivePhotoVideo(videoData: Data, filename: String) async throws -> String {
        let url = URL(string: "\(APIConfig.current.baseURL)\(APIConfig.Media.uploadStart)")!

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120  // 2 minutes for Live Photo video (typically small)

        if let token = client.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: video/quicktime\r\n\r\n".data(using: .utf8)!)  // MOV is video/quicktime
        body.append(videoData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        #if DEBUG
        print("[Media] Starting Live Photo video upload: \(videoData.count / 1024) KB")
        #endif

        let (data, response) = try await uploadSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            let decoder = JSONDecoder()
            let uploadResponse = try decoder.decode(UploadResponse.self, from: data)

            if let mediaUrl = uploadResponse.mediaUrl, !mediaUrl.isEmpty {
                return mediaUrl
            } else if let presignedUrl = uploadResponse.presignedUrl, !presignedUrl.isEmpty {
                try await uploadToPresignedUrl(presignedUrl, data: videoData, contentType: "video/quicktime")
                return presignedUrl.components(separatedBy: "?").first ?? presignedUrl
            } else if let uploadId = uploadResponse.uploadId, !uploadId.isEmpty {
                return uploadId
            }

            throw APIError.serverError(statusCode: 200, message: "Upload response missing required fields")
        case 401:
            throw APIError.unauthorized
        case 413:
            throw APIError.serverError(statusCode: 413, message: "File too large")
        default:
            let message = String(data: data, encoding: .utf8) ?? "Upload failed"
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: message)
        }
    }

    // MARK: - Legacy Support

    /// Legacy method for backward compatibility
    func uploadImage(image: Data, userId: String, contentType: String = "image/jpeg") async throws -> String {
        return try await uploadImage(imageData: image, filename: "avatar_\(UUID().uuidString).jpg")
    }
}

// MARK: - Upload Progress Delegate

/// URLSession delegate for tracking upload progress
private class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let progressCallback: UploadProgressCallback?
    
    init(progressCallback: UploadProgressCallback?) {
        self.progressCallback = progressCallback
        super.init()
    }
    
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        
        DispatchQueue.main.async { [weak self] in
            self?.progressCallback?(progress)
        }
    }
}
