import Foundation
import UIKit

// MARK: - Alias Edit State

/// Shared state for editing alias accounts
@MainActor
class AliasEditState: ObservableObject {
    static let shared = AliasEditState()

    @Published var editingAccount: Account?
    @Published var isEditing: Bool = false

    private init() {}

    func startEditing(account: Account) {
        self.editingAccount = account
        self.isEditing = true
    }

    func clearEditingState() {
        self.editingAccount = nil
        self.isEditing = false
    }
}

// MARK: - Accounts Service

/// Manages multiple accounts for a single user
/// Handles account listing, switching, and removal
class AccountsService {
    static let shared = AccountsService()
    private let client = APIClient.shared

    private init() {}

    // MARK: - Get Accounts

    /// Get list of all accounts associated with current user
    /// - Returns: List of user accounts
    func getAccounts() async throws -> AccountsResponse {
        #if DEBUG
        print("[AccountsService] GET \(APIConfig.Accounts.getAccounts)")
        #endif

        let response: AccountsResponse = try await client.get(endpoint: APIConfig.Accounts.getAccounts)

        #if DEBUG
        print("[AccountsService] Got \(response.accounts.count) accounts")
        for account in response.accounts {
            print("  - [\(account.id.prefix(8))...] \(account.effectiveDisplayName) (isAlias: \(account.isAlias), isPrimary: \(account.isPrimary))")
        }
        #endif

        return response
    }

    // MARK: - Switch Account

    /// Switch to a different account
    /// - Parameter accountId: ID of the account to switch to
    /// - Returns: New authentication tokens for the switched account
    func switchAccount(accountId: String) async throws -> SwitchAccountResponse {
        struct Request: Codable {
            let accountId: String

            enum CodingKeys: String, CodingKey {
                case accountId = "account_id"
            }
        }

        let request = Request(accountId: accountId)
        return try await client.request(
            endpoint: APIConfig.Accounts.switchAccount,
            method: "POST",
            body: request
        )
    }

    // MARK: - Remove Account

    /// Remove an account from the multi-account list
    /// - Parameter accountId: ID of the account to remove
    func removeAccount(accountId: String) async throws {
        struct Response: Codable {
            let success: Bool
        }

        let _: Response = try await client.request(
            endpoint: "\(APIConfig.Accounts.removeAccount)/\(accountId)",
            method: "DELETE"
        )
    }

    // MARK: - Add Account

    /// Link a new account to current user
    /// - Parameters:
    ///   - username: Username or email of the account to add
    ///   - password: Password for the account
    /// - Returns: Added account information
    func addAccount(username: String, password: String) async throws -> Account {
        struct Request: Codable {
            let username: String
            let password: String
        }

        struct Response: Codable {
            let account: Account
        }

        let request = Request(username: username, password: password)
        let response: Response = try await client.request(
            endpoint: APIConfig.Accounts.getAccounts,
            method: "POST",
            body: request
        )

        return response.account
    }

    // MARK: - Set Primary Account

    /// Set an account as the primary account
    /// - Parameter accountId: ID of the account to set as primary
    func setPrimaryAccount(accountId: String) async throws {
        struct Request: Codable {
            let accountId: String
            let primary: Bool

            enum CodingKeys: String, CodingKey {
                case accountId = "account_id"
                case primary
            }
        }

        struct Response: Codable {
            let success: Bool
        }

        let request = Request(accountId: accountId, primary: true)
        let _: Response = try await client.request(
            endpoint: "\(APIConfig.Accounts.getAccounts)/\(accountId)",
            method: "PUT",
            body: request
        )
    }

    // MARK: - Alias Account Methods

    /// Create a new alias account
    /// - Parameter request: Create alias account request
    /// - Returns: Created alias account
    func createAliasAccount(request: CreateAliasAccountRequest) async throws -> Account {
        #if DEBUG
        print("[AccountsService] POST \(APIConfig.Accounts.createAlias)")
        print("  aliasName: \(request.aliasName)")
        #endif

        struct Response: Codable {
            let account: Account
        }

        let response: Response = try await client.request(
            endpoint: APIConfig.Accounts.createAlias,
            method: "POST",
            body: request
        )

        #if DEBUG
        print("[AccountsService] Created alias account: \(response.account.effectiveDisplayName)")
        #endif

        return response.account
    }

    /// Update an existing alias account
    /// - Parameters:
    ///   - accountId: ID of the alias account to update
    ///   - request: Update request with new values
    /// - Returns: Updated alias account
    func updateAliasAccount(accountId: String, request: UpdateAliasAccountRequest) async throws -> Account {
        struct Response: Codable {
            let account: Account
        }

        let response: Response = try await client.request(
            endpoint: "\(APIConfig.Accounts.updateAlias)/\(accountId)",
            method: "PUT",
            body: request
        )

        return response.account
    }

    /// Get alias account details
    /// - Parameter accountId: ID of the alias account
    /// - Returns: Alias account details
    func getAliasAccount(accountId: String) async throws -> Account {
        struct Response: Codable {
            let account: Account
        }

        let response: Response = try await client.get(
            endpoint: "\(APIConfig.Accounts.getAlias)/\(accountId)"
        )

        return response.account
    }
}

// MARK: - Models

/// Account model for multi-account support
struct Account: Codable, Identifiable {
    let id: String
    let username: String
    let displayName: String?
    let avatarUrl: String?
    let isPrimary: Bool
    let isActive: Bool
    let isAlias: Bool
    let lastActiveAt: Date?
    let createdAt: Date

    // Alias-specific fields
    let aliasName: String?
    let dateOfBirth: String?
    let gender: Gender?
    let profession: String?
    let location: String?

    /// Full name for display (displayName > username)
    var fullName: String {
        if let display = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !display.isEmpty {
            return display
        }
        return username
    }

    /// Effective display name - uses aliasName for alias accounts
    var effectiveDisplayName: String {
        if isAlias {
            return aliasName ?? fullName
        }
        return fullName
    }

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case isPrimary = "is_primary"
        case isActive = "is_active"
        case isAlias = "is_alias"
        case lastActiveAt = "last_active_at"
        case createdAt = "created_at"
        case aliasName = "alias_name"
        case dateOfBirth = "date_of_birth"
        case gender
        case profession
        case location
    }

    // Custom decoder to handle missing fields gracefully
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        isPrimary = try container.decodeIfPresent(Bool.self, forKey: .isPrimary) ?? false
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        isAlias = try container.decodeIfPresent(Bool.self, forKey: .isAlias) ?? false
        lastActiveAt = try container.decodeIfPresent(Date.self, forKey: .lastActiveAt)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        aliasName = try container.decodeIfPresent(String.self, forKey: .aliasName)
        dateOfBirth = try container.decodeIfPresent(String.self, forKey: .dateOfBirth)
        gender = try container.decodeIfPresent(Gender.self, forKey: .gender)
        profession = try container.decodeIfPresent(String.self, forKey: .profession)
        location = try container.decodeIfPresent(String.self, forKey: .location)
    }
}

/// Accounts list response
struct AccountsResponse: Codable {
    let accounts: [Account]
    let currentAccountId: String

    enum CodingKeys: String, CodingKey {
        case accounts
        case currentAccountId = "current_account_id"
    }
}

/// Switch account response
struct SwitchAccountResponse: Codable {
    let success: Bool
    let accessToken: String
    let refreshToken: String?
    let account: Account

    enum CodingKeys: String, CodingKey {
        case success
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case account
    }
}

// MARK: - Alias Account Requests

/// Request to create a new alias account
struct CreateAliasAccountRequest: Codable {
    let aliasName: String
    let avatarUrl: String?
    let dateOfBirth: String?
    let gender: Gender?
    let profession: String?
    let location: String?

    enum CodingKeys: String, CodingKey {
        case aliasName = "alias_name"
        case avatarUrl = "avatar_url"
        case dateOfBirth = "date_of_birth"
        case gender
        case profession
        case location
    }
}

/// Request to update an existing alias account
struct UpdateAliasAccountRequest: Codable {
    let aliasName: String?
    let avatarUrl: String?
    let dateOfBirth: String?
    let gender: Gender?
    let profession: String?
    let location: String?

    enum CodingKeys: String, CodingKey {
        case aliasName = "alias_name"
        case avatarUrl = "avatar_url"
        case dateOfBirth = "date_of_birth"
        case gender
        case profession
        case location
    }
}
