import SwiftUI

struct DevicesView: View {
    @Binding var currentPage: AppPage
    @State private var devices: [Device] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack {
                    Button(action: {
                        currentPage = .setting
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20))
                            .foregroundColor(DesignTokens.textPrimary)
                    }

                    Spacer()

                    Text("Devices")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(DesignTokens.textPrimary)

                    Spacer()

                    // 占位，保持标题居中
                    Color.clear
                        .frame(width: 20)
                }
                .frame(height: DesignTokens.topBarHeight)
                .padding(.horizontal, 20)
                .background(Color.white)

                // 分隔线
                Rectangle()
                    .fill(DesignTokens.borderColor)
                    .frame(height: 0.5)

                // MARK: - 内容区域
                ZStack {
                    if isLoading && devices.isEmpty {
                        // 加载状态
                        ProgressView()
                            .scaleEffect(1.2)
                    } else if let errorMessage = errorMessage, devices.isEmpty {
                        // 错误状态
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 48))
                                .foregroundColor(.gray)

                            Text(errorMessage)
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)

                            Button("重试") {
                                Task {
                                    await loadDevices()
                                }
                            }
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                            .background(DesignTokens.accentColor)
                            .cornerRadius(8)
                        }
                    } else if devices.isEmpty {
                        // 空状态
                        VStack(spacing: 16) {
                            Image(systemName: "laptopcomputer.and.iphone")
                                .font(.system(size: 48))
                                .foregroundColor(.gray)

                            Text("暂无登录设备")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                        }
                    } else {
                        // 设备列表
                        ScrollView {
                            VStack(spacing: 16) {
                                ForEach(devices) { device in
                                    DeviceCard(device: device)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 20)
                        }
                        .refreshable {
                            await loadDevices()
                        }
                    }
                }

                Spacer()
            }
        }
        .task {
            await loadDevices()
        }
    }

    // MARK: - 加载设备列表
    private func loadDevices() async {
        isLoading = true
        errorMessage = nil

        do {
            devices = try await DeviceService.shared.getDevices()
        } catch {
            errorMessage = "加载设备列表失败：\(error.localizedDescription)"
            print("Failed to load devices: \(error)")
        }

        isLoading = false
    }
}

// MARK: - 设备卡片组件
struct DeviceCard: View {
    let device: Device

    var body: some View {
        Button(action: {
            // TODO: 查看设备详情
        }) {
            HStack(spacing: 16) {
                // 设备图标
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(DesignTokens.accentColor, lineWidth: 2)
                        .frame(width: 50, height: 50)

                    Image(systemName: device.deviceType.iconName)
                        .font(.system(size: 24))
                        .foregroundColor(DesignTokens.accentColor)
                }

                // 设备信息
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(device.deviceName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.black)

                        // 当前设备标记
                        if device.isCurrent == true {
                            Text("当前设备")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(DesignTokens.accentColor)
                                .cornerRadius(4)
                        }
                    }

                    Text("Last active: \(device.formattedLastActive)")
                        .font(.system(size: 12))
                        .foregroundColor(DesignTokens.textSecondary)
                }

                Spacer()

                // 右箭头
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .background(Color.white)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(DesignTokens.borderColor, lineWidth: 0.5)
        )
    }
}

#Preview {
    DevicesView(currentPage: .constant(.setting))
}

#Preview("Device Card") {
    VStack(spacing: 16) {
        DeviceCard(device: Device(
            id: "1",
            userId: "user123",
            deviceType: .ios,
            deviceName: "iPhone 15 Pro",
            deviceModel: "iPhone15,2",
            osVersion: "iOS 18.0",
            appVersion: "1.0.0",
            lastActiveAt: Int64(Date().timeIntervalSince1970 * 1000),
            createdAt: Int64(Date().timeIntervalSince1970 * 1000),
            isCurrent: true
        ))

        DeviceCard(device: Device(
            id: "2",
            userId: "user123",
            deviceType: .macos,
            deviceName: "MacBook Pro",
            deviceModel: "MacBookPro18,1",
            osVersion: "macOS 15.0",
            appVersion: "1.0.0",
            lastActiveAt: Int64((Date().timeIntervalSince1970 - 3600 * 24 * 2) * 1000),
            createdAt: Int64(Date().timeIntervalSince1970 * 1000),
            isCurrent: false
        ))
    }
    .padding()
}
