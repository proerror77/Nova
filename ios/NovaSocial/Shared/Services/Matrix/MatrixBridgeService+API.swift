import Foundation

// MARK: - Backend API Extension

extension MatrixBridgeService {

    // MARK: - Types

    /// Matrix credentials returned from Nova backend
    struct MatrixCredentials {
        let accessToken: String
        let matrixUserId: String
        let deviceId: String
        let homeserverUrl: String?
        /// Token expiry timestamp (Unix seconds)
        let expiresAt: Int64?

        /// Check if the token is expired or will expire soon
        /// - Parameter bufferSeconds: Time buffer before actual expiry (default 10 minutes)
        /// - Returns: true if token is expired or will expire within buffer time
        func isExpiredOrExpiringSoon(bufferSeconds: Int64 = 600) -> Bool {
            guard let expiresAt = expiresAt else { return false }
            let currentTime = Int64(Date().timeIntervalSince1970)
            return currentTime >= (expiresAt - bufferSeconds)
        }

        /// Time until token expires (in seconds)
        var timeUntilExpiry: Int64? {
            guard let expiresAt = expiresAt else { return nil }
            let currentTime = Int64(Date().timeIntervalSince1970)
            return expiresAt - currentTime
        }
    }

    // MARK: - Bridge Configuration

    func checkBridgeEnabled() async -> Bool {
        // Check feature flag from backend
        do {
            struct ConfigResponse: Codable {
                let enabled: Bool
                let homeserverUrl: String?
            }

            let response: ConfigResponse = try await apiClient.get(
                endpoint: APIConfig.Matrix.getConfig
            )
            #if DEBUG
            print("[MatrixBridge] Backend config: enabled=\(response.enabled), homeserver=\(response.homeserverUrl ?? "nil")")
            #endif
            return response.enabled
        } catch {
            #if DEBUG
            print("[MatrixBridge] Failed to check bridge status: \(error)")
            print("[MatrixBridge] Backend Matrix config not available; assuming enabled for Matrix-first mode")
            #endif
            // Matrix-first: default to ENABLED when backend is not available.
            return true
        }
    }

    // MARK: - Credentials

    /// Get Matrix credentials from Nova backend
    /// Returns access token, Matrix user ID, device ID, and homeserver URL
    ///
    /// The backend generates a device-bound access token using Synapse Admin API.
    /// This enables seamless single sign-on without requiring a second SSO prompt.
    func getMatrixCredentials(novaUserId: String) async throws -> MatrixCredentials {
        struct MatrixTokenRequest: Codable {
            let deviceId: String

            enum CodingKeys: String, CodingKey {
                case deviceId = "device_id"
            }
        }

        struct MatrixTokenResponse: Codable {
            // Note: No CodingKeys needed - APIClient uses .convertFromSnakeCase
            let accessToken: String
            let matrixUserId: String
            let deviceId: String
            let homeserverUrl: String?
            /// Token expiry timestamp (Unix seconds)
            let expiresAt: Int64?
        }

        // Generate a persistent device ID for this device
        // This ensures E2EE keys are consistent across app sessions
        let deviceId = getOrCreateDeviceId()

        #if DEBUG
        print("[MatrixBridge] Requesting device-bound token with device_id: \(deviceId)")
        #endif

        let response: MatrixTokenResponse = try await apiClient.request(
            endpoint: APIConfig.Matrix.getToken,
            method: "POST",
            body: MatrixTokenRequest(deviceId: deviceId)
        )

        #if DEBUG
        if let expiresAt = response.expiresAt {
            let expiryDate = Date(timeIntervalSince1970: TimeInterval(expiresAt))
            print("[MatrixBridge] Token expires at: \(expiryDate) (in \((expiresAt - Int64(Date().timeIntervalSince1970))/60) minutes)")
        }
        #endif

        return MatrixCredentials(
            accessToken: response.accessToken,
            matrixUserId: response.matrixUserId,
            deviceId: response.deviceId,
            homeserverUrl: response.homeserverUrl,
            expiresAt: response.expiresAt
        )
    }

    /// Get or create a persistent device ID for Matrix sessions
    /// This ensures E2EE keys are consistent across app sessions on the same device
    func getOrCreateDeviceId() -> String {
        // Check if we already have a device ID stored
        if let existingDeviceId = keychain.get(.matrixDeviceId), !existingDeviceId.isEmpty {
            return existingDeviceId
        }

        // Generate a new device ID
        // Format: NOVA_IOS_{UUID} to identify Nova iOS clients
        let newDeviceId = "NOVA_IOS_\(UUID().uuidString.prefix(8))"

        // Store for future use
        _ = keychain.save(newDeviceId, for: .matrixDeviceId)

        #if DEBUG
        print("[MatrixBridge] Generated new device ID: \(newDeviceId)")
        #endif

        return newDeviceId
    }

    // MARK: - Room Mapping API

    func queryRoomMapping(conversationId: String) async throws -> String? {
        // APIClient uses .convertFromSnakeCase for decoding
        struct RoomMappingResponse: Codable {
            let roomId: String?
        }

        do {
            let response: RoomMappingResponse = try await apiClient.get(
                endpoint: APIConfig.Matrix.getRoomMapping(conversationId)
            )
            return response.roomId
        } catch {
            // 404 means no mapping exists
            return nil
        }
    }

    func queryConversationMapping(roomId: String) async throws -> String? {
        // APIClient uses .convertFromSnakeCase for decoding
        struct ConversationMappingResponse: Codable {
            let conversationId: String?
        }

        // URL encode room ID (!xxx:server contains special chars)
        let encodedRoomId = roomId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? roomId

        do {
            let response: ConversationMappingResponse = try await apiClient.get(
                endpoint: APIConfig.Matrix.getConversationMapping,
                queryParams: ["room_id": encodedRoomId]
            )
            return response.conversationId
        } catch {
            return nil
        }
    }

    func saveRoomMapping(conversationId: String, roomId: String) async throws {
        struct SaveMappingRequest: Codable {
            let conversationId: String
            let roomId: String

            enum CodingKeys: String, CodingKey {
                case conversationId = "conversation_id"
                case roomId = "room_id"
            }
        }

        struct EmptyResponse: Codable {}

        let _: EmptyResponse = try await apiClient.request(
            endpoint: APIConfig.Matrix.saveRoomMapping,
            method: "POST",
            body: SaveMappingRequest(conversationId: conversationId, roomId: roomId)
        )
    }

    func loadConversationMappings() async throws {
        struct AllMappingsResponse: Codable {
            let mappings: [MappingEntry]

            // Note: APIClient uses .convertFromSnakeCase which auto-converts
            // conversation_id -> conversationId and room_id -> roomId
            struct MappingEntry: Codable {
                let conversationId: String
                let roomId: String
            }
        }

        do {
            let response: AllMappingsResponse = try await apiClient.get(
                endpoint: APIConfig.Matrix.getRoomMappings
            )

            for mapping in response.mappings {
                cacheMapping(conversationId: mapping.conversationId, roomId: mapping.roomId)
            }

            #if DEBUG
            print("[MatrixBridge] Loaded \(response.mappings.count) conversation mappings")
            #endif
        } catch {
            #if DEBUG
            print("[MatrixBridge] Failed to load mappings: \(error)")
            #endif
            // Not critical - mappings will be created on demand
        }
    }
}
