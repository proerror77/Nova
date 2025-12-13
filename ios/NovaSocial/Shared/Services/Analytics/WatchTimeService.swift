import Foundation
import Combine

// MARK: - Watch Time Service
/// TikTok-style watch time tracking for personalized recommendations
/// Tracks video completion rate, engagement signals, and scroll behavior
/// This is the most critical signal for the recommendation algorithm

class WatchTimeService: ObservableObject {
    static let shared = WatchTimeService()

    private let client = APIClient.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Configuration

    /// Batch size before auto-sending
    private let batchSize = 10

    /// Auto-send interval in seconds
    private let autoSendInterval: TimeInterval = 30

    /// Minimum watch duration to track (ms)
    private let minWatchDuration: Int = 500

    // MARK: - State

    /// Pending events to be sent
    @Published private(set) var pendingEvents: [WatchEvent] = []

    /// Current active watch session
    private var activeSession: WatchSession?

    /// Session ID for current app session
    private var sessionId: String = UUID().uuidString

    /// Auto-send timer
    private var autoSendTimer: Timer?

    // MARK: - Init

    private init() {
        setupAutoSend()
        setupAppLifecycleObservers()
    }

    // MARK: - Public API

    /// Start tracking watch time for a content item
    /// Call this when content becomes visible
    func startWatching(contentId: String, contentDuration: Int, contentTags: [String] = []) {
        // End any existing session
        if let existing = activeSession, existing.contentId != contentId {
            endWatching(contentId: existing.contentId)
        }

        // Start new session
        activeSession = WatchSession(
            contentId: contentId,
            contentDuration: contentDuration,
            contentTags: contentTags,
            startTime: Date()
        )

        print("[WatchTime] Started watching: \(contentId)")
    }

    /// Update watch progress
    /// Call this periodically or on seek
    func updateProgress(contentId: String, currentPosition: Int) {
        guard var session = activeSession, session.contentId == contentId else { return }
        session.currentPosition = currentPosition
        session.lastUpdateTime = Date()
        activeSession = session
    }

    /// End watch tracking for a content item
    /// Call this when content becomes invisible
    func endWatching(contentId: String) {
        guard let session = activeSession, session.contentId == contentId else { return }

        let watchDuration = Int(Date().timeIntervalSince(session.startTime) * 1000)

        // Only track if watched long enough
        if watchDuration >= minWatchDuration {
            let event = createWatchEvent(from: session, watchDuration: watchDuration)
            pendingEvents.append(event)

            print("[WatchTime] Ended watching: \(contentId), duration: \(watchDuration)ms, completion: \(event.completionRate)")

            // Auto-send if batch is full
            if pendingEvents.count >= batchSize {
                Task { await sendPendingEvents() }
            }
        }

        activeSession = nil
    }

    /// Record engagement action (like, comment, share, etc.)
    func recordEngagement(contentId: String, action: EngagementAction) {
        let event = EngagementEvent(
            contentId: contentId,
            action: action,
            timestamp: Date(),
            sessionId: sessionId
        )

        Task {
            await sendEngagementEvent(event)
        }

        print("[WatchTime] Engagement: \(action.rawValue) on \(contentId)")
    }

    /// Record negative signal (skip, not interested)
    func recordNegativeSignal(contentId: String, reason: NegativeSignalReason) {
        let event = NegativeSignalEvent(
            contentId: contentId,
            reason: reason,
            timestamp: Date(),
            sessionId: sessionId
        )

        Task {
            await sendNegativeSignalEvent(event)
        }

        print("[WatchTime] Negative signal: \(reason.rawValue) on \(contentId)")
    }

    /// Manually flush pending events
    func flush() {
        Task { await sendPendingEvents() }
    }

    /// Start a new session (call on app launch)
    func startSession() {
        sessionId = UUID().uuidString
        print("[WatchTime] New session started: \(sessionId)")
    }

    /// End current session (call on app background/terminate)
    func endSession() {
        // End any active watch
        if let session = activeSession {
            endWatching(contentId: session.contentId)
        }

        // Send all pending events
        Task { await sendPendingEvents() }

        print("[WatchTime] Session ended: \(sessionId)")
    }

    // MARK: - Private Methods

    private func createWatchEvent(from session: WatchSession, watchDuration: Int) -> WatchEvent {
        let completionRate = session.contentDuration > 0
            ? min(1.0, Float(watchDuration) / Float(session.contentDuration))
            : 0.0

        return WatchEvent(
            contentId: session.contentId,
            watchDuration: watchDuration,
            contentDuration: session.contentDuration,
            completionRate: completionRate,
            contentTags: session.contentTags,
            isReplay: session.isReplay,
            sessionId: sessionId,
            timestamp: Date()
        )
    }

    private func setupAutoSend() {
        autoSendTimer = Timer.scheduledTimer(withTimeInterval: autoSendInterval, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.sendPendingEvents()
            }
        }
    }

    private func setupAppLifecycleObservers() {
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.endSession()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.startSession()
            }
            .store(in: &cancellables)
    }

    // MARK: - API Calls

    private func sendPendingEvents() async {
        guard !pendingEvents.isEmpty else { return }

        let eventsToSend = pendingEvents
        pendingEvents = []

        do {
            let request = BatchWatchEventRequest(events: eventsToSend)
            try await client.post(
                endpoint: APIConfig.Analytics.recordWatchEvents,
                body: request
            )
            print("[WatchTime] Sent \(eventsToSend.count) watch events")
        } catch {
            // Re-add events on failure
            pendingEvents.insert(contentsOf: eventsToSend, at: 0)
            print("[WatchTime] Failed to send events: \(error)")
        }
    }

    private func sendEngagementEvent(_ event: EngagementEvent) async {
        do {
            try await client.post(
                endpoint: APIConfig.Analytics.recordEngagement,
                body: event
            )
        } catch {
            print("[WatchTime] Failed to send engagement: \(error)")
        }
    }

    private func sendNegativeSignalEvent(_ event: NegativeSignalEvent) async {
        do {
            try await client.post(
                endpoint: APIConfig.Analytics.recordNegativeSignal,
                body: event
            )
        } catch {
            print("[WatchTime] Failed to send negative signal: \(error)")
        }
    }
}

// MARK: - Models

/// Active watch session state
private struct WatchSession {
    let contentId: String
    let contentDuration: Int
    let contentTags: [String]
    let startTime: Date
    var currentPosition: Int = 0
    var lastUpdateTime: Date
    var isReplay: Bool = false

    init(contentId: String, contentDuration: Int, contentTags: [String], startTime: Date) {
        self.contentId = contentId
        self.contentDuration = contentDuration
        self.contentTags = contentTags
        self.startTime = startTime
        self.lastUpdateTime = startTime
    }
}

/// Watch event to be sent to backend
struct WatchEvent: Codable {
    let contentId: String
    let watchDuration: Int
    let contentDuration: Int
    let completionRate: Float
    let contentTags: [String]
    let isReplay: Bool
    let sessionId: String
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case contentId = "content_id"
        case watchDuration = "watch_duration_ms"
        case contentDuration = "content_duration_ms"
        case completionRate = "completion_rate"
        case contentTags = "content_tags"
        case isReplay = "is_replay"
        case sessionId = "session_id"
        case timestamp
    }
}

/// Batch request for watch events
struct BatchWatchEventRequest: Codable {
    let events: [WatchEvent]
}

/// Engagement actions
enum EngagementAction: String, Codable {
    case like
    case comment
    case share
    case save
    case follow
}

/// Engagement event
struct EngagementEvent: Codable {
    let contentId: String
    let action: EngagementAction
    let timestamp: Date
    let sessionId: String

    enum CodingKeys: String, CodingKey {
        case contentId = "content_id"
        case action
        case timestamp
        case sessionId = "session_id"
    }
}

/// Negative signal reasons
enum NegativeSignalReason: String, Codable {
    case skip = "skip"
    case notInterested = "not_interested"
    case scrollAway = "scroll_away"
    case reportContent = "report"
    case hideContent = "hide"
}

/// Negative signal event
struct NegativeSignalEvent: Codable {
    let contentId: String
    let reason: NegativeSignalReason
    let timestamp: Date
    let sessionId: String

    enum CodingKeys: String, CodingKey {
        case contentId = "content_id"
        case reason
        case timestamp
        case sessionId = "session_id"
    }
}

// Note: Analytics endpoints are defined in APIConfig.Analytics
