import SwiftUI

struct MyChannelsView: View {
    @Binding var currentPage: AppPage
    @State private var selectedChannels: Set<String> = ["Camping", "Automotive", "NFT", "Crypto"]

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

                    Text("My Channels")
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
                    VStack(alignment: .leading, spacing: 20) {
                        // MARK: - Sports & Outdoor Activities
                        ChannelCategory(
                            title: "Sports & Outdoor Activities",
                            channels: ["Sports", "Tennis", "American Football", "Football", "Snowboarding", "Automotive", "Camping"],
                            selectedChannels: $selectedChannels
                        )

                        // MARK: - Science & Education
                        ChannelCategory(
                            title: "Science & Education",
                            channels: ["Astronomy", "Astrology", "Health", "Society"],
                            selectedChannels: $selectedChannels
                        )

                        // MARK: - Business & Finance
                        ChannelCategory(
                            title: "Business & Finance",
                            channels: ["Business", "Stocks", "Wealth", "Crypto", "NFT"],
                            selectedChannels: $selectedChannels
                        )

                        // MARK: - Art & Culture
                        ChannelCategory(
                            title: "Art & Culture",
                            channels: ["Art", "Photography", "Craftsmanship", "Culture", "Music", "Fashion"],
                            selectedChannels: $selectedChannels
                        )

                        // MARK: - Technology & Digital
                        ChannelCategory(
                            title: "Technology & Digital",
                            channels: ["Tech", "AI", "Gaming", "Software"],
                            selectedChannels: $selectedChannels
                        )

                        // MARK: - Lifestyle & Travel
                        ChannelCategory(
                            title: "Lifestyle & Travel",
                            channels: ["Travel", "Food", "Charity"],
                            selectedChannels: $selectedChannels
                        )
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 20)
                    .padding(.bottom, 100)
                }

                Spacer()
            }

            // MARK: - 底部按钮
            VStack {
                Spacer()

                Button(action: {
                    // TODO: 保存选择的频道
                }) {
                    Text("Choose Channels")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                }
                .frame(width: 343)
                .background(Color(red: 0.82, green: 0.13, blue: 0.25))
                .cornerRadius(36)
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - 频道分类组件
struct ChannelCategory: View {
    let title: String
    let channels: [String]
    @Binding var selectedChannels: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 分类标题
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(DesignTokens.text)
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
                                selectedChannels.remove(channel)
                            } else {
                                selectedChannels.insert(channel)
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
                    .foregroundColor(isSelected ? DesignTokens.accent : DesignTokens.text)

                Text(name)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? DesignTokens.accent : DesignTokens.text)
            }
            .padding(.horizontal, 55)
            .padding(.vertical, 4)
            .frame(height: 30)
        }
        .background(isSelected ? DesignTokens.accentLightColor : DesignTokens.card)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? DesignTokens.accent : DesignTokens.border, lineWidth: 0.5)
        )
    }
}

#Preview {
    MyChannelsView(currentPage: .constant(.setting))
}
