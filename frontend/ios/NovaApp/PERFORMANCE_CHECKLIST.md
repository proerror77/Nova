# Nova iOS - Performance Checklist

## P50 Latency Targets

### Critical Screens
| Screen | Target | Measurement Point |
|--------|--------|-------------------|
| Feed initial load | < 500ms | First post visible |
| Post detail | < 300ms | Image + caption rendered |
| Search results | < 400ms | First result visible |
| Profile load | < 350ms | Avatar + bio visible |
| Comment thread | < 250ms | First comment visible |

### Upload Targets
| File Size | Target | Notes |
|-----------|--------|-------|
| 1MB image | < 1.5s | After compression |
| 2MB image | < 2.5s | After compression |
| 5MB image | < 5s | Max allowed size |

## Skeleton Loader Timing
- **Show skeleton if:** Load takes > 200ms
- **Min display time:** 300ms (avoid flicker)
- **Max display time:** 3s (then show error)

## Image Optimization

### Compression
- **Max file size:** 2MB (before upload)
- **Quality:** 85% JPEG
- **Resize:** Max 2048x2048px
- **Format:** JPEG (not HEIC for web compatibility)

### Caching
- **Local cache:** 100MB max
- **Cache expiry:** 7 days
- **Eviction policy:** LRU (Least Recently Used)

### Lazy Loading
- **Feed images:** Load when within 1 screen height
- **Profile grids:** Load in batches of 12

## Network Optimization

### Retry Strategy
- **Max retries:** 3
- **Backoff:** Exponential (0.5s, 1s, 2s)
- **Retry on:** 429, 5xx errors
- **Don't retry:** 4xx errors (except 401)

### Request Batching
- **Analytics events:** Batch 50 events or 30s interval
- **Feed pagination:** Fetch 20 posts per page
- **Comments:** Fetch 20 comments per page

### Connection Pooling
- **Max concurrent requests:** 6
- **Connection timeout:** 30s
- **Resource timeout:** 300s (5 min for uploads)

## Memory Management

### View Lifecycle
- **Deinit check:** All ViewModels must deinit when view disappears
- **Retained cycles:** Avoid strong reference cycles in closures
- **Image memory:** Release cached images when memory warning

### Cache Limits
- **Feed cache:** Max 100 posts in memory
- **Image cache:** Max 100MB on disk
- **Event buffer:** Max 500 events before forced flush

## Battery Optimization

### Location Services
- **Usage:** None (MVP does not use location)
- **Future:** Use `.whenInUse` permission only

### Background Tasks
- **Upload queue:** Process only when app is foreground
- **Analytics:** Flush on background, pause tracking

### Network Efficiency
- **Poll interval:** Use WebSocket instead (future)
- **Background refresh:** Disabled for MVP

## UI Performance

### ScrollView Optimization
- **Use LazyVStack:** Not VStack for long lists
- **Limit grid items:** Max 3 columns in profile grid
- **Prefetch:** Load next page when 80% scrolled

### Animation
- **Frame rate:** 60fps for all animations
- **Duration:** < 300ms for most transitions
- **Complexity:** Avoid complex animations during scroll

### Layout
- **View hierarchy depth:** Max 10 levels
- **Conditional rendering:** Use `if` not opacity for hiding views
- **GeometryReader:** Use sparingly (causes layout recalculation)

## Profiling Tools

### Xcode Instruments
- **Time Profiler:** Identify slow functions
- **Allocations:** Track memory usage
- **Leaks:** Detect memory leaks
- **Network:** Monitor API calls

### Performance Tests
```swift
func testFeedLoadPerformance() {
    measure {
        // Load feed and wait for first post
    }
}
```

## Monitoring Metrics

### App Launch
- **Cold start:** < 2s (from tap to first screen)
- **Warm start:** < 1s

### Crashes
- **Crash-free rate:** > 99.5%
- **ANR rate:** < 0.1%

### Network Success Rate
- **Feed load:** > 99%
- **Upload success:** > 95%

## Optimization Checklist

### Before Release
- [ ] Run Time Profiler on critical flows
- [ ] Check for memory leaks with Instruments
- [ ] Verify image compression working
- [ ] Test on slow network (Edge/3G)
- [ ] Test on low-end devices (iPhone SE)
- [ ] Measure app size (< 50MB)
- [ ] Check battery usage (< 5%/hour active use)

### Continuous Monitoring
- [ ] Track P50 latency in production
- [ ] Monitor crash reports daily
- [ ] Review analytics event volume
- [ ] Check API error rates

## Known Performance Issues

### Feed Scroll Lag (Fixed)
- **Issue:** Lag when scrolling fast
- **Solution:** Switched from VStack to LazyVStack
- **Commit:** `abc123`

### Image Memory Spike (Monitoring)
- **Issue:** Memory spikes when viewing large images
- **Mitigation:** Resize images before display
- **Status:** Monitoring in beta

## Future Optimizations

### Phase 2
- [ ] Implement CDN for images
- [ ] Add progressive image loading (blur-up)
- [ ] Use WebP format (50% smaller than JPEG)
- [ ] Implement predictive prefetch

### Phase 3
- [ ] Add local database (SQLite/CoreData)
- [ ] Implement full offline mode
- [ ] Use background app refresh
- [ ] Add push notifications
