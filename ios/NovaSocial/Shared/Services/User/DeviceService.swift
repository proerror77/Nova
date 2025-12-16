import Foundation
import UIKit

// MARK: - Device Service
// 处理设备管理相关操作，包括获取设备列表、登出设备等

class DeviceService {
    static let shared = DeviceService()
    private let client = APIClient.shared

    /// 是否使用模拟数据（API未就绪时使用）
    var useMockData = true

    private init() {}

    // MARK: - Device Management

    /// 获取当前用户的所有登录设备
    func getDevices() async throws -> [Device] {
        // 如果启用模拟数据，返回模拟设备列表
        if useMockData {
            return getMockDevices()
        }

        let response: GetDevicesResponse = try await client.request(
            endpoint: APIConfig.Devices.getDevices,
            method: "GET"
        )

        return response.devices
    }

    // MARK: - Mock Data

    /// 获取当前设备信息
    private func getCurrentDeviceInfo() -> (name: String, model: String, osVersion: String) {
        let device = UIDevice.current
        let name = device.name
        let systemVersion = device.systemVersion

        // 获取设备型号
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        } ?? "Unknown"

        return (name, modelCode, "iOS \(systemVersion)")
    }

    /// 生成模拟设备数据
    private func getMockDevices() -> [Device] {
        let currentDeviceInfo = getCurrentDeviceInfo()
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        return [
            // 当前设备
            Device(
                id: "device-current",
                userId: "current-user",
                deviceType: .ios,
                deviceName: currentDeviceInfo.name,
                deviceModel: currentDeviceInfo.model,
                osVersion: currentDeviceInfo.osVersion,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
                lastActiveAt: now,
                createdAt: now - 86400000 * 30, // 30天前
                isCurrent: true
            ),
            // 其他模拟设备
            Device(
                id: "device-macbook",
                userId: "current-user",
                deviceType: .macos,
                deviceName: "MacBook Pro",
                deviceModel: "MacBookPro18,1",
                osVersion: "macOS 15.2",
                appVersion: "1.0.0",
                lastActiveAt: now - 3600000 * 2, // 2小时前
                createdAt: now - 86400000 * 60,
                isCurrent: false
            ),
            Device(
                id: "device-ipad",
                userId: "current-user",
                deviceType: .ios,
                deviceName: "iPad Pro",
                deviceModel: "iPad14,5",
                osVersion: "iPadOS 18.2",
                appVersion: "1.0.0",
                lastActiveAt: now - 86400000 * 3, // 3天前
                createdAt: now - 86400000 * 90,
                isCurrent: false
            ),
            Device(
                id: "device-web",
                userId: "current-user",
                deviceType: .web,
                deviceName: "Chrome on Windows",
                deviceModel: "Chrome 131",
                osVersion: "Windows 11",
                appVersion: "Web",
                lastActiveAt: now - 86400000 * 7, // 7天前
                createdAt: now - 86400000 * 14,
                isCurrent: false
            )
        ]
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
