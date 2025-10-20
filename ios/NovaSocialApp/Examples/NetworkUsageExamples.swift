import Foundation
import UIKit

/// 网络层使用示例
/// 展示如何在实际业务中使用 Repository 层
class NetworkUsageExamples {

    // MARK: - 1. 用户认证示例

    func loginExample() async {
        let authRepo = AuthRepository()

        do {
            let (user, tokens) = try await authRepo.login(
                email: "user@example.com",
                password: "password123"
            )

            print("✅ 登录成功")
            print("用户名: \(user.username)")
            print("Access Token: \(tokens.accessToken)")

            // 认证信息已自动保存到 Keychain
            // 后续请求会自动携带 Token

        } catch let error as APIError {
            print("❌ 登录失败: \(error.localizedDescription)")
        } catch {
            print("❌ 未知错误: \(error)")
        }
    }

    func registerExample() async {
        let authRepo = AuthRepository()

        do {
            let (user, _) = try await authRepo.register(
                email: "newuser@example.com",
                username: "newuser",
                password: "securepassword"
            )

            print("✅ 注册成功，用户名: \(user.username)")

        } catch APIError.emailAlreadyExists {
            print("❌ 该邮箱已被注册")
        } catch APIError.usernameAlreadyExists {
            print("❌ 用户名已被占用")
        } catch {
            print("❌ 注册失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 2. Feed 加载示例

    func loadFeedExample() async {
        let feedRepo = FeedRepository()

        do {
            // 首次加载会尝试返回缓存数据（如果有）
            let posts = try await feedRepo.loadFeed(cursor: nil, limit: 20)

            print("✅ 加载了 \(posts.count) 条帖子")

            for post in posts {
                print("- \(post.user?.username ?? "Unknown"): \(post.caption ?? "无描述")")
            }

        } catch {
            print("❌ 加载 Feed 失败: \(error.localizedDescription)")
        }
    }

    func refreshFeedExample() async {
        let feedRepo = FeedRepository()

        do {
            // 下拉刷新，会清空缓存并获取最新数据
            let posts = try await feedRepo.refreshFeed(limit: 20)

            print("✅ 刷新成功，加载了 \(posts.count) 条帖子")

        } catch {
            print("❌ 刷新失败: \(error.localizedDescription)")
        }
    }

    func loadMoreFeedExample(currentPosts: [Post]) async {
        let feedRepo = FeedRepository()

        guard let lastPost = currentPosts.last else { return }
        let cursor = ISO8601DateFormatter().string(from: lastPost.createdAt)

        do {
            let morePosts = try await feedRepo.loadFeed(cursor: cursor, limit: 20)

            print("✅ 加载了更多 \(morePosts.count) 条帖子")

        } catch {
            print("❌ 加载更多失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 3. 发布帖子示例

    func createPostExample(image: UIImage, caption: String?) async {
        let postRepo = PostRepository()

        do {
            let post = try await postRepo.createPost(
                image: image,
                caption: caption
            )

            print("✅ 发布成功")
            print("Post ID: \(post.id)")
            print("图片 URL: \(post.imageUrl)")

        } catch APIError.fileTooLarge {
            print("❌ 文件大小超过限制（最大 10MB）")
        } catch APIError.invalidFileFormat {
            print("❌ 不支持的文件格式")
        } catch APIError.captionTooLong {
            print("❌ 描述文字过长（最多 300 字符）")
        } catch {
            print("❌ 发布失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 4. 点赞/评论示例

    func likePostExample(postId: UUID) async {
        let postRepo = PostRepository()

        do {
            let (liked, likeCount) = try await postRepo.likePost(id: postId)

            if liked {
                print("✅ 点赞成功，当前点赞数: \(likeCount)")
            }

        } catch {
            print("❌ 点赞失败: \(error.localizedDescription)")
        }
    }

    func commentExample(postId: UUID, text: String) async {
        let postRepo = PostRepository()

        do {
            let comment = try await postRepo.createComment(
                postId: postId,
                text: text
            )

            print("✅ 评论成功，评论 ID: \(comment.id)")

        } catch {
            print("❌ 评论失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 5. 用户操作示例

    func getUserProfileExample(username: String) async {
        let userRepo = UserRepository()

        do {
            let profile = try await userRepo.getUserProfile(username: username)

            print("✅ 获取用户资料成功")
            print("用户名: \(profile.user.username)")
            print("帖子数: \(profile.stats.postCount)")
            print("粉丝数: \(profile.stats.followerCount)")
            print("关注数: \(profile.stats.followingCount)")

        } catch APIError.notFound {
            print("❌ 用户不存在")
        } catch {
            print("❌ 获取用户资料失败: \(error.localizedDescription)")
        }
    }

    func followUserExample(userId: UUID) async {
        let userRepo = UserRepository()

        do {
            let (following, followerCount) = try await userRepo.followUser(id: userId)

            if following {
                print("✅ 关注成功，当前粉丝数: \(followerCount)")
            }

        } catch {
            print("❌ 关注失败: \(error.localizedDescription)")
        }
    }

    func searchUsersExample(query: String) async {
        let userRepo = UserRepository()

        do {
            let users = try await userRepo.searchUsers(query: query, limit: 20)

            print("✅ 搜索到 \(users.count) 个用户")

            for user in users {
                print("- \(user.username)")
            }

        } catch {
            print("❌ 搜索失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 6. 通知示例

    func getNotificationsExample() async {
        let notificationRepo = NotificationRepository()

        do {
            let (notifications, unreadCount) = try await notificationRepo.getNotifications()

            print("✅ 获取通知成功")
            print("未读通知数: \(unreadCount)")
            print("通知列表: \(notifications.count) 条")

        } catch {
            print("❌ 获取通知失败: \(error.localizedDescription)")
        }
    }

    func markAllNotificationsAsReadExample() async {
        let notificationRepo = NotificationRepository()

        do {
            try await notificationRepo.markAllAsRead()
            print("✅ 所有通知已标记为已读")

        } catch {
            print("❌ 标记失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 7. 错误处理最佳实践

    func errorHandlingExample() async {
        let authRepo = AuthRepository()

        do {
            let (user, _) = try await authRepo.login(
                email: "user@example.com",
                password: "wrong_password"
            )

            print("登录成功: \(user.username)")

        } catch let error as APIError {
            // 根据错误类型进行不同处理
            switch error {
            case .unauthorized, .invalidCredentials:
                print("❌ 邮箱或密码错误，请重新输入")

            case .noConnection:
                print("❌ 无网络连接，请检查网络后重试")

            case .timeout:
                print("❌ 请求超时，请稍后重试")

            case .serverError:
                print("❌ 服务器错误，请稍后重试")

            case .rateLimitExceeded:
                print("❌ 操作过于频繁，请稍后再试")

            default:
                // 使用错误的 localizedDescription
                print("❌ \(error.localizedDescription)")
            }

        } catch {
            print("❌ 未知错误: \(error)")
        }
    }

    // MARK: - 8. 离线模式示例

    func offlineModeExample() async {
        let feedRepo = FeedRepository()

        // 即使网络断开，首次加载也会返回缓存数据
        do {
            let posts = try await feedRepo.loadFeed()

            if posts.isEmpty {
                print("⚠️ 暂无缓存数据")
            } else {
                print("✅ 从缓存加载了 \(posts.count) 条帖子")
            }

        } catch APIError.noConnection {
            print("❌ 无网络连接，且无缓存数据")
        } catch {
            print("❌ 加载失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 9. Token 自动刷新示例

    func tokenRefreshExample() async {
        // Token 刷新是自动的，开发者无需手动处理
        // RequestInterceptor 会在以下情况自动刷新 Token：
        // 1. Token 即将过期（提前 1 分钟）
        // 2. API 返回 401 错误

        let feedRepo = FeedRepository()

        // 即使 Access Token 过期，这个请求也会自动刷新 Token 并重试
        do {
            let posts = try await feedRepo.loadFeed()
            print("✅ 加载成功（Token 可能已自动刷新）")

        } catch APIError.unauthorized {
            // 如果 Refresh Token 也过期，会抛出此错误
            print("❌ 登录已过期，请重新登录")

            // 清空认证信息并跳转到登录页
            AuthManager.shared.clearAuth()
            // 跳转到登录页的代码...

        } catch {
            print("❌ 加载失败: \(error.localizedDescription)")
        }
    }
}
