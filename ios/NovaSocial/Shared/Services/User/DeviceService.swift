import Foundation
import UIKit

// MARK: - Device Service
// 处理设备管理相关操作，包括获取设备列表、登出设备等

class DeviceService {
    static let shared = DeviceService()
    private let client = APIClient.shared

    private init() {}

    // MARK: - Device Management

    /// 獲取當前用戶的所有登錄設備
    func getDevices() async throws -> [Device] {
        let response: GetDevicesResponse = try await client.request(
            endpoint: APIConfig.Devices.getDevices,
            method: "GET"
        )
        return response.devices
    }

    /// 獲取當前設備信息
    func getCurrentDevice() async throws -> Device {
        let response: GetCurrentDeviceResponse = try await client.request(
            endpoint: APIConfig.Devices.getCurrentDevice,
            method: "GET"
        )
        return response.device
    }

    /// 從指定設備登出
    func logoutDevice(deviceId: String) async throws -> Bool {
        let request = LogoutDeviceRequest(deviceId: deviceId)

        let response: LogoutDeviceResponse = try await client.request(
            endpoint: APIConfig.Devices.logoutDevice,
            method: "POST",
            body: request
        )

        return response.success
    }
    
    /// 從所有設備登出
    func logoutAllDevices() async throws -> Bool {
        // Use the "all" flag to logout from all devices
        struct LogoutAllRequest: Codable {
            let all: Bool
            
            enum CodingKeys: String, CodingKey {
                case all
            }
        }
        
        let request = LogoutAllRequest(all: true)
        
        let response: LogoutDeviceResponse = try await client.request(
            endpoint: APIConfig.Devices.logoutDevice,
            method: "POST",
            body: request
        )
        
        return response.success
    }

    /// 獲取設備數量
    func getDeviceCount() async throws -> Int {
        let response: GetDevicesResponse = try await client.request(
            endpoint: APIConfig.Devices.getDevices,
            method: "GET"
        )

        return response.total ?? response.devices.count
    }
}
