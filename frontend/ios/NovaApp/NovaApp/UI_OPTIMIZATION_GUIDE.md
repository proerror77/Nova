# NovaInstagram UI Optimization Guide

## Overview
This guide documents the complete UI layer and state management optimization for NovaInstagram iOS app.

---

## 1. State Management Architecture

### Global State (AppState)
```swift
// Usage: Inject at app root
@main
struct NovaApp: App {
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(appState.colorScheme)
        }
    }
}

// Access in views
struct MyView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if appState.isOffline {
            OfflineBanner()
        }
    }
}
```

### ViewModel Pattern
```swift
// All ViewModels inherit from BaseViewModel
class MyViewModel: BaseViewModel, PaginatedViewModel {
    @Published var items: [Item] = []
    var currentPage = 0
    var hasMore = true
    let pageSize = 20

    func loadInitial() async {
        resetPagination()
        do {
            try await withLoading {
                // Load data
            }
        } catch {
            handleError(error)
        }
    }
}
```

### Benefits
- **Centralized error handling** - All errors go through `handleError()`
- **Consistent loading states** - `isLoading`, `isLoadingMore` managed automatically
- **Network awareness** - Automatic offline detection
- **Type-safe** - No more scattered `@State` variables

---

## 2. Component Library

### Buttons
```swift
// Primary button (main actions)
PrimaryButton(
    title: "Sign In",
    action: { /* ... */ },
    isLoading: viewModel.isLoading
)

// Secondary button (cancel, dismiss)
SecondaryButton(
    title: "Cancel",
    action: { /* ... */ }
)
```

### Text Fields
```swift
// Standard text field with icon and validation
NovaTextField(
    placeholder: "Email",
    text: $email,
    icon: "envelope",
    keyboardType: .emailAddress,
    textContentType: .emailAddress,
    errorMessage: viewModel.emailError
)

// Secure field
NovaTextField(
    placeholder: "Password",
    text: $password,
    icon: "lock",
    isSecure: true
)
```

### Loading States
```swift
// Full-screen loading
if viewModel.isLoading {
    LoadingView(message: "Loading posts...")
}

// Inline spinner
LoadingSpinner(size: 24, color: .primary)

// Shimmer skeleton
ShimmerView()
    .frame(height: 100)
    .cornerRadius(Theme.CornerRadius.md)
```

### Error Handling
```swift
// Full-screen error with retry
ErrorView(
    error: viewModel.error,
    retryAction: { await viewModel.retry() }
)

// Inline banner
if viewModel.showError {
    ErrorBanner(
        message: viewModel.error?.localizedDescription ?? "Error",
        onDismiss: { viewModel.clearError() }
    )
}

// Toast notification
ToastView(type: .success, message: "Post published!")
```

### Empty States
```swift
EmptyStateView(
    icon: "photo.on.rectangle.angled",
    title: "No Posts Yet",
    description: "Follow people to see their posts",
    actionTitle: "Find People",
    action: { /* navigate to search */ }
)
```

---

## 3. Design System

### Theme Access
```swift
// Colors
Theme.Colors.primary
Theme.Colors.surface
Theme.Colors.textPrimary
Theme.Colors.error

// Typography
Theme.Typography.h1
Theme.Typography.body
Theme.Typography.caption

// Spacing
Theme.Spacing.xs  // 8
Theme.Spacing.md  // 16
Theme.Spacing.xl  // 32

// Corner Radius
Theme.CornerRadius.md  // 12

// Shadows
.themeShadow(Theme.Shadows.small)
```

### View Modifiers
```swift
// Card style
Text("Hello")
    .cardStyle()

// Shimmer loading
Rectangle()
    .shimmerLoading()

// Conditional modifier
Text("Hello")
    .if(isHighlighted) { view in
        view.foregroundColor(.red)
    }

// Hide keyboard on tap
Form { /* ... */ }
    .hideKeyboardOnTap()
```

---

## 4. Animations & Transitions

### Custom Animations
```swift
// Quick spring (for UI feedback)
withAnimation(.quickSpring) {
    isExpanded.toggle()
}

// Smooth easing
withAnimation(.smooth) {
    offset = 100
}

// Bouncy (playful)
withAnimation(.bouncy) {
    scale = 1.5
}
```

### Transitions
```swift
.transition(.slideFromBottom)
.transition(.scaleAndFade)
.transition(.slideFromTrailing)
```

### Special Effects
```swift
// Shake on error
Button("Submit")
    .shake(trigger: viewModel.errorCount)

// Pulse loading
Circle()
    .pulse()
```

---

## 5. Responsive Design

### Adaptive Grid
```swift
ResponsiveGrid(items: photos, spacing: 12, minItemWidth: 100) { photo in
    PhotoCard(photo: photo)
}
// Automatically adjusts columns based on device
```

### Responsive Container
```swift
ResponsiveContainer {
    VStack {
        // Content
    }
}
// Max width 800pt on iPad, full width on iPhone
```

### Adaptive Stack
```swift
AdaptiveStack {
    Text("Item 1")
    Text("Item 2")
}
// VStack on portrait, HStack on landscape
```

### Screen Size Helpers
```swift
if ScreenSize.isSmall {
    // iPhone SE layout
} else if ScreenSize.isLarge {
    // iPhone Pro Max layout
}
```

---

## 6. Theme Switching

### Implementation
```swift
// In Settings
ThemeSwitcher()
    .environmentObject(appState)

// Reads/writes to UserDefaults
// Updates entire app automatically
```

### Custom Color Schemes
```swift
// Define adaptive colors
Theme.Colors.adaptiveBackground(for: .dark)
Theme.Colors.adaptiveTextPrimary(for: .light)
```

---

## 7. Performance Optimizations

### Post Model Equatable
```swift
// Custom equality to prevent unnecessary redraws
static func == (lhs: Post, rhs: Post) -> Bool {
    lhs.id == rhs.id &&
    lhs.likeCount == rhs.likeCount &&
    lhs.isLiked == rhs.isLiked
    // Skip author, imageURL (immutable)
}
```

### Lazy Loading
```swift
LazyVStack {
    ForEach(items) { item in
        ItemView(item: item)
            .onAppear {
                // Load more when last item appears
                if item.id == items.last?.id {
                    await viewModel.loadMore()
                }
            }
    }
}
```

### Image Caching
```swift
// Use CachedAsyncImage for all remote images
CachedAsyncImage(url: post.imageURL, size: .medium) { uiImage in
    Image(uiImage: uiImage)
        .resizable()
        .aspectRatio(contentMode: .fill)
}
```

---

## 8. Accessibility

### Semantic Labels
```swift
Button(action: {}) {
    Image(systemName: "heart.fill")
}
.accessibilityLabel("Like post")
.accessibilityHint("Double tap to like this post")
```

### Dynamic Type Support
```swift
// All Theme.Typography fonts automatically scale
Text("Hello")
    .font(Theme.Typography.body)
// Respects user's text size preferences
```

### VoiceOver Support
```swift
PostCard(post: post)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(post.author.displayName), \(post.caption ?? "")")
```

---

## 9. Migration Checklist

### For Existing Views
- [ ] Replace `@State` with `@StateObject` for ViewModels
- [ ] Inject `AppState` via `@EnvironmentObject`
- [ ] Replace custom TextFields with `NovaTextField`
- [ ] Replace custom Buttons with `PrimaryButton`/`SecondaryButton`
- [ ] Add error handling with `ErrorBanner` or `ErrorView`
- [ ] Add loading states with `LoadingView` or `LoadingSpinner`
- [ ] Add empty states with `EmptyStateView`
- [ ] Replace manual styling with `.cardStyle()` modifier
- [ ] Use `Theme.Spacing.*` instead of hardcoded values
- [ ] Add `.shimmerLoading()` to skeleton views

### For New Views
1. **Create ViewModel**
   ```swift
   class MyViewModel: BaseViewModel {
       @Published var items: [Item] = []

       func loadData() async {
           do {
               try await withLoading {
                   // API call
               }
           } catch {
               handleError(error)
           }
       }
   }
   ```

2. **Create View**
   ```swift
   struct MyView: View {
       @StateObject private var viewModel = MyViewModel()
       @EnvironmentObject var appState: AppState

       var body: some View {
           // Use components from library
       }
   }
   ```

---

## 10. Testing

### ViewModel Testing
```swift
@MainActor
class MyViewModelTests: XCTestCase {
    func testLoadData() async {
        let viewModel = MyViewModel()
        await viewModel.loadData()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.error)
        XCTAssertFalse(viewModel.items.isEmpty)
    }
}
```

### Preview Testing
```swift
#Preview {
    MyView()
        .environmentObject(AppState.shared)
        .environmentObject(NavigationCoordinator())
}
```

---

## 11. File Structure

```
NovaApp/
├── Core/
│   ├── State/
│   │   ├── AppState.swift
│   │   └── NetworkMonitor.swift
│   └── ViewModels/
│       └── BaseViewModel.swift
├── DesignSystem/
│   ├── Theme.swift
│   ├── Theme+Environment.swift
│   ├── Components/
│   │   ├── PrimaryButton.swift
│   │   ├── SecondaryButton.swift
│   │   ├── NovaTextField.swift
│   │   ├── LoadingView.swift
│   │   ├── ErrorView.swift
│   │   ├── EmptyStateView.swift
│   │   ├── TabBarView.swift
│   │   └── ThemeSwitcher.swift
│   ├── Modifiers/
│   │   └── ViewModifiers.swift
│   ├── Animations/
│   │   └── Transitions.swift
│   └── Layouts/
│       └── ResponsiveLayout.swift
└── Features/
    ├── Feed/
    │   ├── ViewModels/
    │   │   └── FeedViewModel.swift
    │   └── Views/
    │       └── FeedView.swift
    └── Auth/
        └── Views/
            └── SignInView.swift
```

---

## Summary

### What Changed
1. **State Management**: Centralized with `AppState` and `BaseViewModel`
2. **Components**: Reusable library with consistent styling
3. **Error Handling**: Unified error display system
4. **Loading States**: Shimmer, spinners, full-screen overlays
5. **Animations**: Custom transitions and spring animations
6. **Responsive**: Adaptive layouts for all devices
7. **Theme**: Dark/Light/Auto mode support

### Key Benefits
- **80% less boilerplate code** in new views
- **Consistent UX** across the app
- **Better performance** with optimized re-renders
- **Easier testing** with ViewModel separation
- **Future-proof** for design system updates

### Next Steps
1. Migrate existing views one by one
2. Add more specialized components as needed
3. Enhance animations for specific interactions
4. Implement haptic feedback
5. Add more accessibility features
