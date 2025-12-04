import Foundation
import UIKit

@MainActor
final class ProfileSettingViewModel: ObservableObject {
    // Form state
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var username = ""
    @Published var dateOfBirth = ""
    @Published var gender: Gender = .preferNotToSay
    @Published var location = ""

    // Avatar
    @Published var avatarImage: UIImage?
    @Published var avatarUrl: String?

    // State
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var showSuccessMessage = false

    var validationError: String? {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedUsername.isEmpty {
            return NSLocalizedString("Username is required", comment: "")
        }

        if !dateOfBirth.isEmpty && !isValidDate(dateOfBirth) {
            return NSLocalizedString("Invalid date", comment: "")
        }

        return nil
    }

    var isValid: Bool {
        validationError == nil
    }

    private let authManager: AuthenticationManager
    private let userService: UserService
    private let mediaService: MediaService

    init(
        authManager: AuthenticationManager? = nil,
        userService: UserService? = nil,
        mediaService: MediaService = MediaService()
    ) {
        self.authManager = authManager ?? AuthenticationManager.shared
        self.userService = userService ?? UserService.shared
        self.mediaService = mediaService
    }

    var hasChanges: Bool {
        guard let user = authManager.currentUser else { return false }
        return firstName != (user.firstName ?? "") ||
               lastName != (user.lastName ?? "") ||
               username != user.username ||
               dateOfBirth != (user.dateOfBirth ?? "") ||
               gender != (user.gender ?? .preferNotToSay) ||
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

        isLoading = false
    }

    func saveProfile() async {
        guard let userId = authManager.currentUser?.id else { return }
        guard isValid else {
            errorMessage = validationError
            return
        }

        isSaving = true
        errorMessage = nil

        do {
            var newAvatarUrl: String?
            if let image = avatarImage,
               let imageData = image.jpegData(compressionQuality: 0.8) {
                newAvatarUrl = try await mediaService.uploadImage(imageData: imageData, filename: "avatar.jpg")
            }

            let updatedUser = try await userService.updateProfile(
                userId: userId,
                avatarUrl: newAvatarUrl,
                location: location.isEmpty ? nil : location,
                firstName: firstName.isEmpty ? nil : firstName,
                lastName: lastName.isEmpty ? nil : lastName,
                dateOfBirth: dateOfBirth.isEmpty ? nil : dateOfBirth,
                gender: gender
            )

            authManager.updateCurrentUser(updatedUser)
            avatarUrl = updatedUser.avatarUrl
            avatarImage = nil
            showSuccessMessage = true
        } catch {
            errorMessage = String(format: NSLocalizedString("Failed to save profile: %@", comment: ""), error.localizedDescription)
        }

        isSaving = false
    }

    func updateAvatarImage(_ image: UIImage) {
        avatarImage = image
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
        gender = user.gender ?? .preferNotToSay
        location = user.location ?? ""
        avatarUrl = user.avatarUrl
    }

    private func isValidDate(_ dateString: String) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString) != nil
    }
}
