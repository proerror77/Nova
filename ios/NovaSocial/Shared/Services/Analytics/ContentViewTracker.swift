import SwiftUI
import Combine
import AVFoundation

// MARK: - Content View Tracker
/// SwiftUI view modifier for automatic watch time tracking
/// Attach to any content view to automatically track visibility and engagement

struct ContentViewTracker: ViewModifier {
    let contentId: String
    let contentDuration: Int
    let contentTags: [String]

    @State private var isVisible = false
    @State private var visibilityThreshold: CGFloat = 0.5

    private let watchTimeService = WatchTimeService.shared

    func body(content: Content) -> some View {
        content
            .onAppear {
                startTracking()
            }
            .onDisappear {
                stopTracking()
            }
    }

    private func startTracking() {
        guard !isVisible else { return }
        isVisible = true
        watchTimeService.startWatching(
            contentId: contentId,
            contentDuration: contentDuration,
            contentTags: contentTags
        )
    }

    private func stopTracking() {
        guard isVisible else { return }
        isVisible = false
        watchTimeService.endWatching(contentId: contentId)
    }
}

// MARK: - View Extension

extension View {
    /// Track watch time for this content view
    /// - Parameters:
    ///   - contentId: Unique content identifier
    ///   - contentDuration: Duration in milliseconds (for videos)
    ///   - contentTags: Tags for interest tracking
    func trackWatchTime(
        contentId: String,
        contentDuration: Int = 0,
        contentTags: [String] = []
    ) -> some View {
        modifier(ContentViewTracker(
            contentId: contentId,
            contentDuration: contentDuration,
            contentTags: contentTags
        ))
    }
}

// MARK: - Video Player Tracker

/// Observable object for video player watch time tracking
/// Use with AVPlayer to track precise watch time and completion
class VideoWatchTracker: ObservableObject {
    private let watchTimeService = WatchTimeService.shared
    private var timeObserver: Any?
    private var player: AVPlayer?
    private var contentId: String = ""
    private var contentDuration: Int = 0
    private var contentTags: [String] = []
    private var lastReportedPosition: Int = 0

    /// Start tracking a video
    func startTracking(
        player: AVPlayer,
        contentId: String,
        contentDuration: Int,
        contentTags: [String] = []
    ) {
        self.player = player
        self.contentId = contentId
        self.contentDuration = contentDuration
        self.contentTags = contentTags
        self.lastReportedPosition = 0

        // Start watch time service tracking
        watchTimeService.startWatching(
            contentId: contentId,
            contentDuration: contentDuration,
            contentTags: contentTags
        )

        // Add time observer for progress updates
        let interval = CMTime(seconds: 1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let positionMs = Int(time.seconds * 1000)

            // Report position every 5 seconds
            if positionMs - self.lastReportedPosition >= 5000 {
                self.watchTimeService.updateProgress(
                    contentId: self.contentId,
                    currentPosition: positionMs
                )
                self.lastReportedPosition = positionMs
            }
        }

        print("[VideoTracker] Started tracking: \(contentId)")
    }

    /// Stop tracking current video
    func stopTracking() {
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
        }
        timeObserver = nil

        watchTimeService.endWatching(contentId: contentId)

        print("[VideoTracker] Stopped tracking: \(contentId)")
    }

    /// Track completion when video finishes
    func onVideoComplete() {
        // Video completed - this is a strong positive signal
        watchTimeService.updateProgress(
            contentId: contentId,
            currentPosition: contentDuration
        )
        print("[VideoTracker] Video completed: \(contentId)")
    }

    /// Track replay event
    func onReplay() {
        // End current tracking and start new one with replay flag
        stopTracking()

        // Start new tracking session
        if player != nil {
            watchTimeService.startWatching(
                contentId: contentId,
                contentDuration: contentDuration,
                contentTags: contentTags
            )
        }

        print("[VideoTracker] Replay started: \(contentId)")
    }

    deinit {
        stopTracking()
    }
}

// MARK: - Scroll Behavior Tracker

/// Tracks scroll behavior for recommendation signals
class ScrollBehaviorTracker: ObservableObject {
    private let watchTimeService = WatchTimeService.shared

    private var lastScrollTime: Date?
    private var scrollStartPosition: CGFloat = 0
    private var contentViewTimes: [String: Date] = [:]

    /// Record scroll start
    func scrollStarted(at position: CGFloat) {
        scrollStartPosition = position
        lastScrollTime = Date()
    }

    /// Record scroll end and calculate behavior
    func scrollEnded(at position: CGFloat) {
        guard let startTime = lastScrollTime else { return }

        let duration = Date().timeIntervalSince(startTime)
        let distance = abs(position - scrollStartPosition)

        // Calculate scroll speed (pixels per second)
        let scrollSpeed = duration > 0 ? distance / duration : 0

        // Fast scroll = user is browsing
        // Slow scroll = user is engaged
        // This data can be used for recommendation tuning

        print("[ScrollTracker] Scroll ended: speed=\(scrollSpeed) px/s, distance=\(distance)")
    }

    /// Record content visibility change
    func contentBecameVisible(_ contentId: String) {
        contentViewTimes[contentId] = Date()
    }

    /// Record content no longer visible
    func contentBecameInvisible(_ contentId: String) {
        guard let viewStart = contentViewTimes[contentId] else { return }

        let viewDuration = Date().timeIntervalSince(viewStart)
        contentViewTimes.removeValue(forKey: contentId)

        // If viewed less than 1 second, consider it a scroll-away
        if viewDuration < 1.0 {
            watchTimeService.recordNegativeSignal(
                contentId: contentId,
                reason: .scrollAway
            )
        }
    }
}

// MARK: - Session Interest Tracker

/// Tracks session-level interests for real-time personalization
class SessionInterestTracker: ObservableObject {
    @Published private(set) var currentInterests: [String: Float] = [:]

    private let maxInterests = 20
    private let decayFactor: Float = 0.9

    /// Update interest based on engagement
    func updateInterest(tags: [String], weight: Float) {
        for tag in tags {
            let currentWeight = currentInterests[tag] ?? 0
            currentInterests[tag] = currentWeight + weight
        }

        // Keep only top interests
        trimInterests()

        print("[SessionInterest] Updated interests: \(currentInterests.count) tags")
    }

    /// Apply time decay to all interests
    func applyDecay() {
        for (tag, weight) in currentInterests {
            let decayedWeight = weight * decayFactor
            if decayedWeight < 0.1 {
                currentInterests.removeValue(forKey: tag)
            } else {
                currentInterests[tag] = decayedWeight
            }
        }
    }

    /// Get current top interests
    func getTopInterests(limit: Int = 10) -> [(String, Float)] {
        currentInterests
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { ($0.key, $0.value) }
    }

    /// Reset session interests
    func reset() {
        currentInterests = [:]
    }

    private func trimInterests() {
        if currentInterests.count > maxInterests {
            let sorted = currentInterests.sorted { $0.value > $1.value }
            currentInterests = Dictionary(uniqueKeysWithValues: Array(sorted.prefix(maxInterests)))
        }
    }
}
