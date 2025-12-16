import SwiftUI

// MARK: - Preview Helpers

/// Helper utilities for SwiftUI previews
enum PreviewHelpers {

    // MARK: - Device Configurations

    /// Common device configurations for previews
    enum Device: String, CaseIterable {
        case iPhone15Pro = "iPhone 15 Pro"
        case iPhone15ProMax = "iPhone 15 Pro Max"
        case iPhoneSE = "iPhone SE (3rd generation)"
        case iPadPro11 = "iPad Pro (11-inch) (4th generation)"
        case iPadMini = "iPad mini (6th generation)"

        var previewDevice: PreviewDevice {
            PreviewDevice(rawValue: rawValue)
        }
    }

    // MARK: - Color Scheme Previews

    /// Generate both light and dark mode previews
    struct ColorSchemePreviews<Content: View>: View {
        let content: Content

        init(@ViewBuilder content: () -> Content) {
            self.content = content()
        }

        var body: some View {
            Group {
                content
                    .preferredColorScheme(.light)
                    .previewDisplayName("Light Mode")

                content
                    .preferredColorScheme(.dark)
                    .previewDisplayName("Dark Mode")
            }
        }
    }

    // MARK: - State Preview Wrapper

    /// Wrapper for previewing views with @Binding properties
    struct StateWrapper<Value, Content: View>: View {
        @State private var value: Value
        let content: (Binding<Value>) -> Content

        init(_ initialValue: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
            self._value = State(initialValue: initialValue)
            self.content = content
        }

        var body: some View {
            content($value)
        }
    }
}

// MARK: - Preview Container

/// Container view for consistent preview setup
struct PreviewContainer<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String = "Preview", @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        content
            .previewSetup()
    }
}

// MARK: - Feature Flag Preview Container

/// Preview container with feature flag configuration
struct FeatureFlagPreview<Content: View>: View {
    let flags: FeatureFlags
    let content: Content

    init(
        useMockData: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.flags = FeatureFlags.shared
        self.flags.useMockData = useMockData
        self.content = content()
    }

    var body: some View {
        content
            .withFeatureFlags(flags)
            .environmentObject(AuthenticationManager.shared)
    }
}

// MARK: - Multi-State Preview

/// Generate previews for multiple states of a view
struct MultiStatePreview<Content: View>: View {
    let states: [(String, Content)]

    init(@ViewBuilder content: () -> [(String, Content)]) {
        self.states = content()
    }

    var body: some View {
        ForEach(Array(states.enumerated()), id: \.offset) { _, state in
            state.1
                .previewDisplayName(state.0)
        }
    }
}

// MARK: - Loading State Preview

/// Preview wrapper showing loading, loaded, and error states
struct LoadingStatePreview<Content: View>: View {
    enum State {
        case loading
        case loaded
        case error(String)
        case empty
    }

    let state: State
    let content: Content

    init(state: State, @ViewBuilder content: () -> Content) {
        self.state = state
        self.content = content()
    }

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView("Loading...")
                    .previewDisplayName("Loading")
            case .loaded:
                content
                    .previewDisplayName("Loaded")
            case .error(let message):
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(message)
                        .foregroundColor(.secondary)
                }
                .previewDisplayName("Error")
            case .empty:
                VStack(spacing: 16) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    Text("No content")
                        .foregroundColor(.secondary)
                }
                .previewDisplayName("Empty")
            }
        }
        .previewSetup()
    }
}

// MARK: - Accessibility Preview

/// Preview wrapper for accessibility testing
struct AccessibilityPreview<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Group {
            content
                .previewDisplayName("Default")

            content
                .environment(\.sizeCategory, .extraExtraExtraLarge)
                .previewDisplayName("XXX Large Text")

            content
                .environment(\.sizeCategory, .extraSmall)
                .previewDisplayName("Extra Small Text")
        }
        .previewSetup()
    }
}

// MARK: - Binding Preview Helper

/// Create a constant binding for previews
extension Binding {
    /// Create a preview-safe binding that doesn't crash
    static func preview(_ value: Value) -> Binding<Value> {
        var storedValue = value
        return Binding(
            get: { storedValue },
            set: { storedValue = $0 }
        )
    }
}

// MARK: - Preview Modifiers

extension View {
    /// Add a border to visualize view bounds in preview
    func previewBorder(_ color: Color = .red) -> some View {
        #if DEBUG
        self.border(color)
        #else
        self
        #endif
    }

    /// Add background color to visualize view area in preview
    func previewBackground(_ color: Color = .blue.opacity(0.1)) -> some View {
        #if DEBUG
        self.background(color)
        #else
        self
        #endif
    }

    /// Preview with navigation context
    func previewWithNavigation() -> some View {
        NavigationStack {
            self
        }
        .previewSetup()
    }

    /// Preview with tab context
    func previewWithTabs() -> some View {
        TabView {
            self
                .tabItem {
                    Label("Preview", systemImage: "star")
                }
        }
        .previewSetup()
    }
}

// MARK: - Mock Data Injection

/// Protocol for views that can use mock data
protocol MockDataSupporting {
    associatedtype MockData
    static var mockData: MockData { get }
}

// MARK: - Preview Canvas Helpers

#if DEBUG
/// Quick preview snippets for common patterns
enum PreviewSnippets {
    /// Preview a view with binding
    static func withBinding<V: View, T>(
        _ value: T,
        @ViewBuilder content: @escaping (Binding<T>) -> V
    ) -> some View {
        PreviewHelpers.StateWrapper(value, content: content)
    }

    /// Preview a view in navigation context
    static func inNavigation<V: View>(@ViewBuilder content: () -> V) -> some View {
        NavigationStack {
            content()
        }
        .previewSetup()
    }

    /// Preview with configured auth state
    @MainActor
    static func withAuth<V: View>(
        user: UserProfile = PreviewData.Users.currentUser,
        @ViewBuilder content: () -> V
    ) -> some View {
        let authManager = AuthenticationManager.shared
        authManager.currentUser = user
        authManager.isAuthenticated = true

        return content()
            .environmentObject(authManager)
            .withFeatureFlags(.preview)
    }
}
#endif
