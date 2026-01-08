import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - AI Session Manager

/// Manages language model sessions for different use cases
@available(iOS 26.0, *)
@Observable
@MainActor
final class AISessionManager {

    // MARK: - Singleton

    static let shared = AISessionManager()

    // MARK: - Properties

    #if canImport(FoundationModels)
    private var sessions: [AISessionType: LanguageModelSession] = [:]
    #endif

    private(set) var isReady: Bool = false

    // MARK: - Instructions

    /// Alice personality instructions for chat context
    private let aliceInstructions = """
    You are Alice, the AI assistant for Icered social app.
    Note: "Icered" is pronounced as "Ice-red" (two syllables).

    Personality:
    - Friendly, helpful, and concise
    - Respond in the user's language (detect from input)
    - Use casual but professional tone
    - Add relevant emoji sparingly when appropriate

    Capabilities:
    - Help users with the Icered app features
    - Search for posts, users, and trending topics using available tools
    - Provide content suggestions and recommendations
    - Assist with post creation and enhancement
    - Answer general questions

    Guidelines:
    - Keep responses brief (under 150 words unless detail is needed)
    - Be honest if you don't know something
    - Use available tools to fetch real-time data when appropriate
    - Never generate harmful or inappropriate content
    - When asked about specific content, use search tools before answering
    """

    /// Instructions for analysis tasks
    private let analysisInstructions = """
    You are a content analysis assistant for a social media platform.

    Guidelines:
    - Provide accurate, structured analysis
    - Focus on objectivity and precision
    - Be concise and actionable in suggestions
    - Consider the social media context (engagement, reach, virality)
    """

    // MARK: - Initialization

    private init() {
        #if canImport(FoundationModels)
        initializeSessions()
        #endif
    }

    // MARK: - Session Management

    #if canImport(FoundationModels)
    /// Initialize all session types
    private func initializeSessions() {
        // Create stateless session for analysis tasks
        sessions[.stateless] = LanguageModelSession(
            instructions: Instructions(analysisInstructions)
        )

        // Create conversational session with Alice personality
        sessions[.conversational] = LanguageModelSession(
            instructions: Instructions(aliceInstructions)
        )

        // Tool-enabled session will be created when tools are registered
        // via registerTools(_:) method

        isReady = true

        #if DEBUG
        print("[AISessionManager] Sessions initialized successfully")
        #endif
    }

    /// Get or create a session for the specified type
    /// - Parameter type: The type of session to retrieve
    /// - Returns: The language model session
    func session(for type: AISessionType) -> LanguageModelSession {
        if let existing = sessions[type] {
            return existing
        }

        let session = createSession(for: type)
        sessions[type] = session
        return session
    }

    /// Create a new session with appropriate configuration
    private func createSession(for type: AISessionType) -> LanguageModelSession {
        switch type {
        case .stateless:
            return LanguageModelSession(
                instructions: Instructions(analysisInstructions)
            )

        case .conversational:
            return LanguageModelSession(
                instructions: Instructions(aliceInstructions)
            )

        case .toolEnabled:
            // Will be configured with tools via registerTools
            return LanguageModelSession(
                instructions: Instructions(aliceInstructions)
            )
        }
    }

    /// Register tools with the tool-enabled session
    /// - Parameter tools: Array of tools to register
    func registerTools(_ tools: [any Tool]) {
        sessions[.toolEnabled] = LanguageModelSession(
            tools: tools,
            instructions: Instructions(aliceInstructions)
        )

        #if DEBUG
        print("[AISessionManager] Registered \(tools.count) tools with session")
        #endif
    }

    /// Reset a specific session type (clears conversation history)
    /// - Parameter type: The session type to reset
    func resetSession(_ type: AISessionType) {
        sessions[type] = createSession(for: type)

        #if DEBUG
        print("[AISessionManager] Reset session: \(type)")
        #endif
    }

    /// Reset all sessions
    func resetAllSessions() {
        sessions.removeAll()
        initializeSessions()

        #if DEBUG
        print("[AISessionManager] Reset all sessions")
        #endif
    }

    /// Get transcript from a session
    /// - Parameter type: The session type
    /// - Returns: The session transcript, or nil if session doesn't exist
    func getTranscript(for type: AISessionType) -> Transcript? {
        guard let session = sessions[type] else { return nil }
        return session.transcript
    }

    /// Check if a session has conversation history
    /// - Parameter type: The session type
    /// - Returns: True if the session has previous messages
    func hasHistory(for type: AISessionType) -> Bool {
        guard let session = sessions[type] else { return false }
        // The transcript is a collection, check if it's empty
        var hasContent = false
        for _ in session.transcript {
            hasContent = true
            break
        }
        return hasContent
    }
    #endif
}

// MARK: - Fallback for older iOS versions

@MainActor
final class AISessionManagerFallback {
    static let shared = AISessionManagerFallback()

    var isReady: Bool { false }

    private init() {}

    func resetSession(_ type: AISessionType) {
        // No-op for fallback
    }

    func resetAllSessions() {
        // No-op for fallback
    }
}
