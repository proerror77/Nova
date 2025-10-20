# Nova iOS - Deployment Checklist

## Pre-Deployment

### Code Review
- [ ] All code reviewed by at least one other developer
- [ ] No commented-out code
- [ ] No debug prints in production code
- [ ] No force unwraps (!) except in tests
- [ ] SwiftLint passes with 0 warnings

### Testing
- [ ] All unit tests pass (> 80% coverage)
- [ ] All integration tests pass
- [ ] E2E tests pass for critical journeys
- [ ] Performance tests meet targets (P50 < thresholds)
- [ ] Accessibility audit complete (VoiceOver, Dynamic Type)
- [ ] Tested on iPhone SE (smallest screen)
- [ ] Tested on iPhone 15 Pro Max (largest screen)
- [ ] Tested on slow network (Edge/3G)

### Configuration
- [ ] Production API endpoint configured
- [ ] ClickHouse production endpoint configured
- [ ] App Store Connect team configured
- [ ] Certificates and provisioning profiles valid
- [ ] App Group configured (if using)
- [ ] Push notification certificate (if using)

---

## TestFlight Release

### Build Preparation
- [ ] Increment build number (CFBundleVersion)
- [ ] Update version string (CFBundleShortVersionString)
- [ ] Set build configuration to "Release"
- [ ] Archive project (Product → Archive)
- [ ] Validate archive (no errors)

### Upload to App Store Connect
- [ ] Upload archive via Xcode Organizer
- [ ] Wait for processing (15-30 min)
- [ ] Check for "Missing Compliance" warning (export compliance)
- [ ] Submit beta information:
  - [ ] What to test
  - [ ] Known issues
  - [ ] Feedback instructions

### Beta Testing
- [ ] Add internal testers (team members)
- [ ] Add external testers (5-10 beta testers)
- [ ] Monitor crash reports daily
- [ ] Collect feedback via TestFlight
- [ ] Track analytics (P50 latency, crash-free rate)

### Beta Success Criteria
- [ ] Crash-free rate: > 99%
- [ ] P50 feed load: < 500ms
- [ ] P50 upload: < 2.5s (2MB image)
- [ ] No critical bugs reported
- [ ] Positive feedback from 80% of testers

---

## App Store Submission

### App Information
- [ ] App name: "Nova"
- [ ] Subtitle: "Share Your Moments" (max 30 chars)
- [ ] Primary category: Social Networking
- [ ] Secondary category: Photo & Video
- [ ] Content rating: 12+ (social media interactions)
- [ ] Privacy policy URL: https://nova.app/privacy
- [ ] Terms of service URL: https://nova.app/terms

### App Store Description
```
Nova is a modern social media app for sharing life's moments with friends and family.

FEATURES:
• Share photos with beautiful filters
• Connect with friends and discover new people
• Like and comment on posts
• Search for users
• Manage your profile

PRIVACY:
• Your data is secure
• No third-party ads
• Optional location sharing

Download Nova today and start sharing your story!
```

### Keywords (100 chars max)
```
photo,social,share,friends,moments,instagram,camera,filter,community
```

### Screenshots (Required Sizes)

#### iPhone 6.7" (iPhone 15 Pro Max)
- [ ] 1. Onboarding screen
- [ ] 2. Feed with posts
- [ ] 3. Post detail
- [ ] 4. Create/upload flow
- [ ] 5. Profile page

#### iPhone 6.5" (iPhone 14 Plus)
- [ ] Same 5 screenshots resized

#### iPhone 5.5" (iPhone 8 Plus)
- [ ] Same 5 screenshots resized

#### iPad Pro 12.9" (if supporting iPad)
- [ ] 5 iPad-optimized screenshots

### App Preview Video (Optional)
- [ ] 15-30 second video showing app in action
- [ ] No audio required
- [ ] Shows key features (feed, post, like, comment)

### App Icon
- [ ] 1024x1024 PNG (no transparency)
- [ ] Follows Apple design guidelines
- [ ] Distinct and recognizable

### Version Information
- [ ] Version: 1.0.0
- [ ] What's New: "Initial release"
- [ ] Copyright: 2025 Nova, Inc.
- [ ] Support URL: https://nova.app/support
- [ ] Marketing URL: https://nova.app

### Age Rating
Answer Apple's questionnaire:
- [ ] Unrestricted Web Access: No
- [ ] Gambling: No
- [ ] Contests: No
- [ ] Profanity or Crude Humor: Infrequent/Mild
- [ ] Mature/Suggestive Themes: Infrequent/Mild
- [ ] Violence: None
- [ ] Horror/Fear Themes: None
- [ ] Medical/Treatment Information: None
- [ ] Alcohol, Tobacco, or Drug Use: None

Result: **12+** (due to social media interactions)

### App Review Information
- [ ] First name: [Your name]
- [ ] Last name: [Your name]
- [ ] Phone: [Support phone]
- [ ] Email: support@nova.app
- [ ] Demo account (required):
  - Username: `reviewer@nova.app`
  - Password: `ReviewPass123!`
- [ ] Notes: "Full functionality available after sign in. Use demo account provided."

### Export Compliance
- [ ] Uses HTTPS encryption: Yes
- [ ] Uses standard encryption: Yes
- [ ] Qualifies for exemption: Yes (HTTPS only)

---

## Post-Submission

### App Review Process (2-7 days)
- [ ] Monitor App Store Connect for status
- [ ] Respond to App Review questions within 24h
- [ ] Fix any rejection issues immediately

### Common Rejection Reasons
1. **Missing demo account** → Provide in App Review Information
2. **Crash on launch** → Test on clean device
3. **Broken links** → Verify all URLs work
4. **Privacy policy missing** → Add to app and website
5. **Guideline 4.3 (Spam)** → Ensure app is unique

### If Approved
- [ ] Set release date (manual or automatic)
- [ ] Prepare launch announcement
- [ ] Monitor crash reports hourly for first 24h
- [ ] Check analytics dashboard
- [ ] Respond to user reviews

### If Rejected
- [ ] Read rejection reason carefully
- [ ] Fix issues
- [ ] Increment build number
- [ ] Re-submit with notes explaining fixes

---

## Production Monitoring

### First 24 Hours
- [ ] Check crash-free rate every hour
- [ ] Monitor P50 latency in analytics
- [ ] Watch for spike in API errors
- [ ] Track user sign-ups
- [ ] Respond to negative reviews immediately

### First Week
- [ ] Daily crash report review
- [ ] Track key metrics:
  - [ ] DAU (Daily Active Users)
  - [ ] Retention (D1, D7)
  - [ ] Crash-free rate (> 99%)
  - [ ] P50 feed load (< 500ms)
  - [ ] Upload success rate (> 95%)
- [ ] Collect user feedback
- [ ] Plan hotfix if needed

### Ongoing
- [ ] Weekly analytics review
- [ ] Monthly performance optimization
- [ ] Quarterly feature planning
- [ ] Bi-annual dependency updates

---

## Hotfix Process

### When to Hotfix
- Critical crash affecting > 1% of users
- Data loss or corruption
- Security vulnerability
- Backend API breaking change

### Hotfix Workflow
1. Create hotfix branch from `main`
2. Fix issue + add regression test
3. Increment build number (e.g., 1.0.0 → 1.0.1)
4. Submit expedited review (if critical)
5. Monitor closely after approval

---

## App Store Optimization (ASO)

### Keywords (Update Monthly)
- [ ] Track keyword rankings
- [ ] A/B test different keywords
- [ ] Monitor competitor keywords

### Screenshots (Update Quarterly)
- [ ] A/B test different layouts
- [ ] Highlight new features
- [ ] Update for seasonal campaigns

### Ratings & Reviews
- [ ] Prompt for reviews after positive interactions
- [ ] Respond to all negative reviews
- [ ] Target: > 4.5 stars average

---

## Compliance

### Privacy
- [ ] Privacy policy published
- [ ] Data collection disclosed in App Store
- [ ] GDPR compliance (for EU users)
- [ ] COPPA compliance (no users < 13)
- [ ] Apple's App Tracking Transparency (if using)

### Security
- [ ] HTTPS only (no HTTP)
- [ ] Certificate pinning (optional)
- [ ] Sensitive data in Keychain
- [ ] No hardcoded secrets
- [ ] Regular security audits

### Legal
- [ ] Terms of service published
- [ ] DMCA compliance (for user content)
- [ ] Content moderation policy
- [ ] User reporting mechanism

---

## Version History

| Version | Release Date | Notes |
|---------|--------------|-------|
| 1.0.0 | TBD | Initial release |
| 1.0.1 | TBD | Bug fixes |
| 1.1.0 | TBD | New features |

---

## Emergency Contacts

- **App Store Connect:** https://appstoreconnect.apple.com
- **Apple Developer Support:** https://developer.apple.com/support/
- **Backend Team:** backend@nova.app
- **On-Call Engineer:** [Phone/Slack]

---

## Success Metrics (Week 1)

- [ ] 1000+ downloads
- [ ] 4.0+ star rating
- [ ] 99%+ crash-free rate
- [ ] < 500ms P50 feed load
- [ ] 50%+ D1 retention

**If any metric fails:** Immediate investigation + hotfix if needed
