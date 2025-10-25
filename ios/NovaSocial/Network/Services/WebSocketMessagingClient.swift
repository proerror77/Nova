import Foundation

/// 连接状态枚举
enum WebSocketConnectionState {
    case disconnected
    case connecting
    case connected
    case failed(Error)
}

/// WebSocketMessagingClient - wraps URLSessionWebSocketTask for messaging with auto-reconnect
final class WebSocketMessagingClient: NSObject, URLSessionDelegate, @unchecked Sendable {
    private var task: URLSessionWebSocketTask?
    private var session: URLSession!
    private let buffer = OrderingBuffer()

    // === CONNECTION STATE ===
    private var connectionState: WebSocketConnectionState = .disconnected
    private var reconnectAttempts: Int = 0
    private let maxReconnectAttempts = 5
    private var reconnectTimer: Timer?

    // === CONNECTION PARAMETERS ===
    private var baseURL: URL?
    private var conversationId: UUID?
    private var userId: UUID?
    private var token: String?

    // === CALLBACKS ===
    var onMessage: ((MessageDto) -> Void)?
    var onTyping: ((UUID, UUID) -> Void)?
    var onOpen: (() async -> Void)?  // 注意：现在是异步回调，用于支持 drain()
    var onClose: (() -> Void)?
    var onStateChange: ((WebSocketConnectionState) -> Void)?

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    deinit {
        reconnectTimer?.invalidate()
    }

    // MARK: - Connection Management

    func connect(baseURL: URL, conversationId: UUID, userId: UUID, token: String? = nil) {
        // 保存连接参数，用于重连
        self.baseURL = baseURL
        self.conversationId = conversationId
        self.userId = userId
        self.token = token

        performConnect(baseURL: baseURL, conversationId: conversationId, userId: userId, token: token)
    }

    private func performConnect(baseURL: URL, conversationId: UUID, userId: UUID, token: String? = nil) {
        updateConnectionState(.connecting)

        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        comps.scheme = (baseURL.scheme == "https") ? "wss" : "ws"
        comps.path = "/ws"
        comps.queryItems = [
            URLQueryItem(name: "conversation_id", value: conversationId.uuidString),
            URLQueryItem(name: "user_id", value: userId.uuidString)
        ]
        if let token { comps.queryItems?.append(URLQueryItem(name: "token", value: token)) }
        guard let url = comps.url else {
            updateConnectionState(.failed(NSError(domain: "WebSocketClient", code: -1, userInfo: nil)))
            return
        }

        task?.cancel(with: .goingAway, reason: nil)
        task = session.webSocketTask(with: url)
        task?.resume()
        receiveLoop()

        // === CRITICAL FIX: Call onOpen asynchronously to support drain() ===
        // 异步调用 onOpen，允许它执行 await queue.drain()
        Task {
            await self.onOpen?()
            self.updateConnectionState(.connected)
            self.reconnectAttempts = 0  // 重置重连计数
        }
    }

    func disconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        updateConnectionState(.disconnected)
        onClose?()
    }

    func sendTyping(conversationId: UUID, userId: UUID) {
        let obj: [String: Any] = [
            "type": "typing",
            "conversation_id": conversationId.uuidString,
            "user_id": userId.uuidString
        ]
        if let data = try? JSONSerialization.data(withJSONObject: obj), let text = String(data: data, encoding: .utf8) {
            task?.send(.string(text)) { _ in }
        }
    }

    // MARK: - Connection State Management

    private func updateConnectionState(_ state: WebSocketConnectionState) {
        connectionState = state
        onStateChange?(state)
        logWS("Connection state changed: \(state)")
    }

    func getConnectionState() -> WebSocketConnectionState {
        connectionState
    }

    // MARK: - Receive Loop

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.handleConnectionFailure(error)
            case .success(let msg):
                switch msg {
                case .string(let text):
                    self.handleText(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) { self.handleText(text) }
                @unknown default:
                    break
                }
                self.receiveLoop()
            }
        }
    }

    private func handleConnectionFailure(_ error: Error) {
        logWS("❌ WebSocket connection failed: \(error)")
        updateConnectionState(.failed(error))
        onClose?()

        // 尝试自动重连
        attemptReconnect()
    }

    // MARK: - Auto-Reconnect with Exponential Backoff

    private func attemptReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            logWS("❌ Max reconnection attempts reached (\(maxReconnectAttempts))")
            updateConnectionState(.failed(NSError(domain: "WebSocketClient", code: -2, userInfo: ["reason": "Max reconnect attempts"])))
            return
        }

        reconnectAttempts += 1

        // 指数退避：1s, 2s, 4s, 8s, 16s
        let delaySeconds = pow(2.0, Double(reconnectAttempts - 1))
        logWS("🔄 Scheduling reconnect attempt \(reconnectAttempts)/\(maxReconnectAttempts) in \(Int(delaySeconds))s")

        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delaySeconds, repeats: false) { [weak self] _ in
            self?.performReconnect()
        }
    }

    private func performReconnect() {
        guard let baseURL = baseURL,
              let conversationId = conversationId,
              let userId = userId else {
            logWS("❌ Missing reconnection parameters")
            return
        }

        logWS("🔗 Attempting to reconnect... (attempt \(reconnectAttempts))")
        performConnect(baseURL: baseURL, conversationId: conversationId, userId: userId, token: token)
    }

    // MARK: - Message Handling

    private func handleText(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        // 处理 typing 消息
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let type = dict["type"] as? String {
            if type == "typing" {
                if let cid = dict["conversation_id"] as? String, let uid = dict["user_id"] as? String,
                   let c = UUID(uuidString: cid), let u = UUID(uuidString: uid) {
                    onTyping?(c, u)
                }
                return
            }
        }

        // 处理实际消息
        if let wrapper = try? JSONDecoder().decode(ServerMessage.self, from: data) {
            if buffer.appendIfNew(wrapper.message) {
                onMessage?(wrapper.message)
            }
        }
    }

    // MARK: - Logging

    private func logWS(_ message: String) {
        print("[WebSocketClient] \(message)")
    }
}

private struct ServerMessage: Decodable { let message: MessageDto }

// MARK: - CustomStringConvertible for connection state
extension WebSocketConnectionState: CustomStringConvertible {
    var description: String {
        switch self {
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .failed(let error): return "failed(\(error.localizedDescription))"
        }
    }
}
