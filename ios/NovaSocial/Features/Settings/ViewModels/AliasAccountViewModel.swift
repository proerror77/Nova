import Foundation
import UIKit

// MARK: - Alias Account ViewModel

/// ViewModel for managing alias account (子账户) profile
@MainActor
@Observable
final class AliasAccountViewModel {
    // MARK: - Form State

    var aliasName = ""
    var dateOfBirth = ""
    var gender: Gender = .notSet
    var profession = ""
    var location = ""

    // Avatar
    var avatarImage: UIImage?
    var avatarUrl: String?

    // MARK: - UI State

    var isLoading = false
    var isSaving = false
    var errorMessage: String?
    var showSuccessMessage = false

    // MARK: - Account State

    /// Current alias account being edited (nil if creating new)
    private(set) var currentAliasAccount: Account?

    /// Whether we're editing an existing alias or creating a new one
    var isEditing: Bool {
        currentAliasAccount != nil
    }

    // MARK: - Validation

    var validationError: String? {
        if aliasName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return NSLocalizedString("Alias name is required", comment: "")
        }
        if !dateOfBirth.isEmpty && !isValidDate(dateOfBirth) {
            return NSLocalizedString("Invalid date format", comment: "")
        }
        return nil
    }

    var isValid: Bool {
        validationError == nil
    }

    var canSave: Bool {
        !aliasName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isValid
    }

    // MARK: - Dependencies

    private let accountsService: AccountsService
    private let mediaService: MediaService

    // MARK: - Initialization

    init(
        accountsService: AccountsService = .shared,
        mediaService: MediaService = MediaService()
    ) {
        self.accountsService = accountsService
        self.mediaService = mediaService
    }

    // MARK: - Load Alias Account

    /// Load an existing alias account for editing
    /// - Parameter accountId: ID of the alias account to load
    func loadAliasAccount(accountId: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let account = try await accountsService.getAliasAccount(accountId: accountId)
            applyAccount(account)
            currentAliasAccount = account
        } catch {
            errorMessage = NSLocalizedString("Failed to load alias account", comment: "")
            #if DEBUG
            print("[AliasAccountViewModel] Error loading alias: \(error)")
            #endif
        }

        isLoading = false
    }

    // MARK: - Save Alias Account

    /// Save the alias account (create new or update existing)
    /// - Returns: The saved account if successful, nil otherwise
    @discardableResult
    func save() async -> Account? {
        guard canSave else {
            errorMessage = validationError ?? NSLocalizedString("Please fill in required fields", comment: "")
            return nil
        }

        isSaving = true
        errorMessage = nil

        do {
            // Upload avatar if changed
            var newAvatarUrl: String?
            if let image = avatarImage,
               let imageData = image.jpegData(compressionQuality: 0.8) {
                newAvatarUrl = try await mediaService.uploadImage(imageData: imageData, filename: "alias_avatar.jpg")
            }

            let savedAccount: Account

            if let existingAccount = currentAliasAccount {
                // Update existing alias account
                let request = UpdateAliasAccountRequest(
                    aliasName: aliasName,
                    avatarUrl: newAvatarUrl ?? avatarUrl,
                    dateOfBirth: dateOfBirth.isEmpty ? nil : dateOfBirth,
                    gender: gender == .notSet ? nil : gender,
                    profession: profession.isEmpty ? nil : profession,
                    location: location.isEmpty ? nil : location
                )
                savedAccount = try await accountsService.updateAliasAccount(
                    accountId: existingAccount.id,
                    request: request
                )
            } else {
                // Create new alias account
                let request = CreateAliasAccountRequest(
                    aliasName: aliasName,
                    avatarUrl: newAvatarUrl,
                    dateOfBirth: dateOfBirth.isEmpty ? nil : dateOfBirth,
                    gender: gender == .notSet ? nil : gender,
                    profession: profession.isEmpty ? nil : profession,
                    location: location.isEmpty ? nil : location
                )
                savedAccount = try await accountsService.createAliasAccount(request: request)
            }

            currentAliasAccount = savedAccount
            avatarUrl = savedAccount.avatarUrl
            avatarImage = nil
            showSuccessMessage = true

            #if DEBUG
            print("[AliasAccountViewModel] Alias account saved successfully: \(savedAccount.id)")
            #endif

            isSaving = false
            return savedAccount

        } catch {
            errorMessage = String(
                format: NSLocalizedString("Failed to save: %@", comment: ""),
                error.localizedDescription
            )
            #if DEBUG
            print("[AliasAccountViewModel] Error saving alias: \(error)")
            #endif
            isSaving = false
            return nil
        }
    }

    // MARK: - Avatar

    func updateAvatarImage(_ image: UIImage) {
        avatarImage = image
    }

    // MARK: - Date Formatting

    /// Format date for display (yyyy-MM-dd -> dd/MM/yyyy)
    func formatDateForDisplay(_ dateString: String) -> String {
        let parts = dateString.split(separator: "-")
        if parts.count == 3 {
            return "\(parts[2])/\(parts[1])/\(parts[0])"
        }
        return dateString
    }

    /// Format date for API (dd/MM/yyyy -> yyyy-MM-dd)
    func formatDateForAPI(_ displayDate: String) -> String {
        let parts = displayDate.split(separator: "/")
        if parts.count == 3 {
            return "\(parts[2])-\(parts[1])-\(parts[0])"
        }
        return displayDate
    }

    // MARK: - Private Helpers

    private func applyAccount(_ account: Account) {
        aliasName = account.aliasName ?? ""
        dateOfBirth = account.dateOfBirth ?? ""
        gender = account.gender ?? .notSet
        profession = account.profession ?? ""
        location = account.location ?? ""
        avatarUrl = account.avatarUrl
    }

    private func isValidDate(_ dateString: String) -> Bool {
        // Support both yyyy-MM-dd and dd/MM/yyyy formats
        let formatters = [
            "yyyy-MM-dd",
            "dd/MM/yyyy"
        ]

        for format in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if formatter.date(from: dateString) != nil {
                return true
            }
        }
        return false
    }

    // MARK: - Reset

    func reset() {
        aliasName = ""
        dateOfBirth = ""
        gender = .notSet
        profession = ""
        location = ""
        avatarImage = nil
        avatarUrl = nil
        currentAliasAccount = nil
        errorMessage = nil
        showSuccessMessage = false
    }
}
