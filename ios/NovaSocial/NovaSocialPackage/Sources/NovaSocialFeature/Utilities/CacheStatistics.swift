import Foundation

/// Tracks cache hit/miss statistics
@Observable
final class CacheStatistics: @unchecked Sendable {
    private let lock = NSLock()
    private var _totalAccesses: Int = 0
    private var _hits: Int = 0
    private var _misses: Int = 0
    private var _invalidations: Int = 0
    private var _accessLog: [(key: String, hit: Bool, timestamp: Date)] = []
    private var _maxLogSize: Int = 1000

    var totalAccesses: Int {
        lock.withLock { _totalAccesses }
    }

    var hits: Int {
        lock.withLock { _hits }
    }

    var misses: Int {
        lock.withLock { _misses }
    }

    var invalidations: Int {
        lock.withLock { _invalidations }
    }

    var hitRate: Double {
        lock.withLock {
            guard _totalAccesses > 0 else { return 0 }
            return Double(_hits) / Double(_totalAccesses)
        }
    }

    var missRate: Double {
        lock.withLock {
            guard _totalAccesses > 0 else { return 0 }
            return Double(_misses) / Double(_totalAccesses)
        }
    }

    var accessLog: [(key: String, hit: Bool, timestamp: Date)] {
        lock.withLock { _accessLog }
    }

    // MARK: - Methods

    func recordHit(key: String) {
        lock.withLock {
            _totalAccesses += 1
            _hits += 1
            _accessLog.append((key: key, hit: true, timestamp: Date()))
            pruneAccessLog()
        }
    }

    func recordMiss(key: String) {
        lock.withLock {
            _totalAccesses += 1
            _misses += 1
            _accessLog.append((key: key, hit: false, timestamp: Date()))
            pruneAccessLog()
        }
    }

    func recordInvalidation() {
        lock.withLock {
            _invalidations += 1
        }
    }

    func reset() {
        lock.withLock {
            _totalAccesses = 0
            _hits = 0
            _misses = 0
            _invalidations = 0
            _accessLog.removeAll()
        }
    }

    func clearLog() {
        lock.withLock {
            _accessLog.removeAll()
        }
    }

    private func pruneAccessLog() {
        if _accessLog.count > _maxLogSize {
            _accessLog.removeFirst(_accessLog.count - _maxLogSize)
        }
    }

    var debugDescription: String {
        lock.withLock {
            """
            Cache Statistics:
            - Total Accesses: \(_totalAccesses)
            - Hits: \(_hits)
            - Misses: \(_misses)
            - Hit Rate: \(String(format: "%.1f%%", hitRate * 100))
            - Miss Rate: \(String(format: "%.1f%%", missRate * 100))
            - Invalidations: \(_invalidations)
            - Log Entries: \(_accessLog.count)
            """
        }
    }

    // MARK: - Statistics by Key

    func statisticsByKey() -> [String: CacheKeyStatistics] {
        lock.withLock {
            var stats: [String: CacheKeyStatistics] = [:]

            for (key, hit, _) in _accessLog {
                if stats[key] == nil {
                    stats[key] = CacheKeyStatistics(key: key)
                }

                if hit {
                    stats[key]?.recordHit()
                } else {
                    stats[key]?.recordMiss()
                }
            }

            return stats
        }
    }

    // MARK: - Recent Statistics

    func recentStatistics(last n: Int = 100) -> CacheStatistics {
        let recent = CacheStatistics()
        let recentLogs = lock.withLock {
            Array(_accessLog.suffix(n))
        }

        for (_, hit, _) in recentLogs {
            if hit {
                recent.recordHit(key: "")
            } else {
                recent.recordMiss(key: "")
            }
        }

        return recent
    }
}

// MARK: - Cache Key Statistics

struct CacheKeyStatistics: Sendable {
    let key: String
    private(set) var hits: Int = 0
    private(set) var misses: Int = 0

    var totalAccesses: Int {
        hits + misses
    }

    var hitRate: Double {
        guard totalAccesses > 0 else { return 0 }
        return Double(hits) / Double(totalAccesses)
    }

    mutating func recordHit() {
        hits += 1
    }

    mutating func recordMiss() {
        misses += 1
    }

    var debugDescription: String {
        """
        \(key):
          - Hits: \(hits)
          - Misses: \(misses)
          - Total: \(totalAccesses)
          - Hit Rate: \(String(format: "%.1f%%", hitRate * 100))
        """
    }
}

// MARK: - Singleton Instance

extension CacheStatistics {
    static let shared = CacheStatistics()
}
