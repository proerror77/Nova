import Foundation

// MARK: - WebSocket State Actor (Thread-safe WebSocket management)

/// Actor for thread-safe WebSocket state management
actor WebSocketStateManager {
    private var webSocketTask: URLSessionWebSocketTask?
    private var isConnected: Bool = false

    func getTask() -> URLSessionWebSocketTask? {
        return webSocketTask
    }

    func setTask(_ task: URLSessionWebSocketTask?) {
        webSocketTask = task
    }

    func getIsConnected() -> Bool {
        return isConnected
    }

    func setIsConnected(_ connected: Bool) {
        isConnected = connected
    }

    func cancelTask() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
    }
}
