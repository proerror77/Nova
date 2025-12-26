import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Foundation Models Service

/// On-device AI service using Apple Foundation Models
/// Requires iOS 26.0+ and compatible hardware (iPhone 15 Pro+, M-series iPad/Mac)
@available(iOS 26.0, *)
@Observable
@MainActor
final class FoundationModelsService {

    // MARK: - Singleton

    static let shared = FoundationModelsService()

    // MARK: - Properties

    #if canImport(FoundationModels)
    private var session: LanguageModelSession?
    private var chatSession: LanguageModelSession?  // Separate session for chat with history
    #endif

    private(set) var isAvailable: Bool = false
    private(set) var isReady: Bool = false
    private(set) var isProcessing: Bool = false

    // MARK: - Configuration

    /// Alice system instructions for chat context
    private let aliceInstructions = """
    You are Alice, the AI assistant for ICERED social app.

    Personality:
    - Friendly, helpful, and concise
    - Respond in the user's language (detect from input)
    - Use casual but professional tone
    - Add relevant emoji sparingly when appropriate

    Capabilities:
    - Help users with the ICERED app features
    - Answer general questions
    - Provide creative suggestions for posts
    - Assist with content ideas

    Guidelines:
    - Keep responses brief (under 150 words unless detail is needed)
    - Be honest if you don't know something
    - Never generate harmful or inappropriate content
    """

    /// Retry configuration
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 0.5

    // MARK: - Initialization

    private init() {
        Task {
            await checkAvailability()
        }
    }

    // MARK: - Availability Check

    /// Check if Foundation Models are available on this device
    func checkAvailability() async {
        #if canImport(FoundationModels)
        let systemModel = SystemLanguageModel.default
        switch systemModel.availability {
        case .available:
            isAvailable = true
            await initializeSessions()
        case .unavailable(let reason):
            isAvailable = false
            #if DEBUG
            print("[FoundationModelsService] Models unavailable: \(reason)")
            #endif
        @unknown default:
            isAvailable = false
        }
        #else
        isAvailable = false
        #if DEBUG
        print("[FoundationModelsService] FoundationModels framework not available")
        #endif
        #endif
    }

    #if canImport(FoundationModels)
    /// Initialize the language model sessions
    private func initializeSessions() async {
        // Basic session for simple tasks (no instructions)
        session = LanguageModelSession()

        // Chat session with Alice instructions for conversational context
        let instructions = Instructions(aliceInstructions)
        chatSession = LanguageModelSession(instructions: instructions)

        isReady = true
        #if DEBUG
        print("[FoundationModelsService] Sessions initialized successfully")
        #endif
    }
    #endif

    // MARK: - Chat (with context)

    /// Send a chat message with conversation history maintained
    /// - Parameter message: User's message
    /// - Returns: AI response
    func chat(message: String) async throws -> String {
        guard isAvailable && isReady else {
            throw AIServiceError.foundationModelsUnavailable
        }

        #if canImport(FoundationModels)
        guard let chatSession = chatSession else {
            throw AIServiceError.modelNotReady
        }

        isProcessing = true
        defer { isProcessing = false }

        return try await withRetry(maxAttempts: maxRetries) {
            let response = try await chatSession.respond(to: message)
            return response.content
        }
        #else
        throw AIServiceError.foundationModelsUnavailable
        #endif
    }

    /// Stream a chat response with conversation history
    /// - Parameter message: User's message
    /// - Returns: Async stream of response chunks
    func streamChat(message: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard isAvailable && isReady else {
                    continuation.finish(throwing: AIServiceError.foundationModelsUnavailable)
                    return
                }

                #if canImport(FoundationModels)
                guard let chatSession = chatSession else {
                    continuation.finish(throwing: AIServiceError.modelNotReady)
                    return
                }

                await MainActor.run { self.isProcessing = true }
                defer {
                    Task { @MainActor in self.isProcessing = false }
                }

                do {
                    // Correct Foundation Models streaming API
                    for try await partial in chatSession.streamResponse(to: message) {
                        continuation.yield(partial.content)
                    }
                    continuation.finish()
                } catch {
                    #if DEBUG
                    print("[FoundationModelsService] Stream chat failed: \(error)")
                    #endif
                    continuation.finish(throwing: error)
                }
                #else
                continuation.finish(throwing: AIServiceError.foundationModelsUnavailable)
                #endif
            }
        }
    }

    /// Reset chat session (clears conversation history)
    func resetChatSession() {
        #if canImport(FoundationModels)
        let instructions = Instructions(aliceInstructions)
        chatSession = LanguageModelSession(instructions: instructions)
        #if DEBUG
        print("[FoundationModelsService] Chat session reset")
        #endif
        #endif
    }

    // MARK: - Text Generation (stateless)

    /// Generate text from a prompt (no conversation history)
    /// - Parameter prompt: The input prompt
    /// - Returns: Generated text response
    func generateText(prompt: String) async throws -> String {
        guard isAvailable && isReady else {
            throw AIServiceError.foundationModelsUnavailable
        }

        #if canImport(FoundationModels)
        guard let session = session else {
            throw AIServiceError.modelNotReady
        }

        isProcessing = true
        defer { isProcessing = false }

        return try await withRetry(maxAttempts: maxRetries) {
            let response = try await session.respond(to: prompt)
            return response.content
        }
        #else
        throw AIServiceError.foundationModelsUnavailable
        #endif
    }

    // MARK: - Sentiment Analysis

    /// Analyze sentiment of text using structured output
    /// - Parameter text: Text to analyze
    /// - Returns: Sentiment analysis result
    func analyzeSentiment(text: String) async throws -> SentimentResult {
        guard isAvailable && isReady else {
            throw AIServiceError.foundationModelsUnavailable
        }

        #if canImport(FoundationModels)
        guard let session = session else {
            throw AIServiceError.modelNotReady
        }

        isProcessing = true
        defer { isProcessing = false }

        return try await withRetry(maxAttempts: maxRetries) {
            let response = try await session.respond(
                to: "Analyze the sentiment of this text: \"\(text)\"",
                generating: SentimentResult.self
            )
            return response.content
        }
        #else
        throw AIServiceError.foundationModelsUnavailable
        #endif
    }

    // MARK: - Summarization

    /// Summarize text
    /// - Parameters:
    ///   - text: Text to summarize
    ///   - maxLength: Maximum summary length in words
    /// - Returns: Summary result
    func summarize(text: String, maxLength: Int = 100) async throws -> SummaryResult {
        guard isAvailable && isReady else {
            throw AIServiceError.foundationModelsUnavailable
        }

        #if canImport(FoundationModels)
        guard let session = session else {
            throw AIServiceError.modelNotReady
        }

        isProcessing = true
        defer { isProcessing = false }

        return try await withRetry(maxAttempts: maxRetries) {
            let prompt = "Summarize the following text in no more than \(maxLength) words. Extract key points: \"\(text)\""
            let response = try await session.respond(
                to: prompt,
                generating: SummaryResult.self
            )
            return response.content
        }
        #else
        throw AIServiceError.foundationModelsUnavailable
        #endif
    }

    // MARK: - Post Analysis (for hybrid mode)

    /// Analyze a post locally before sending to server for enhancement
    /// - Parameter content: Post content text
    /// - Returns: Local analysis result
    func analyzePostLocally(content: String) async throws -> LocalPostAnalysis {
        guard isAvailable && isReady else {
            throw AIServiceError.foundationModelsUnavailable
        }

        #if canImport(FoundationModels)
        guard let session = session else {
            throw AIServiceError.modelNotReady
        }

        isProcessing = true
        defer { isProcessing = false }

        return try await withRetry(maxAttempts: maxRetries) {
            let prompt = """
            Analyze this social media post and extract:
            1. Main topics discussed
            2. Relevant hashtags
            3. Overall sentiment

            Post: "\(content)"
            """

            let response = try await session.respond(
                to: prompt,
                generating: LocalPostAnalysis.self
            )
            return response.content
        }
        #else
        throw AIServiceError.foundationModelsUnavailable
        #endif
    }

    // MARK: - Streaming Response (stateless)

    /// Stream a response for longer generation tasks (no conversation history)
    /// - Parameter prompt: Input prompt
    /// - Returns: Async stream of response chunks
    func streamResponse(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard isAvailable && isReady else {
                    continuation.finish(throwing: AIServiceError.foundationModelsUnavailable)
                    return
                }

                #if canImport(FoundationModels)
                guard let session = session else {
                    continuation.finish(throwing: AIServiceError.modelNotReady)
                    return
                }

                await MainActor.run { self.isProcessing = true }
                defer {
                    Task { @MainActor in self.isProcessing = false }
                }

                do {
                    // Correct Foundation Models streaming API
                    for try await partial in session.streamResponse(to: prompt) {
                        continuation.yield(partial.content)
                    }
                    continuation.finish()
                } catch {
                    #if DEBUG
                    print("[FoundationModelsService] Stream failed: \(error)")
                    #endif
                    continuation.finish(throwing: error)
                }
                #else
                continuation.finish(throwing: AIServiceError.foundationModelsUnavailable)
                #endif
            }
        }
    }

    // MARK: - Simple Q&A

    /// Answer a simple question (offline-capable)
    /// - Parameter question: User's question
    /// - Returns: Answer text
    func answerQuestion(question: String) async throws -> String {
        guard isAvailable && isReady else {
            throw AIServiceError.foundationModelsUnavailable
        }

        #if canImport(FoundationModels)
        guard let session = session else {
            throw AIServiceError.modelNotReady
        }

        isProcessing = true
        defer { isProcessing = false }

        return try await withRetry(maxAttempts: maxRetries) {
            let response = try await session.respond(to: question)
            return response.content
        }
        #else
        throw AIServiceError.foundationModelsUnavailable
        #endif
    }

    // MARK: - Keyword Extraction

    /// Extract keywords from text
    /// - Parameter text: Input text
    /// - Returns: List of extracted keywords
    func extractKeywords(text: String) async throws -> [String] {
        guard isAvailable && isReady else {
            throw AIServiceError.foundationModelsUnavailable
        }

        #if canImport(FoundationModels)
        guard let session = session else {
            throw AIServiceError.modelNotReady
        }

        isProcessing = true
        defer { isProcessing = false }

        return try await withRetry(maxAttempts: maxRetries) {
            let response = try await session.respond(
                to: "Extract the main keywords from this text: \"\(text)\"",
                generating: KeywordExtractionResult.self
            )
            return response.content.keywords
        }
        #else
        throw AIServiceError.foundationModelsUnavailable
        #endif
    }

    // MARK: - Tool-Enabled Chat

    /// Chat with tool access for dynamic data fetching
    /// - Parameter message: User's message
    /// - Returns: AI response with potential tool usage
    func chatWithTools(message: String) async throws -> String {
        guard isAvailable && isReady else {
            throw AIServiceError.foundationModelsUnavailable
        }

        #if canImport(FoundationModels)
        let sessionManager = AISessionManager.shared

        // Register tools if not already done
        let toolsRegistry = AIToolsRegistry.shared
        sessionManager.registerTools(toolsRegistry.allTools)

        let toolSession = sessionManager.session(for: .toolEnabled)

        isProcessing = true
        defer { isProcessing = false }

        return try await withRetry(maxAttempts: maxRetries) {
            let response = try await toolSession.respond(to: message)
            return response.content
        }
        #else
        throw AIServiceError.foundationModelsUnavailable
        #endif
    }

    /// Stream chat with tools
    /// - Parameter message: User's message
    /// - Returns: Async stream of response chunks
    func streamChatWithTools(message: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard self.isAvailable && self.isReady else {
                    continuation.finish(throwing: AIServiceError.foundationModelsUnavailable)
                    return
                }

                #if canImport(FoundationModels)
                let sessionManager = AISessionManager.shared
                let toolsRegistry = AIToolsRegistry.shared
                sessionManager.registerTools(toolsRegistry.allTools)

                let toolSession = sessionManager.session(for: .toolEnabled)

                await MainActor.run { self.isProcessing = true }
                defer {
                    Task { @MainActor in self.isProcessing = false }
                }

                do {
                    for try await partial in toolSession.streamResponse(to: message) {
                        continuation.yield(partial.content)
                    }
                    continuation.finish()
                } catch {
                    #if DEBUG
                    print("[FoundationModelsService] Stream chat with tools failed: \(error)")
                    #endif
                    continuation.finish(throwing: error)
                }
                #else
                continuation.finish(throwing: AIServiceError.foundationModelsUnavailable)
                #endif
            }
        }
    }

    // MARK: - Structured Output Generation

    /// Generate post suggestions
    /// - Parameters:
    ///   - topic: Topic for the post
    ///   - style: Style of the post (casual, professional, etc.)
    /// - Returns: Structured post suggestion
    func generatePostSuggestion(topic: String, style: String = "casual") async throws -> PostSuggestion {
        guard isAvailable && isReady else {
            throw AIServiceError.foundationModelsUnavailable
        }

        #if canImport(FoundationModels)
        guard let session = session else {
            throw AIServiceError.modelNotReady
        }

        isProcessing = true
        defer { isProcessing = false }

        let prompt = """
            Generate a social media post suggestion about "\(topic)"
            in a \(style) style for the ICERED platform.
            Make it engaging and include relevant hashtags.
            """

        return try await withRetry(maxAttempts: maxRetries) {
            let response = try await session.respond(
                to: prompt,
                generating: PostSuggestion.self
            )
            return response.content
        }
        #else
        throw AIServiceError.foundationModelsUnavailable
        #endif
    }

    /// Classify content
    /// - Parameter content: Content to classify
    /// - Returns: Structured classification result
    func classifyContent(_ content: String) async throws -> ContentClassification {
        guard isAvailable && isReady else {
            throw AIServiceError.foundationModelsUnavailable
        }

        #if canImport(FoundationModels)
        guard let session = session else {
            throw AIServiceError.modelNotReady
        }

        isProcessing = true
        defer { isProcessing = false }

        return try await withRetry(maxAttempts: maxRetries) {
            let response = try await session.respond(
                to: "Classify this social media content for category, tone, and audience: \"\(content)\"",
                generating: ContentClassification.self
            )
            return response.content
        }
        #else
        throw AIServiceError.foundationModelsUnavailable
        #endif
    }

    /// Generate hashtag recommendations
    /// - Parameter content: Content to analyze for hashtags
    /// - Returns: Structured hashtag recommendation
    func recommendHashtags(for content: String) async throws -> HashtagRecommendation {
        guard isAvailable && isReady else {
            throw AIServiceError.foundationModelsUnavailable
        }

        #if canImport(FoundationModels)
        guard let session = session else {
            throw AIServiceError.modelNotReady
        }

        isProcessing = true
        defer { isProcessing = false }

        return try await withRetry(maxAttempts: maxRetries) {
            let response = try await session.respond(
                to: "Recommend hashtags for this social media post on ICERED: \"\(content)\"",
                generating: HashtagRecommendation.self
            )
            return response.content
        }
        #else
        throw AIServiceError.foundationModelsUnavailable
        #endif
    }

    /// Enhance post content
    /// - Parameter content: Original post content
    /// - Returns: Structured enhancement result
    func enhancePost(_ content: String) async throws -> PostEnhancementResult {
        guard isAvailable && isReady else {
            throw AIServiceError.foundationModelsUnavailable
        }

        #if canImport(FoundationModels)
        guard let session = session else {
            throw AIServiceError.modelNotReady
        }

        isProcessing = true
        defer { isProcessing = false }

        return try await withRetry(maxAttempts: maxRetries) {
            let response = try await session.respond(
                to: """
                    Enhance this social media post for better engagement.
                    Fix any errors and suggest improvements: "\(content)"
                    """,
                generating: PostEnhancementResult.self
            )
            return response.content
        }
        #else
        throw AIServiceError.foundationModelsUnavailable
        #endif
    }

    /// Generate reply suggestions
    /// - Parameters:
    ///   - message: Message to reply to
    ///   - context: Optional context about the conversation
    /// - Returns: Structured reply suggestions
    func suggestReplies(to message: String, context: String? = nil) async throws -> ReplySuggestion {
        guard isAvailable && isReady else {
            throw AIServiceError.foundationModelsUnavailable
        }

        #if canImport(FoundationModels)
        guard let session = session else {
            throw AIServiceError.modelNotReady
        }

        isProcessing = true
        defer { isProcessing = false }

        var prompt = "Suggest replies to this message: \"\(message)\""
        if let context = context {
            prompt += "\nContext: \(context)"
        }

        return try await withRetry(maxAttempts: maxRetries) {
            let response = try await session.respond(
                to: prompt,
                generating: ReplySuggestion.self
            )
            return response.content
        }
        #else
        throw AIServiceError.foundationModelsUnavailable
        #endif
    }

    /// Generate caption suggestions for media
    /// - Parameters:
    ///   - description: Description of the media content
    ///   - mediaType: Type of media (image, video)
    /// - Returns: Structured caption suggestions
    func generateCaption(for description: String, mediaType: String = "image") async throws -> CaptionSuggestion {
        guard isAvailable && isReady else {
            throw AIServiceError.foundationModelsUnavailable
        }

        #if canImport(FoundationModels)
        guard let session = session else {
            throw AIServiceError.modelNotReady
        }

        isProcessing = true
        defer { isProcessing = false }

        return try await withRetry(maxAttempts: maxRetries) {
            let response = try await session.respond(
                to: "Generate caption options for a \(mediaType) that shows: \"\(description)\"",
                generating: CaptionSuggestion.self
            )
            return response.content
        }
        #else
        throw AIServiceError.foundationModelsUnavailable
        #endif
    }

    // MARK: - Retry Helper

    /// Execute an async operation with retry logic
    private func withRetry<T>(
        maxAttempts: Int,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                #if DEBUG
                print("[FoundationModelsService] Attempt \(attempt) failed: \(error)")
                #endif

                // Don't retry on certain errors
                if case AIServiceError.foundationModelsUnavailable = error { throw error }
                if case AIServiceError.modelNotReady = error { throw error }

                // Wait before retrying
                if attempt < maxAttempts {
                    try await Task.sleep(for: .seconds(retryDelay * Double(attempt)))
                }
            }
        }

        throw lastError ?? AIServiceError.generationFailed("Unknown error after \(maxAttempts) attempts")
    }
}

// MARK: - Fallback for older iOS versions

/// Fallback service for devices that don't support Foundation Models
@MainActor
final class FoundationModelsFallback {
    static let shared = FoundationModelsFallback()

    var isAvailable: Bool { false }
    var isReady: Bool { false }

    func generateText(prompt: String) async throws -> String {
        throw AIServiceError.foundationModelsUnavailable
    }

    func chat(message: String) async throws -> String {
        throw AIServiceError.foundationModelsUnavailable
    }

    func analyzeSentiment(text: String) async throws -> SentimentResult {
        throw AIServiceError.foundationModelsUnavailable
    }

    func summarize(text: String, maxLength: Int) async throws -> SummaryResult {
        throw AIServiceError.foundationModelsUnavailable
    }

    func resetChatSession() {
        // No-op for fallback
    }
}
