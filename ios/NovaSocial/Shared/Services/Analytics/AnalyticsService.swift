import Foundation

// MARK: - Analytics Service

/// Manages analytics and recommendation signals using analytics API
/// Handles watch events, engagement tracking, and session data
class AnalyticsService {
    static let shared = AnalyticsService()
    private let client = APIClient.shared

    private init() {}

    // MARK: - Watch Events

    /// Record batch watch events for recommendation algorithm
    /// - Parameter events: Array of watch events to record
    func recordWatchEvents(_ events: [WatchEvent]) async throws {
        struct Request: Codable {
            let events: [WatchEvent]
        }

        struct Response: Codable {
            let success: Bool
            let processedCount: Int?

            enum CodingKeys: String, CodingKey {
                case success
                case processedCount = "processed_count"
            }
        }

        let request = Request(events: events)
        let _: Response = try await client.request(
            endpoint: APIConfig.Analytics.recordWatchEvents,
            method: "POST",
            body: request
        )
    }

    // MARK: - Engagement Signals

    /// Record user engagement with content
    /// - Parameters:
    ///   - contentId: ID of the content
    ///   - contentType: Type of content (post, video, reel, etc.)
    ///   - engagementType: Type of engagement (like, comment, share, save, etc.)
    ///   - metadata: Additional metadata
    func recordEngagement(
        contentId: String,
        contentType: ContentType,
        engagementType: EngagementType,
        metadata: [String: String]? = nil
    ) async throws {
        struct Request: Codable {
            let contentId: String
            let contentType: String
            let engagementType: String
            let metadata: [String: String]?
            let timestamp: Int64

            enum CodingKeys: String, CodingKey {
                case contentId = "content_id"
                case contentType = "content_type"
                case engagementType = "engagement_type"
                case metadata
                case timestamp
            }
        }

        struct Response: Codable {
            let success: Bool
        }

        let request = Request(
            contentId: contentId,
            contentType: contentType.rawValue,
            engagementType: engagementType.rawValue,
            metadata: metadata,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000)
        )

        let _: Response = try await client.request(
            endpoint: APIConfig.Analytics.recordEngagement,
            method: "POST",
            body: request
        )
    }

    // MARK: - Negative Signals

    /// Record negative signal (not interested, hide, report)
    /// - Parameters:
    ///   - contentId: ID of the content
    ///   - contentType: Type of content
    ///   - signalType: Type of negative signal
    ///   - reason: Optional reason for the signal
    func recordNegativeSignal(
        contentId: String,
        contentType: ContentType,
        signalType: NegativeSignalType,
        reason: String? = nil
    ) async throws {
        struct Request: Codable {
            let contentId: String
            let contentType: String
            let signalType: String
            let reason: String?
            let timestamp: Int64

            enum CodingKeys: String, CodingKey {
                case contentId = "content_id"
                case contentType = "content_type"
                case signalType = "signal_type"
                case reason
                case timestamp
            }
        }

        struct Response: Codable {
            let success: Bool
        }

        let request = Request(
            contentId: contentId,
            contentType: contentType.rawValue,
            signalType: signalType.rawValue,
            reason: reason,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000)
        )

        let _: Response = try await client.request(
            endpoint: APIConfig.Analytics.recordNegativeSignal,
            method: "POST",
            body: request
        )
    }

    // MARK: - Session Data

    /// Record session data for analytics
    /// - Parameter session: Session data to record
    func recordSession(_ session: SessionData) async throws {
        struct Response: Codable {
            let success: Bool
        }

        let _: Response = try await client.request(
            endpoint: APIConfig.Analytics.recordSession,
            method: "POST",
            body: session
        )
    }
}

// MARK: - Models

/// Watch event for content viewing
struct WatchEvent: Codable {
    let contentId: String
    let contentType: String
    let watchDurationMs: Int64
    let totalDurationMs: Int64?
    let percentWatched: Double?
    let timestamp: Int64
    let source: String?  // feed, profile, search, etc.

    enum CodingKeys: String, CodingKey {
        case contentId = "content_id"
        case contentType = "content_type"
        case watchDurationMs = "watch_duration_ms"
        case totalDurationMs = "total_duration_ms"
        case percentWatched = "percent_watched"
        case timestamp
        case source
    }

    init(
        contentId: String,
        contentType: ContentType,
        watchDurationMs: Int64,
        totalDurationMs: Int64? = nil,
        percentWatched: Double? = nil,
        source: String? = nil
    ) {
        self.contentId = contentId
        self.contentType = contentType.rawValue
        self.watchDurationMs = watchDurationMs
        self.totalDurationMs = totalDurationMs
        self.percentWatched = percentWatched
        self.timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        self.source = source
    }
}

/// Content type for analytics
enum ContentType: String, Codable {
    case post = "post"
    case video = "video"
    case reel = "reel"
    case story = "story"
    case stream = "stream"
    case profile = "profile"
}

/// Engagement type for analytics
enum EngagementType: String, Codable {
    case like = "like"
    case comment = "comment"
    case share = "share"
    case save = "save"
    case click = "click"
    case follow = "follow"
    case profileView = "profile_view"
}

/// Negative signal type
enum NegativeSignalType: String, Codable {
    case notInterested = "not_interested"
    case hide = "hide"
    case report = "report"
    case mute = "mute"
    case block = "block"
}

/// Session data for analytics
struct SessionData: Codable {
    let sessionId: String
    let startTime: Int64
    let endTime: Int64
    let durationMs: Int64
    let screenViews: [ScreenView]?
    let deviceInfo: DeviceInfo?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case startTime = "start_time"
        case endTime = "end_time"
        case durationMs = "duration_ms"
        case screenViews = "screen_views"
        case deviceInfo = "device_info"
    }
}

/// Screen view for session tracking
struct ScreenView: Codable {
    let screenName: String
    let timestamp: Int64
    let durationMs: Int64?

    enum CodingKeys: String, CodingKey {
        case screenName = "screen_name"
        case timestamp
        case durationMs = "duration_ms"
    }
}

/// Device info for analytics
struct DeviceInfo: Codable {
    let platform: String
    let osVersion: String
    let appVersion: String
    let deviceModel: String?

    enum CodingKeys: String, CodingKey {
        case platform
        case osVersion = "os_version"
        case appVersion = "app_version"
        case deviceModel = "device_model"
    }
}
