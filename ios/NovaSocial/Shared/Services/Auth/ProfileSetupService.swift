import Foundation
import UIKit

// MARK: - Profile Setup Service

/// Handles profile setup during registration flow
/// Completes registration with verified phone/email and profile information
class ProfileSetupService {
    static let shared = ProfileSetupService()

    private let client = APIClient.shared
    private let mediaService = MediaService()

    private init() {}

    // MARK: - Response Types

    struct ProfileSetupResponse: Codable {
        let userId: String
        let token: String
        let refreshToken: String?
        let user: UserProfile

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case token
            case refreshToken = "refresh_token"
            case user
        }
    }

    // MARK: - Request Types

    struct ProfileSetupRequest: Codable {
        let verificationToken: String
        let username: String
        let firstName: String?
        let lastName: String?
        let dateOfBirth: String?  // ISO 8601: YYYY-MM-DD
        let location: String?
        let avatarUrl: String?
        let inviteCode: String?
        // For email-based registration
        let email: String?
        // For phone-based registration
        let phoneNumber: String?

        enum CodingKeys: String, CodingKey {
            case verificationToken = "verification_token"
            case username
            case firstName = "first_name"
            case lastName = "last_name"
            case dateOfBirth = "date_of_birth"
            case location
            case avatarUrl = "avatar_url"
            case inviteCode = "invite_code"
            case email
            case phoneNumber = "phone_number"
        }
    }

    // MARK: - API Methods

    /// Complete profile setup with email verification
    /// - Parameters:
    ///   - email: Verified email address
    ///   - verificationToken: Token from email verification
    ///   - username: Chosen username
    ///   - firstName: Optional first name
    ///   - lastName: Optional last name
    ///   - dateOfBirth: Optional date of birth
    ///   - location: Optional location
    ///   - avatarImage: Optional profile photo
    ///   - inviteCode: Optional invite code
    /// - Returns: ProfileSetupResponse with auth tokens and user profile
    func completeEmailProfileSetup(
        email: String,
        verificationToken: String,
        username: String,
        firstName: String? = nil,
        lastName: String? = nil,
        dateOfBirth: Date? = nil,
        location: String? = nil,
        avatarImage: UIImage? = nil,
        inviteCode: String? = nil
    ) async throws -> ProfileSetupResponse {
        // Upload avatar if provided
        var avatarUrl: String? = nil
        if let image = avatarImage {
            avatarUrl = try await uploadAvatar(image: image)
        }

        // Format date of birth
        let dobString: String?
        if let dob = dateOfBirth {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            dobString = formatter.string(from: dob)
        } else {
            dobString = nil
        }

        let request = ProfileSetupRequest(
            verificationToken: verificationToken,
            username: username,
            firstName: firstName,
            lastName: lastName,
            dateOfBirth: dobString,
            location: location,
            avatarUrl: avatarUrl,
            inviteCode: inviteCode,
            email: email,
            phoneNumber: nil
        )

        return try await submitProfileSetup(request: request, endpoint: "/api/v2/auth/email/complete-profile")
    }

    /// Complete profile setup with phone verification
    /// - Parameters:
    ///   - phoneNumber: Verified phone number
    ///   - verificationToken: Token from phone verification
    ///   - username: Chosen username
    ///   - firstName: Optional first name
    ///   - lastName: Optional last name
    ///   - dateOfBirth: Optional date of birth
    ///   - location: Optional location
    ///   - avatarImage: Optional profile photo
    ///   - inviteCode: Optional invite code
    /// - Returns: ProfileSetupResponse with auth tokens and user profile
    func completePhoneProfileSetup(
        phoneNumber: String,
        verificationToken: String,
        username: String,
        firstName: String? = nil,
        lastName: String? = nil,
        dateOfBirth: Date? = nil,
        location: String? = nil,
        avatarImage: UIImage? = nil,
        inviteCode: String? = nil
    ) async throws -> ProfileSetupResponse {
        // Upload avatar if provided
        var avatarUrl: String? = nil
        if let image = avatarImage {
            avatarUrl = try await uploadAvatar(image: image)
        }

        // Format date of birth
        let dobString: String?
        if let dob = dateOfBirth {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            dobString = formatter.string(from: dob)
        } else {
            dobString = nil
        }

        let request = ProfileSetupRequest(
            verificationToken: verificationToken,
            username: username,
            firstName: firstName,
            lastName: lastName,
            dateOfBirth: dobString,
            location: location,
            avatarUrl: avatarUrl,
            inviteCode: inviteCode,
            email: nil,
            phoneNumber: phoneNumber
        )

        return try await submitProfileSetup(request: request, endpoint: "/api/v2/auth/phone/complete-profile")
    }

    // MARK: - Private Methods

    /// Upload avatar image and return CDN URL
    private func uploadAvatar(image: UIImage) async throws -> String {
        // Compress image to JPEG
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw ProfileSetupError.imageCompressionFailed
        }

        #if DEBUG
        print("[ProfileSetup] Uploading avatar: \(imageData.count / 1024) KB")
        #endif

        let filename = "avatar_\(UUID().uuidString).jpg"
        let cdnUrl = try await mediaService.uploadImage(imageData: imageData, filename: filename)

        #if DEBUG
        print("[ProfileSetup] Avatar uploaded: \(cdnUrl)")
        #endif

        return cdnUrl
    }

    /// Submit profile setup request
    private func submitProfileSetup(request: ProfileSetupRequest, endpoint: String) async throws -> ProfileSetupResponse {
        let url = URL(string: "\(APIConfig.current.baseURL)\(endpoint)")!

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 30

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        #if DEBUG
        print("[ProfileSetup] Submitting profile to: \(endpoint)")
        if let body = urlRequest.httpBody, let bodyStr = String(data: body, encoding: .utf8) {
            print("[ProfileSetup] Request body: \(bodyStr)")
        }
        #endif

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProfileSetupError.invalidResponse
        }

        #if DEBUG
        print("[ProfileSetup] Response status: \(httpResponse.statusCode)")
        if let responseStr = String(data: data, encoding: .utf8) {
            print("[ProfileSetup] Response body: \(responseStr)")
        }
        #endif

        switch httpResponse.statusCode {
        case 200, 201:
            let decoder = JSONDecoder()
            return try decoder.decode(ProfileSetupResponse.self, from: data)

        case 400:
            // Parse error message
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw ProfileSetupError.validationError(errorResponse.message ?? "Invalid request")
            }
            throw ProfileSetupError.validationError("Invalid request")

        case 401:
            throw ProfileSetupError.invalidVerificationToken

        case 409:
            // Username already taken
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                if errorResponse.message?.lowercased().contains("username") == true {
                    throw ProfileSetupError.usernameAlreadyTaken
                }
            }
            throw ProfileSetupError.usernameAlreadyTaken

        case 429:
            throw ProfileSetupError.rateLimited

        default:
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw ProfileSetupError.serverError(errorResponse.message ?? "Server error")
            }
            throw ProfileSetupError.serverError("Server error: \(httpResponse.statusCode)")
        }
    }
}

// MARK: - Profile Setup Errors

enum ProfileSetupError: LocalizedError {
    case imageCompressionFailed
    case imageUploadFailed
    case invalidVerificationToken
    case usernameAlreadyTaken
    case validationError(String)
    case rateLimited
    case networkError(String)
    case serverError(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .imageCompressionFailed:
            return "Failed to process profile photo"
        case .imageUploadFailed:
            return "Failed to upload profile photo"
        case .invalidVerificationToken:
            return "Verification expired. Please verify your email/phone again."
        case .usernameAlreadyTaken:
            return "This username is already taken. Please choose another."
        case .validationError(let message):
            return message
        case .rateLimited:
            return "Too many attempts. Please try again later."
        case .networkError(let message):
            return "Network error: \(message)"
        case .serverError(let message):
            return message
        case .invalidResponse:
            return "Invalid server response"
        }
    }
}

// MARK: - Error Response

private struct ErrorResponse: Codable {
    let message: String?
    let error: String?
}
