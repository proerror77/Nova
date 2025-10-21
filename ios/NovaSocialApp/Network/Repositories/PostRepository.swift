import Foundation
import UIKit

/// PostRepository - 帖子业务逻辑层（统一版本）
/// 职责：处理帖子发布、点赞、评论等操作，支持可选的离线缓存
///
/// 改进点:
/// 1. 集成请求去重器，防止重复点赞/评论
/// 2. 输入验证
/// 3. 可选的离线缓存支持（消除了 PostRepositoryEnhanced 的重复）
/// 4. 向后兼容的依赖注入设计
/// 5. 简化错误处理
///
/// 使用示例：
/// ```
/// // 基础用法（无离线支持）
/// let repo = PostRepository()
///
/// // 启用离线同步
/// let repoWithOffline = PostRepository(enableOfflineSync: true)
/// ```
final class PostRepository {
    private let apiClient: APIClient
    private let interceptor: RequestInterceptor
    private let deduplicator = RequestDeduplicator()
    private let cacheOrchestrator: CacheOrchestrator
    private let enableOfflineSync: Bool

    init(apiClient: APIClient? = nil, enableOfflineSync: Bool = false) {
        self.apiClient = apiClient ?? APIClient(baseURL: AppConfig.baseURL)
        self.interceptor = RequestInterceptor(apiClient: self.apiClient)
        self.cacheOrchestrator = CacheOrchestrator(enableOfflineSync: enableOfflineSync)
        self.enableOfflineSync = enableOfflineSync
    }

    // MARK: - Post CRUD

    /// 创建帖子（完整流程：upload/init → PUT 上传 → upload/complete → 获取帖子详情）
    /// 如果启用了离线同步，会自动缓存到本地存储
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

        // 2. 初始化上傳（取得預簽 URL、post_id、upload_token）
        let filename = "post_\(UUID().uuidString).jpg"
        let initReq = PostUploadInitRequest(
            filename: filename,
            contentType: "image/jpeg",
            fileSize: imageData.count,
            caption: caption
        )
        let initEndpoint = APIEndpoint(
            path: "/api/v1/posts/upload/init",
            method: .post,
            body: initReq
        )
        let initResp: PostUploadInitResponse = try await interceptor.executeWithRetry(initEndpoint)

        // 3. 上传图片到 S3 (PUT)
        try await uploadImageToS3(data: imageData, url: initResp.presignedUrl)

        // 4. 完成上傳（提交雜湊與檔案大小）
        let fileHash = imageData.sha256Hex
        let completeReq = PostUploadCompleteRequest(
            postId: initResp.postId,
            uploadToken: initResp.uploadToken,
            fileHash: fileHash,
            fileSize: imageData.count
        )
        let completeEndpoint = APIEndpoint(
            path: "/api/v1/posts/upload/complete",
            method: .post,
            body: completeReq
        )
        _ = try await interceptor.executeWithRetry(completeEndpoint) as PostUploadCompleteResponse

        // 5. 拉取帖子詳情
        let getEndpoint = APIEndpoint(
            path: "/api/v1/posts/\(initResp.postId)",
            method: .get
        )
        let response: PostResponse = try await interceptor.executeWithRetry(getEndpoint)

        // 6. 如果启用离线同步，缓存到本地
        if enableOfflineSync {
            let localPost = LocalPost.from(response.post)
            try await LocalStorageManager.shared.save(localPost)
        }

        return response.post
    }

    /// 获取帖子详情
    /// 如果启用了离线同步，会先检查本地缓存，缓存未命中才从服务器获取
    func getPost(id: UUID) async throws -> Post {
        // 如果启用离线同步，先尝试从本地缓存读取
        if enableOfflineSync {
            if let localPost = try await LocalStorageManager.shared.fetchFirst(
                LocalPost.self,
                predicate: #Predicate { $0.id == id.uuidString }
            ), let post = localPost.toPost() {
                Logger.log("📦 Returning cached post \(id)", level: .debug)

                // 后台同步更新缓存
                Task {
                    try? await syncPostInBackground(id: id)
                }

                return post
            }
        }

        // 缓存未命中或未启用离线同步，从服务器获取
        let endpoint = APIEndpoint(
            path: "/api/v1/posts/\(id.uuidString)",
            method: .get
        )

        let response: PostResponse = try await interceptor.executeWithRetry(endpoint)

        // 缓存到本地
        if enableOfflineSync {
            let localPost = LocalPost.from(response.post)
            try await LocalStorageManager.shared.save(localPost)
        }

        return response.post
    }

    /// 删除帖子
    func deletePost(id: UUID) async throws {
        let endpoint = APIEndpoint(
            path: "/api/v1/posts/\(id.uuidString)",
            method: .delete
        )

        try await interceptor.executeNoResponseWithRetry(endpoint)

        // 从本地缓存删除
        if enableOfflineSync {
            try await LocalStorageManager.shared.delete(
                LocalPost.self,
                predicate: #Predicate { $0.id == id.uuidString }
            )
        }
    }

    // MARK: - Like Operations (带去重和离线支持)

    /// 点赞
    /// 去重策略: 相同帖子的点赞请求会被自动合并
    /// 离线支持: 如果启用离线同步，进行乐观更新和后台同步
    func likePost(id: UUID) async throws -> (liked: Bool, likeCount: Int) {
        let key = RequestDeduplicator.likeKey(postId: id)

        return try await deduplicator.execute(key: key) {
            // 如果启用离线同步，执行乐观更新
            if self.enableOfflineSync {
                if let localPost = try await LocalStorageManager.shared.fetchFirst(
                    LocalPost.self,
                    predicate: #Predicate { $0.id == id.uuidString }
                ) {
                    localPost.isLiked = true
                    localPost.likeCount += 1
                    localPost.syncState = .localModified
                    localPost.localModifiedAt = Date()
                    try await LocalStorageManager.shared.update(localPost)
                }
            }

            // 调用 API
            let endpoint = APIEndpoint(
                path: "/api/v1/posts/\(id.uuidString)/like",
                method: .post
            )

            do {
                let response: LikeResponse = try await self.interceptor.executeWithRetry(endpoint)

                // 同步服务器响应到本地
                if self.enableOfflineSync {
                    if let localPost = try await LocalStorageManager.shared.fetchFirst(
                        LocalPost.self,
                        predicate: #Predicate { $0.id == id.uuidString }
                    ) {
                        localPost.isLiked = response.liked
                        localPost.likeCount = response.likeCount
                        localPost.syncState = .synced
                        localPost.localModifiedAt = nil
                        try await LocalStorageManager.shared.update(localPost)
                    }
                }

                return (response.liked, response.likeCount)

            } catch {
                // API 失败，回滚乐观更新
                if self.enableOfflineSync {
                    if let localPost = try await LocalStorageManager.shared.fetchFirst(
                        LocalPost.self,
                        predicate: #Predicate { $0.id == id.uuidString }
                    ) {
                        localPost.isLiked = false
                        localPost.likeCount -= 1
                        localPost.syncState = .synced
                        localPost.localModifiedAt = nil
                        try await LocalStorageManager.shared.update(localPost)
                    }
                }

                throw error
            }
        }
    }

    /// 取消点赞
    func unlikePost(id: UUID) async throws -> (liked: Bool, likeCount: Int) {
        let key = RequestDeduplicator.unlikeKey(postId: id)

        return try await deduplicator.execute(key: key) {
            // 如果启用离线同步，执行乐观更新
            if self.enableOfflineSync {
                if let localPost = try await LocalStorageManager.shared.fetchFirst(
                    LocalPost.self,
                    predicate: #Predicate { $0.id == id.uuidString }
                ) {
                    localPost.isLiked = false
                    localPost.likeCount -= 1
                    localPost.syncState = .localModified
                    localPost.localModifiedAt = Date()
                    try await LocalStorageManager.shared.update(localPost)
                }
            }

            // 调用 API
            let endpoint = APIEndpoint(
                path: "/api/v1/posts/\(id.uuidString)/like",
                method: .delete
            )

            do {
                let response: LikeResponse = try await self.interceptor.executeWithRetry(endpoint)

                // 同步服务器响应到本地
                if self.enableOfflineSync {
                    if let localPost = try await LocalStorageManager.shared.fetchFirst(
                        LocalPost.self,
                        predicate: #Predicate { $0.id == id.uuidString }
                    ) {
                        localPost.isLiked = response.liked
                        localPost.likeCount = response.likeCount
                        localPost.syncState = .synced
                        localPost.localModifiedAt = nil
                        try await LocalStorageManager.shared.update(localPost)
                    }
                }

                return (response.liked, response.likeCount)

            } catch {
                // API 失败，回滚乐观更新
                if self.enableOfflineSync {
                    if let localPost = try await LocalStorageManager.shared.fetchFirst(
                        LocalPost.self,
                        predicate: #Predicate { $0.id == id.uuidString }
                    ) {
                        localPost.isLiked = true
                        localPost.likeCount += 1
                        localPost.syncState = .synced
                        localPost.localModifiedAt = nil
                        try await LocalStorageManager.shared.update(localPost)
                    }
                }

                throw error
            }
        }
    }

    // MARK: - Comment Operations (带去重和离线支持)

    /// 获取评论列表
    /// 如果启用离线同步且无分页游标，会先返回本地缓存，后台同步更新
    func getComments(postId: UUID, cursor: String? = nil, limit: Int = 20) async throws -> [Comment] {
        // 如果启用离线同步且无分页游标，先尝试从本地缓存读取
        if enableOfflineSync, cursor == nil {
            let localComments = try await LocalStorageManager.shared.fetch(
                LocalComment.self,
                predicate: #Predicate { $0.postId == postId.uuidString },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )

            if !localComments.isEmpty {
                Logger.log("📦 Returning cached comments (\(localComments.count))", level: .debug)

                // 后台同步
                Task {
                    try? await syncCommentsInBackground(postId: postId, limit: limit)
                }

                return localComments.compactMap { $0.toComment() }
            }
        }

        // 缓存未命中或分页请求，从服务器获取
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

        // 缓存到本地（仅缓存首页结果）
        if enableOfflineSync, cursor == nil {
            let localComments = response.comments.map { LocalComment.from($0) }
            try await LocalStorageManager.shared.save(localComments)
        }

        return response.comments
    }

    /// 发表评论
    /// 去重策略: 相同内容的评论会被防止重复提交
    /// 离线支持: 如果启用离线同步，会缓存新评论
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

            // 缓存到本地
            if self.enableOfflineSync {
                let localComment = LocalComment.from(response.comment)
                try await LocalStorageManager.shared.save(localComment)
            }

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

        // 从本地缓存删除
        if enableOfflineSync {
            try await LocalStorageManager.shared.delete(
                LocalComment.self,
                predicate: #Predicate { $0.id == id.uuidString }
            )
        }
    }

    // MARK: - Private Helpers

    // 兼容舊代碼保留占位，實際不再使用
    private func requestUploadURL(contentType: String) async throws -> UploadURLResponse {
        throw APIError.badRequest("/api/v1/posts/upload-url is deprecated; use upload/init + upload/complete")
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

    /// 后台同步 Post（后台更新缓存）
    private func syncPostInBackground(id: UUID) async throws {
        guard enableOfflineSync else { return }

        let endpoint = APIEndpoint(
            path: "/api/v1/posts/\(id.uuidString)",
            method: .get
        )

        do {
            let response: PostResponse = try await interceptor.executeWithRetry(endpoint)
            try await cacheOrchestrator.syncPosts([response.post])
            Logger.log("✅ Background sync completed for post \(id)", level: .debug)
        } catch {
            Logger.log("⚠️ Background sync failed for post \(id): \(error.localizedDescription)", level: .warning)
        }
    }

    /// 后台同步 Comments（后台更新评论缓存）
    private func syncCommentsInBackground(postId: UUID, limit: Int) async throws {
        guard enableOfflineSync else { return }

        let queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        let endpoint = APIEndpoint(
            path: "/api/v1/posts/\(postId.uuidString)/comments",
            method: .get,
            queryItems: queryItems
        )

        do {
            let response: CommentsResponse = try await interceptor.executeWithRetry(endpoint)
            try await cacheOrchestrator.syncComments(response.comments)
            Logger.log("✅ Background sync completed for comments (post \(postId))", level: .debug)
        } catch {
            Logger.log("⚠️ Background sync failed for comments: \(error.localizedDescription)", level: .warning)
        }
    }
}
