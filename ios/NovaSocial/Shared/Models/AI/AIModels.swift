import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - AI Service Types

/// Type of AI service to use
enum AIServiceType {
    case onDevice      // Foundation Models (local)
    case remote        // AliceService (server)
    case hybrid        // Combined approach
}

// MARK: - AI Task Types

/// Types of AI tasks that can be routed
enum AITaskType {
    case chat                 // Complex conversation → Remote
    case sentiment            // Sentiment analysis → On-device
    case summarize            // Text summarization → On-device
    case keywordExtraction    // Extract keywords → On-device
    case imageAnalysis        // Image understanding → Remote (GPT-4V)
    case postEnhancement      // Enhance post content → Hybrid
    case simpleQA             // Simple questions → On-device
}

// MARK: - AI Service Errors

/// Errors that can occur during AI processing
enum AIServiceError: LocalizedError {
    case foundationModelsUnavailable
    case modelNotReady
    case contextTooLong
    case networkUnavailable
    case fallbackToRemote
    case generationFailed(String)
    case invalidInput
    case timeout

    var errorDescription: String? {
        switch self {
        case .foundationModelsUnavailable:
            return NSLocalizedString("On-device AI is not available on this device", comment: "")
        case .modelNotReady:
            return NSLocalizedString("AI model is still loading, please wait", comment: "")
        case .contextTooLong:
            return NSLocalizedString("The input is too long to process", comment: "")
        case .networkUnavailable:
            return NSLocalizedString("Network connection required for this operation", comment: "")
        case .fallbackToRemote:
            return NSLocalizedString("Switching to cloud AI processing", comment: "")
        case .generationFailed(let reason):
            return String(format: NSLocalizedString("AI generation failed: %@", comment: ""), reason)
        case .invalidInput:
            return NSLocalizedString("Invalid input provided", comment: "")
        case .timeout:
            return NSLocalizedString("AI processing timed out", comment: "")
        }
    }
}

// MARK: - Structured Output Models

// Note: @Generable macro requires iOS 26.0+ and FoundationModels framework
// These structs define the expected output structure for on-device AI

/// Sentiment analysis result
#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct SentimentResult: Sendable {
    @Guide(description: "The overall sentiment: positive, negative, or neutral")
    var sentiment: String

    @Guide(description: "Confidence score between 0.0 and 1.0")
    var confidence: Double

    @Guide(description: "Key phrases that influenced the sentiment analysis")
    var keyPhrases: [String]
}
#else
struct SentimentResult: Sendable {
    var sentiment: String
    var confidence: Double
    var keyPhrases: [String]
}
#endif

/// Text summarization result
#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct SummaryResult: Sendable {
    @Guide(description: "Concise summary of the text")
    var summary: String

    @Guide(description: "Main key points extracted from the text")
    var keyPoints: [String]

    @Guide(description: "Word count of the original text")
    var wordCount: Int
}
#else
struct SummaryResult: Sendable {
    var summary: String
    var keyPoints: [String]
    var wordCount: Int
}
#endif

/// Local post analysis result (for hybrid enhancement)
#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct LocalPostAnalysis: Sendable {
    @Guide(description: "Topics detected in the post content")
    var detectedTopics: [String]

    @Guide(description: "Suggested hashtags based on content")
    var suggestedHashtags: [String]

    @Guide(description: "Overall sentiment of the post: positive, negative, or neutral")
    var sentiment: String

    @Guide(description: "Suggested improvements for the post")
    var suggestions: [String]
}
#else
struct LocalPostAnalysis: Sendable {
    var detectedTopics: [String]
    var suggestedHashtags: [String]
    var sentiment: String
    var suggestions: [String]
}
#endif

/// Keyword extraction result
#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct KeywordExtractionResult: Sendable {
    @Guide(description: "List of important keywords from the text")
    var keywords: [String]

    @Guide(description: "Categories these keywords belong to")
    var categories: [String]
}
#else
struct KeywordExtractionResult: Sendable {
    var keywords: [String]
    var categories: [String]
}
#endif

// MARK: - AI Response Types

/// Generic AI response wrapper
struct AIResponse {
    let text: String
    let source: AIServiceType
    let processingTime: TimeInterval
    let metadata: [String: Any]?

    init(
        text: String,
        source: AIServiceType,
        processingTime: TimeInterval = 0,
        metadata: [String: Any]? = nil
    ) {
        self.text = text
        self.source = source
        self.processingTime = processingTime
        self.metadata = metadata
    }
}

/// AI task request
struct AITask {
    let type: AITaskType
    let input: String
    let imageData: Data?
    let options: AITaskOptions

    init(
        type: AITaskType,
        input: String,
        imageData: Data? = nil,
        options: AITaskOptions = .default
    ) {
        self.type = type
        self.input = input
        self.imageData = imageData
        self.options = options
    }
}

/// Options for AI task processing
struct AITaskOptions {
    let preferOnDevice: Bool
    let allowFallback: Bool
    let maxTokens: Int?
    let temperature: Double?

    static let `default` = AITaskOptions(
        preferOnDevice: true,
        allowFallback: true,
        maxTokens: nil,
        temperature: nil
    )

    init(
        preferOnDevice: Bool = true,
        allowFallback: Bool = true,
        maxTokens: Int? = nil,
        temperature: Double? = nil
    ) {
        self.preferOnDevice = preferOnDevice
        self.allowFallback = allowFallback
        self.maxTokens = maxTokens
        self.temperature = temperature
    }
}

// MARK: - Post Enhancement Models

/// Request for hybrid post enhancement
struct PostEnhancementRequest {
    let content: String
    let localAnalysis: LocalPostAnalysis?
    let imageDescriptions: [String]?

    init(
        content: String,
        localAnalysis: LocalPostAnalysis? = nil,
        imageDescriptions: [String]? = nil
    ) {
        self.content = content
        self.localAnalysis = localAnalysis
        self.imageDescriptions = imageDescriptions
    }
}

/// Enhanced post suggestion from hybrid AI processing
struct HybridPostEnhancementSuggestion {
    let enhancedContent: String
    let hashtags: [String]
    let sentiment: String
    let improvements: [String]
    let source: AIServiceType
}
