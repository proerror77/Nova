import Foundation

/// 请求去重器 - 防止重复请求
/// 使用 Actor 保证线程安全，缓存正在进行的请求
actor RequestDeduplicator {
    // MARK: - Properties

    private var pendingRequests: [String: Task<Any, Error>] = [:]

    // MARK: - Public API

    /// 执行请求并自动去重
    /// - Parameters:
    ///   - key: 去重标识（通常是 endpoint 路径 + 参数）
    ///   - request: 实际请求闭包
    /// - Returns: 请求结果
    func deduplicate<T>(
        key: String,
        request: @escaping () async throws -> T
    ) async throws -> T {
        // 检查是否有正在进行的相同请求
        if let existingTask = pendingRequests[key] {
            Logger.log("🔄 Request DEDUP: Using existing request for \(key)", level: .debug)

            // 复用现有请求
            guard let result = try await existingTask.value as? T else {
                throw APIError.invalidResponse
            }
            return result
        }

        // 创建新请求
        Logger.log("🆕 Request DEDUP: Creating new request for \(key)", level: .debug)

        let task = Task<Any, Error> {
            defer {
                // 请求完成后移除记录
                Task { await self.removePendingRequest(key: key) }
            }

            let result = try await request()
            return result as Any
        }

        pendingRequests[key] = task

        // 执行并返回结果
        guard let result = try await task.value as? T else {
            throw APIError.invalidResponse
        }

        return result
    }

    /// 清除特定 key 的待处理请求
    func cancel(key: String) {
        pendingRequests[key]?.cancel()
        pendingRequests.removeValue(forKey: key)
        Logger.log("❌ Request DEDUP: Cancelled request for \(key)", level: .debug)
    }

    /// 清除所有待处理请求
    func cancelAll() {
        pendingRequests.values.forEach { $0.cancel() }
        pendingRequests.removeAll()
        Logger.log("❌ Request DEDUP: Cancelled all requests", level: .debug)
    }

    // MARK: - Private Helpers

    private func removePendingRequest(key: String) {
        pendingRequests.removeValue(forKey: key)
    }
}

// MARK: - Deduplication Key Generator

/// 去重键生成器
enum DeduplicationKey {
    /// 生成标准的去重键
    static func generate(
        path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem]? = nil,
        body: Encodable? = nil
    ) -> String {
        var components: [String] = [method.rawValue, path]

        // 添加查询参数
        if let queryItems = queryItems, !queryItems.isEmpty {
            let queryString = queryItems
                .sorted { $0.name < $1.name }
                .map { "\($0.name)=\($0.value ?? "")" }
                .joined(separator: "&")
            components.append(queryString)
        }

        // 添加 Body Hash（如果有）
        if let body = body {
            if let data = try? JSONEncoder().encode(body),
               let hash = String(data: data, encoding: .utf8) {
                components.append(hash)
            }
        }

        return components.joined(separator: "|")
    }

    /// 生成自定义去重键
    static func custom(_ key: String) -> String {
        key
    }
}

// MARK: - APIEndpoint Extension

extension APIEndpoint {
    /// 生成去重键
    var deduplicationKey: String {
        DeduplicationKey.generate(
            path: path,
            method: method,
            queryItems: queryItems,
            body: body
        )
    }
}
