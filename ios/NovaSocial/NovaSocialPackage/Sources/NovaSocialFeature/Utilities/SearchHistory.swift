import Foundation

/// Manages search history and suggestions
@Observable
final class SearchHistory: @unchecked Sendable {
    private let lock = NSLock()
    private var _history: [SearchHistoryEntry] = []
    private let maxHistorySize: Int = 50

    var history: [SearchHistoryEntry] {
        lock.withLock {
            Array(_history.prefix(20)) // Return most recent 20
        }
    }

    var allHistory: [SearchHistoryEntry] {
        lock.withLock { Array(_history) }
    }

    // MARK: - Methods

    func addQuery(_ query: String) {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)

        lock.withLock {
            // Remove duplicate if exists
            _history.removeAll { $0.query.lowercased() == trimmedQuery.lowercased() }

            // Add to front
            let entry = SearchHistoryEntry(
                id: UUID(),
                query: trimmedQuery,
                timestamp: Date()
            )
            _history.insert(entry, at: 0)

            // Keep size under control
            if _history.count > maxHistorySize {
                _history.removeLast(_history.count - maxHistorySize)
            }
        }

        saveToUserDefaults()
    }

    func removeQuery(_ query: String) {
        lock.withLock {
            _history.removeAll { $0.query == query }
        }

        saveToUserDefaults()
    }

    func removeEntry(id: UUID) {
        lock.withLock {
            _history.removeAll { $0.id == id }
        }

        saveToUserDefaults()
    }

    func clearHistory() {
        lock.withLock {
            _history.removeAll()
        }

        saveToUserDefaults()
    }

    func loadHistory() {
        lock.withLock {
            if let data = UserDefaults.standard.data(forKey: "searchHistory") {
                if let decoded = try? JSONDecoder().decode([SearchHistoryEntry].self, from: data) {
                    _history = decoded
                }
            }
        }
    }

    private func saveToUserDefaults() {
        lock.withLock {
            if let encoded = try? JSONEncoder().encode(_history) {
                UserDefaults.standard.set(encoded, forKey: "searchHistory")
            }
        }
    }

    // MARK: - Suggestions

    func suggestions(for query: String, limit: Int = 5) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else {
            return lock.withLock { Array(_history.prefix(limit).map { $0.query }) }
        }

        return lock.withLock {
            _history
                .filter { $0.query.lowercased().contains(trimmed) }
                .prefix(limit)
                .map { $0.query }
        }
    }

    // MARK: - Popular Searches

    func popularSearches(limit: Int = 10) -> [String] {
        lock.withLock {
            var frequencyMap: [String: Int] = [:]

            for entry in _history {
                frequencyMap[entry.query, default: 0] += 1
            }

            return frequencyMap
                .sorted { $0.value > $1.value }
                .prefix(limit)
                .map { $0.key }
        }
    }
}

// MARK: - Search History Entry

struct SearchHistoryEntry: Codable, Sendable, Identifiable {
    let id: UUID
    let query: String
    let timestamp: Date

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .short
        return formatter.string(from: timestamp)
    }

    var isRecent: Bool {
        let dayAgo = Date().addingTimeInterval(-86400) // 24 hours
        return timestamp > dayAgo
    }
}

// MARK: - Singleton

extension SearchHistory {
    static let shared = SearchHistory()
}
