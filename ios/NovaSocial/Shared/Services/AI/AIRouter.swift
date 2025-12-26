import Foundation
import Network

// MARK: - AI Router

/// Routes AI tasks to the appropriate service (on-device or remote)
@Observable
@MainActor
final class AIRouter {

    // MARK: - Singleton

    static let shared = AIRouter()

    // MARK: - Properties

    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.icered.ai.network")

    private(set) var isOnline: Bool = true
    private(set) var preferOnDevice: Bool = true

    /// Whether Foundation Models are available on this device
    var isOnDeviceAvailable: Bool {
        if #available(iOS 26.0, *) {
            return FoundationModelsService.shared.isAvailable
        }
        return false
    }

    /// Whether on-device AI is ready to use
    var isOnDeviceReady: Bool {
        if #available(iOS 26.0, *) {
            return FoundationModelsService.shared.isReady
        }
        return false
    }

    // MARK: - Initialization

    private init() {
        setupNetworkMonitoring()
    }

    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
            }
        }
        networkMonitor.start(queue: monitorQueue)
    }

    // MARK: - Routing Logic

    /// Determine which service to use for a given task type
    /// - Parameters:
    ///   - taskType: The type of AI task
    ///   - options: Task options
    /// - Returns: The recommended service type
    func route(taskType: AITaskType, options: AITaskOptions = .default) -> AIServiceType {
        // If explicitly preferring on-device and it's available
        if options.preferOnDevice && isOnDeviceAvailable && isOnDeviceReady {
            switch taskType {
            case .sentiment, .summarize, .keywordExtraction, .simpleQA:
                // These tasks work well on-device
                return .onDevice

            case .postEnhancement:
                // Hybrid: local analysis + remote enhancement
                return .hybrid

            case .chat, .imageAnalysis:
                // Complex tasks require remote processing
                if isOnline {
                    return .remote
                } else if options.allowFallback {
                    // Try on-device as fallback for simple queries
                    return .onDevice
                } else {
                    return .remote // Will fail with network error
                }
            }
        }

        // Default to remote if on-device not available
        return .remote
    }

    // MARK: - Task Processing

    /// Process an AI task using the appropriate service
    /// - Parameter task: The AI task to process
    /// - Returns: AI response
    func process(task: AITask) async throws -> AIResponse {
        let startTime = Date()
        let serviceType = route(taskType: task.type, options: task.options)

        #if DEBUG
        print("[AIRouter] Processing \(task.type) via \(serviceType)")
        #endif

        do {
            let result: String

            switch serviceType {
            case .onDevice:
                result = try await processOnDevice(task: task)

            case .remote:
                result = try await processRemote(task: task)

            case .hybrid:
                result = try await processHybrid(task: task)
            }

            let processingTime = Date().timeIntervalSince(startTime)
            return AIResponse(
                text: result,
                source: serviceType,
                processingTime: processingTime
            )

        } catch let error as AIServiceError {
            // Handle fallback if allowed
            if task.options.allowFallback && serviceType == .onDevice {
                #if DEBUG
                print("[AIRouter] On-device failed, falling back to remote: \(error)")
                #endif
                return try await processFallback(task: task, startTime: startTime)
            }
            throw error

        } catch {
            throw AIServiceError.generationFailed(error.localizedDescription)
        }
    }

    // MARK: - On-Device Processing

    private func processOnDevice(task: AITask) async throws -> String {
        guard #available(iOS 26.0, *) else {
            throw AIServiceError.foundationModelsUnavailable
        }

        let service = FoundationModelsService.shared

        switch task.type {
        case .sentiment:
            let result = try await service.analyzeSentiment(text: task.input)
            return formatSentimentResult(result)

        case .summarize:
            let result = try await service.summarize(text: task.input)
            return result.summary

        case .keywordExtraction:
            let keywords = try await service.extractKeywords(text: task.input)
            return keywords.joined(separator: ", ")

        case .simpleQA:
            return try await service.answerQuestion(question: task.input)

        case .chat, .imageAnalysis, .postEnhancement:
            // These should be routed to remote or hybrid
            throw AIServiceError.fallbackToRemote
        }
    }

    // MARK: - Remote Processing

    private func processRemote(task: AITask) async throws -> String {
        guard isOnline else {
            throw AIServiceError.networkUnavailable
        }

        let aliceService = AliceService.shared

        switch task.type {
        case .chat, .simpleQA:
            let response = try await aliceService.sendMessage(task.input)
            return response.message

        case .imageAnalysis:
            if let imageData = task.imageData {
                let response = try await aliceService.enhancePostWithImage(
                    content: task.input,
                    imageData: [imageData]
                )
                return response.enhanced_content ?? task.input
            } else {
                let response = try await aliceService.enhancePost(content: task.input)
                return response.enhanced_content ?? task.input
            }

        case .postEnhancement:
            let response = try await aliceService.enhancePost(content: task.input)
            return response.enhanced_content ?? task.input

        case .sentiment, .summarize, .keywordExtraction:
            // Use chat endpoint for these if on-device not available
            let prompt = buildPromptForTask(task)
            let response = try await aliceService.sendMessage(prompt)
            return response.message
        }
    }

    // MARK: - Hybrid Processing

    private func processHybrid(task: AITask) async throws -> String {
        guard #available(iOS 26.0, *) else {
            // Fall back to pure remote
            return try await processRemote(task: task)
        }

        // For post enhancement: local analysis first, then remote refinement
        if task.type == .postEnhancement {
            let service = FoundationModelsService.shared

            // Step 1: Local analysis (fast, no network)
            let localAnalysis: LocalPostAnalysis?
            do {
                localAnalysis = try await service.analyzePostLocally(content: task.input)
                #if DEBUG
                print("[AIRouter] Local analysis: \(localAnalysis?.detectedTopics ?? [])")
                #endif
            } catch {
                #if DEBUG
                print("[AIRouter] Local analysis failed, continuing with remote only: \(error)")
                #endif
                localAnalysis = nil
            }

            // Step 2: Remote enhancement with local context
            guard isOnline else {
                // Offline: return local suggestions only
                if let analysis = localAnalysis {
                    return formatLocalAnalysis(analysis)
                }
                throw AIServiceError.networkUnavailable
            }

            // Include local analysis in remote request for better results
            let enhancedPrompt: String
            if let analysis = localAnalysis {
                enhancedPrompt = """
                Content: \(task.input)

                Local analysis detected:
                - Topics: \(analysis.detectedTopics.joined(separator: ", "))
                - Sentiment: \(analysis.sentiment)
                - Suggested hashtags: \(analysis.suggestedHashtags.joined(separator: " "))

                Please enhance this post considering the above analysis.
                """
            } else {
                enhancedPrompt = task.input
            }

            let aliceService = AliceService.shared
            let response = try await aliceService.enhancePost(content: enhancedPrompt)
            return response.enhanced_content ?? task.input
        }

        // For other tasks, just use remote
        return try await processRemote(task: task)
    }

    // MARK: - Fallback Processing

    private func processFallback(task: AITask, startTime: Date) async throws -> AIResponse {
        guard isOnline else {
            throw AIServiceError.networkUnavailable
        }

        let result = try await processRemote(task: task)
        let processingTime = Date().timeIntervalSince(startTime)

        return AIResponse(
            text: result,
            source: .remote,
            processingTime: processingTime,
            metadata: ["fallback": true]
        )
    }

    // MARK: - Helpers

    private func buildPromptForTask(_ task: AITask) -> String {
        switch task.type {
        case .sentiment:
            return "Analyze the sentiment of this text and respond with 'positive', 'negative', or 'neutral': \(task.input)"
        case .summarize:
            return "Summarize this text in 2-3 sentences: \(task.input)"
        case .keywordExtraction:
            return "Extract the main keywords from this text as a comma-separated list: \(task.input)"
        default:
            return task.input
        }
    }

    private func formatSentimentResult(_ result: SentimentResult) -> String {
        """
        Sentiment: \(result.sentiment)
        Confidence: \(Int(result.confidence * 100))%
        Key phrases: \(result.keyPhrases.joined(separator: ", "))
        """
    }

    private func formatLocalAnalysis(_ analysis: LocalPostAnalysis) -> String {
        """
        Topics: \(analysis.detectedTopics.joined(separator: ", "))
        Sentiment: \(analysis.sentiment)
        Suggested hashtags: \(analysis.suggestedHashtags.joined(separator: " "))
        Suggestions: \(analysis.suggestions.joined(separator: "; "))
        """
    }

    // MARK: - Configuration

    /// Set preference for on-device processing
    /// - Parameter prefer: Whether to prefer on-device AI when available
    func setOnDevicePreference(_ prefer: Bool) {
        preferOnDevice = prefer
        #if DEBUG
        print("[AIRouter] On-device preference set to: \(prefer)")
        #endif
    }
}

// MARK: - Convenience Extensions

extension AIRouter {

    // MARK: - Chat Methods

    /// Chat with automatic routing (uses on-device with history when available)
    /// - Parameter message: User's message
    /// - Returns: AI response text
    func chat(_ message: String) async throws -> String {
        // Prefer on-device chat if available (maintains conversation history)
        if #available(iOS 26.0, *), isOnDeviceAvailable && isOnDeviceReady {
            return try await FoundationModelsService.shared.chat(message: message)
        }

        // Fallback to remote
        guard isOnline else {
            throw AIServiceError.networkUnavailable
        }

        let response = try await AliceService.shared.sendMessage(message)
        return response.message
    }

    /// Stream chat response with automatic routing
    /// - Parameter message: User's message
    /// - Returns: Async stream of response chunks
    func streamChat(_ message: String) -> AsyncThrowingStream<String, Error> {
        // Prefer on-device streaming if available
        if #available(iOS 26.0, *), isOnDeviceAvailable && isOnDeviceReady {
            return FoundationModelsService.shared.streamChat(message: message)
        }

        // Fallback: single response as stream
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard self.isOnline else {
                        continuation.finish(throwing: AIServiceError.networkUnavailable)
                        return
                    }
                    let response = try await AliceService.shared.sendMessage(message)
                    continuation.yield(response.message)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Reset the on-device chat session (clears conversation history)
    func resetChatSession() {
        if #available(iOS 26.0, *) {
            FoundationModelsService.shared.resetChatSession()
        }
    }

    // MARK: - Sentiment Analysis

    /// Quick sentiment analysis with automatic routing
    func analyzeSentiment(_ text: String) async throws -> SentimentResult {
        if #available(iOS 26.0, *), isOnDeviceAvailable && isOnDeviceReady {
            return try await FoundationModelsService.shared.analyzeSentiment(text: text)
        }

        // Fallback: parse remote response into SentimentResult
        let task = AITask(type: .sentiment, input: text)
        let response = try await process(task: task)

        // Simple parsing of remote response
        let sentiment = response.text.lowercased().contains("positive") ? "positive" :
                       response.text.lowercased().contains("negative") ? "negative" : "neutral"

        return SentimentResult(
            sentiment: sentiment,
            confidence: 0.8,
            keyPhrases: []
        )
    }

    /// Quick summarization with automatic routing
    func summarize(_ text: String, maxLength: Int = 100) async throws -> String {
        if #available(iOS 26.0, *), isOnDeviceAvailable && isOnDeviceReady {
            let result = try await FoundationModelsService.shared.summarize(text: text, maxLength: maxLength)
            return result.summary
        }

        let task = AITask(type: .summarize, input: text)
        let response = try await process(task: task)
        return response.text
    }

    /// Enhance a post with hybrid processing
    func enhancePost(_ content: String, imageData: [Data]? = nil) async throws -> HybridPostEnhancementSuggestion {
        let task = AITask(
            type: .postEnhancement,
            input: content,
            imageData: imageData?.first
        )

        let response = try await process(task: task)

        // Parse the response into a structured suggestion
        return HybridPostEnhancementSuggestion(
            enhancedContent: response.text,
            hashtags: extractHashtags(from: response.text),
            sentiment: "positive", // Default
            improvements: [],
            source: response.source
        )
    }

    private func extractHashtags(from text: String) -> [String] {
        let pattern = "#\\w+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        return matches.compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }

    // MARK: - Tool-Enabled Chat

    /// Chat with tool access for dynamic data fetching
    /// Falls back to regular chat if tools unavailable
    /// - Parameter message: User's message
    /// - Returns: AI response text
    func chatWithTools(_ message: String) async throws -> String {
        if #available(iOS 26.0, *), isOnDeviceAvailable && isOnDeviceReady {
            return try await FoundationModelsService.shared.chatWithTools(message: message)
        }

        // Fallback to regular remote chat
        return try await chat(message)
    }

    /// Stream chat with tools
    /// - Parameter message: User's message
    /// - Returns: Async stream of response chunks
    func streamChatWithTools(_ message: String) -> AsyncThrowingStream<String, Error> {
        if #available(iOS 26.0, *), isOnDeviceAvailable && isOnDeviceReady {
            return FoundationModelsService.shared.streamChatWithTools(message: message)
        }

        // Fallback to regular stream
        return streamChat(message)
    }

    // MARK: - Structured Output Methods

    /// Generate post suggestions using on-device AI
    /// - Parameters:
    ///   - topic: Topic for the post
    ///   - style: Style of the post
    /// - Returns: Structured post suggestion
    func generatePostSuggestion(topic: String, style: String = "casual") async throws -> PostSuggestion {
        guard #available(iOS 26.0, *), isOnDeviceAvailable && isOnDeviceReady else {
            throw AIServiceError.foundationModelsUnavailable
        }
        return try await FoundationModelsService.shared.generatePostSuggestion(topic: topic, style: style)
    }

    /// Classify content using on-device AI
    /// - Parameter content: Content to classify
    /// - Returns: Structured classification result
    func classifyContent(_ content: String) async throws -> ContentClassification {
        guard #available(iOS 26.0, *), isOnDeviceAvailable && isOnDeviceReady else {
            throw AIServiceError.foundationModelsUnavailable
        }
        return try await FoundationModelsService.shared.classifyContent(content)
    }

    /// Recommend hashtags using on-device AI
    /// - Parameter content: Content to analyze
    /// - Returns: Structured hashtag recommendations
    func recommendHashtags(for content: String) async throws -> HashtagRecommendation {
        guard #available(iOS 26.0, *), isOnDeviceAvailable && isOnDeviceReady else {
            throw AIServiceError.foundationModelsUnavailable
        }
        return try await FoundationModelsService.shared.recommendHashtags(for: content)
    }

    /// Enhance post using on-device AI
    /// - Parameter content: Original post content
    /// - Returns: Structured enhancement result
    func enhancePostOnDevice(_ content: String) async throws -> PostEnhancementResult {
        guard #available(iOS 26.0, *), isOnDeviceAvailable && isOnDeviceReady else {
            throw AIServiceError.foundationModelsUnavailable
        }
        return try await FoundationModelsService.shared.enhancePost(content)
    }

    /// Suggest replies using on-device AI
    /// - Parameters:
    ///   - message: Message to reply to
    ///   - context: Optional context
    /// - Returns: Structured reply suggestions
    func suggestReplies(to message: String, context: String? = nil) async throws -> ReplySuggestion {
        guard #available(iOS 26.0, *), isOnDeviceAvailable && isOnDeviceReady else {
            throw AIServiceError.foundationModelsUnavailable
        }
        return try await FoundationModelsService.shared.suggestReplies(to: message, context: context)
    }

    /// Generate captions using on-device AI
    /// - Parameters:
    ///   - description: Description of the media
    ///   - mediaType: Type of media
    /// - Returns: Structured caption suggestions
    func generateCaption(for description: String, mediaType: String = "image") async throws -> CaptionSuggestion {
        guard #available(iOS 26.0, *), isOnDeviceAvailable && isOnDeviceReady else {
            throw AIServiceError.foundationModelsUnavailable
        }
        return try await FoundationModelsService.shared.generateCaption(for: description, mediaType: mediaType)
    }

    // MARK: - Session Management

    /// Reset the tool-enabled session
    func resetToolSession() {
        if #available(iOS 26.0, *) {
            AISessionManager.shared.resetSession(.toolEnabled)
        }
    }

    /// Reset all AI sessions
    func resetAllSessions() {
        if #available(iOS 26.0, *) {
            AISessionManager.shared.resetAllSessions()
        }
        resetChatSession()
    }
}
