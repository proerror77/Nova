# Bookmark API Migration Checklist

## 📋 Overview

This document tracks the migration from the old bookmark API endpoints to the new save/saved-posts endpoints.

**Migration Date**: 2026-01-08
**Deprecation Sunset**: 2026-04-01 (3 months)

---

## 🎯 New API Endpoints

### Write Operations (Actions)
- ✅ `POST /api/v2/social/save` - Save a post
- ✅ `DELETE /api/v2/social/save/{post_id}` - Unsave a post

### Read Operations (Resources)
- ✅ `GET /api/v2/social/saved-posts` - Get saved posts list
- ✅ `GET /api/v2/social/saved-posts/{post_id}/check` - Check if post is saved
- ✅ `POST /api/v2/social/saved-posts/batch-check` - Batch check saved status

---

## ✅ Completed Tasks

### Backend
- [x] Update proto definitions (`backend/proto/services_v2/social_service.proto`)
- [x] Update REST API routes (`backend/graphql-gateway/src/rest_api/social_likes.rs`)
- [x] Add backward-compatible deprecated routes (`backend/graphql-gateway/src/rest_api/deprecated_bookmarks.rs`)
- [x] Add deprecation headers (`Deprecation`, `Sunset`, `Link`)
- [x] Add warning logs for deprecated endpoint usage
- [x] Register deprecated routes in `main.rs`

### iOS Client
- [x] Update API configuration (`ios/NovaSocial/Shared/Services/Networking/APIConfig.swift`)

### Git
- [x] Create comprehensive commit with migration details
- [x] Fix compilation errors (HttpMessage import)

---

## 📝 Deployment Checklist

### Pre-Deployment

- [ ] **Code Review**
  - [ ] Review proto changes
  - [ ] Review REST API route changes
  - [ ] Review deprecated endpoint implementation
  - [ ] Review iOS client changes

- [ ] **Testing (Staging)**
  - [ ] Test new endpoints work correctly
    - [ ] POST /api/v2/social/save
    - [ ] DELETE /api/v2/social/save/{id}
    - [ ] GET /api/v2/social/saved-posts
    - [ ] GET /api/v2/social/saved-posts/{id}/check
    - [ ] POST /api/v2/social/saved-posts/batch-check
  - [ ] Test deprecated endpoints still work
    - [ ] POST /api/v2/social/bookmark
    - [ ] DELETE /api/v2/social/bookmark/{id}
    - [ ] GET /api/v2/social/bookmarks
    - [ ] GET /api/v2/social/check-bookmarked/{id}
    - [ ] POST /api/v2/social/bookmarks/batch-check
  - [ ] Verify deprecation headers are present
    - [ ] `Deprecation: true`
    - [ ] `Sunset: Tue, 1 Apr 2026 23:59:59 GMT`
    - [ ] `Link: </api/v2/social/save>; rel="alternate"`
  - [ ] Check logs show deprecation warnings
  - [ ] Test iOS app works with new endpoints
  - [ ] Test backward compatibility with old iOS app version

### Deployment

- [x] **Backend Deployment**
  - [x] Deploy to staging
    ```bash
    git push origin main
    # CI/CD will auto-deploy
    ```
    **Deployed**: 2026-01-08 20:19 GMT+8 (GitHub Actions run #20830034202)
  - [x] Monitor staging logs for errors
    **Result**: ✅ No errors found. Service healthy and responding.
  - [x] Verify both old and new endpoints work
    **Result**: ✅ Both endpoint sets responding correctly with JWT authentication
  - [ ] Deploy to production (after staging validation)

- [ ] **iOS Deployment**
  - [ ] Submit updated app to TestFlight
  - [ ] Test on TestFlight
  - [ ] Submit to App Store for review
  - [ ] Schedule release (coordinate with backend)

### Post-Deployment

- [ ] **Monitoring (Week 1)**
  - [ ] Monitor deprecation warning logs
  - [ ] Track usage of old vs new endpoints
  - [ ] Check for any errors in new endpoints
  - [ ] Monitor user reports/feedback

- [ ] **Communication**
  - [ ] Notify team about new endpoints
  - [ ] Update internal documentation
  - [ ] Add migration guide to API docs (if applicable)

---

## 📊 Deprecation Timeline

### Phase 1: Soft Launch (2026-01-08 → 2026-02-01)
- [x] Deploy backend with dual endpoint support
- [ ] Deploy iOS app update to TestFlight
- [ ] Monitor adoption and errors
- **Goal**: 50% of users on new app version

### Phase 2: Gradual Migration (2026-02-01 → 2026-03-01)
- [ ] Release iOS app to App Store
- [ ] Monitor old endpoint usage (should decrease)
- [ ] Send push notifications encouraging app update (if needed)
- **Goal**: 80% of users on new app version

### Phase 3: Final Push (2026-03-01 → 2026-04-01)
- [ ] Add more prominent deprecation warnings
- [ ] Consider showing in-app update prompt for old versions
- **Goal**: 95% of users on new app version

### Phase 4: Sunset (2026-04-01)
- [ ] Remove deprecated endpoints
  ```diff
  - .service(deprecated_bookmarks::create_bookmark_deprecated)
  - .service(deprecated_bookmarks::delete_bookmark_deprecated)
  - .service(deprecated_bookmarks::get_bookmarks_deprecated)
  - .service(deprecated_bookmarks::check_bookmarked_deprecated)
  - .service(deprecated_bookmarks::batch_check_bookmarked_deprecated)
  ```
- [ ] Delete `backend/graphql-gateway/src/rest_api/deprecated_bookmarks.rs`
- [ ] Remove from `mod.rs`
- [ ] Deploy to production
- [ ] Monitor for any stragglers using old endpoints

---

## 🔍 Verification Commands

### Check Backend Logs for Deprecation Warnings
```bash
# Staging
kubectl logs -l app=graphql-gateway -n nova-staging --tail=100 | grep DEPRECATED

# Production
kubectl logs -l app=graphql-gateway -n nova-prod --tail=100 | grep DEPRECATED
```

### Test New Endpoints (Replace with your staging URL)
```bash
STAGING_URL="https://api-staging.nova.social"
TOKEN="your_jwt_token"

# Save a post
curl -X POST "$STAGING_URL/api/v2/social/save" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"post_id": "test-post-id"}'

# Get saved posts
curl -X GET "$STAGING_URL/api/v2/social/saved-posts?limit=20" \
  -H "Authorization: Bearer $TOKEN"

# Check if saved
curl -X GET "$STAGING_URL/api/v2/social/saved-posts/test-post-id/check" \
  -H "Authorization: Bearer $TOKEN"

# Unsave
curl -X DELETE "$STAGING_URL/api/v2/social/save/test-post-id" \
  -H "Authorization: Bearer $TOKEN"
```

### Test Deprecated Endpoints (Should return deprecation headers)
```bash
# Should include: Deprecation: true, Sunset: ..., Link: ...
curl -X POST "$STAGING_URL/api/v2/social/bookmark" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"post_id": "test-post-id"}' \
  -i  # -i to show headers
```

---

## 📈 Metrics to Track

### Backend Metrics
- [ ] Request count: `/api/v2/social/save` vs `/api/v2/social/bookmark`
- [ ] Request count: `/api/v2/social/saved-posts` vs `/api/v2/social/bookmarks`
- [ ] Error rates on new endpoints
- [ ] Response times (should be identical)

### iOS Metrics
- [ ] App version distribution
- [ ] Bookmark feature usage
- [ ] Crash rates related to bookmark feature

---

## 🚨 Rollback Plan

If critical issues are discovered:

### Rollback Backend
```bash
# Option 1: Revert commit
git revert 4fc8d6fd
git push origin main

# Option 2: Temporarily disable new endpoints in main.rs
# Comment out new routes, keep only deprecated routes
```

### Rollback iOS
```bash
# Revert APIConfig.swift changes
git revert <commit-hash>
# Submit emergency build to App Store
```

---

## 📞 Emergency Contacts

- **Backend Lead**: [Name]
- **iOS Lead**: [Name]
- **DevOps**: [Name]
- **On-Call**: Check PagerDuty

---

## ✅ Sign-Off

### Backend Team
- [ ] Code reviewed and approved
- [ ] Tested on staging
- [ ] Ready for production

### iOS Team
- [ ] Code reviewed and approved
- [ ] Tested on TestFlight
- [ ] Ready for App Store submission

### DevOps
- [ ] CI/CD pipeline validated
- [ ] Monitoring dashboards set up
- [ ] Ready to deploy

---

## 📚 Additional Resources

- **API Documentation**: [Link to API docs]
- **Proto Definitions**: `backend/proto/services_v2/social_service.proto`
- **Commit**: `4fc8d6fd` - refactor(api): rename bookmark endpoints to save/saved-posts for clarity
- **Architecture Decision**: This migration addresses confusion between `/bookmark` (singular) and `/bookmarks` (plural) by using semantic naming: `/save` for actions, `/saved-posts` for resources

---

**Last Updated**: 2026-01-08
**Migration Manager**: [Your Name]
