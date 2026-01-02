import Foundation
import UIKit

@MainActor
@Observable
final class ProfileSettingViewModel {
    // Form state
    var firstName = ""
    var lastName = ""
    var username = ""
    var dateOfBirth = ""
    var gender: Gender = .notSet
    var profession = ""
    var identity = ""
    var location = ""

    // Avatar
    var avatarImage: UIImage?
    var avatarUrl: String?

    // State
    var isLoading = false
    var isSaving = false
    var errorMessage: String?
    var showSuccessMessage = false

    var validationError: String? {
        if !dateOfBirth.isEmpty && !isValidDate(dateOfBirth) {
            return NSLocalizedString("Invalid date", comment: "")
        }

        return nil
    }

    var isValid: Bool {
        validationError == nil
    }

    /// Save 按钮可用条件：Username 必填，First name 和 Last name 可选
    var canSave: Bool {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 只要求 Username 必填，其他字段可选
        // 这样用户可以只更改头像而不必填写所有字段
        return !trimmedUsername.isEmpty && isValid
    }

    private let authManager: AuthenticationManager
    private let userService: UserService
    private let mediaService: MediaService
    private let avatarManager: AvatarManager

    init(
        authManager: AuthenticationManager? = nil,
        userService: UserService? = nil,
        mediaService: MediaService = MediaService()
    ) {
        self.authManager = authManager ?? AuthenticationManager.shared
        self.userService = userService ?? UserService.shared
        self.mediaService = mediaService
        self.avatarManager = AvatarManager.shared
    }

    var hasChanges: Bool {
        guard let user = authManager.currentUser else { return false }
        return firstName != (user.firstName ?? "") ||
               lastName != (user.lastName ?? "") ||
               username != user.username ||
               dateOfBirth != (user.dateOfBirth ?? "") ||
               gender != (user.gender ?? .notSet) ||
               profession != (user.bio ?? "") ||  // profession maps to bio
               identity != "" ||  // identity is local only for now
               location != (user.location ?? "") ||
               avatarImage != nil
    }

    func onAppear() {
        Task { await loadProfile() }
    }

    func loadProfile() async {
        guard let userId = authManager.currentUser?.id else { return }

        isLoading = true
        errorMessage = nil

        do {
            let user = try await userService.getUser(userId: userId)
            applyUser(user)
        } catch {
            if let user = authManager.currentUser {
                applyUser(user)
            }
            errorMessage = NSLocalizedString("Failed to load profile", comment: "")
        }

        // 检查 AvatarManager 中是否有待上传的头像（来自注册页或Profile页）
        if let pendingAvatar = avatarManager.getPendingAvatar() {
            avatarImage = pendingAvatar
            #if DEBUG
            print("[ProfileSettingViewModel] 已加载来自 AvatarManager 的待上传头像")
            #endif
        }

        isLoading = false
    }

    /// 保存个人资料，返回是否成功
    func saveProfile() async -> Bool {
        guard let userId = authManager.currentUser?.id else { return false }
        guard canSave else {
            errorMessage = NSLocalizedString("Please fill in Username", comment: "")
            return false
        }

        isSaving = true
        errorMessage = nil

        do {
            var newAvatarUrl: String?
            if let image = avatarImage,
               let imageData = image.jpegData(compressionQuality: 0.8) {
                newAvatarUrl = try await mediaService.uploadImage(imageData: imageData, filename: "avatar.jpg")
            }

            var updatedUser = try await userService.updateProfile(
                userId: userId,
                avatarUrl: newAvatarUrl,
                location: location.isEmpty ? nil : location,
                firstName: firstName.isEmpty ? nil : firstName,
                lastName: lastName.isEmpty ? nil : lastName,
                dateOfBirth: dateOfBirth.isEmpty ? nil : dateOfBirth,
                gender: gender == .notSet ? nil : gender
            )

            // Ensure avatar URL is preserved
            // Backend may not return avatar_url in response, so preserve the URL
            if updatedUser.avatarUrl == nil {
                if let newUrl = newAvatarUrl {
                    // Use newly uploaded avatar URL
                    updatedUser.avatarUrl = newUrl
                    #if DEBUG
                    print("[ProfileSettingViewModel] Backend didn't return avatar_url, using uploaded URL: \(newUrl)")
                    #endif
                } else if let existingUrl = self.avatarUrl {
                    // Preserve existing avatar URL when no new avatar was uploaded
                    updatedUser.avatarUrl = existingUrl
                    #if DEBUG
                    print("[ProfileSettingViewModel] Backend didn't return avatar_url, preserving existing URL: \(existingUrl)")
                    #endif
                }
            }

            #if DEBUG
            print("[ProfileSettingViewModel] Updating currentUser with avatarUrl: \(updatedUser.avatarUrl ?? "nil")")
            #endif

            authManager.updateCurrentUser(updatedUser)
            avatarUrl = updatedUser.avatarUrl
            avatarImage = nil

            // 清除 AvatarManager 中的待上传头像（已成功上传）
            if newAvatarUrl != nil {
                avatarManager.clearPendingAvatar()
                #if DEBUG
                print("[ProfileSettingViewModel] 头像上传成功，已清除 AvatarManager 中的待上传头像")
                #endif
            }

            // Sync updated profile to Matrix (display name and avatar)
            Task {
                do {
                    try await MatrixBridgeService.shared.syncProfileToMatrix()
                    #if DEBUG
                    print("[ProfileSettingViewModel] ✅ Profile synced to Matrix")
                    #endif
                } catch {
                    #if DEBUG
                    print("[ProfileSettingViewModel] ⚠️ Failed to sync profile to Matrix: \(error)")
                    #endif
                }
            }

            isSaving = false
            return true
        } catch {
            errorMessage = String(format: NSLocalizedString("Failed to save profile: %@", comment: ""), error.localizedDescription)
            isSaving = false
            return false
        }
    }

    func updateAvatarImage(_ image: UIImage) {
        avatarImage = image
        // 同步更新到 AvatarManager，确保其他页面也能看到更新
        avatarManager.savePendingAvatar(image)
        #if DEBUG
        print("[ProfileSettingViewModel] 已更新头像并同步到 AvatarManager")
        #endif
    }

    func formatDateForDisplay(_ dateString: String) -> String {
        let parts = dateString.split(separator: "-")
        if parts.count == 3 {
            return "\(parts[1])/\(parts[2])/\(parts[0])"
        }
        return dateString
    }

    private func applyUser(_ user: UserProfile) {
        firstName = user.firstName ?? ""
        lastName = user.lastName ?? ""
        username = user.username
        dateOfBirth = user.dateOfBirth ?? ""
        gender = user.gender ?? .notSet
        profession = user.bio ?? ""  // profession maps to bio
        // identity is local only for now
        location = user.location ?? ""
        avatarUrl = user.avatarUrl
    }

    private func isValidDate(_ dateString: String) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString) != nil
    }
}
