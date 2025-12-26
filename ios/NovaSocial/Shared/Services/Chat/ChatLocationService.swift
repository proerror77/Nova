import Foundation

// MARK: - Chat Location Service

/// Chat Location Service - 位置分享服务
/// 职责：
/// - 分享当前位置
/// - 停止位置分享
/// - 获取附近用户
final class ChatLocationService {
    // MARK: - Properties

    private let client = APIClient.shared

    // MARK: - Location Sharing

    /// 分享当前位置到会话
    /// - Parameters:
    ///   - conversationId: 会话ID
    ///   - latitude: 纬度
    ///   - longitude: 经度
    ///   - accuracy: 精度（米）
    @MainActor
    func shareLocation(
        conversationId: String,
        latitude: Double,
        longitude: Double,
        accuracy: Double? = nil
    ) async throws {
        struct Request: Codable {
            let latitude: Double
            let longitude: Double
            let accuracy: Double?
        }

        struct Response: Codable {
            let success: Bool
        }

        let request = Request(latitude: latitude, longitude: longitude, accuracy: accuracy)

        let _: Response = try await client.request(
            endpoint: APIConfig.Chat.shareLocation(conversationId),
            method: "POST",
            body: request
        )

        #if DEBUG
        print("[ChatLocationService] Location shared: \(latitude), \(longitude)")
        #endif
    }

    /// 停止分享位置
    /// - Parameter conversationId: 会话ID
    @MainActor
    func stopSharingLocation(conversationId: String) async throws {
        struct EmptyResponse: Codable {}

        let _: EmptyResponse = try await client.request(
            endpoint: APIConfig.Chat.stopSharingLocation(conversationId),
            method: "DELETE"
        )

        #if DEBUG
        print("[ChatLocationService] Stopped sharing location for conversation \(conversationId)")
        #endif
    }

    /// 获取附近的用户
    /// - Parameters:
    ///   - latitude: 当前纬度
    ///   - longitude: 当前经度
    ///   - radius: 搜索半径（米，默认1000米）
    /// - Returns: 附近用户列表
    @MainActor
    func getNearbyUsers(
        latitude: Double,
        longitude: Double,
        radius: Int = 1000
    ) async throws -> NearbyUsersResponse {
        let response: NearbyUsersResponse = try await client.get(
            endpoint: APIConfig.Chat.getNearbyUsers,
            queryParams: [
                "latitude": String(latitude),
                "longitude": String(longitude),
                "radius": String(radius)
            ]
        )

        #if DEBUG
        print("[ChatLocationService] Found \(response.users.count) nearby users")
        #endif

        return response
    }
}
