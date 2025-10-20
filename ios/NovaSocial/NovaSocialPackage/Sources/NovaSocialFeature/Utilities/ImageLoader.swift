import SwiftUI
import Kingfisher

/// AsyncImage wrapper using Kingfisher for optimized image loading
struct KFImageView: View {
    let url: URL?
    var contentMode: Image.ResizingMode = .stretch
    var placeholder: String = "person.crop.circle.fill"
    var placeholderColor: Color = .blue.opacity(0.5)

    var body: some View {
        ZStack {
            if let url = url {
                KFImage(url)
                    .retry(maxCount: 3)
                    .cacheMemoryOnly()
                    .onProgress { receivedSize, totalSize in }
                    .onSuccess { result in }
                    .onFailure { error in }
                    .placeholder {
                        Image(systemName: placeholder)
                            .font(.system(size: 40))
                            .foregroundColor(placeholderColor)
                    }
                    .scaledToFill()
            } else {
                Image(systemName: placeholder)
                    .font(.system(size: 40))
                    .foregroundColor(placeholderColor)
            }
        }
        .clipped()
    }
}

/// Image cache statistics for performance monitoring
@Observable
final class ImageCacheStatistics: @unchecked Sendable {
    private let lock = NSLock()
    private var _totalRequests: Int = 0
    private var _cacheHits: Int = 0
    private var _cacheMisses: Int = 0
    private var _bytesLoaded: Int = 0

    var totalRequests: Int {
        lock.withLock { _totalRequests }
    }

    var cacheHits: Int {
        lock.withLock { _cacheHits }
    }

    var cacheMisses: Int {
        lock.withLock { _cacheMisses }
    }

    var bytesLoaded: Int {
        lock.withLock { _bytesLoaded }
    }

    var hitRate: Double {
        lock.withLock {
            guard _totalRequests > 0 else { return 0 }
            return Double(_cacheHits) / Double(_totalRequests)
        }
    }

    func recordRequest() {
        lock.withLock {
            _totalRequests += 1
        }
    }

    func recordHit() {
        lock.withLock {
            _cacheHits += 1
        }
    }

    func recordMiss() {
        lock.withLock {
            _cacheMisses += 1
        }
    }

    func recordBytes(_ bytes: Int) {
        lock.withLock {
            _bytesLoaded += bytes
        }
    }

    func reset() {
        lock.withLock {
            _totalRequests = 0
            _cacheHits = 0
            _cacheMisses = 0
            _bytesLoaded = 0
        }
    }

    var debugDescription: String {
        lock.withLock {
            """
            Image Cache Statistics:
            - Total Requests: \(_totalRequests)
            - Cache Hits: \(_cacheHits)
            - Cache Misses: \(_cacheMisses)
            - Hit Rate: \(String(format: "%.1f%%", hitRate * 100))
            - Bytes Loaded: \(_bytesLoaded) bytes (\(formatBytes(_bytesLoaded)))
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
