# Nova API Changelog

All notable changes to the Nova API will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added
- None

### Changed
- None

### Deprecated
- None

### Removed
- None

### Fixed
- None

### Security
- None

---

## [2.0.0] - 2026-01-08

### Added

#### Social Service - Comment Likes (Instagram/Xiaohongshu Style)
- `POST /api/v2/social/comment/like` - Like a comment
- `DELETE /api/v2/social/comment/unlike/{comment_id}` - Unlike a comment
- `GET /api/v2/social/comment/likes/{comment_id}` - Get comment like count
- `GET /api/v2/social/comment/check-liked/{comment_id}` - Check if user liked comment

**Request Format:**
```json
{
  "user_id": "uuid",
  "comment_id": "comment_uuid"
}
```

**Response Format:**
```json
{
  "success": true,
  "like_count": 42
}
```

**Commits:**
- `dfc25434` - feat(ios): integrate comment like API with IG/XHS-style UI
- `20827620` - feat(backend): add comment like API endpoints

#### Matrix Integration - Profile Sync (Client-Side)
- Automatic profile synchronization from Nova to Matrix
- Syncs display name and avatar on login and profile updates
- Background sync with retry logic (up to 3 attempts)

**Sync Triggers:**
- After successful login/registration
- When user updates profile
- After Matrix bridge initialization

**Commits:**
- `6425aa88` - feat(ios): sync profile to Matrix when user updates profile
- `5c0c6693` - feat(ios): add Matrix profile sync for avatar and display name
- `fcc02c7a` - feat(ios): auto-sync profile to Matrix after bridge initialization
- `9ee75872` - feat(ios): add retry logic to Matrix profile sync

---

## [1.9.0] - 2025-12-16

### Added
- OAuth authentication endpoints for Google and Apple
- Passkey authentication support for iOS
- Phone number authentication with SMS OTP (AWS SNS)

### Changed
- Updated API documentation structure
- Improved error response format consistency

---

## [1.8.0] - 2025-11-30

### Added
- Real-time chat service with WebSocket support
- End-to-End Encryption (E2EE) for messages
- Voice and video call signaling endpoints
- Location sharing API

### Changed
- Migrated to gRPC for inter-service communication
- Updated GraphQL schema for better performance

---

## API Versioning Policy

### Version Format
- API versions follow semantic versioning: `MAJOR.MINOR.PATCH`
- Major version changes indicate breaking changes
- Minor version changes add new features (backward compatible)
- Patch version changes are bug fixes

### Deprecation Policy
- Deprecated endpoints will be marked in documentation
- Deprecated endpoints will be supported for at least 6 months
- Breaking changes will only occur in major version updates
- Clients will receive warnings when using deprecated endpoints

### Base URLs
- **Production**: `https://api.nova.social`
- **Staging**: Check deployment documentation for current ELB

### API Version Headers
All requests should include:
```
Accept: application/json
API-Version: 2.0
```

---

## Contributing to This Changelog

When adding new API endpoints or making changes:

1. **Add entries** under the `[Unreleased]` section
2. **Categorize** changes under appropriate headers (Added, Changed, Deprecated, etc.)
3. **Include** request/response examples for new endpoints
4. **Reference** relevant commit hashes
5. **Update** the date when releasing a new version

### Example Entry

```markdown
### Added

#### Service Name - Feature Name
- `POST /api/v2/example/endpoint` - Brief description
- Request format and example
- Response format and example
- Relevant commit hashes
```

---

## Questions or Issues?

- **API Documentation**: See [API_REFERENCE.md](./API_REFERENCE.md)
- **Issues**: Report at [GitHub Issues](https://github.com/proerror77/Nova/issues)
- **Support**: Contact development team

---

**Last Updated**: 2026-01-08
**Maintained By**: Nova Development Team
