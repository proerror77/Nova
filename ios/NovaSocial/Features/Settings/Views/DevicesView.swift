import SwiftUI

struct DevicesView: View {
    @Binding var currentPage: AppPage

    var body: some View {
        ZStack {
            DesignTokens.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack {
                    Button(action: {
                        currentPage = .setting
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20))
                            .foregroundColor(DesignTokens.text)
                    }

                    Spacer()

                    Text("Devices")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(DesignTokens.text)

                    Spacer()

                    // 占位，保持标题居中
                    Color.clear
                        .frame(width: 20)
                }
                .frame(height: DesignTokens.topBarHeight)
                .padding(.horizontal, 20)
                .background(DesignTokens.card)

                // 分隔线
                Rectangle()
                    .fill(DesignTokens.border)
                    .frame(height: 0.5)

                ScrollView {
                    VStack(spacing: 16) {
                        // MARK: - iPhone 设备
                        DeviceCard(
                            icon: "iphone",
                            deviceName: "Apple iPhone17",
                            lastActive: "Last active: Invalid Date"
                        )
                        .padding(.top, 20)

                        // MARK: - Mac 设备
                        DeviceCard(
                            icon: "desktopcomputer",
                            deviceName: "Mac",
                            lastActive: "Last active: Invalid Date"
                        )
                    }
                    .padding(.horizontal, 12)
                }

                Spacer()
            }
        }
    }
}

// MARK: - 设备卡片组件
struct DeviceCard: View {
    let icon: String
    let deviceName: String
    let lastActive: String

    var body: some View {
        Button(action: {
            // TODO: 查看设备详情
        }) {
            HStack(spacing: 16) {
                // 设备图标
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(DesignTokens.accent, lineWidth: 2)
                        .frame(width: 50, height: 50)

                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundColor(DesignTokens.accent)
                }

                // 设备信息
                VStack(alignment: .leading, spacing: 2) {
                    Text(deviceName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(DesignTokens.text)

                    Text(lastActive)
                        .font(.system(size: 12))
                        .foregroundColor(DesignTokens.textLight)
                }

                Spacer()

                // 右箭头
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(DesignTokens.textLight)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .background(DesignTokens.card)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(DesignTokens.border, lineWidth: 0.5)
        )
    }
}

#Preview {
    DevicesView(currentPage: .constant(.setting))
}
