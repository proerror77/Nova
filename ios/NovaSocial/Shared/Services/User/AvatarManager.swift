import Foundation
import SwiftUI

/// 管理用户头像的服务
/// 在创建账号时保存头像，在个人资料页面显示
@MainActor
class AvatarManager: ObservableObject {
    static let shared = AvatarManager()

    @Published var pendingAvatar: UIImage?

    private let userDefaults = UserDefaults.standard
    private let avatarKey = "pending_user_avatar"

    private init() {
        loadSavedAvatar()
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
}
