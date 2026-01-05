import Foundation

#if canImport(FoundationModels)
import FoundationModels

// MARK: - Get User Profile Tool Arguments

/// Arguments for the get user profile tool
@available(iOS 26.0, *)
@Generable
struct GetUserProfileArguments: Sendable {
    @Guide(description: "Username to look up, without the @ symbol")
    var username: String
}

// MARK: - Get User Profile Tool

/// Tool for looking up user profiles on the Icered platform
@available(iOS 26.0, *)
struct GetUserProfileTool: Tool {

    // MARK: - Tool Protocol

    let name = "get_user_profile"
    let description = """
        Look up a user's profile information on Icered by their username.
        Use this tool when the user asks about a specific person, wants to know about a creator,
        or needs information about someone on the platform.
        Returns the user's display name, verification status, and basic profile information.
        """

    typealias Arguments = GetUserProfileArguments

    // MARK: - Properties

    private let searchService: SearchService

    // MARK: - Initialization

    init(searchService: SearchService) {
        self.searchService = searchService
    }

    // MARK: - Tool Execution

    func call(arguments: GetUserProfileArguments) async throws -> String {
        // Normalize username (remove @ if present)
        var username = arguments.username.trimmingCharacters(in: .whitespacesAndNewlines)
        if username.hasPrefix("@") {
            username = String(username.dropFirst())
        }

        guard !username.isEmpty else {
            return "Please provide a username to look up."
        }

        #if DEBUG
        print("[GetUserProfileTool] Looking up user: @\(username)")
        #endif

        do {
            // Search for the user
            let results = try await searchService.searchUsers(
                query: username,
                limit: 5
            )

            // Find exact or close match
            guard let firstResult = results.first else {
                return "User @\(username) was not found on Icered."
            }

            // Check for exact match
            if case .user(let id, let foundUsername, let displayName, let avatarUrl, let isVerified) = firstResult {
                // Check if it's an exact match
                if foundUsername.lowercased() == username.lowercased() {
                    return formatUserProfile(
                        username: foundUsername,
                        displayName: displayName,
                        isVerified: isVerified,
                        hasAvatar: avatarUrl != nil
                    )
                } else {
                    // Close match found
                    var output = "No exact match for @\(username). Did you mean:\n"
                    output += formatUserProfile(
                        username: foundUsername,
                        displayName: displayName,
                        isVerified: isVerified,
                        hasAvatar: avatarUrl != nil
                    )

                    // Add other suggestions
                    for result in results.dropFirst().prefix(2) {
                        if case .user(_, let otherUsername, let otherDisplayName, _, let otherVerified) = result {
                            output += "\n\nOr: @\(otherUsername)"
                            if otherVerified {
                                output += " (Verified)"
                            }
                            output += " - \(otherDisplayName)"
                        }
                    }

                    return output
                }
            }

            return "User @\(username) was not found on ICERED."

        } catch {
            #if DEBUG
            print("[GetUserProfileTool] Lookup failed: \(error)")
            #endif
            return "Unable to look up user profile at the moment. Please try again later."
        }
    }

    // MARK: - Helpers

    private func formatUserProfile(
        username: String,
        displayName: String,
        isVerified: Bool,
        hasAvatar: Bool
    ) -> String {
        var output = "Found user: @\(username)"
        if isVerified {
            output += " (Verified)"
        }
        output += "\nDisplay Name: \(displayName)"
        output += "\nProfile: \(hasAvatar ? "Has profile photo" : "No profile photo")"
        return output
    }
}

#endif
