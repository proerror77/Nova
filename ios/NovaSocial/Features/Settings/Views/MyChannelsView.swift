import SwiftUI

struct MyChannelsView: View {
    @Binding var currentPage: AppPage

    // 最大选择数量限制
    private let maxChannelSelection = 5

    // 使用 @AppStorage 持久化选择的频道
    @AppStorage("selectedChannels") private var savedChannelsData: Data = Data()

    // 当前选择的频道
    @State private var selectedChannels: Set<String> = []

    // 显示超出限制的提示弹窗
    @State private var showLimitAlert = false

    var body: some View {
        ZStack {
            DesignTokens.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack {
                    // 左侧返回按钮
                    Button(action: {
                        currentPage = .setting
                    }) {
                        Image(systemName: "chevron.left")
                            .frame(width: 24, height: 24)
                            .foregroundColor(DesignTokens.textPrimary)
                    }
                    .frame(width: 50, alignment: .leading)

                    Spacer()

                    // 居中标题（参考 NewPost 页面样式）
                    Text(LocalizedStringKey("My_Channels_Title"))
                        .font(.system(size: 18, weight: .medium))
                        .lineSpacing(20)
                        .foregroundColor(DesignTokens.textPrimary)

                    Spacer()

                    // 右侧显示已选择数量（与左侧宽度一致以保持标题居中）
                    Text("\(selectedChannels.count)/\(maxChannelSelection)")
                        .font(.system(size: 14))
                        .foregroundColor(DesignTokens.textSecondary)
                        .frame(width: 50, alignment: .trailing)
                }
                .frame(height: DesignTokens.topBarHeight)
                .padding(.horizontal, 20)
                .background(DesignTokens.surface)

                // 分隔线
                Rectangle()
                    .fill(DesignTokens.borderColor)
                    .frame(height: 0.5)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // MARK: - Sports & Outdoor Activities
                        ChannelCategory(
                            title: NSLocalizedString("Sports_Outdoor", comment: ""),
                            channels: ["Sports", "Tennis", "American Football", "Football", "Snowboarding", "Automotive", "Camping"],
                            selectedChannels: $selectedChannels,
                            maxSelection: maxChannelSelection,
                            onLimitReached: { showLimitAlert = true }
                        )

                        // MARK: - Science & Education
                        ChannelCategory(
                            title: NSLocalizedString("Science_Education", comment: ""),
                            channels: ["Astronomy", "Astrology", "Health", "Society"],
                            selectedChannels: $selectedChannels,
                            maxSelection: maxChannelSelection,
                            onLimitReached: { showLimitAlert = true }
                        )

                        // MARK: - Business & Finance
                        ChannelCategory(
                            title: NSLocalizedString("Business_Finance", comment: ""),
                            channels: ["Business", "Stocks", "Wealth", "Crypto", "NFT"],
                            selectedChannels: $selectedChannels,
                            maxSelection: maxChannelSelection,
                            onLimitReached: { showLimitAlert = true }
                        )

                        // MARK: - Art & Culture
                        ChannelCategory(
                            title: NSLocalizedString("Art_Culture", comment: ""),
                            channels: ["Art", "Photography", "Craftsmanship", "Culture", "Music", "Fashion"],
                            selectedChannels: $selectedChannels,
                            maxSelection: maxChannelSelection,
                            onLimitReached: { showLimitAlert = true }
                        )

                        // MARK: - Technology & Digital
                        ChannelCategory(
                            title: NSLocalizedString("Technology_Digital", comment: ""),
                            channels: ["Tech", "AI", "Gaming", "Software"],
                            selectedChannels: $selectedChannels,
                            maxSelection: maxChannelSelection,
                            onLimitReached: { showLimitAlert = true }
                        )

                        // MARK: - Lifestyle & Travel
                        ChannelCategory(
                            title: NSLocalizedString("Lifestyle_Travel", comment: ""),
                            channels: ["Travel", "Food", "Charity"],
                            selectedChannels: $selectedChannels,
                            maxSelection: maxChannelSelection,
                            onLimitReached: { showLimitAlert = true }
                        )
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 20)
                    .padding(.bottom, 100)
                }

                Spacer()
            }

            // MARK: - 底部按钮（带白色遮挡背景）
            VStack {
                Spacer()

                Button(action: {
                    // 保存选择的频道并返回
                    saveSelectedChannels()
                    currentPage = .setting
                }) {
                    Text("Confirm")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 343, height: 46)
                        .background(Color(red: 0.87, green: 0.11, blue: 0.26))
                        .cornerRadius(31.50)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
                .background(DesignTokens.backgroundColor)
            }
        }
        .onAppear {
            // 页面出现时加载之前保存的选择
            loadSelectedChannels()
        }
        .alert("Selection Limit Reached", isPresented: $showLimitAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("You can only select up to \(maxChannelSelection) channels. Please deselect one before adding another.")
        }
    }

    // MARK: - 保存选择的频道到 UserDefaults
    private func saveSelectedChannels() {
        if let encoded = try? JSONEncoder().encode(Array(selectedChannels)) {
            savedChannelsData = encoded
        }
    }

    // MARK: - 从 UserDefaults 加载之前保存的频道
    private func loadSelectedChannels() {
        if let decoded = try? JSONDecoder().decode([String].self, from: savedChannelsData) {
            selectedChannels = Set(decoded)
        }
    }
}

// MARK: - 频道分类组件
struct ChannelCategory: View {
    let title: String
    let channels: [String]
    @Binding var selectedChannels: Set<String>
    let maxSelection: Int
    let onLimitReached: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 分类标题
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(DesignTokens.textPrimary)
                .padding(.leading, 4)

            // 频道标签网格
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(channels, id: \.self) { channel in
                    SelectableChannelTag(
                        name: channel,
                        isSelected: selectedChannels.contains(channel),
                        onTap: {
                            if selectedChannels.contains(channel) {
                                // 取消选择
                                selectedChannels.remove(channel)
                            } else {
                                // 检查是否达到最大选择数量
                                if selectedChannels.count >= maxSelection {
                                    onLimitReached()
                                } else {
                                    selectedChannels.insert(channel)
                                }
                            }
                        }
                    )
                }
            }
        }
    }
}

// MARK: - 频道标签组件
struct SelectableChannelTag: View {
    let name: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                // Plus 图标
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? DesignTokens.accentColor : DesignTokens.textPrimary)

                Text(name)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? DesignTokens.accentColor : DesignTokens.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
        }
        .background(isSelected ? DesignTokens.accentLight : DesignTokens.surface)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? DesignTokens.accentColor : DesignTokens.borderColor, lineWidth: 0.5)
        )
    }
}

#Preview {
    MyChannelsView(currentPage: .constant(.setting))
}
