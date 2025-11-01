import Foundation
import Observation

/// AppServices - Central service container for dependency injection
/// Uses @Observable for modern SwiftUI state management
/// All app-wide services are managed here and injected via Environment
@Observable
final class AppServices: Sendable {
    // MARK: - Services

    let authService: AuthService
    let authRepository: AuthRepository
    let feedService: FeedService
    let postInteractionService: PostInteractionService
    let voiceMessageService: VoiceMessageService
    let locationService: LocationService
    let locationPermissionManager: LocationPermissionManager

    // MARK: - Initialization

    init() {
        // Initialize AuthService
        self.authService = AuthService()

        // Initialize AuthRepository with AuthService
        self.authRepository = AuthRepository(authService: authService)

        // Initialize other services
        self.feedService = FeedService()
        self.postInteractionService = PostInteractionService()
        self.voiceMessageService = VoiceMessageService()
        self.locationService = LocationService()
        self.locationPermissionManager = LocationPermissionManager()
    }

    // MARK: - Convenience Properties

    /// Current authenticated user
    var currentUser: User? {
        authService.currentUser
    }

    /// Whether user is authenticated
    var isAuthenticated: Bool {
        authService.isAuthenticated
    }
}
