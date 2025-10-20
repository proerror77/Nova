import Foundation

/// Monitors network requests and performance metrics
@Observable
final class NetworkMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var _requestLogs: [NetworkRequestLog] = []
    private var _totalRequests: Int = 0
    private var _successfulRequests: Int = 0
    private var _failedRequests: Int = 0
    private var _totalBytesDownloaded: Int = 0
    private var _totalBytesUploaded: Int = 0
    private var _averageResponseTime: TimeInterval = 0
    private var _responseTimeSamples: [TimeInterval] = []
    private var _isEnabled: Bool = true
    private var _maxLogSize: Int = 100

    // MARK: - Public Properties

    var totalRequests: Int {
        lock.withLock { _totalRequests }
    }

    var successfulRequests: Int {
        lock.withLock { _successfulRequests }
    }

    var failedRequests: Int {
        lock.withLock { _failedRequests }
    }

    var totalBytesDownloaded: Int {
        lock.withLock { _totalBytesDownloaded }
    }

    var totalBytesUploaded: Int {
        lock.withLock { _totalBytesUploaded }
    }

    var averageResponseTime: TimeInterval {
        lock.withLock { _averageResponseTime }
    }

    var isEnabled: Bool {
        get { lock.withLock { _isEnabled } }
        set { lock.withLock { _isEnabled = newValue } }
    }

    var requestLogs: [NetworkRequestLog] {
        lock.withLock { _requestLogs }
    }

    var successRate: Double {
        lock.withLock {
            guard _totalRequests > 0 else { return 0 }
            return Double(_successfulRequests) / Double(_totalRequests)
        }
    }

    // MARK: - Methods

    func logRequest(
        endpoint: String,
        method: String,
        statusCode: Int?,
        duration: TimeInterval,
        bytesDownloaded: Int = 0,
        bytesUploaded: Int = 0,
        error: Error? = nil
    ) {
        guard isEnabled else { return }

        lock.withLock {
            _totalRequests += 1

            if let statusCode = statusCode, (200...299).contains(statusCode) {
                _successfulRequests += 1
            } else if error != nil {
                _failedRequests += 1
            }

            _totalBytesDownloaded += bytesDownloaded
            _totalBytesUploaded += bytesUploaded

            // Update average response time
            _responseTimeSamples.append(duration)
            if _responseTimeSamples.count > 100 {
                _responseTimeSamples.removeFirst()
            }
            _averageResponseTime = _responseTimeSamples.reduce(0, +) / Double(_responseTimeSamples.count)

            // Log the request
            let log = NetworkRequestLog(
                timestamp: Date(),
                endpoint: endpoint,
                method: method,
                statusCode: statusCode,
                duration: duration,
                bytesDownloaded: bytesDownloaded,
                bytesUploaded: bytesUploaded,
                error: error?.localizedDescription
            )

            _requestLogs.append(log)

            // Keep only recent logs
            if _requestLogs.count > _maxLogSize {
                _requestLogs.removeFirst(_requestLogs.count - _maxLogSize)
            }
        }
    }

    func clearLogs() {
        lock.withLock {
            _requestLogs.removeAll()
            _responseTimeSamples.removeAll()
        }
    }

    func reset() {
        lock.withLock {
            _requestLogs.removeAll()
            _totalRequests = 0
            _successfulRequests = 0
            _failedRequests = 0
            _totalBytesDownloaded = 0
            _totalBytesUploaded = 0
            _averageResponseTime = 0
            _responseTimeSamples.removeAll()
        }
    }

    var debugDescription: String {
        lock.withLock {
            let bytesDownloadedFormatted = formatBytes(_totalBytesDownloaded)
            let bytesUploadedFormatted = formatBytes(_totalBytesUploaded)

            return """
            Network Monitor Statistics:
            - Total Requests: \(_totalRequests)
            - Successful: \(_successfulRequests)
            - Failed: \(_failedRequests)
            - Success Rate: \(String(format: "%.1f%%", successRate * 100))
            - Average Response Time: \(String(format: "%.2fms", _averageResponseTime * 1000))
            - Total Downloaded: \(bytesDownloadedFormatted)
            - Total Uploaded: \(bytesUploadedFormatted)
            - Recent Logs: \(_requestLogs.count)
            """
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Network Request Log

/// Represents a single network request log entry
struct NetworkRequestLog: Sendable, Identifiable {
    let id: UUID = UUID()
    let timestamp: Date
    let endpoint: String
    let method: String
    let statusCode: Int?
    let duration: TimeInterval
    let bytesDownloaded: Int
    let bytesUploaded: Int
    let error: String?

    var statusDescription: String {
        if let statusCode = statusCode {
            return "\(statusCode)"
        }
        return "No Response"
    }

    var durationMs: String {
        String(format: "%.2fms", duration * 1000)
    }

    var isSuccess: Bool {
        guard let statusCode = statusCode else { return false }
        return (200...299).contains(statusCode)
    }

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: timestamp)
    }
}

// MARK: - Singleton Instance

extension NetworkMonitor {
    static let shared = NetworkMonitor()
}
