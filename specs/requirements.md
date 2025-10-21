# Social Platform Core - Requirements Document

**Feature Branch**: `feat/social-platform-core`
**Created**: 2025-10-21
**Last Updated**: 2025-10-21 (Code Audit Complete)
**Status**: Requirements Phase → Implementation Phase (72% complete)
**Scope**: Phases 2-3 - Social graph, content integration, real-time interactions, and discovery

---

## 🔍 Audit Update

✅ **Code Audit Complete** (See CODE_IMPLEMENTATION_AUDIT.md)
- **67.8 / 94 hours** of Phase 2-3 foundation already implemented
- **Key Finding**: Database schemas exist but REST API endpoints missing
- **Action Items**:
  1. Create REST endpoints for social graph (4h - URGENT)
  2. Add integration tests (8h)
  3. Eliminate code redundancy (56h)

---

## Overview

Nova is an Instagram-like social media platform. This specification defines the **core social infrastructure** required to make multi-content forms (Posts, Reels, Stories, Live, DM) work together as a cohesive social experience, not as isolated features.

**Key Principle**: Everything is driven by **user relationships** and **real-time interactions**. Features succeed because they connect people, not because they have advanced technology.

---

## Core Features

### 1. **Social Graph** (Relationships)
- Relationship model: Follow/Followers with proper indexing
- Privacy controls: Block, Mute, custom visibility settings
- Recommendation foundation: Suggest follows based on mutual connections
- Integrity: No self-follows, cascade deletes, temporal tracking

### 2. **Unified Content Model**
All content forms (Posts, Reels, Stories, Live, DM) support:
- Multi-type content in a single feed (not separate feeds)
- Common interactions: Like, Comment, Share, Save (where applicable)
- Consistent metadata: Creator, timestamp, engagement counts
- Lifecycle management: Creation → Visibility → Archival/Deletion

### 3. **Real-Time Interactions** (WebSocket Layer)
- Event broadcasting: Any social action → instant push to relevant users
- Channels: Per-stream (live), per-user (notifications), global (trending)
- Reliable delivery: Reconnection logic, heartbeat monitoring
- Distributed: Support for multi-server deployments (Redis Pub/Sub)

### 4. **Feed & Discovery**
- **For You Feed**: Personalized ranking (Posts + Reels + Stories + Lives mixed)
- **Following Feed**: Chronological + engagement-weighted from people you follow
- **Discovery Page**: Trending, categories, search across users/content/tags
- **Real-time trending**: What's being watched/liked/shared right now

### 5. **Creator Monetization**
- Gift/tip during live streams (real-time transactions)
- Fan subscriptions (recurring revenue, exclusive content access)
- Analytics dashboard: Viewers, engagement, revenue metrics
- Income distribution: Creator gets share, platform takes fee

### 6. **Content Safety & Moderation**
- User reporting: Content/user reports with triage
- Automated filtering: Spam, harmful content, policy violations
- Appeal process: Users can appeal moderation decisions
- Privacy compliance: GDPR deletion, data export, account recovery

---

## User Stories

### P1: Core Social Experience (Must Have)

**Story 1: User Builds Their Network**
- As a creator, I want to follow accounts I'm interested in, so that I see their content in my feed
- As a viewer, I want to be notified when someone I follow goes live, so that I can join in real-time
- As a user, I want to block accounts, so that I don't see their content

**Story 2: User Discovers Content**
- As a user, I want to see a personalized "For You" feed with Posts, Reels, and Lives mixed together, so that I discover new content I enjoy
- As a user, I want to search for users and hashtags, so that I can find specific creators and topics
- As a user, I want to see what's trending right now, so that I know what my peers are watching

**Story 3: User Engages with Content**
- As a user, I want to like, comment, and share posts from people I follow, so that I can express my opinions and support creators
- As a viewer, I want to send comments and tips during a live stream, so that I can interact with the broadcaster in real-time
- As a user, I want to save posts for later, so that I can revisit content I found valuable

**Story 4: Content Creators Monetize**
- As a creator, I want to receive tips/gifts during live streams, so that I can earn revenue from my audience
- As a creator, I want to see analytics (viewer count, watch time, engagement), so that I can understand my audience and improve my content
- As a creator, I want subscribers to pay monthly for exclusive content, so that I can build a sustainable income

### P2: Advanced Social Features (Nice to Have)

**Story 5: User Customizes Their Experience**
- As a user, I want to mute specific accounts while not unfollowing, so that I can reduce noise without offending creators
- As a user, I want to control who can see my profile/content (public/private), so that I can protect my privacy
- As a user, I want to customize notification preferences, so that I'm not overwhelmed by alerts

**Story 6: Content Creators Build Influence**
- As a creator, I want recommendations for who to follow next, so that I can grow my network strategically
- As a creator, I want to see which content formats perform best, so that I can focus my efforts
- As a creator, I want to share my content across multiple platforms, so that I can maximize reach

---

## Acceptance Criteria

### Social Graph
- [ ] Follow/unfollow functionality works bidirectionally with proper state
- [ ] All social relationships are indexed for fast queries (follower count, following list)
- [ ] Block relationships prevent interactions (no comments, tips, follows back)
- [ ] Mute relationships hide content but allow relationships to exist
- [ ] All relationship changes trigger real-time updates via WebSocket

### Unified Feed
- [ ] Posts, Reels, Stories, and Lives appear in a single feed for "For You"
- [ ] Feed ranking balances multiple signals: recency, engagement, creator relationship, content quality
- [ ] Pagination works smoothly with cursor-based navigation
- [ ] Feed can handle 1000+ items efficiently (load time <2s)
- [ ] Blocked/muted content never appears in feed

### Real-Time Layer
- [ ] WebSocket connections remain stable for 24+ hours
- [ ] Message delivery to 10,000 concurrent viewers completes within 500ms
- [ ] Reconnection after network failure is transparent to user
- [ ] Event broadcasting to specific audience (followers only, etc.) works reliably

### Interactions
- [ ] Like/unlike updates count in real-time and persists
- [ ] Comments appear within 1-2 seconds for all viewers
- [ ] Shares are tracked and visible in engagement metrics
- [ ] Save/bookmark functionality works for all content types

### Discovery
- [ ] Search returns relevant users within 1 second
- [ ] Trending content reflects last 1-24 hours activity
- [ ] Trending updates in real-time as engagement changes
- [ ] Discovery page categories are populated and discoverable

### Creator Monetization
- [ ] Tips/gifts are processed and recorded in real-time
- [ ] Creator analytics show accurate viewer/engagement/revenue numbers
- [ ] Revenue payouts are calculated correctly and scheduled monthly
- [ ] Creators can see breakdown by content type (Lives vs Posts)

### Safety & Moderation
- [ ] Users can report content with reason and evidence
- [ ] Reported content gets triaged (investigate within 24h)
- [ ] Blocked/flagged content is removed from feed immediately
- [ ] Users can appeal moderation decisions

---

## Non-Functional Requirements

### Performance
- Feed load: < 2 seconds for first page (20 items)
- API response: < 200ms p95 for all endpoints
- Real-time event delivery: < 500ms for broadcast to 10k viewers
- Search results: < 1 second for any query
- Concurrent users: 100k+ without degradation

### Scalability
- Horizontal scaling: Each service can scale independently
- Database: Support 10M+ users, 1B+ posts
- Real-time: 100k+ WebSocket connections per server
- Feed ranking: Compute results for 10M users daily
- Storage: Media processing for 1000+ hours video/day

### Security & Privacy
- All communications: HTTPS/TLS 1.3+
- Authentication: JWT with 1-hour access tokens, 30-day refresh
- Encryption: DM messages E2E encrypted (Phase 5)
- Rate limiting: 100 requests/min per user, 1000/min per IP
- Data privacy: GDPR compliance (deletion, export, consent)
- Content moderation: Automated scanning + human review

### Availability
- Uptime SLA: 99.9% (43 minutes downtime/month)
- Recovery time: 5 minutes from failure detection to restoration
- Database replication: Multi-region replication for disaster recovery
- CDN: Global edge caching for media (CloudFront)

### Reliability
- Data integrity: No loss of user interactions
- Consistency model: Eventual consistency for feed, strong for user data
- Backup strategy: Daily backups with 30-day retention
- Monitoring: Real-time alerts for errors >0.1% error rate

### User Experience
- Mobile-first: All UX designed for iOS first (Phase 1: iOS)
- Accessibility: WCAG 2.1 AA compliance
- Dark mode: Supported from day one
- Internationalization: Support for 10+ languages (Phase 4)
- Offline support: Cache recent feed for offline browsing

---

## Key Entities

### User
- Basic profile: Name, username, bio, avatar, follower/following counts
- Account status: Active, suspended, deleted (soft-delete for GDPR)
- Preferences: Privacy settings, notification preferences, content filters

### Relationship (Follow/Block/Mute)
- Follow: Establishes social connection for feed visibility
- Block: Prevents all interactions, hiding content in both directions
- Mute: Silences notifications and feed, but relationship exists

### Content (Base Type)
- ContentType: Post | Reel | Story | Live | DM
- Creator: User who created the content
- Visibility: Public | FollowersOnly | Private
- Lifecycle: Drafted → Published → Archived/Deleted

### Post (Content subtype)
- Caption: Text describing the image
- Media: One or more images with processing status
- Engagement: Likes, comments, shares (counts + list)
- Metadata: Created date, edit history, view count

### Reel (Content subtype)
- Video: Single video file with transcoding status
- Captions/Text: Overlay text and hashtags
- Engagement: Likes, comments, shares, saves
- Analytics: Play count, watch time, completion rate

### Story (Content subtype)
- Media: Photo or video (expires after 24 hours)
- Viewers: List of who viewed (with timestamp)
- Responses: Direct messages in reply to story
- Analytics: View count, reply count

### Live (Content subtype)
- Stream: RTMP connection details, status (starting/live/ended)
- Viewers: Real-time viewer count, join timestamp
- Chat: Real-time comments/tips during stream
- Recording: Auto-saved for replay (converts to Reel)
- Analytics: Peak viewers, average watch time, total tips

### Interaction
- Type: Like | Comment | Share | Save | Tip
- Target: Can apply to any content type
- Creator/Recipient: User who performed and who receives credit
- Timestamp: When action occurred

### Notification
- Event: Follow, Like, Comment, Mention, Live_StartedByFollower, Tip
- Actor: User who triggered the notification
- Target: User receiving the notification
- Read status: Timestamp of when read (or null if unread)

### LiveSession (for analytics)
- StreamId: Unique identifier for the broadcast
- Creator: User broadcasting
- StartTime/EndTime: When stream began and ended
- Viewers: Peak count, total unique, list with join times
- Tips: Total revenue, list of tips with amounts
- Comments: Total count, sample comments

---

## Assumptions

1. **Social Model**: Nova follows the Instagram model (public by default, but with privacy controls). Users are primarily public figures or willing to be semi-public.

2. **Content Processing**: Image and video transcoding is handled by external services (S3 + FFmpeg + CloudFront). Spec assumes these are available.

3. **Real-Time Scale**: For MVP, <100k concurrent users. Beyond that, Redis Pub/Sub is required for distributed WebSocket.

4. **Monetization**: Payments are processed via Stripe/PayPal (details in Phase 3-4). MVP focuses on architecture, not payment integration.

5. **Moderation**: Content moderation starts with user reporting and manual review (Phase 2-3). Automated ML-based filtering comes in Phase 5+.

6. **Authentication**: OAuth2 + JWT is handled in Phase 1 (authentication service exists). This spec assumes users are authenticated.

7. **Analytics**: ClickHouse is the source of truth for analytics queries. PostgreSQL is for operational data.

8. **Database**: PostgreSQL for relational data, ClickHouse for analytics, Redis for real-time caching.

---

## Out of Scope (For Future Phases)

- Automated content moderation (ML-based filtering) - Phase 5+
- Video editing tools on client - Phase 4+
- Advanced creator tools (scheduling, drafts, analytics export) - Phase 3+
- Ads/sponsorships - Phase 4+
- Live gifting with custom animations - Phase 3+
- Stories with advanced effects - Phase 3+
- Full-text search - Phase 4+
- Trending algorithm machine learning - Phase 5+
