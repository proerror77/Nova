import Foundation

final class ChatSocket: NSObject {
    private var task: URLSessionWebSocketTask?
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    var onMessageNew: ((UUID, UUID, String, Date) -> Void)? // (senderId, messageId, plaintext, createdAt)
    var onTyping: ((UUID) -> Void)? // userId
    var onError: ((Error) -> Void)?

    private var conversationId: UUID!
    private var meUserId: UUID!
    private var peerPublicKeyB64: String?

    func connect(conversationId: UUID, meUserId: UUID, jwtToken: String?, peerPublicKeyB64: String?) {
        self.conversationId = conversationId
        self.meUserId = meUserId
        self.peerPublicKeyB64 = peerPublicKeyB64

        var comps = URLComponents(url: AppConfig.messagingWebSocketBaseURL.appendingPathComponent("/ws"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "conversation_id", value: conversationId.uuidString),
                     URLQueryItem(name: "user_id", value: meUserId.uuidString)]
        if let t = jwtToken { items.append(URLQueryItem(name: "token", value: t)) }
        comps.queryItems = items
        guard let url = comps.url else { return }

        let request = URLRequest(url: url)
        let t = session.webSocketTask(with: request)
        self.task = t
        t.resume()
        receiveLoop()
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    func sendTyping() {
        guard let t = task else { return }
        let payload: [String: Any] = ["type": "typing",
                                       "conversation_id": conversationId.uuidString,
                                       "user_id": meUserId.uuidString]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
           let s = String(data: data, encoding: .utf8) {
            t.send(.string(s)) { _ in }
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let err):
                self.onError?(err)
            case .success(let msg):
                switch msg {
                case .string(let text):
                    self.handleIncoming(text: text)
                case .data(let data):
                    if let s = String(data: data, encoding: .utf8) { self.handleIncoming(text: s) }
                @unknown default:
                    break
                }
                self.receiveLoop()
            }
        }
    }

    private func handleIncoming(text: String) {
        // Two possible payloads:
        // A) From user-service via Redis fanout: {"type":"message.new","data":{"id":"...","conversation_id":"...","sender_id":"...","encrypted_content":"...","nonce":"...","message_type":"text","created_at":"..."}}
        // B) Typing echo from messaging-service: {"type":"typing","conversation_id":"...","user_id":"..."}
        guard let data = text.data(using: .utf8) else { return }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let type = obj["type"] as? String {
            if type == "typing" {
                if let uidStr = obj["user_id"] as? String, let uid = UUID(uuidString: uidStr) {
                    onTyping?(uid)
                }
                return
            }
            if type == "message.new", let d = obj["data"] as? [String: Any] {
                guard let msgIdStr = d["id"] as? String, let msgId = UUID(uuidString: msgIdStr),
                      let senderStr = d["sender_id"] as? String, let senderId = UUID(uuidString: senderStr),
                      let enc = d["encrypted_content"] as? String,
                      let nonce = d["nonce"] as? String,
                      let createdAtStr = d["created_at"] as? String,
                      let createdAt = ISO8601DateFormatter().date(from: createdAtStr) else { return }
                do {
                    guard let mySk = CryptoKeyStore.shared.getSecretKey() else {
                        return
                    }
                    // 1:1 conversation: decrypt with peer's public key
                    guard let peerPk = peerPublicKeyB64 else { return }
                    let plaintext = try NaClCrypto.decrypt(ciphertextB64: enc, nonceB64: nonce, senderPublicKeyB64: peerPk, mySecretKeyB64: mySk)
                    let content = String(decoding: plaintext, as: UTF8.self)
                    onMessageNew?(senderId, msgId, content, createdAt)
                } catch {
                    // Ignore decrypt errors
                }
                return
            }
        }
    }
}

extension ChatSocket: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {}
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {}
}
