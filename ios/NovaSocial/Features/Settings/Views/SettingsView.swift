import SwiftUI

struct SettingsView: View {
    @Binding var showSetting: Bool
    @State private var isDarkMode = false

    var body: some View {
        ZStack {
            // 背景色
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack {
                    Button(action: {
                        showSetting = false
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.black)
                    }

                    Spacer()

                    Text("Settings")
                        .font(Font.custom("Helvetica Neue", size: 24).weight(.medium))
                        .foregroundColor(.black)

                    Spacer()

                    // 占位，保持标题居中
                    Color.clear
                        .frame(width: 20)
                }
                .frame(height: 56)
                .padding(.horizontal, 16)
                .background(Color.white)

                Divider()
                    .frame(height: 0.5)
                    .background(Color(red: 0.74, green: 0.74, blue: 0.74))

                ScrollView {
                    VStack(spacing: 16) {
                        // MARK: - 第一组设置项
                        VStack(spacing: 0) {
                            SettingItem(title: "Profile Settings", showChevron: true)
                            Divider().padding(.leading, 50)
                            SettingItem(title: "My Account", showChevron: true)
                            Divider().padding(.leading, 50)
                            SettingItem(title: "Devices", showChevron: true)
                            Divider().padding(.leading, 50)
                            SettingItem(title: "Invite Friends", showChevron: true)
                            Divider().padding(.leading, 50)
                            SettingItem(title: "My Channels", showChevron: true)
                        }
                        .background(Color.white)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(red: 0.68, green: 0.68, blue: 0.68), lineWidth: 0.5)
                        )
                        .padding(.horizontal, 21)

                        // MARK: - Dark Mode
                        HStack {
                            Image(systemName: "person.fill")
                                .font(.system(size: 20))
                                .foregroundColor(Color(red: 0.82, green: 0.13, blue: 0.25))
                                .frame(width: 24)

                            Text("Dark Mode")
                                .font(Font.custom("Helvetica Neue", size: 15).weight(.medium))
                                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

                            Spacer()

                            Toggle("", isOn: $isDarkMode)
                                .labelsHidden()
                        }
                        .padding(.horizontal, 20)
                        .frame(height: 54)
                        .background(Color.white)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(red: 0.68, green: 0.68, blue: 0.68), lineWidth: 0.5)
                        )
                        .padding(.horizontal, 21)

                        // MARK: - Sign Out
                        HStack {
                            Image(systemName: "person.fill")
                                .font(.system(size: 20))
                                .foregroundColor(Color(red: 0.82, green: 0.13, blue: 0.25))
                                .frame(width: 24)

                            Text("Sign Out")
                                .font(Font.custom("Helvetica Neue", size: 15).weight(.medium))
                                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .frame(height: 54)
                        .background(Color.white)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(red: 0.68, green: 0.68, blue: 0.68), lineWidth: 0.5)
                        )
                        .padding(.horizontal, 21)
                    }
                    .padding(.top, 24)
                }

                Spacer()
            }
        }
    }
}

// MARK: - 设置项组件
struct SettingItem: View {
    let title: String
    let showChevron: Bool

    var body: some View {
        HStack {
            Image(systemName: "person.fill")
                .font(.system(size: 20))
                .foregroundColor(Color(red: 0.82, green: 0.13, blue: 0.25))
                .frame(width: 24)

            Text(title)
                .font(Font.custom("Helvetica Neue", size: 15).weight(.medium))
                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

            Spacer()

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.68, green: 0.68, blue: 0.68))
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 50)
        .background(Color.white)
    }
}

#Preview {
    SettingsView(showSetting: .constant(true))
}
