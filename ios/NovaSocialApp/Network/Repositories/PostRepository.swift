import Foundation
import UIKit

/// PostRepository - 帖子业务逻辑层
/// 职责：处理帖子发布、点赞、评论等操作
///
/// 改进点:
/// 1. 集成请求去重器,防止重复点赞/评论
/// 2. 输入验证
/// 3. 消除重复的 Response 定义
/// 4. 简化错误处理
final class PostRepository {
    private let apiClient: APIClient
    private let interceptor: RequestInterceptor
    private let deduplicator = RequestDeduplicator()

    init(apiClient: APIClient? = nil) {
        self.apiClient = apiClient ?? APIClient(baseURL: AppConfig.baseURL)
        self.interceptor = RequestInterceptor(apiClient: self.apiClient)
    }

    // MARK: - Post CRUD

    /// 创建帖子（完整流程：获取上传 URL → 上传图片 → 创建帖子记录）
    func createPost(image: UIImage, caption: String?) async throws -> Post {
        // 验证输入
        if let caption = caption {
            try RequestDeduplicator.validate(caption, maxLength: 2000)
        }

        // 1. 压缩图片
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw APIError.invalidFileFormat
        }

        // 检查文件大小（10MB）
        let maxSize = 10 * 1024 * 1024
        guard imageData.count <= maxSize else {
            throw APIError.fileTooLarge
        }

        // 2. 获取预签名 URL
        let uploadInfo = try await requestUploadURL(contentType: "image/jpeg")

        // 3. 上传图片到 S3
        try await uploadImageToS3(data: imageData, url: uploadInfo.uploadUrl)

        // 4. 创建帖子记录
        let request = CreatePostRequest(
            fileKey: uploadInfo.fileKey,
            caption: caption
        )

        let endpoint = APIEndpoint(
            path: "/api/v1/posts",
            method: .post,
            body: request
        )

        let response: PostResponse = try await interceptor.executeWithRetry(endpoint)
        return response.post
    }

    /// 获取帖子详情
    func getPost(id: UUID) async throws -> Post {
        let endpoint = APIEndpoint(
            path: "/api/v1/posts/\(id.uuidString)",
            method: .get
        )

        let response: PostResponse = try await interceptor.executeWithRetry(endpoint)
        return response.post
    }

    /// 删除帖子
    func deletePost(id: UUID) async throws {
        let endpoint = APIEndpoint(
            path: "/api/v1/posts/\(id.uuidString)",
            method: .delete
        )

        try await interceptor.executeNoResponseWithRetry(endpoint)
    }

    // MARK: - Like Operations (带去重)

    /// 点赞
    /// 去重策略: 相同帖子的点赞请求会被自动合并
    func likePost(id: UUID) async throws -> (liked: Bool, likeCount: Int) {
        let key = RequestDeduplicator.likeKey(postId: id)

        return try await deduplicator.execute(key: key) {
            let endpoint = APIEndpoint(
                path: "/api/v1/posts/\(id.uuidString)/like",
                method: .post
            )

            let response: LikeResponse = try await self.interceptor.executeWithRetry(endpoint)
            return (response.liked, response.likeCount)
        }
    }

    /// 取消点赞
    func unlikePost(id: UUID) async throws -> (liked: Bool, likeCount: Int) {
        let key = RequestDeduplicator.unlikeKey(postId: id)

        return try await deduplicator.execute(key: key) {
            let endpoint = APIEndpoint(
                path: "/api/v1/posts/\(id.uuidString)/like",
                method: .delete
            )

            let response: LikeResponse = try await self.interceptor.executeWithRetry(endpoint)
            return (response.liked, response.likeCount)
        }
    }

    // MARK: - Comment Operations (带去重)

    /// 获取评论列表
    func getComments(postId: UUID, cursor: String? = nil, limit: Int = 20) async throws -> [Comment] {
        var queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        if let cursor = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }

        let endpoint = APIEndpoint(
            path: "/api/v1/posts/\(postId.uuidString)/comments",
            method: .get,
            queryItems: queryItems
        )

        let response: CommentsResponse = try await interceptor.executeWithRetry(endpoint)
        return response.comments
    }

    /// 发表评论
    /// 去重策略: 相同内容的评论会被防止重复提交
    func createComment(postId: UUID, text: String) async throws -> Comment {
        // 验证评论内容
        try RequestDeduplicator.validate(text, maxLength: 500)

        let key = RequestDeduplicator.commentKey(postId: postId, text: text)

        return try await deduplicator.execute(key: key) {
            let request = CreateCommentRequest(text: text)

            let endpoint = APIEndpoint(
                path: "/api/v1/posts/\(postId.uuidString)/comments",
                method: .post,
                body: request
            )

            let response: CommentResponse = try await self.interceptor.executeWithRetry(endpoint)
            return response.comment
        }
    }

    /// 删除评论
    func deleteComment(id: UUID) async throws {
        let endpoint = APIEndpoint(
            path: "/api/v1/comments/\(id.uuidString)",
            method: .delete
        )

        try await interceptor.executeNoResponseWithRetry(endpoint)
    }

    // MARK: - Private Helpers

    private func requestUploadURL(contentType: String) async throws -> UploadURLResponse {
        let request = UploadURLRequest(contentType: contentType)

        let endpoint = APIEndpoint(
            path: "/api/v1/posts/upload-url",
            method: .post,
            body: request
        )

        return try await interceptor.executeWithRetry(endpoint)
    }

    private func uploadImageToS3(data: Data, url: String) async throws {
        guard let uploadURL = URL(string: url) else {
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError
        }

        Logger.log("✅ Image uploaded to S3", level: .info)
    }
}
