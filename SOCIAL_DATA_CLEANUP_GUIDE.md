# Social Interactions Data Consolidation - Cleanup Guide

**Date**: 2026-01-09
**Status**: Ready for execution after iOS testing
**Related Commits**:
- `2e70ace6` - fix(ios): fix likes read/write inconsistency
- `d2cdf877` - refactor(api): rename bookmark endpoints to save/saved-posts

---

## 📋 Overview

This document outlines the cleanup steps needed after consolidating social interaction data (likes, bookmarks) from content-service to social-service as the single source of truth.

### Problem Fixed

**Before**:
- Writes → `nova_social.likes` and `nova_social.saved_posts`
- Reads → `nova_content.likes` and `nova_content.bookmarks`
- Result: Data inconsistency, stale reads

**After**:
- Writes → `nova_social.likes` and `nova_social.saved_posts`
- Reads → `nova_social.likes` and `nova_social.saved_posts`
- Result: Consistent data, single source of truth ✅

---

## ✅ Completed Tasks

### 1. iOS Client Updates
- [x] ProfileData.swift - Use social-service for likes
- [x] ProfileData.swift - Use social-service for bookmarks
- [x] UserProfileView.swift - Use social-service for likes
- [x] Committed: `2e70ace6`

### 2. Backend API Deprecation
- [x] Marked `GET /api/v1/posts/user/{id}/liked` as deprecated
- [x] Marked `GET /api/v1/posts/user/{id}/saved` as deprecated
- [x] Added Rust `#[deprecated]` attributes with sunset date
- [x] Updated documentation comments

### 3. Database Migration Files
- [x] Created `20260109_remove_unused_social_tables.sql`
- [x] Created `20260109_remove_unused_social_tables.down.sql` (rollback)

---

## 🔄 Pending Tasks

### Phase 1: Testing & Validation (Week 1)

**iOS App Testing**:
- [ ] Test Liked tab shows recently liked posts
- [ ] Test Saved tab shows recently saved posts
- [ ] Test pagination works correctly
- [ ] Test on both own profile and other users' profiles
- [ ] Verify no crashes or errors

**Testing Resources**:
- 📖 Full Guide: `IOS_TESTING_GUIDE.md` - Comprehensive testing scenarios and debugging tips
- ⚡ Quick Test: `QUICK_TEST_CHECKLIST.md` - 5-minute smoke test for rapid validation
- 📋 Summary: `IMPLEMENTATION_SUMMARY.md` - Complete overview of changes and timeline

**Backend Monitoring**:
- [ ] Monitor staging logs for any errors
- [ ] Check if deprecated endpoints are still being called
- [ ] Verify new endpoints are working correctly

**Commands**:
```bash
# Check for deprecated endpoint usage
kubectl logs -n nova-staging -l app=graphql-gateway --tail=1000 | grep "/api/v1/posts/user.*liked\|/api/v1/posts/user.*saved"

# Monitor new endpoint usage
kubectl logs -n nova-staging -l app=graphql-gateway --tail=1000 | grep "/api/v2/social/saved-posts\|getUserLikedPosts"
```

### Phase 2: Database Cleanup (Week 2-3)

**Pre-Migration Checklist**:
- [ ] Confirm iOS app is deployed and working
- [ ] Verify no services are reading from `nova_content.likes` or `nova_content.bookmarks`
- [ ] Take database backup
- [ ] Schedule maintenance window

**Execute Migration**:
```bash
# Staging
psql -h <staging-db> -U postgres -d nova_content -f backend/content-service/migrations/20260109_remove_unused_social_tables.sql

# Production (after staging validation)
psql -h <prod-db> -U postgres -d nova_content -f backend/content-service/migrations/20260109_remove_unused_social_tables.sql
```

**Rollback (if needed)**:
```bash
psql -h <db-host> -U postgres -d nova_content -f backend/content-service/migrations/20260109_remove_unused_social_tables.down.sql
# Note: This only recreates tables, data must be restored from backup
```

### Phase 3: API Endpoint Removal (After 2026-04-01)

**Remove Deprecated Endpoints**:
- [ ] Remove `get_user_liked_posts()` from `backend/graphql-gateway/src/rest_api/content.rs`
- [ ] Remove `get_user_saved_posts()` from `backend/graphql-gateway/src/rest_api/content.rs`
- [ ] Remove route registrations from `main.rs`
- [ ] Update API documentation

---

## 🗄️ Database Tables Status

### Tables to Remove (nova_content database)

| Table | Status | Last Updated | Safe to Remove |
|-------|--------|--------------|----------------|
| `likes` | ❌ Unused | Never (writes go to social-service) | ✅ Yes, after iOS testing |
| `bookmarks` | ❌ Unused | Never (writes go to social-service) | ✅ Yes, after iOS testing |
| `shares` | ⚠️ Check | Unknown | ⚠️ Verify first |

### Tables to Keep (nova_social database)

| Table | Status | Purpose |
|-------|--------|---------|
| `likes` | ✅ Active | Single source of truth for likes |
| `saved_posts` | ✅ Active | Single source of truth for bookmarks |
| `shares` | ✅ Active | Single source of truth for shares |
| `comments` | ✅ Active | Single source of truth for comments |
| `comment_likes` | ✅ Active | Single source of truth for comment likes |

---

## 📊 Verification Queries

### Check if tables are still being used

```sql
-- Check nova_content.likes usage (should be 0 new rows)
SELECT COUNT(*), MAX(created_at) FROM nova_content.likes;

-- Check nova_content.bookmarks usage (should be 0 new rows)
SELECT COUNT(*), MAX(created_at) FROM nova_content.bookmarks;

-- Compare with social-service tables (should have recent data)
SELECT COUNT(*), MAX(created_at) FROM nova_social.likes;
SELECT COUNT(*), MAX(created_at) FROM nova_social.saved_posts;
```

### Check for stale data

```sql
-- Find likes in content-service that don't exist in social-service
SELECT c.post_id, c.user_id, c.created_at
FROM nova_content.likes c
LEFT JOIN nova_social.likes s ON c.post_id = s.post_id AND c.user_id = s.user_id
WHERE s.post_id IS NULL
LIMIT 10;

-- Find bookmarks in content-service that don't exist in social-service
SELECT c.post_id, c.user_id, c.created_at
FROM nova_content.bookmarks c
LEFT JOIN nova_social.saved_posts s ON c.post_id = s.post_id AND c.user_id = s.user_id
WHERE s.post_id IS NULL
LIMIT 10;
```

---

## 🚨 Rollback Plan

If issues are discovered after migration:

### Immediate Rollback (< 24 hours)
1. Run rollback migration to recreate tables
2. Restore data from backup
3. Revert iOS app to previous version (if needed)
4. Revert backend code changes

### Data Recovery (> 24 hours)
1. Restore from most recent backup
2. Sync missing data from social-service to content-service
3. Investigate root cause before retrying

---

## 📈 Success Metrics

- ✅ iOS Liked tab shows recently liked posts immediately
- ✅ iOS Saved tab shows recently saved posts immediately
- ✅ No increase in error rates
- ✅ No user complaints about missing likes/bookmarks
- ✅ Deprecated endpoints receive < 1% of traffic
- ✅ Database size reduced after table removal

---

## 📞 Contacts

- **Backend Lead**: [Name]
- **iOS Lead**: [Name]
- **Database Admin**: [Name]
- **On-Call**: Check PagerDuty

---

## 📚 Related Documentation

- `IMPLEMENTATION_SUMMARY.md` - Complete overview of changes, timeline, and team responsibilities
- `IOS_TESTING_GUIDE.md` - Comprehensive iOS testing guide for social data consolidation
- `QUICK_TEST_CHECKLIST.md` - 5-minute smoke test checklist
- `BOOKMARK_API_MIGRATION.md` - Bookmark API migration plan
- `BOOKMARK_API_TEST_RESULTS.md` - Staging test results
- Backend migrations: `backend/content-service/migrations/`
- iOS changes: `ios/NovaSocial/Features/Profile/Views/`

---

**Last Updated**: 2026-01-09
**Next Review**: After iOS testing completion
