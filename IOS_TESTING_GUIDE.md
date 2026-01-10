# iOS App Testing Guide - Social Data Consolidation

**Date**: 2026-01-09
**Related Commits**:
- `2e70ace6` - fix(ios): fix likes read/write inconsistency
- `d2cdf877` - refactor(api): rename bookmark endpoints to save/saved-posts
- `c25eda54` - chore(cleanup): prepare for removal of unused content-service social tables

---

## 🎯 Testing Objective

Verify that the iOS app correctly reads likes and bookmarks from `social-service` (nova_social database) instead of `content-service` (nova_content database), ensuring data consistency between writes and reads.

---

## 📱 Test Scenarios

### 1. Profile View - Liked Tab

**What Changed**:
- `ProfileData.swift:828-829` - Now uses `socialService.getUserLikedPosts()` instead of `contentService.getUserLikedPosts()`
- Reads from `nova_social.likes` (single source of truth)

**Test Steps**:
1. Open the app and navigate to your Profile
2. Like a new post from the Home feed
3. Immediately switch to Profile → Liked tab
4. **Expected**: The newly liked post should appear at the top of the list
5. Pull to refresh the Liked tab
6. **Expected**: The post should still be visible (no disappearing)
7. Unlike the post
8. Refresh the Liked tab
9. **Expected**: The post should be removed from the list

**Success Criteria**:
- ✅ Newly liked posts appear immediately in Liked tab
- ✅ No stale data (posts don't disappear after refresh)
- ✅ Unliking removes posts from the list
- ✅ Pagination works correctly (scroll to load more)
- ✅ No crashes or errors

---

### 2. Profile View - Saved Tab

**What Changed**:
- `ProfileData.swift:768-782` - Now uses `socialService.getUserSavedPosts()` instead of `contentService.getUserSavedPosts()`
- Reads from `nova_social.saved_posts` (single source of truth)

**Test Steps**:
1. Open the app and navigate to your Profile
2. Save/bookmark a new post from the Home feed
3. Immediately switch to Profile → Saved tab
4. **Expected**: The newly saved post should appear at the top of the list
5. Pull to refresh the Saved tab
6. **Expected**: The post should still be visible (no disappearing)
7. Unsave the post
8. Refresh the Saved tab
9. **Expected**: The post should be removed from the list

**Success Criteria**:
- ✅ Newly saved posts appear immediately in Saved tab
- ✅ No stale data (posts don't disappear after refresh)
- ✅ Unsaving removes posts from the list
- ✅ Pagination works correctly (scroll to load more)
- ✅ No crashes or errors

---

### 3. UserProfileView - Liked Tab (Other Users)

**What Changed**:
- `UserProfileView.swift:828-829` - Now uses `socialService.getUserLikedPosts()` for other users' profiles

**Test Steps**:
1. Navigate to another user's profile
2. Switch to their Liked tab
3. **Expected**: See their liked posts (if public)
4. Scroll down to test pagination
5. **Expected**: More posts load correctly

**Success Criteria**:
- ✅ Other users' liked posts display correctly
- ✅ Pagination works
- ✅ No crashes when viewing empty liked lists

---

### 4. Cross-Feature Integration Tests

**Test Steps**:
1. Like a post from Home feed
2. Check if it appears in Profile → Liked tab
3. Unlike from Profile → Liked tab
4. Check if the heart icon is unfilled in Home feed
5. Save a post from Post Detail view
6. Check if it appears in Profile → Saved tab
7. Unsave from Profile → Saved tab
8. Check if the bookmark icon is unfilled in Post Detail view

**Success Criteria**:
- ✅ Like/unlike state is consistent across all views
- ✅ Save/unsave state is consistent across all views
- ✅ No race conditions or state desync

---

## 🐛 Known Issues to Watch For

### Issue 1: Empty State After Fresh Like/Save
**Symptom**: Like a post, but Liked tab shows empty
**Root Cause**: API not returning newly created records
**Check**: Verify social-service returns the post in the response

### Issue 2: Pagination Breaks After First Page
**Symptom**: Scroll down, but no more posts load
**Root Cause**: Offset/limit parameters not passed correctly
**Check**: Monitor network requests in Xcode console

### Issue 3: Stale Data After Unlike/Unsave
**Symptom**: Unlike a post, but it still shows in Liked tab
**Root Cause**: Local cache not invalidated
**Check**: Verify `ProfileData.swift` clears cache on state change

---

## 🔍 Debugging Tips

### Enable Debug Logging
The iOS app has debug print statements:
```swift
#if DEBUG
print("[ProfileData] ❤️ Loading liked posts for userId: \(userId)")
print("[ProfileData] ✅ Loaded \(likedPosts.count) liked posts")
#endif
```

**How to View**:
1. Run app in Xcode (Cmd+R)
2. Open Console (Cmd+Shift+C)
3. Filter by `[ProfileData]` or `[UserProfile]`

### Check Network Requests
Monitor API calls in Xcode console:
```
[ProfileData] 🔖 Loading saved posts for userId: <uuid>
[ProfileData] ❤️ Loading liked posts for userId: <uuid>
```

### Verify API Endpoints
The app should call:
- `GET /api/v2/social/users/{userId}/liked-posts` (NEW ✅)
- `GET /api/v2/social/saved-posts` (NEW ✅)

**NOT**:
- `GET /api/v1/posts/user/{userId}/liked` (DEPRECATED ❌)
- `GET /api/v1/posts/user/{userId}/saved` (DEPRECATED ❌)

---

## 📊 Test Results Template

Copy this template to document your test results:

```markdown
## Test Results - [Your Name] - [Date]

### Environment
- iOS Version:
- Device:
- App Version:
- Backend: Staging / Production

### Test 1: Profile Liked Tab
- [ ] Newly liked posts appear immediately
- [ ] No stale data after refresh
- [ ] Unlike removes posts
- [ ] Pagination works
- [ ] No crashes
- **Notes**:

### Test 2: Profile Saved Tab
- [ ] Newly saved posts appear immediately
- [ ] No stale data after refresh
- [ ] Unsave removes posts
- [ ] Pagination works
- [ ] No crashes
- **Notes**:

### Test 3: UserProfileView Liked Tab
- [ ] Other users' liked posts display
- [ ] Pagination works
- [ ] Empty state handled correctly
- **Notes**:

### Test 4: Cross-Feature Integration
- [ ] Like/unlike state consistent
- [ ] Save/unsave state consistent
- [ ] No race conditions
- **Notes**:

### Issues Found
1. [Issue description]
2. [Issue description]

### Overall Status
- [ ] All tests passed ✅
- [ ] Minor issues found ⚠️
- [ ] Major issues found ❌
```

---

## 🚀 Next Steps After Testing

### If All Tests Pass ✅
1. Mark "Test iOS app Liked tab functionality" as complete in `SOCIAL_DATA_CLEANUP_GUIDE.md`
2. Proceed to Phase 2: Database Cleanup (Week 2-3)
3. Schedule maintenance window for migration

### If Issues Found ❌
1. Document issues in GitHub Issues
2. Assign to iOS team for fixes
3. Re-test after fixes are deployed
4. Do NOT proceed with database cleanup until all issues resolved

---

## 📞 Contacts

- **iOS Lead**: [Name]
- **Backend Lead**: [Name]
- **QA Lead**: [Name]

---

**Last Updated**: 2026-01-09
**Next Review**: After iOS testing completion
