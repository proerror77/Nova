import Foundation

// MARK: - Chat Call Service

/// Chat Call Service - Voice/Video Calls (WebRTC)
/// Handles voice and video call operations including WebRTC signaling
final class ChatCallService {
    // MARK: - Properties

    private let client = APIClient.shared

    // MARK: - Voice/Video Calls (WebRTC)

    /// 发起语音或视频通话
    /// - Parameters:
    ///   - conversationId: 会话ID
    ///   - isVideo: 是否为视频通话
    /// - Returns: 通话ID和相关信息
    @MainActor
    func initiateCall(conversationId: String, isVideo: Bool) async throws -> CallResponse {
        struct Request: Codable {
            let isVideo: Bool

            enum CodingKeys: String, CodingKey {
                case isVideo = "is_video"
            }
        }

        let request = Request(isVideo: isVideo)

        let response: CallResponse = try await client.request(
            endpoint: APIConfig.Chat.initiateCall(conversationId),
            method: "POST",
            body: request
        )

        #if DEBUG
        print("[ChatCallService] Call initiated: \(response.callId), video: \(isVideo)")
        #endif

        return response
    }

    /// 接听通话
    /// - Parameter callId: 通话ID
    @MainActor
    func answerCall(callId: String) async throws {
        struct EmptyRequest: Codable {}
        struct Response: Codable {
            let success: Bool
        }

        let _: Response = try await client.request(
            endpoint: APIConfig.Chat.answerCall(callId),
            method: "POST",
            body: EmptyRequest()
        )

        #if DEBUG
        print("[ChatCallService] Call answered: \(callId)")
        #endif
    }

    /// 拒绝通话
    /// - Parameter callId: 通话ID
    @MainActor
    func rejectCall(callId: String) async throws {
        struct EmptyRequest: Codable {}
        struct Response: Codable {
            let success: Bool
        }

        let _: Response = try await client.request(
            endpoint: APIConfig.Chat.rejectCall(callId),
            method: "POST",
            body: EmptyRequest()
        )

        #if DEBUG
        print("[ChatCallService] Call rejected: \(callId)")
        #endif
    }

    /// 结束通话
    /// - Parameter callId: 通话ID
    @MainActor
    func endCall(callId: String) async throws {
        struct EmptyRequest: Codable {}
        struct Response: Codable {
            let success: Bool
        }

        let _: Response = try await client.request(
            endpoint: APIConfig.Chat.endCall(callId),
            method: "POST",
            body: EmptyRequest()
        )

        #if DEBUG
        print("[ChatCallService] Call ended: \(callId)")
        #endif
    }

    /// 发送 ICE candidate（WebRTC连接建立）
    /// - Parameters:
    ///   - callId: 通话ID
    ///   - candidate: ICE candidate 数据
    @MainActor
    func sendIceCandidate(callId: String, candidate: String) async throws {
        struct Request: Codable {
            let callId: String
            let candidate: String

            enum CodingKeys: String, CodingKey {
                case callId = "call_id"
                case candidate
            }
        }

        struct Response: Codable {
            let success: Bool
        }

        let request = Request(callId: callId, candidate: candidate)

        let _: Response = try await client.request(
            endpoint: APIConfig.Chat.sendIceCandidate,
            method: "POST",
            body: request
        )

        #if DEBUG
        print("[ChatCallService] ICE candidate sent for call \(callId)")
        #endif
    }

    /// 获取 TURN/STUN 服务器配置（用于 WebRTC）
    /// - Returns: ICE 服务器配置列表
    @MainActor
    func getIceServers() async throws -> IceServersResponse {
        let response: IceServersResponse = try await client.get(
            endpoint: APIConfig.Chat.getIceServers
        )

        #if DEBUG
        print("[ChatCallService] Fetched \(response.iceServers.count) ICE servers")
        #endif

        return response
    }
}
