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

    /// Enable debug logging
    var enableDebugLogging: Bool = isDebug

    // MARK: - Communication Features (Actually Used)

    /// Enable video calls
    var enableVideoCalls: Bool = true

    /// Enable voice calls
    var enableVoiceCalls: Bool = true

    // MARK: - UI Preview Mode (Development Only)

    /// Enable message preview mode with mock conversations (for UI development)
    var useMessagePreviewMode: Bool = isDebug && isSimulator

    /// Enable feed preview mode with mock posts
    var useFeedPreviewMode: Bool = false

    /// Enable profile preview mode with mock data
    var useProfilePreviewMode: Bool = false

    // MARK: - Analytics

    /// Enable analytics tracking
    var enableAnalytics: Bool = true

    // MARK: - Private Init

    private init() {}
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

    /// Create an instance with all features enabled (for testing)
    static var allEnabled: FeatureFlags {
        let flags = FeatureFlags.shared
        flags.enableVideoCalls = true
        flags.enableVoiceCalls = true
        return flags
    }
}
