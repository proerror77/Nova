import Foundation
import SwiftUI

// MARK: - Feature Flags

/// Centralized feature flag management for the app
/// Controls feature availability across different environments and for A/B testing
@Observable
@MainActor
final class FeatureFlags {
    static let shared = FeatureFlags()

    // MARK: - Environment Detection

    /// Check if running in SwiftUI Preview
    static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    /// Check if running in Debug mode
    static var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// Check if running in Simulator
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Core Feature Flags

    /// Use mock data instead of real API calls (for previews and testing)
    var useMockData: Bool = isPreview

    /// Enable offline mode with cached data
    var enableOfflineMode: Bool = false

    /// Enable debug logging
    var enableDebugLogging: Bool = isDebug

    // MARK: - Authentication Features

    /// Enable Google Sign-In
    var enableGoogleSignIn: Bool = true

    /// Enable Apple Sign-In
    var enableAppleSignIn: Bool = true

    /// Enable guest mode (skip login)
    var enableGuestMode: Bool = true

    /// Enable biometric authentication (Face ID / Touch ID)
    var enableBiometricAuth: Bool = false

    // MARK: - Feed Features

    /// Enable pull-to-refresh on feed
    var enableFeedRefresh: Bool = true

    /// Enable infinite scroll pagination
    var enableInfiniteScroll: Bool = true

    /// Enable feed algorithm selection (chronological vs recommended)
    var enableFeedAlgorithmSwitch: Bool = false

    /// Enable trending section in home feed
    var enableTrendingSection: Bool = true

    /// Enable promo banner on home screen
    var enablePromoBanner: Bool = true

    /// Enable ranking list carousel
    var enableRankingCarousel: Bool = true

    // MARK: - Content Creation Features

    /// Enable photo posting
    var enablePhotoPosting: Bool = true

    /// Enable video posting
    var enableVideoPosting: Bool = false

    /// Enable AI image generation
    var enableAIImageGeneration: Bool = true

    /// Enable text-only posts
    var enableTextOnlyPosts: Bool = true

    /// Enable stories feature
    var enableStories: Bool = false

    /// Enable reels feature
    var enableReels: Bool = false

    // MARK: - Social Features

    /// Enable likes
    var enableLikes: Bool = true

    /// Enable comments
    var enableComments: Bool = true

    /// Enable sharing
    var enableSharing: Bool = true

    /// Enable bookmarks/saves
    var enableBookmarks: Bool = true

    /// Enable follow/unfollow
    var enableFollow: Bool = true

    /// Enable direct messaging
    var enableDirectMessaging: Bool = true

    /// Enable group chats
    var enableGroupChats: Bool = true

    /// Enable voice messages
    var enableVoiceMessages: Bool = true

    /// Enable video calls
    var enableVideoCalls: Bool = true

    /// Enable voice calls
    var enableVoiceCalls: Bool = true

    // MARK: - Profile Features

    /// Enable profile editing
    var enableProfileEditing: Bool = true

    /// Enable avatar upload
    var enableAvatarUpload: Bool = true

    /// Enable cover photo
    var enableCoverPhoto: Bool = false

    /// Enable verification badge request
    var enableVerificationRequest: Bool = true

    /// Enable account switching
    var enableAccountSwitching: Bool = true

    /// Enable alias/anonymous mode
    var enableAliasMode: Bool = true

    // MARK: - Search & Discovery Features

    /// Enable search
    var enableSearch: Bool = true

    /// Enable user search
    var enableUserSearch: Bool = true

    /// Enable hashtag search
    var enableHashtagSearch: Bool = true

    /// Enable location-based discovery
    var enableLocationDiscovery: Bool = false

    /// Enable friend recommendations
    var enableFriendRecommendations: Bool = true

    // MARK: - AI Features

    /// Enable Alice AI assistant
    var enableAliceAI: Bool = true

    /// Enable Alice voice mode
    var enableAliceVoiceMode: Bool = true

    /// Enable AI-powered content suggestions
    var enableAIContentSuggestions: Bool = false

    // MARK: - Notification Features

    /// Enable push notifications
    var enablePushNotifications: Bool = true

    /// Enable in-app notifications
    var enableInAppNotifications: Bool = true

    /// Enable notification preferences
    var enableNotificationPreferences: Bool = true

    // MARK: - Poll Features

    /// Enable polls/voting
    var enablePolls: Bool = true

    /// Enable poll creation
    var enablePollCreation: Bool = false

    // MARK: - Channel Features

    /// Enable channels
    var enableChannels: Bool = true

    /// Enable channel subscription
    var enableChannelSubscription: Bool = true

    // MARK: - Settings Features

    /// Enable theme customization
    var enableThemeCustomization: Bool = false

    /// Enable privacy settings
    var enablePrivacySettings: Bool = true

    /// Enable security settings
    var enableSecuritySettings: Bool = true

    /// Enable device management
    var enableDeviceManagement: Bool = true

    // MARK: - Invitation System

    /// Enable invitation system
    var enableInvitationSystem: Bool = true

    /// Enable invite code generation
    var enableInviteCodeGeneration: Bool = true

    // MARK: - E2EE Features

    /// Enable end-to-end encryption for messages
    var enableE2EE: Bool = false

    /// Enable Matrix integration
    var enableMatrixIntegration: Bool = false

    // MARK: - QR Code Features

    /// Enable QR code scanning
    var enableQRScanner: Bool = true

    /// Enable personal QR code
    var enablePersonalQRCode: Bool = true

    // MARK: - UI Preview Mode (Development Only)

    /// Enable message preview mode with mock conversations (for UI development)
    /// Set to true to see mock conversations without real friends
    var useMessagePreviewMode: Bool = isDebug && isSimulator

    /// Enable feed preview mode with mock posts
    var useFeedPreviewMode: Bool = false

    /// Enable profile preview mode with mock data
    var useProfilePreviewMode: Bool = false

    // MARK: - Experimental Features

    /// Enable all experimental features
    var enableExperimentalFeatures: Bool = false

    /// Enable new UI components
    var enableNewUIComponents: Bool = false

    /// Enable analytics tracking
    var enableAnalytics: Bool = true

    // MARK: - Private Init

    private init() {
        // Load any persisted feature flag overrides
        loadPersistedFlags()
    }

    // MARK: - Persistence

    private let userDefaultsKey = "FeatureFlagsOverrides"

    /// Save feature flag overrides to UserDefaults
    func saveFlags() {
        // Implementation for persisting flag overrides
        // This allows testing different configurations
    }

    /// Load persisted feature flag overrides
    private func loadPersistedFlags() {
        // Only load overrides in debug mode
        guard FeatureFlags.isDebug else { return }

        // Load from UserDefaults if needed
    }

    // MARK: - Reset

    /// Reset all flags to defaults
    func resetToDefaults() {
        // Reset all flags - useful for testing
    }
}

// MARK: - Environment Key

private struct FeatureFlagsKey: EnvironmentKey {
    static let defaultValue = FeatureFlags.shared
}

extension EnvironmentValues {
    var featureFlags: FeatureFlags {
        get { self[FeatureFlagsKey.self] }
        set { self[FeatureFlagsKey.self] = newValue }
    }
}

// MARK: - View Extension

extension View {
    /// Conditionally show view based on feature flag
    @ViewBuilder
    func featureFlag(_ isEnabled: Bool) -> some View {
        if isEnabled {
            self
        }
    }

    /// Show placeholder when feature is disabled
    @ViewBuilder
    func featureFlag(_ isEnabled: Bool, placeholder: some View) -> some View {
        if isEnabled {
            self
        } else {
            placeholder
        }
    }

    /// Inject feature flags into environment
    @MainActor
    func withFeatureFlags(_ flags: FeatureFlags = .shared) -> some View {
        environment(\.featureFlags, flags)
    }
}

// MARK: - Preview Helpers

extension FeatureFlags {
    /// Create a preview-specific instance with mock data enabled
    static var preview: FeatureFlags {
        let flags = FeatureFlags.shared
        flags.useMockData = true
        flags.enableDebugLogging = true
        return flags
    }

    /// Create an instance with all features enabled
    static var allEnabled: FeatureFlags {
        let flags = FeatureFlags.shared
        // Enable all features for testing
        flags.enableVideoPosting = true
        flags.enableStories = true
        flags.enableReels = true
        flags.enableVoiceMessages = true
        flags.enableVideoCalls = true
        flags.enableVoiceCalls = true
        flags.enableE2EE = true
        flags.enableExperimentalFeatures = true
        return flags
    }

    /// Create an instance with minimal features (for performance testing)
    static var minimal: FeatureFlags {
        let flags = FeatureFlags.shared
        flags.enableTrendingSection = false
        flags.enablePromoBanner = false
        flags.enableRankingCarousel = false
        flags.enableAIImageGeneration = false
        flags.enableAliceAI = false
        return flags
    }
}

// Note: previewSetup() extension is defined in PreviewData.swift
