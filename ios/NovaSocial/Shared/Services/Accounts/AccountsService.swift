import Foundation

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
        return try await client.get(endpoint: APIConfig.Accounts.getAccounts)
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
    let lastActiveAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case isPrimary = "is_primary"
        case isActive = "is_active"
        case lastActiveAt = "last_active_at"
        case createdAt = "created_at"
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
