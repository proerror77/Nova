import Foundation

// MARK: - Device Service
// 处理设备管理相关操作，包括获取设备列表、登出设备等

class DeviceService {
    static let shared = DeviceService()
    private let client = APIClient.shared

    private init() {}

    // MARK: - Device Management

    /// 获取当前用户的所有登录设备
    func getDevices() async throws -> [Device] {
        let response: GetDevicesResponse = try await client.request(
            endpoint: APIConfig.Devices.getDevices,
            method: "GET"
        )

        return response.devices
    }

    /// 获取当前设备信息
    func getCurrentDevice() async throws -> Device {
        let response: GetCurrentDeviceResponse = try await client.request(
            endpoint: APIConfig.Devices.getCurrentDevice,
            method: "GET"
        )

        return response.device
    }

    /// 从指定设备登出
    func logoutDevice(deviceId: String) async throws -> Bool {
        let request = LogoutDeviceRequest(deviceId: deviceId)

        let response: LogoutDeviceResponse = try await client.request(
            endpoint: APIConfig.Devices.logoutDevice,
            method: "POST",
            body: request
        )

        return response.success
    }

    /// 获取设备数量
    func getDeviceCount() async throws -> Int {
        let response: GetDevicesResponse = try await client.request(
            endpoint: APIConfig.Devices.getDevices,
            method: "GET"
        )

        return response.total ?? response.devices.count
    }
}
