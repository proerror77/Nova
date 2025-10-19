# Nova iOS - 2-Week Sprint Plan

## Overview
Complete MVP implementation in 2 weeks (10 working days)

## Week 1: Core Infrastructure + Auth + Feed

### Day 1-2: Foundation (Infrastructure)
**Goal:** Setup project + DesignSystem + Navigation

**Tasks:**
- [x] Project initialization (XcodeGen config)
- [x] DesignSystem v1 (Theme, Colors, Typography)
- [x] Core Components (Button, Avatar, PostCard, Skeleton)
- [x] Navigation architecture (Coordinator, Router, DeepLink)
- [x] Data layer setup (APIClient, Repositories, Cache, Queue)
- [x] Analytics foundation (Events, Tracker, ClickHouseClient)

**Deliverables:**
- ✅ Compiling project with all modules
- ✅ Design tokens accessible app-wide
- ✅ Navigation between dummy screens working

**Testing:**
- Unit tests for NavigationCoordinator
- Unit tests for DeepLinkHandler

---

### Day 3-4: Auth Flow
**Goal:** Complete authentication (email + Apple Sign In)

**Tasks:**
- [ ] Implement OnboardingView (O00)
- [ ] Implement SignInView (A01)
- [ ] Implement SignUpView (A02)
- [ ] Implement AppleSignInGateView (A03)
- [ ] AuthService with token management
- [ ] AuthRepository with API integration
- [ ] KeychainManager for secure storage
- [ ] Token refresh logic

**Deliverables:**
- ✅ User can sign up with email/password
- ✅ User can sign in with Apple
- ✅ Tokens stored securely in Keychain
- ✅ Auto sign-in on app relaunch

**Testing:**
- Integration test: Sign up → Sign in → Token refresh
- Unit tests for AuthService
- Mock Apple Sign In flow

**Analytics:**
- Track: onboarding_view, sign_in, sign_up, sign_in (method: apple)

---

### Day 5-6: Feed + Posts
**Goal:** Display feed with skeleton loader + cache

**Tasks:**
- [ ] FeedView (F01) with LazyVStack
- [ ] FeedViewModel with pagination
- [ ] FeedRepository with cache support
- [ ] Skeleton loader (show < 200ms)
- [ ] Pull-to-refresh
- [ ] PostCard component (reuse from DesignSystem)
- [ ] Like/unlike with optimistic updates
- [ ] Offline action queue

**Deliverables:**
- ✅ Feed loads with skeleton → posts
- ✅ Infinite scroll pagination
- ✅ Cache works (30s TTL)
- ✅ Like button works (optimistic)

**Testing:**
- Unit tests for FeedViewModel (pagination logic)
- Integration test: Feed load → scroll → load more
- Test offline like → go online → syncs

**Analytics:**
- Track: feed_view, post_impression, post_tap, post_like, post_unlike

**Performance:**
- P50 feed load: < 500ms

---

### Day 7: Upload Presign + Image Compression
**Goal:** Prepare upload infrastructure

**Tasks:**
- [ ] PhotoPickerView (U01) with native PHPicker
- [ ] Image compression service (max 2MB, JPEG 85%)
- [ ] Image resize logic (max 2048x2048)
- [ ] Presigned URL endpoint integration
- [ ] S3 direct upload logic
- [ ] UploadQueueView (U04) for offline uploads

**Deliverables:**
- ✅ User can select photo from library
- ✅ Image compressed before upload
- ✅ Presigned URL obtained
- ✅ Upload to S3 works

**Testing:**
- Test compression (5MB → < 2MB)
- Test presigned URL expiry handling
- Test upload retry on failure

**Analytics:**
- Track: upload_start, upload_success, upload_fail

**Performance:**
- 2MB upload: < 2.5s

---

## Week 2: Post Detail + Comments + Profile + Search + Settings

### Day 8: Post Detail + Comments
**Goal:** Full post viewing experience

**Tasks:**
- [ ] PostDetailView (P01)
- [ ] PostDetailViewModel
- [ ] CommentsSheet (C01) as bottom sheet
- [ ] CommentsViewModel with pagination
- [ ] Comment creation with optimistic update
- [ ] CommentRow component

**Deliverables:**
- ✅ Tap post → view full detail
- ✅ Tap comment icon → view comments
- ✅ User can add comment
- ✅ Comments paginate

**Testing:**
- Integration test: Feed → Post detail → Comments → Add comment
- Unit tests for CommentsViewModel

**Analytics:**
- Track: comment_view, comment_create

**Performance:**
- Post detail load: < 300ms
- Comments load: < 250ms

---

### Day 9: Profile + Edit
**Goal:** User profile pages

**Tasks:**
- [ ] MyProfileView (PR01)
- [ ] UserProfileView (PR02)
- [ ] EditProfileView (PR03)
- [ ] ProfileViewModel
- [ ] Post grid layout (3 columns)
- [ ] Profile editing (display name, bio, avatar)
- [ ] Avatar upload with compression

**Deliverables:**
- ✅ View own profile
- ✅ View other user's profile
- ✅ Edit profile fields
- ✅ Update avatar

**Testing:**
- Integration test: Profile → Edit → Save → Verify changes
- Test avatar compression

**Analytics:**
- Track: profile_view, profile_update

**Performance:**
- Profile load: < 350ms

---

### Day 10: Search + Notifications
**Goal:** Search users + activity feed

**Tasks:**
- [ ] SearchView (S01)
- [ ] SearchViewModel with throttling (300ms)
- [ ] UserResultListView (S02)
- [ ] NotificationsView (N01)
- [ ] NotificationsViewModel
- [ ] NotificationRow component

**Deliverables:**
- ✅ User can search by username
- ✅ Search throttled (not on every keystroke)
- ✅ View activity notifications
- ✅ Tap notification → navigate to post/profile

**Testing:**
- Test search throttling (< 300ms delay)
- Integration test: Search → Tap result → View profile

**Analytics:**
- Track: search_submit, search_result_click, notification_open

**Performance:**
- Search results: < 400ms

---

### Day 11: Settings + Account Deletion
**Goal:** App settings + account management

**Tasks:**
- [ ] SettingsView (ST01)
- [ ] DeleteAccountFlow (ST02) with confirmation
- [ ] PolicyWebView (ST03)
- [ ] Account deletion logic
- [ ] Clear local data on sign out

**Deliverables:**
- ✅ Settings menu accessible
- ✅ User can delete account (with confirmation)
- ✅ Privacy policy viewable

**Testing:**
- Test account deletion (cannot undo)
- Test sign out clears cache

**Analytics:**
- Track: account_delete

---

### Day 12: Integration + Polish
**Goal:** Bug fixes + edge cases + polish

**Tasks:**
- [ ] Fix layout issues on iPhone SE
- [ ] Fix iPad layout (if supporting iPad)
- [ ] Handle empty states (no posts, no search results)
- [ ] Handle error states (network error, 404, etc.)
- [ ] Add loading indicators where missing
- [ ] Test all deep links
- [ ] Test offline → online transitions
- [ ] Performance profiling with Instruments

**Deliverables:**
- ✅ All screens responsive
- ✅ Graceful error handling
- ✅ No memory leaks
- ✅ All P50 targets met

**Testing:**
- Full E2E test suite
- Accessibility audit (VoiceOver)
- Test on iPhone SE, 14 Pro, 15 Pro Max

---

## Delivery Checklist

### Code Quality
- [ ] All ViewModels have unit tests
- [ ] All Repositories have unit tests
- [ ] No force unwraps (!) except in tests
- [ ] No retain cycles (weak/unowned used correctly)
- [ ] SwiftLint passes (0 warnings)

### Performance
- [ ] Feed load: < 500ms P50
- [ ] Post detail: < 300ms P50
- [ ] Search: < 400ms P50
- [ ] Profile: < 350ms P50
- [ ] Upload: < 2.5s for 2MB

### Analytics
- [ ] All 16+ events integrated
- [ ] Batch upload working (50 events / 30s)
- [ ] Events visible in ClickHouse

### Documentation
- [x] PROJECT_ARCHITECTURE.md complete
- [x] ROUTING_MAP.md complete
- [x] API_SPEC.md complete
- [x] DATA_FLOW.md complete
- [x] PERFORMANCE_CHECKLIST.md complete
- [x] SPRINT_PLAN.md (this file)

### Deployment
- [ ] TestFlight build uploaded
- [ ] Beta testers invited (5-10 people)
- [ ] Crash reporting enabled (Crashlytics or similar)
- [ ] Analytics dashboard setup

---

## Post-Sprint (Week 3+)

### Beta Testing (Week 3)
- Collect feedback from beta testers
- Fix critical bugs
- Performance tuning
- Prepare App Store assets (screenshots, description)

### App Store Submission (Week 4)
- Final QA pass
- Submit to App Review
- Respond to App Review feedback
- Release 1.0.0

---

## Risks & Mitigations

### Risk: Backend API not ready
**Mitigation:** Use mock data / JSON fixtures for development

### Risk: Apple Sign In integration issues
**Mitigation:** Allocate extra time on Day 4 for debugging

### Risk: Upload reliability
**Mitigation:** Implement robust retry logic + offline queue

### Risk: Performance targets not met
**Mitigation:** Daily performance checks with Instruments

---

## Success Metrics

### Sprint Success
- All 21 screens functional (template or complete)
- Auth flow complete (email + Apple)
- Feed + Post detail complete
- Upload flow working
- Analytics integrated

### MVP Success (Post-Release)
- Crash-free rate: > 99%
- P50 latency targets met
- 100+ beta testers onboarded
- Positive App Store reviews (> 4.0 stars)
