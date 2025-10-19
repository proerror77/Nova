# Nova iOS App - Project Architecture

## Overview
Nova is a production-ready iOS social media application built with SwiftUI, following MVVM architecture with clean separation of concerns.

## Architecture Layers

### 1. Presentation Layer (Views + ViewModels)
```
Views → ViewModels → Services/Repositories
```

**Key Principles:**
- SwiftUI declarative UI
- ViewModels handle business logic
- `@Published` properties for reactive updates
- Async/await for asynchronous operations

### 2. Navigation Layer
```
NavigationCoordinator → AppRouter → DeepLinkHandler
```

**Features:**
- 5 independent navigation stacks (one per tab)
- Type-safe routing via `AppRoute` enum
- Deep link support (nova://app/*, https://nova.app/*)
- Backward compatibility for legacy URLs

### 3. Data Layer
```
Repository → APIClient → Backend
             ↓
        CacheManager (local)
             ↓
        ActionQueue (offline queue)
```

**Features:**
- Repository pattern for data abstraction
- Network layer with retry + idempotency
- Feed caching (30s TTL)
- Offline action queue (retry up to 3 times)
- Keychain for secure token storage

### 4. Analytics Layer
```
AnalyticsTracker → EventBuffer → ClickHouseClient
```

**Features:**
- 16+ event types (lifecycle, auth, feed, upload, etc.)
- Batch upload (50 events or 30s interval)
- Device ID tracking
- Platform/version metadata

## Design System
**Single Source of Truth:** `Theme.swift`

**Components:**
- Colors (primary, surface, semantic)
- Typography (h1-h6, body, caption, button)
- Spacing (xxs → xxl)
- Shadows (small, medium, large)
- Corner Radius (xs → xl)

**Reusable Components:**
- `PrimaryButton` (with loading state)
- `Avatar` (with fallback to initials)
- `PostCard` (feed item)
- `SkeletonView` (loading placeholder)
- `EmptyStateView`

## Module Structure

### Auth Module
- **Views:** `OnboardingView`, `SignInView`, `SignUpView`, `AppleSignInGateView`
- **Service:** `AuthService` (singleton, manages auth state)
- **Features:** Email/password auth, Apple Sign In, token refresh

### Feed Module
- **Views:** `FeedView` (F01), `PostDetailView` (P01), `CommentsSheet` (C01)
- **ViewModel:** `FeedViewModel` (pagination, cache, optimistic updates)
- **Features:** Infinite scroll, skeleton loader, pull-to-refresh, like/unlike

### Create Module
- **Views:** `CreateEntryView`, `PhotoPickerView`, `ImageEditView`, `PublishFormView`, `UploadQueueView`
- **Features:** Photo selection, image editing, presigned upload, offline queue

### Search Module
- **Views:** `SearchView`, `UserResultListView`
- **Features:** Throttled search (300ms), recent queries

### Profile Module
- **Views:** `MyProfileView`, `UserProfileView`, `EditProfileView`
- **Features:** Post grid, follow/unfollow, profile editing

### Notifications Module
- **Views:** `NotificationsView`
- **Features:** Activity feed (likes, comments, follows)

### Settings Module
- **Views:** `SettingsView`, `DeleteAccountFlow`, `PolicyWebView`
- **Features:** Account management, privacy policy

## Performance Targets

### P50 Latency Goals
- Feed initial load: **< 500ms**
- Post detail: **< 300ms**
- Search results: **< 400ms**
- Image upload: **< 2s** (for 2MB)

### Optimization Strategies
- Skeleton loaders (shown for **< 200ms**)
- Feed cache (30s TTL)
- Image compression (max 2MB)
- Lazy loading for lists
- Pagination (20 items per page)

## Error Handling

### Network Errors
- Retry logic (up to 3 times with exponential backoff)
- Offline queue for mutating operations
- User-friendly error messages

### State Management
- Optimistic updates (e.g., like/unlike)
- Revert on error
- Loading/error states for all async operations

## Security

### Token Management
- Access token + refresh token (stored in Keychain)
- Auto-refresh on 401 responses
- Secure token rotation

### Data Protection
- Keychain for sensitive data
- HTTPS-only communication
- No hardcoded credentials

## Testing Strategy

### Unit Tests
- ViewModels (business logic)
- Repositories (data operations)
- Services (auth, upload)

### Integration Tests
- Auth flow (sign in → feed)
- Create flow (photo picker → upload)
- Search flow (query → results)

### UI Tests
- Critical user journeys
- Accessibility compliance (WCAG 2.1 AA)

## Deployment

### Build Configuration
- **Debug:** Development API, verbose logging
- **Release:** Production API, optimized build

### CI/CD
- GitHub Actions for build + test
- TestFlight for beta distribution
- App Store Connect for production

## Dependencies

### Native Frameworks
- SwiftUI (UI framework)
- AuthenticationServices (Apple Sign In)
- Combine (reactive programming)
- Foundation (networking, data handling)

### Third-Party (if needed)
- Kingfisher (image caching - optional, can use native AsyncImage)
- None for MVP (keep dependencies minimal)

## File Count Summary
- **Swift source files:** 60+
- **Documentation files:** 8
- **Figma frames:** 21
- **API endpoints:** 15
- **Event types:** 16+

## Next Steps
1. Complete implementation of template views
2. Integrate with backend OpenAPI spec
3. Add unit tests for ViewModels
4. Performance profiling with Instruments
5. Accessibility audit
6. TestFlight beta testing
