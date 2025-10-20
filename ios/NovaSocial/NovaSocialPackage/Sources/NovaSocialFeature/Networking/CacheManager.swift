import Foundation

/// Generic wrapper for caching Codable types
private final class CodableBox<T>: NSObject where T: Codable {
    let value: T

    init(_ value: T) {
        self.value = value
    }
}

/// In-memory cache manager with TTL support
final class CacheManager: Sendable {
    private nonisolated(unsafe) let cache = NSCache<NSString, CodableBox<AnyCodable>>()
    private nonisolated(unsafe) let timestamps = NSMapTable<NSString, NSNumber>(keyOptions: .copyIn, valueOptions: .strongMemory)
    private let cacheTTL: TimeInterval = 5 * 60 // 5 minutes

    /// Retrieves a cached value if it exists and hasn't expired
    func get<T: Decodable>(for key: String) -> T? {
        let nsKey = key as NSString

        guard let timestamp = timestamps.object(forKey: nsKey)?.doubleValue else {
            return nil
        }

        let elapsed = Date().timeIntervalSince(Date(timeIntervalSince1970: timestamp))
        guard elapsed < cacheTTL else {
            cache.removeObject(forKey: nsKey)
            timestamps.removeObject(forKey: nsKey)
            return nil
        }

        guard let box = cache.object(forKey: nsKey) else {
            return nil
        }

        return box.value.value as? T
    }

    /// Stores a value in the cache
    func set<T: Encodable>(_ value: T, for key: String) {
        let nsKey = key as NSString
        let anyValue = AnyCodable(value)
        let box = CodableBox(anyValue)

        cache.setObject(box, forKey: nsKey)
        timestamps.setObject(NSNumber(value: Date().timeIntervalSince1970), forKey: nsKey)
    }

    /// Clears a specific cached value
    func clear(for key: String) {
        let nsKey = key as NSString
        cache.removeObject(forKey: nsKey)
        timestamps.removeObject(forKey: nsKey)
    }

    /// Clears all cached values
    func clearAll() {
        cache.removeAllObjects()
        timestamps.removeAllObjects()
    }
}

/// Type-erased wrapper for Codable values
private struct AnyCodable: Codable {
    let value: Any

    init<T: Encodable>(_ value: T) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let encodable = value as? Encodable {
            try container.encode(encodable)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = ()
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode AnyCodable")
        }
    }
}
