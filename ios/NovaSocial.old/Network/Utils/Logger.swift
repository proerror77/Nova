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
        let safeMessage = sanitize(message)
        print("\(level.rawValue) [\(timestamp)] [\(filename):\(line)] \(function) - \(safeMessage)")
        #endif
    }

    private static func sanitize(_ message: String) -> String {
        var sanitized = message

        let patterns: [(pattern: String, template: String)] = [
            "(?i)bearer\\s+[A-Za-z0-9._\\-]+": "Bearer [REDACTED]",
            "(?i)(access[-_]?token|refresh[-_]?token|auth[-_]?token)\\s*[:=]\\s*[A-Za-z0-9._\\-]+": "$1=[REDACTED]",
            "(?i)(password|secret|api[-_]?key)\\s*[:=]\\s*[^\\s]+": "$1=[REDACTED]"
        ]

        for entry in patterns {
            if let regex = try? NSRegularExpression(pattern: entry.pattern, options: []) {
                let range = NSRange(location: 0, length: sanitized.utf16.count)
                sanitized = regex.stringByReplacingMatches(in: sanitized, options: [], range: range, withTemplate: entry.template)
            }
        }

        return sanitized
    }
}
