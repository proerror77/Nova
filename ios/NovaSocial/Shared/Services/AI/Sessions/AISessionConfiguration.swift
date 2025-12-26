import Foundation

// MARK: - AI Session Configuration

/// Configuration presets for different AI task types
@available(iOS 26.0, *)
struct AISessionConfiguration: Sendable {

    // MARK: - Properties

    let maxTokens: Int
    let temperature: Double
    let topP: Double
    let frequencyPenalty: Double
    let presencePenalty: Double

    // MARK: - Presets

    /// Configuration for casual chat conversations
    static let chat = AISessionConfiguration(
        maxTokens: 500,
        temperature: 0.7,
        topP: 0.9,
        frequencyPenalty: 0.0,
        presencePenalty: 0.0
    )

    /// Configuration for creative content generation
    static let creative = AISessionConfiguration(
        maxTokens: 1000,
        temperature: 0.9,
        topP: 0.95,
        frequencyPenalty: 0.5,
        presencePenalty: 0.5
    )

    /// Configuration for precise, factual responses
    static let precise = AISessionConfiguration(
        maxTokens: 300,
        temperature: 0.3,
        topP: 0.8,
        frequencyPenalty: 0.0,
        presencePenalty: 0.0
    )

    /// Configuration for content analysis tasks
    static let analysis = AISessionConfiguration(
        maxTokens: 500,
        temperature: 0.2,
        topP: 0.7,
        frequencyPenalty: 0.0,
        presencePenalty: 0.0
    )

    /// Configuration for structured output generation
    static let structured = AISessionConfiguration(
        maxTokens: 400,
        temperature: 0.4,
        topP: 0.85,
        frequencyPenalty: 0.0,
        presencePenalty: 0.0
    )

    // MARK: - Initialization

    init(
        maxTokens: Int = 500,
        temperature: Double = 0.7,
        topP: Double = 0.9,
        frequencyPenalty: Double = 0.0,
        presencePenalty: Double = 0.0
    ) {
        self.maxTokens = maxTokens
        self.temperature = max(0, min(2, temperature))
        self.topP = max(0, min(1, topP))
        self.frequencyPenalty = max(0, min(2, frequencyPenalty))
        self.presencePenalty = max(0, min(2, presencePenalty))
    }
}

// MARK: - Session Type

/// Types of AI sessions with different behaviors
@available(iOS 26.0, *)
enum AISessionType: String, CaseIterable {
    /// Stateless session for single requests (analysis, classification)
    case stateless

    /// Conversational session with history (Alice chat)
    case conversational

    /// Tool-enabled session with app data access
    case toolEnabled

    /// Default configuration for this session type
    var defaultConfiguration: AISessionConfiguration {
        switch self {
        case .stateless:
            return .analysis
        case .conversational:
            return .chat
        case .toolEnabled:
            return .chat
        }
    }
}
