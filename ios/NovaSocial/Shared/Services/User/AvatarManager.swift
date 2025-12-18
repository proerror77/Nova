import Foundation
import SwiftUI

// MARK: - Avatar Update Notification

/// 头像更新通知的 userInfo 键
enum AvatarNotificationKey: String {
    case userId = "userId"
    case avatarUrl = "avatarUrl"
}

/// 头像更新通知名称
extension Notification.Name {
    /// 当任何用户头像更新时发送此通知
    /// userInfo: [AvatarNotificationKey.userId: String, AvatarNotificationKey.avatarUrl: String?]
    static let userAvatarDidUpdate = Notification.Name("userAvatarDidUpdate")
}

/// 管理用户头像的服务
/// 在创建账号时保存头像，在个人资料页面显示
/// 支持全局头像更新通知，让所有显示头像的地方都能收到更新
@MainActor
class AvatarManager: ObservableObject {
    static let shared = AvatarManager()

    @Published var pendingAvatar: UIImage?

    /// 缓存的用户头像 URL（用于快速查找）
    @Published private(set) var avatarCache: [String: String] = [:]

    private let userDefaults = UserDefaults.standard
    private let avatarKey = "pending_user_avatar"
    private let avatarCacheKey = "avatar_url_cache"

    private init() {
        loadSavedAvatar()
        loadAvatarCache()
    }

    // MARK: - Public Methods

    /// 保存待上传的头像（在创建账号时使用）
    func savePendingAvatar(_ image: UIImage) {
        pendingAvatar = image

        // 将图片转换为 Data 并保存到 UserDefaults
        if let imageData = image.jpegData(compressionQuality: 0.8) {
            userDefaults.set(imageData, forKey: avatarKey)

            #if DEBUG
            print("[AvatarManager] 头像已保存到本地")
            #endif
        }
    }

    /// 获取待上传的头像
    func getPendingAvatar() -> UIImage? {
        return pendingAvatar
    }

    /// 清除待上传的头像（上传成功后使用）
    func clearPendingAvatar() {
        pendingAvatar = nil
        userDefaults.removeObject(forKey: avatarKey)

        #if DEBUG
        print("[AvatarManager] 已清除待上传头像")
        #endif
    }

    // MARK: - Avatar Update Notification

    /// 广播用户头像更新通知
    /// 当用户上传新头像后调用此方法，所有监听者都会收到通知
    /// - Parameters:
    ///   - userId: 更新头像的用户 ID
    ///   - avatarUrl: 新的头像 URL
    func notifyAvatarUpdate(userId: String, avatarUrl: String?) {
        // 更新缓存
        if let url = avatarUrl {
            avatarCache[userId] = url
            saveAvatarCache()
        }

        // 发送通知
        NotificationCenter.default.post(
            name: .userAvatarDidUpdate,
            object: self,
            userInfo: [
                AvatarNotificationKey.userId.rawValue: userId,
                AvatarNotificationKey.avatarUrl.rawValue: avatarUrl as Any
            ]
        )

        #if DEBUG
        print("[AvatarManager] 广播头像更新通知: userId=\(userId), avatarUrl=\(avatarUrl ?? "nil")")
        #endif
    }

    /// 获取缓存的头像 URL
    /// - Parameter userId: 用户 ID
    /// - Returns: 缓存的头像 URL，如果没有则返回 nil
    func getCachedAvatarUrl(for userId: String) -> String? {
        return avatarCache[userId]
    }

    /// 批量更新头像缓存（用于从 API 响应中更新）
    /// - Parameter avatars: 用户 ID 到头像 URL 的映射
    func updateAvatarCache(_ avatars: [String: String]) {
        for (userId, url) in avatars {
            avatarCache[userId] = url
        }
        saveAvatarCache()
    }

    // MARK: - Private Methods

    /// 加载保存的头像
    private func loadSavedAvatar() {
        if let imageData = userDefaults.data(forKey: avatarKey),
           let image = UIImage(data: imageData) {
            pendingAvatar = image

            #if DEBUG
            print("[AvatarManager] 已加载保存的头像")
            #endif
        }
    }

    /// 加载头像缓存
    private func loadAvatarCache() {
        if let cached = userDefaults.dictionary(forKey: avatarCacheKey) as? [String: String] {
            avatarCache = cached
            #if DEBUG
            print("[AvatarManager] 已加载 \(cached.count) 个头像缓存")
            #endif
        }
    }

    /// 保存头像缓存
    private func saveAvatarCache() {
        userDefaults.set(avatarCache, forKey: avatarCacheKey)
    }

    /// 清除所有缓存（登出时调用）
    func clearAllCache() {
        avatarCache.removeAll()
        userDefaults.removeObject(forKey: avatarCacheKey)
        clearPendingAvatar()

        #if DEBUG
        print("[AvatarManager] 已清除所有头像缓存")
        #endif
    }
}
