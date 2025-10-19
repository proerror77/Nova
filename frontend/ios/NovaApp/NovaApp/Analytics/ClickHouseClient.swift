import Foundation

/// ClickHouse client for batch event upload
class ClickHouseClient {
    static let shared = ClickHouseClient()

    private let baseURL: URL
    private let tableName = "events"
    private let maxRetries = 3

    private init() {
        // TODO: Load from environment
        self.baseURL = URL(string: "https://clickhouse.nova.app")!
    }

    // MARK: - Send Batch
    func sendBatch(_ events: [TrackedEvent]) async {
        guard !events.isEmpty else { return }

        do {
            let payload = try JSONEncoder().encode(events)
            try await sendToClickHouse(payload)
            print("✅ Sent \(events.count) events to ClickHouse")
        } catch {
            print("⚠️ ClickHouse upload error: \(error)")
            // TODO: Persist failed events for retry
        }
    }

    // MARK: - HTTP Request
    private func sendToClickHouse(_ data: Data) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("/insert"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(tableName, forHTTPHeaderField: "X-ClickHouse-Table")
        request.httpBody = data

        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw ClickHouseError.invalidResponse
                }

                if (200...299).contains(httpResponse.statusCode) {
                    return // Success
                } else {
                    throw ClickHouseError.httpError(httpResponse.statusCode)
                }
            } catch {
                lastError = error
                if attempt < maxRetries - 1 {
                    // Exponential backoff
                    let delay = pow(2.0, Double(attempt)) * 0.5
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        throw lastError ?? ClickHouseError.unknown
    }
}

// MARK: - ClickHouse Errors
enum ClickHouseError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid ClickHouse response"
        case .httpError(let code): return "ClickHouse HTTP error: \(code)"
        case .unknown: return "Unknown ClickHouse error"
        }
    }
}
