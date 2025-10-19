import Foundation
import UIKit

/// Central analytics tracker with batch upload to ClickHouse
@MainActor
class AnalyticsTracker: ObservableObject {
    static let shared = AnalyticsTracker()

    private var eventBuffer: [TrackedEvent] = []
    private let bufferSize = 50
    private let flushInterval: TimeInterval = 30.0
    private var flushTimer: Timer?

    private let clickHouseClient = ClickHouseClient.shared
    private let deviceId: String

    private init() {
        // Get or create device ID
        if let existing = UserDefaults.standard.string(forKey: "device_id") {
            self.deviceId = existing
        } else {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: "device_id")
            self.deviceId = newId
        }

        // Start flush timer
        startFlushTimer()

        // Register app lifecycle events
        registerAppLifecycleEvents()
    }

    // MARK: - Track Event
    func track(_ event: AnalyticsEvent) {
        let tracked = TrackedEvent(
            name: event.name,
            category: event.category,
            parameters: event.parameters,
            timestamp: Date(),
            deviceId: deviceId,
            userId: AuthService.shared.currentUser?.id,
            platform: "ios",
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        )

        eventBuffer.append(tracked)

        // Flush if buffer is full
        if eventBuffer.count >= bufferSize {
            flush()
        }
    }

    // MARK: - Flush
    func flush() {
        guard !eventBuffer.isEmpty else { return }

        let events = eventBuffer
        eventBuffer.removeAll()

        Task {
            await clickHouseClient.sendBatch(events)
        }
    }

    // MARK: - Flush Timer
    private func startFlushTimer() {
        flushTimer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.flush()
            }
        }
    }

    // MARK: - App Lifecycle
    private func registerAppLifecycleEvents() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.track(.appBackground)
            self?.flush() // Flush immediately on background
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.track(.appForeground)
        }
    }
}

// MARK: - Tracked Event Model
struct TrackedEvent: Codable {
    let name: String
    let category: String
    let parameters: [String: Any]
    let timestamp: Date
    let deviceId: String
    let userId: String?
    let platform: String
    let appVersion: String

    enum CodingKeys: String, CodingKey {
        case name
        case category
        case parameters
        case timestamp
        case deviceId = "device_id"
        case userId = "user_id"
        case platform
        case appVersion = "app_version"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        category = try container.decode(String.self, forKey: .category)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        deviceId = try container.decode(String.self, forKey: .deviceId)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        platform = try container.decode(String.self, forKey: .platform)
        appVersion = try container.decode(String.self, forKey: .appVersion)

        // Decode parameters from JSON string
        if let jsonString = try container.decodeIfPresent(String.self, forKey: .parameters),
           let jsonData = jsonString.data(using: .utf8),
           let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            parameters = dict
        } else {
            parameters = [:]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(category, forKey: .category)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(deviceId, forKey: .deviceId)
        try container.encodeIfPresent(userId, forKey: .userId)
        try container.encode(platform, forKey: .platform)
        try container.encode(appVersion, forKey: .appVersion)

        // Encode parameters as JSON string
        let jsonData = try JSONSerialization.data(withJSONObject: parameters)
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            try container.encode(jsonString, forKey: .parameters)
        }
    }
}
