# Nova iOS - Routing Map

## Overview
All 21 screens mapped to type-safe routes defined in `AppRoute` enum.

## Route Definitions

### Auth Routes (4)
| Route | View | Path | Figma Frame |
|-------|------|------|-------------|
| `.onboarding` | `OnboardingView` | `/onboarding` | O00 |
| `.signIn` | `SignInView` | `/auth/signin` | A01 |
| `.signUp` | `SignUpView` | `/auth/signup` | A02 |
| `.appleSignInGate` | `AppleSignInGateView` | `/auth/apple` | A03 |

### Main Tab Routes (5)
| Route | View | Path | Figma Frame |
|-------|------|------|-------------|
| `.feed` | `FeedView` | `/` | F01 |
| `.search` | `SearchView` | `/search` | S01 |
| `.create` | `CreateEntryView` | `/create` | U00 |
| `.notifications` | `NotificationsView` | `/notifications` | N01 |
| `.profile(userId: nil)` | `MyProfileView` | `/profile` | PR01 |

### Post Routes (2)
| Route | View | Path | Figma Frame |
|-------|------|------|-------------|
| `.postDetail(postId)` | `PostDetailView` | `/post/:id` | P01 |
| `.comments(postId)` | `CommentsSheet` | `/post/:id/comments` | C01 |

### Create Flow Routes (4)
| Route | View | Path | Figma Frame |
|-------|------|------|-------------|
| `.photoPicker` | `PhotoPickerView` | `/create/picker` | U01 |
| `.imageEdit(imageData)` | `ImageEditView` | `/create/edit` | U02 |
| `.publishForm(imageData)` | `PublishFormView` | `/create/publish` | U03 |
| `.uploadQueue` | `UploadQueueView` | `/create/queue` | U04 |

### Search Routes (1)
| Route | View | Path | Figma Frame |
|-------|------|------|-------------|
| `.userResults(query)` | `UserResultListView` | `/search/users?q={query}` | S02 |

### Profile Routes (2)
| Route | View | Path | Figma Frame |
|-------|------|------|-------------|
| `.profile(userId)` | `UserProfileView` | `/profile/:userId` | PR02 |
| `.editProfile` | `EditProfileView` | `/profile/edit` | PR03 |

### Settings Routes (3)
| Route | View | Path | Figma Frame |
|-------|------|------|-------------|
| `.settings` | `SettingsView` | `/settings` | ST01 |
| `.deleteAccount` | `DeleteAccountFlow` | `/settings/delete` | ST02 |
| `.policy(url)` | `PolicyWebView` | `/settings/policy?url={url}` | ST03 |

## Navigation Stacks
Nova uses 5 independent navigation stacks managed by `NavigationCoordinator`:

### 1. Feed Stack (`feedPath`)
- Root: `FeedView`
- Pushes: `PostDetailView`, `CommentsSheet`

### 2. Search Stack (`searchPath`)
- Root: `SearchView`
- Pushes: `UserResultListView`

### 3. Create Stack (`createPath`)
- Root: `CreateEntryView`
- Pushes: `PhotoPickerView`, `ImageEditView`, `PublishFormView`, `UploadQueueView`

### 4. Notifications Stack (`notificationsPath`)
- Root: `NotificationsView`

### 5. Profile Stack (`profilePath`)
- Root: `MyProfileView`
- Pushes: `UserProfileView`, `EditProfileView`, `SettingsView`, `DeleteAccountFlow`, `PolicyWebView`

## Deep Link Handling

### Supported URL Schemes
- **Custom scheme:** `nova://app/*`
- **Web URLs:** `https://nova.app/*`

### Deep Link Examples

#### Post Detail
```
nova://app/post/abc123
https://nova.app/post/abc123
```
→ Navigate to `PostDetailView(postId: "abc123")`

#### Comments
```
nova://app/post/abc123/comments
https://nova.app/post/abc123/comments
```
→ Navigate to `CommentsSheet(postId: "abc123")`

#### User Profile
```
nova://app/profile/user456
https://nova.app/profile/user456
```
→ Navigate to `UserProfileView(userId: "user456")`

#### Search Results
```
nova://app/search/users?q=john
https://nova.app/search/users?q=john
```
→ Navigate to `UserResultListView(query: "john")`

### Backward Compatibility
Legacy URL format (pre-v2.0):
```
nova://post?id=abc123
```
→ Automatically converted to `nova://app/post/abc123`

## Navigation Methods

### Programmatic Navigation
```swift
coordinator.navigate(to: .postDetail(postId: "abc123"))
```

### Pop to Root
```swift
coordinator.navigateToRoot(tab: .feed)
```

### Sheet Presentation
```swift
coordinator.presentSheet(.comments(postId: "abc123"))
```

### Full Screen Cover
```swift
coordinator.presentFullScreenCover(.imageEdit(imageData: data))
```

## Route Guards
Routes requiring authentication (checked via `requiresAuth` property):
- All routes except: `.onboarding`, `.signIn`, `.signUp`, `.appleSignInGate`

If user is not authenticated → redirect to `AuthCoordinatorView`

## Analytics Integration
Every navigation triggers an analytics event:
```swift
AnalyticsTracker.shared.track(.navigation(to: route.analyticsName))
```

## Testing Deep Links
Use Safari or terminal to test deep links:
```bash
# macOS Simulator
xcrun simctl openurl booted "nova://app/post/test123"

# Physical device (via Safari)
https://nova.app/post/test123
```

## Route Priority
When multiple routes match a URL, priority is:
1. Exact path match
2. Parameterized path (e.g., `/post/:id`)
3. Query-based path (e.g., `/search/users?q=`)
4. Fallback to root (`.feed`)
