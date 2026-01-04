import SwiftUI

// MARK: - Text Parsing Utilities

/// Shared utilities for parsing and formatting text content
/// Includes @mention highlighting, hashtag detection, and URL handling

/// Regex cache for performance optimization (avoids recompilation per render)
private enum TextParsingRegex {
    /// Cached regex for @mention matching (supports Chinese, English, numbers, underscores)
    static let mentionPattern: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "@[\\w\\u4e00-\\u9fff]+", options: [])
    }()

    /// Cached regex for #hashtag matching
    static let hashtagPattern: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "#[\\w\\u4e00-\\u9fff]+", options: [])
    }()
}

/// Parse comment text and highlight @mentions with accent color (IG/Xiaohongshu style)
/// - Parameter text: The raw comment text to parse
/// - Returns: A SwiftUI Text view with highlighted @mentions
func parseCommentText(_ text: String) -> Text {
    guard let regex = TextParsingRegex.mentionPattern else {
        return Text(text)
    }

    let nsString = text as NSString
    let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

    if matches.isEmpty {
        return Text(text)
    }

    var result = Text("")
    var lastEnd = 0

    for match in matches {
        // Add text before @mention
        if match.range.location > lastEnd {
            let beforeRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
            let beforeText = nsString.substring(with: beforeRange)
            result = result + Text(beforeText)
        }

        // Add highlighted @mention
        let mentionText = nsString.substring(with: match.range)
        result = result + Text(mentionText)
            .foregroundColor(DesignTokens.accentColor)
            .fontWeight(.medium)

        lastEnd = match.range.location + match.range.length
    }

    // Add text after last @mention
    if lastEnd < nsString.length {
        let afterText = nsString.substring(from: lastEnd)
        result = result + Text(afterText)
    }

    return result
}

/// Parse text and highlight both @mentions and #hashtags
/// - Parameter text: The raw text to parse
/// - Returns: A SwiftUI Text view with highlighted @mentions and #hashtags
func parseRichText(_ text: String) -> Text {
    guard let mentionRegex = TextParsingRegex.mentionPattern,
          let hashtagRegex = TextParsingRegex.hashtagPattern else {
        return Text(text)
    }

    let nsString = text as NSString
    let range = NSRange(location: 0, length: nsString.length)

    // Find all matches
    let mentionMatches = mentionRegex.matches(in: text, options: [], range: range)
    let hashtagMatches = hashtagRegex.matches(in: text, options: [], range: range)

    if mentionMatches.isEmpty && hashtagMatches.isEmpty {
        return Text(text)
    }

    // Combine and sort matches by location
    struct MatchInfo {
        let range: NSRange
        let isMention: Bool
    }

    var allMatches: [MatchInfo] = []
    allMatches.append(contentsOf: mentionMatches.map { MatchInfo(range: $0.range, isMention: true) })
    allMatches.append(contentsOf: hashtagMatches.map { MatchInfo(range: $0.range, isMention: false) })
    allMatches.sort { $0.range.location < $1.range.location }

    var result = Text("")
    var lastEnd = 0

    for match in allMatches {
        // Skip overlapping matches
        if match.range.location < lastEnd {
            continue
        }

        // Add text before match
        if match.range.location > lastEnd {
            let beforeRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
            let beforeText = nsString.substring(with: beforeRange)
            result = result + Text(beforeText)
        }

        // Add highlighted match
        let matchText = nsString.substring(with: match.range)
        let color = match.isMention ? DesignTokens.accentColor : Color.blue
        result = result + Text(matchText)
            .foregroundColor(color)
            .fontWeight(.medium)

        lastEnd = match.range.location + match.range.length
    }

    // Add text after last match
    if lastEnd < nsString.length {
        let afterText = nsString.substring(from: lastEnd)
        result = result + Text(afterText)
    }

    return result
}
