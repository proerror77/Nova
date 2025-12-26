import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Post Suggestion

/// Structured output for post content suggestions
#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct PostSuggestion: Sendable {
    @Guide(description: "The suggested post content text, optimized for engagement and the ICERED platform style")
    var content: String

    @Guide(description: "Recommended hashtags for the post, without # symbol, between 3 and 8 tags")
    var hashtags: [String]

    @Guide(description: "Best time to post for maximum engagement: morning, afternoon, evening, or night")
    var optimalPostTime: String

    @Guide(description: "Estimated engagement level based on content quality: low, medium, or high")
    var estimatedEngagement: String

    @Guide(description: "Suggested mentions of relevant users or creators, without @ symbol")
    var suggestedMentions: [String]
}
#else
struct PostSuggestion: Sendable {
    var content: String
    var hashtags: [String]
    var optimalPostTime: String
    var estimatedEngagement: String
    var suggestedMentions: [String]
}
#endif

// MARK: - Content Classification

/// Structured output for classifying content
#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct ContentClassification: Sendable {
    @Guide(description: "Primary category: fashion, travel, food, tech, lifestyle, sports, entertainment, news, art, music, gaming, or other")
    var primaryCategory: String

    @Guide(description: "Secondary categories if applicable, up to 3")
    var secondaryCategories: [String]

    @Guide(description: "Content tone: professional, casual, humorous, inspirational, informative, or emotional")
    var tone: String

    @Guide(description: "Target audience: general, young adults, professionals, parents, students, or niche")
    var targetAudience: String

    @Guide(description: "Whether the content contains sensitive topics that may require moderation")
    var isSensitive: Bool

    @Guide(description: "Confidence score between 0.0 and 1.0")
    var confidence: Double
}
#else
struct ContentClassification: Sendable {
    var primaryCategory: String
    var secondaryCategories: [String]
    var tone: String
    var targetAudience: String
    var isSensitive: Bool
    var confidence: Double
}
#endif

// MARK: - User Interest Profile

/// Structured output for user interest analysis
#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct UserInterestProfile: Sendable {
    @Guide(description: "Top interest categories based on user activity, up to 5")
    var topInterests: [String]

    @Guide(description: "Preferred content types: images, videos, text, stories, reels, or mixed")
    var preferredContentTypes: [String]

    @Guide(description: "Most active time periods: morning, afternoon, evening, or night")
    var activeTimePeriods: [String]

    @Guide(description: "Engagement style: passive viewer, active commenter, content creator, or curator")
    var engagementStyle: String

    @Guide(description: "Recommended channels based on interests")
    var recommendedChannels: [String]
}
#else
struct UserInterestProfile: Sendable {
    var topInterests: [String]
    var preferredContentTypes: [String]
    var activeTimePeriods: [String]
    var engagementStyle: String
    var recommendedChannels: [String]
}
#endif

// MARK: - Hashtag Recommendation

/// Structured output for hashtag recommendations
#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct HashtagRecommendation: Sendable {
    @Guide(description: "Primary hashtag most relevant to the content, without # symbol")
    var primaryHashtag: String

    @Guide(description: "Trending hashtags that match the content, up to 3, without # symbol")
    var trendingHashtags: [String]

    @Guide(description: "Niche hashtags for targeted reach, up to 3, without # symbol")
    var nicheHashtags: [String]

    @Guide(description: "Location-based hashtags if applicable, without # symbol")
    var locationHashtags: [String]

    @Guide(description: "Total recommended count of hashtags to use, between 3 and 10")
    var recommendedCount: Int
}
#else
struct HashtagRecommendation: Sendable {
    var primaryHashtag: String
    var trendingHashtags: [String]
    var nicheHashtags: [String]
    var locationHashtags: [String]
    var recommendedCount: Int
}
#endif

// MARK: - Conversation Summary

/// Structured output for summarizing conversations
#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct ConversationSummary: Sendable {
    @Guide(description: "Brief summary of the conversation in 1-2 sentences")
    var summary: String

    @Guide(description: "Main topics discussed, up to 5")
    var mainTopics: [String]

    @Guide(description: "Action items or follow-ups mentioned")
    var actionItems: [String]

    @Guide(description: "Overall sentiment of the conversation: positive, neutral, or negative")
    var overallSentiment: String
}
#else
struct ConversationSummary: Sendable {
    var summary: String
    var mainTopics: [String]
    var actionItems: [String]
    var overallSentiment: String
}
#endif

// MARK: - Post Enhancement Result

/// Structured output for enhanced post content
#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct PostEnhancementResult: Sendable {
    @Guide(description: "The enhanced post content with improved clarity, grammar, and engagement")
    var enhancedContent: String

    @Guide(description: "Grammar and spelling corrections made, if any")
    var corrections: [String]

    @Guide(description: "Suggestions for improving the post further")
    var suggestions: [String]

    @Guide(description: "Recommended hashtags based on content analysis, without # symbol")
    var recommendedHashtags: [String]

    @Guide(description: "Detected language of the content: en, zh, ja, ko, or other language code")
    var detectedLanguage: String
}
#else
struct PostEnhancementResult: Sendable {
    var enhancedContent: String
    var corrections: [String]
    var suggestions: [String]
    var recommendedHashtags: [String]
    var detectedLanguage: String
}
#endif

// MARK: - Reply Suggestion

/// Structured output for reply suggestions
#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct ReplySuggestion: Sendable {
    @Guide(description: "Quick reply options, short and casual, up to 3")
    var quickReplies: [String]

    @Guide(description: "Detailed reply option with more context")
    var detailedReply: String

    @Guide(description: "Emoji-only reply suggestions, up to 3")
    var emojiReplies: [String]

    @Guide(description: "Whether the original message requires a response")
    var requiresResponse: Bool
}
#else
struct ReplySuggestion: Sendable {
    var quickReplies: [String]
    var detailedReply: String
    var emojiReplies: [String]
    var requiresResponse: Bool
}
#endif

// MARK: - Caption Generator

/// Structured output for image/video caption generation
#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct CaptionSuggestion: Sendable {
    @Guide(description: "Short caption option, under 50 characters")
    var shortCaption: String

    @Guide(description: "Medium caption with context, 50-150 characters")
    var mediumCaption: String

    @Guide(description: "Long descriptive caption, 150-300 characters")
    var longCaption: String

    @Guide(description: "Call-to-action phrases that could be added")
    var callToActions: [String]

    @Guide(description: "Relevant emojis to include, up to 5")
    var suggestedEmojis: [String]
}
#else
struct CaptionSuggestion: Sendable {
    var shortCaption: String
    var mediumCaption: String
    var longCaption: String
    var callToActions: [String]
    var suggestedEmojis: [String]
}
#endif

// MARK: - Thread Breakdown

/// Structured output for breaking long content into threads
#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct ThreadBreakdown: Sendable {
    @Guide(description: "Opening hook to grab attention")
    var hook: String

    @Guide(description: "Main content broken into thread parts, each under 280 characters")
    var threadParts: [String]

    @Guide(description: "Closing statement or call-to-action")
    var closing: String

    @Guide(description: "Total number of parts in the thread")
    var partCount: Int
}
#else
struct ThreadBreakdown: Sendable {
    var hook: String
    var threadParts: [String]
    var closing: String
    var partCount: Int
}
#endif

// MARK: - Type Aliases for Cross-Platform Compatibility

#if canImport(FoundationModels)
@available(iOS 26.0, *)
typealias AIPostSuggestion = PostSuggestion
@available(iOS 26.0, *)
typealias AIContentClassification = ContentClassification
@available(iOS 26.0, *)
typealias AIHashtagRecommendation = HashtagRecommendation
@available(iOS 26.0, *)
typealias AIPostEnhancement = PostEnhancementResult
@available(iOS 26.0, *)
typealias AIReplySuggestion = ReplySuggestion
#else
typealias AIPostSuggestion = PostSuggestion
typealias AIContentClassification = ContentClassification
typealias AIHashtagRecommendation = HashtagRecommendation
typealias AIPostEnhancement = PostEnhancementResult
typealias AIReplySuggestion = ReplySuggestion
#endif
