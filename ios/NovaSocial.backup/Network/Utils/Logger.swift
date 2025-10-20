import Foundation

/// Logger - 简洁的日志工具
/// 遵循 Linus 原则：简单、直接、零废话
enum LogLevel: String {
    case debug = "🔍 DEBUG"
    case info = "ℹ️ INFO"
    case warning = "⚠️ WARNING"
    case error = "❌ ERROR"
}

struct Logger {
    /// 记录日志
    static func log(
        _ message: String,
        level: LogLevel = .info,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        let filename = (file as NSString).lastPathComponent
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("\(level.rawValue) [\(timestamp)] [\(filename):\(line)] \(function) - \(message)")
        #endif
    }
}
