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
    #endif

    private(set) var isAvailable: Bool = false
    private(set) var isReady: Bool = false
    private(set) var isProcessing: Bool = false

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
            await initializeSession()
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
    /// Initialize the language model session
    private func initializeSession() async {
        do {
            session = LanguageModelSession()
            isReady = true
            #if DEBUG
            print("[FoundationModelsService] Session initialized successfully")
            #endif
        } catch {
            isReady = false
            #if DEBUG
            print("[FoundationModelsService] Failed to initialize session: \(error)")
            #endif
        }
    }
    #endif

    // MARK: - Text Generation

    /// Generate text from a prompt
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

        do {
            let response = try await session.respond(to: prompt)
            return response.content
        } catch {
            #if DEBUG
            print("[FoundationModelsService] Generation failed: \(error)")
            #endif
            throw AIServiceError.generationFailed(error.localizedDescription)
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

        do {
            let response = try await session.respond(
                to: "Analyze the sentiment of this text: \"\(text)\"",
                generating: SentimentResult.self
            )
            return response.content
        } catch {
            #if DEBUG
            print("[FoundationModelsService] Sentiment analysis failed: \(error)")
            #endif
            throw AIServiceError.generationFailed(error.localizedDescription)
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

        do {
            let prompt = "Summarize the following text in no more than \(maxLength) words. Extract key points: \"\(text)\""
            let response = try await session.respond(
                to: prompt,
                generating: SummaryResult.self
            )
            return response.content
        } catch {
            #if DEBUG
            print("[FoundationModelsService] Summarization failed: \(error)")
            #endif
            throw AIServiceError.generationFailed(error.localizedDescription)
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

        do {
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
        } catch {
            #if DEBUG
            print("[FoundationModelsService] Post analysis failed: \(error)")
            #endif
            throw AIServiceError.generationFailed(error.localizedDescription)
        }
        #else
        throw AIServiceError.foundationModelsUnavailable
        #endif
    }

    // MARK: - Streaming Response

    /// Stream a response for longer generation tasks
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

                isProcessing = true
                defer {
                    Task { @MainActor in
                        self.isProcessing = false
                    }
                }

                do {
                    let stream = session.streamResponse(to: prompt)
                    for try await chunk in stream {
                        continuation.yield(chunk.content)
                    }
                    continuation.finish()
                } catch {
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

        do {
            let response = try await session.respond(to: question)
            return response.content
        } catch {
            throw AIServiceError.generationFailed(error.localizedDescription)
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

        do {
            let response = try await session.respond(
                to: "Extract the main keywords from this text: \"\(text)\"",
                generating: KeywordExtractionResult.self
            )
            return response.content.keywords
        } catch {
            throw AIServiceError.generationFailed(error.localizedDescription)
        }
        #else
        throw AIServiceError.foundationModelsUnavailable
        #endif
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

    func analyzeSentiment(text: String) async throws -> SentimentResult {
        throw AIServiceError.foundationModelsUnavailable
    }

    func summarize(text: String, maxLength: Int) async throws -> SummaryResult {
        throw AIServiceError.foundationModelsUnavailable
    }
}
