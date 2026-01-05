import SwiftUI

struct DevicesView: View {
    @Binding var currentPage: AppPage
    @State private var devices: [Device] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedDevice: Device?
    @State private var showLogoutConfirmation = false
    @State private var deviceToLogout: Device?

    // 分组：当前设备和其他设备
    private var currentDevice: Device? {
        devices.first { $0.isCurrent == true }
    }

    private var otherDevices: [Device] {
        devices.filter { $0.isCurrent != true }
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack {
                    Button(action: {
                        currentPage = .setting
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17.f))
                            .foregroundColor(DesignTokens.accentColor)
                    }

                    Spacer()

                    Text("Devices")
                        .font(Font.custom("SFProDisplay-Semibold", size: 17.f))
                        .foregroundColor(DesignTokens.textPrimary)

                    Spacer()

                    // 占位，保持标题居中
                    Color.clear
                        .frame(width: 24)
                }
                .frame(height: 44)
                .padding(.horizontal, 16)
                .background(Color(uiColor: .systemGroupedBackground))

                // MARK: - 内容区域
                ZStack {
                    if isLoading && devices.isEmpty {
                        // 加载状态
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Loading devices...")
                                .font(Font.custom("SFProDisplay-Regular", size: 15.f))
                                .foregroundColor(.secondary)
                        }
                    } else if let errorMessage = errorMessage, devices.isEmpty {
                        // 错误状态
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 48.f))
                                .foregroundColor(.secondary)

                            Text(errorMessage)
                                .font(Font.custom("SFProDisplay-Regular", size: 15.f))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)

                            Button("Retry") {
                                Task {
                                    await loadDevices()
                                }
                            }
                            .font(Font.custom("SFProDisplay-Medium", size: 17.f))
                            .foregroundColor(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                            .background(DesignTokens.accentColor)
                            .cornerRadius(10)
                        }
                    } else if devices.isEmpty {
                        // 空状态
                        VStack(spacing: 16) {
                            Image(systemName: "laptopcomputer.and.iphone")
                                .font(.system(size: 48.f))
                                .foregroundColor(.secondary)

                            Text("No devices found")
                                .font(Font.custom("SFProDisplay-Regular", size: 15.f))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        // 设备列表 - iOS 原生风格
                        ScrollView {
                            VStack(spacing: 24) {
                                // 当前设备部分
                                if let current = currentDevice {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("THIS DEVICE")
                                            .font(Font.custom("SFProDisplay-Regular", size: 13.f))
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 16)

                                        DeviceRow(
                                            device: current,
                                            isFirst: true,
                                            isLast: true,
                                            onTap: { selectedDevice = current },
                                            onLogout: nil // 当前设备不显示登出按钮
                                        )
                                    }
                                }

                                // 其他设备部分
                                if !otherDevices.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("OTHER DEVICES")
                                            .font(Font.custom("SFProDisplay-Regular", size: 13.f))
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 16)

                                        VStack(spacing: 0) {
                                            ForEach(Array(otherDevices.enumerated()), id: \.element.id) { index, device in
                                                DeviceRow(
                                                    device: device,
                                                    isFirst: index == 0,
                                                    isLast: index == otherDevices.count - 1,
                                                    onTap: { selectedDevice = device },
                                                    onLogout: {
                                                        deviceToLogout = device
                                                        showLogoutConfirmation = true
                                                    }
                                                )
                                            }
                                        }
                                    }
                                }

                                // 说明文字
                                Text("Devices that are logged into your account are shown here. You can log out from any device remotely.")
                                    .font(Font.custom("SFProDisplay-Regular", size: 13.f))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 8)
                            }
                            .padding(.vertical, 16)
                        }
                        .refreshable {
                            await loadDevices()
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .task {
            await loadDevices()
        }
        .alert("Log Out Device", isPresented: $showLogoutConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Log Out", role: .destructive) {
                if let device = deviceToLogout {
                    Task {
                        await logoutDevice(device)
                    }
                }
            }
        } message: {
            if let device = deviceToLogout {
                Text("Are you sure you want to log out \"\(device.deviceName)\"? This device will need to sign in again to access your account.")
            }
        }
        .sheet(item: $selectedDevice) { device in
            DeviceDetailSheet(device: device, onLogout: {
                if device.isCurrent != true {
                    deviceToLogout = device
                    selectedDevice = nil
                    showLogoutConfirmation = true
                }
            })
        }
    }

    // MARK: - 加载设备列表
    private func loadDevices() async {
        isLoading = true
        errorMessage = nil

        do {
            devices = try await DeviceService.shared.getDevices()
        } catch {
            errorMessage = "Failed to load devices: \(error.localizedDescription)"
            print("Failed to load devices: \(error)")
        }

        isLoading = false
    }

    // MARK: - 登出设备
    private func logoutDevice(_ device: Device) async {
        do {
            let success = try await DeviceService.shared.logoutDevice(deviceId: device.id)
            if success {
                // 从列表中移除设备
                devices.removeAll { $0.id == device.id }
            }
        } catch {
            print("Failed to logout device: \(error)")
        }
    }
}

// MARK: - 设备行组件 (iOS 风格)
struct DeviceRow: View {
    let device: Device
    let isFirst: Bool
    let isLast: Bool
    let onTap: () -> Void
    let onLogout: (() -> Void)?

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // 设备图标 - iOS 风格
                ZStack {
                    Circle()
                        .fill(deviceIconBackground)
                        .frame(width: 44, height: 44)

                    Image(systemName: deviceIconName)
                        .font(Font.custom("SFProDisplay-Regular", size: 20.f))
                        .foregroundColor(.white)
                }

                // 设备信息
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(device.deviceName)
                            .font(Font.custom("SFProDisplay-Regular", size: 17.f))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if device.isCurrent == true {
                            Text("This Device")
                                .font(Font.custom("SFProDisplay-Medium", size: 12.f))
                                .foregroundColor(DesignTokens.accentColor)
                        }
                    }

                    Text(deviceSubtitle)
                        .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // 登出按钮或箭头
                if device.isCurrent != true, onLogout != nil {
                    Button {
                        onLogout?()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22.f))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14.f))
                        .foregroundColor(Color(uiColor: .tertiaryLabel))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .buttonStyle(.plain)
        .clipShape(
            RoundedCorners(
                topLeft: isFirst ? 10 : 0,
                topRight: isFirst ? 10 : 0,
                bottomLeft: isLast ? 10 : 0,
                bottomRight: isLast ? 10 : 0
            )
        )
        .overlay(
            VStack {
                Spacer()
                if !isLast {
                    Rectangle()
                        .fill(Color(uiColor: .separator))
                        .frame(height: 0.5)
                        .padding(.leading, 74)
                }
            }
        )
        .padding(.horizontal, 16)
    }

    private var deviceIconName: String {
        switch device.deviceType {
        case .ios:
            if device.deviceName.lowercased().contains("ipad") {
                return "ipad"
            }
            return "iphone"
        case .macos:
            if device.deviceName.lowercased().contains("imac") {
                return "desktopcomputer"
            }
            return "laptopcomputer"
        case .android:
            return "phone.fill"
        case .web:
            return "globe"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private var deviceIconBackground: Color {
        switch device.deviceType {
        case .ios:
            return Color.blue
        case .macos:
            return Color.gray
        case .android:
            return Color.green
        case .web:
            return Color.orange
        case .unknown:
            return Color.secondary
        }
    }

    private var deviceSubtitle: String {
        if device.isCurrent == true {
            return device.osVersion ?? "Active now"
        }
        return "Last active: \(device.formattedLastActive)"
    }
}

// MARK: - 设备详情 Sheet
struct DeviceDetailSheet: View {
    let device: Device
    let onLogout: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // 设备信息
                Section {
                    LabeledContent("Device Name", value: device.deviceName)
                    LabeledContent("Device Type", value: device.deviceType.rawValue)
                    if let model = device.deviceModel {
                        LabeledContent("Model", value: model)
                    }
                    if let osVersion = device.osVersion {
                        LabeledContent("OS Version", value: osVersion)
                    }
                    if let appVersion = device.appVersion {
                        LabeledContent("App Version", value: appVersion)
                    }
                }

                // 活动信息
                Section {
                    LabeledContent("Last Active", value: device.formattedLastActive)
                    if let createdAt = device.createdAt {
                        LabeledContent("First Login", value: formatDate(createdAt))
                    }
                }

                // 登出按钮
                if device.isCurrent != true {
                    Section {
                        Button(role: .destructive) {
                            dismiss()
                            onLogout()
                        } label: {
                            HStack {
                                Spacer()
                                Text("Log Out This Device")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(device.deviceName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func formatDate(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - 圆角辅助
struct RoundedCorners: Shape {
    var topLeft: CGFloat = 0.0
    var topRight: CGFloat = 0.0
    var bottomLeft: CGFloat = 0.0
    var bottomRight: CGFloat = 0.0

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let tl = min(min(topLeft, rect.width / 2), rect.height / 2)
        let tr = min(min(topRight, rect.width / 2), rect.height / 2)
        let bl = min(min(bottomLeft, rect.width / 2), rect.height / 2)
        let br = min(min(bottomRight, rect.width / 2), rect.height / 2)

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()

        return path
    }
}

// MARK: - Device Hashable Extension
extension Device: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: Device, rhs: Device) -> Bool {
        lhs.id == rhs.id
    }
}

// Previews disabled - DeviceModels.swift not added to project
/*
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
*/
