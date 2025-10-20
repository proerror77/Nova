import Foundation

/// RequestDeduplicator - 请求去重器
///
/// 职责：防止相同请求的并发执行
/// 设计原则：
/// 1. 简洁 - 使用 Task 作为值,自动处理并发
/// 2. 类型安全 - 泛型支持任意返回类型
/// 3. 线程安全 - 使用 actor 隔离
/// 4. 无特殊情况 - 所有请求统一处理,无 if/else 分支
///
/// Linus 哲学:
/// "Bad programmers worry about the code. Good programmers worry about data structures."
/// 这里的数据结构是: [String: Task] - 简单到极致
actor RequestDeduplicator {

    // MARK: - Storage

    /// 正在执行的请求任务
    /// Key: 请求的唯一标识符
    /// Value: 正在执行的 Task
    private var activeTasks: [String: Task<Any, Error>] = [:]

    // MARK: - Public API

    /// 执行请求,如果相同请求正在进行中则复用
    ///
    /// - Parameters:
    ///   - key: 请求的唯一标识符(通常是 method + path + params)
    ///   - operation: 实际的网络请求操作
    /// - Returns: 请求结果
    /// - Throws: 请求错误
    func execute<T>(
        key: String,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        // 如果已有相同请求正在执行,复用它
        if let existingTask = activeTasks[key] {
            // 这就是"好品味"代码 - 没有特殊情况,直接复用
            return try await existingTask.value as! T
        }

        // 创建新任务
        let task = Task<Any, Error> {
            defer {
                // 清理:任务完成后移除
                Task { await self.removeTask(for: key) }
            }

            // 执行实际操作
            return try await operation()
        }

        // 存储任务
        activeTasks[key] = task

        // 等待结果
        return try await task.value as! T
    }

    /// 清除所有活跃任务(用于测试或重置)
    func clear() {
        activeTasks.removeAll()
    }

    /// 获取当前活跃任务数量(用于调试)
    func activeCount() -> Int {
        return activeTasks.count
    }

    // MARK: - Private Helpers

    private func removeTask(for key: String) {
        activeTasks.removeValue(forKey: key)
    }
}

// MARK: - Key Generation Helpers

extension RequestDeduplicator {

    /// 生成请求的唯一标识符
    ///
    /// 原则: 简单 > 完美
    /// 我们不需要复杂的哈希算法,字符串拼接就够了
    static func makeKey(
        method: HTTPMethod,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        body: String? = nil
    ) -> String {
        var components = [method.rawValue, path]

        // 添加查询参数(如果有)
        if let items = queryItems, !items.isEmpty {
            let query = items
                .sorted { $0.name < $1.name } // 排序确保一致性
                .map { "\($0.name)=\($0.value ?? "")" }
                .joined(separator: "&")
            components.append(query)
        }

        // 添加 body(如果有)
        if let body = body {
            components.append(body)
        }

        return components.joined(separator: "|")
    }

    /// 为常见操作生成 key 的便捷方法
    static func likeKey(postId: UUID) -> String {
        return "POST|/posts/\(postId.uuidString)/like"
    }

    static func unlikeKey(postId: UUID) -> String {
        return "DELETE|/posts/\(postId.uuidString)/like"
    }

    static func followKey(userId: UUID) -> String {
        return "POST|/users/\(userId.uuidString)/follow"
    }

    static func unfollowKey(userId: UUID) -> String {
        return "DELETE|/users/\(userId.uuidString)/follow"
    }

    static func commentKey(postId: UUID, text: String) -> String {
        // 评论内容作为 key 的一部分,防止重复提交相同评论
        return "POST|/posts/\(postId.uuidString)/comments|\(text)"
    }
}

// MARK: - Validation Helpers

extension RequestDeduplicator {

    /// 验证输入参数
    /// Linus: "永远不要信任用户输入"
    static func validate(_ text: String, maxLength: Int = 1000) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyInput
        }

        guard text.count <= maxLength else {
            throw ValidationError.inputTooLong(max: maxLength)
        }
    }
}

// MARK: - Validation Error

enum ValidationError: LocalizedError {
    case emptyInput
    case inputTooLong(max: Int)
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "输入不能为空"
        case .inputTooLong(let max):
            return "输入超过最大长度 \(max)"
        case .invalidFormat:
            return "输入格式无效"
        }
    }
}
