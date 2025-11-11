 import SwiftUI

// MARK: - Design Tokens
struct DesignTokens {
    // Colors
    static let backgroundColor = Color(red: 0.97, green: 0.96, blue: 0.96)
    static let white = Color.white
    static let textPrimary = Color(red: 0.38, green: 0.37, blue: 0.37)
    static let textSecondary = Color(red: 0.68, green: 0.68, blue: 0.68)
    static let accentColor = Color(red: 0.82, green: 0.13, blue: 0.25)
    static let accentLight = Color(red: 1, green: 0.78, blue: 0.78)
    static let borderColor = Color(red: 0.74, green: 0.74, blue: 0.74)
    static let placeholderColor = Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50)

    // Spacing
    static let spacing8: CGFloat = 8
    static let spacing16: CGFloat = 16
    static let spacing13: CGFloat = 13

    // Sizes
    static let tagWidth: CGFloat = 173.36
    static let tagHeight: CGFloat = 30.80
    static let avatarSize: CGFloat = 38
    static let topBarHeight: CGFloat = 56  // 统一的顶部导航栏高度（与 HomeView 一致）
}

struct NewPostView: View {
    @Binding var showNewPost: Bool
    @State private var postText: String = "Where to camp in Shanghai?"
    @State private var selectedChannels: Set<Int> = [6]
    @State private var showUserMenu = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var showLocation = false

    var body: some View {
        ZStack {
            // 条件渲染：根据状态即时切换视图
            if showPhotoPicker {
                PhotoPickerView(showPhotoPicker: $showPhotoPicker)
                    .transition(.identity)
            } else if showCamera {
                CameraScreen(showCamera: $showCamera)
                    .transition(.identity)
            } else if showLocation {
                LocationView(showLocation: $showLocation)
                    .transition(.identity)
            } else {
                newPostContent
            }
        }
        .animation(.none, value: showPhotoPicker)
        .animation(.none, value: showCamera)
        .animation(.none, value: showLocation)
    }

    var newPostContent: some View {
        ZStack {
            // Background
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Navigation Bar
                TopNavigationBar(showNewPost: $showNewPost)
                    .background(Color.white)

                Divider()
                    .frame(height: 0.5)
                    .background(DesignTokens.borderColor)

                // Text Input Area
                TextInputArea(text: $postText)
                    .padding(.horizontal, DesignTokens.spacing16)
                    .padding(.vertical, 16)

                // Post As Section
                PostAsSection()
                    .padding(.horizontal, DesignTokens.spacing16)
                    .padding(.vertical, 0)

                // Quick Actions with Avatar in same row
                HStack(spacing: 50) {
                    // Add photos
                    Button(action: {
                        showPhotoPicker = true
                    }) {
                        QuickActionButton(label: "Add photos")
                    }
                    .frame(width: 55, height: 80)

                    // Alice avatar only
                    VStack(spacing: 4) {
                        Image("alice-icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                    }
                    .frame(width: 45, height: 80)

                    // Take photos
                    Button(action: {
                        showCamera = true
                    }) {
                        QuickActionButton(label: "Take photos")
                    }
                    .frame(width: 55, height: 80)

                    // Add Location
                    Button(action: {
                        showLocation = true
                    }) {
                        QuickActionButton(label: "Add Location")
                    }
                    .frame(width: 55, height: 80)
                }
                .padding(.horizontal, DesignTokens.spacing16)
                .padding(.vertical, 0)

                // Suggested Channels Title
                Text("Suggested Channels")
                    .font(.custom("Helvetica Neue", size: 18, relativeTo: .headline))
                    .fontWeight(.medium)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DesignTokens.spacing16)
                    .padding(.bottom, 16)
                    .padding(.top, -2)

                // Scrollable Suggested Channels
                ScrollView {
                    SuggestedChannelsSection(selectedChannels: $selectedChannels)
                        .padding(.horizontal, DesignTokens.spacing16)
                        .padding(.vertical, 0)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .transition(.opacity)
    }
}

// MARK: - Header View
struct HeaderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Suggested Channels")
                .font(.custom("Helvetica Neue", size: 16, relativeTo: .headline))
                .fontWeight(.medium)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DesignTokens.spacing16)

            // Channels Grid
            VStack(spacing: 12) {
                HStack(spacing: 20) {
                    ChannelTag(title: "American Football", isHighlighted: false)
                    ChannelTag(title: "Snowboarding", isHighlighted: false)
                }

                HStack(spacing: 20) {
                    ChannelTag(title: "Camping", isHighlighted: true)
                    ChannelTag(title: "Tennis", isHighlighted: false)
                }

                HStack(spacing: 20) {
                    ChannelTag(title: "Sports", isHighlighted: false)
                    ChannelTag(title: "Football", isHighlighted: false)
                }

                HStack(spacing: 20) {
                    ChannelTag(title: "Tennis", isHighlighted: false)
                    ChannelTag(title: "Football", isHighlighted: false)
                }

                HStack(spacing: 20) {
                    ChannelTag(title: "Automotive", isHighlighted: true)
                    ChannelTag(title: "Sports", isHighlighted: false)
                }
            }
            .padding(.horizontal, DesignTokens.spacing16)
            .padding(.bottom, 12)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Channel Tag Component
struct ChannelTag: View {
    let title: String
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 5) {
            VStack {
                Rectangle()
                    .stroke(isHighlighted ? DesignTokens.accentColor : DesignTokens.textSecondary, lineWidth: 0.5)
                    .frame(height: 0)
                    .frame(width: 11)
            }

            VStack {
                Rectangle()
                    .stroke(isHighlighted ? DesignTokens.accentColor : DesignTokens.textSecondary, lineWidth: 0.5)
                    .frame(height: 0)
                    .frame(width: 11)
            }

            Text(title)
                .font(.custom("Helvetica Neue", size: 12, relativeTo: .caption))
                .lineSpacing(20)
                .foregroundColor(isHighlighted ? DesignTokens.accentColor : DesignTokens.textPrimary)
        }
        .padding(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
        .frame(maxWidth: .infinity)
        .frame(height: DesignTokens.tagHeight)
        .background(isHighlighted ? DesignTokens.accentLight : DesignTokens.white)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .inset(by: 0.5)
                .stroke(isHighlighted ? DesignTokens.accentColor : DesignTokens.textSecondary, lineWidth: 0.5)
        )
    }
}

// MARK: - Channel Grid Tag Component
struct ChannelGridTag: View {
    let title: String
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isHighlighted ? DesignTokens.accentColor : DesignTokens.textSecondary)

            Text(title)
                .font(.custom("Helvetica Neue", size: 13, relativeTo: .body))
                .foregroundColor(isHighlighted ? DesignTokens.accentColor : DesignTokens.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .background(isHighlighted ? DesignTokens.accentLight : Color.white)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .inset(by: 0.5)
                .stroke(isHighlighted ? DesignTokens.accentColor : DesignTokens.textSecondary, lineWidth: 0.5)
        )
    }
}

// MARK: - Post As Section
struct PostAsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Post as:")
                .font(.custom("Helvetica Neue", size: 16, relativeTo: .headline))
                .fontWeight(.medium)
                .foregroundColor(.black)

            HStack(spacing: 12) {
                // 使用 Account-icon 自定义头像图标
                Image("Account-icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: DesignTokens.avatarSize, height: DesignTokens.avatarSize)

                HStack {
                    Text("Kent Peng")
                        .font(.custom("Helvetica Neue", size: 16, relativeTo: .headline))
                        .fontWeight(.medium)
                        .foregroundColor(.black)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            .frame(height: 54)
            .background(DesignTokens.white)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .inset(by: 0.5)
                    .stroke(Color(red: 0.85, green: 0.85, blue: 0.85), lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Text Input Area
struct TextInputArea: View {
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Where to camp in Shanghai?", text: $text)
                .font(.custom("Helvetica Neue", size: 16, relativeTo: .body))
                .foregroundColor(DesignTokens.textPrimary)
                .frame(minHeight: 180, alignment: .topLeading)
                .padding(16)
                .background(Color(red: 0.85, green: 0.85, blue: 0.85))
                .cornerRadius(6)
        }
    }
}

// MARK: - Suggested Channels Section
struct SuggestedChannelsSection: View {
    @Binding var selectedChannels: Set<Int>

    let channels = [
        "Sports", "Tennis", "American Football", "Football",
        "Snowboarding", "Automotive", "Camping", "Tennis",
        "Tennis", "Football", "Sports", "American Football"
    ]

    var body: some View {
        VStack(spacing: 16) {
            ForEach(0..<(channels.count / 2), id: \.self) { index in
                HStack(spacing: 14) {
                    let channelIndex1 = index * 2
                    let channel1 = channels[channelIndex1]
                    let isSelected1 = selectedChannels.contains(channelIndex1)

                    Button(action: {
                        if isSelected1 {
                            selectedChannels.remove(channelIndex1)
                        } else {
                            selectedChannels.insert(channelIndex1)
                        }
                    }) {
                        ChannelGridTag(
                            title: channel1,
                            isHighlighted: isSelected1
                        )
                    }

                    if index * 2 + 1 < channels.count {
                        let channelIndex2 = index * 2 + 1
                        let channel2 = channels[channelIndex2]
                        let isSelected2 = selectedChannels.contains(channelIndex2)

                        Button(action: {
                            if isSelected2 {
                                selectedChannels.remove(channelIndex2)
                            } else {
                                selectedChannels.insert(channelIndex2)
                            }
                        }) {
                            ChannelGridTag(
                                title: channel2,
                                isHighlighted: isSelected2
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Quick Action Button
struct QuickActionButton: View {
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            // 使用系统图标
            if label == "Add photos" {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundColor(.black)
            } else if label == "Take photos" {
                Image(systemName: "camera.fill")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundColor(.black)
            } else if label == "Add Location" {
                Image(systemName: "location.fill")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundColor(.black)
            }

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.black)
                .lineLimit(1)
                .multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Top Navigation Bar
struct TopNavigationBar: View {
    @Binding var showNewPost: Bool

    var body: some View {
        HStack(spacing: 88) {
            Button(action: {
                showNewPost = false
            }) {
                Text("Cancel")
                    .font(.custom("Helvetica Neue", size: 14, relativeTo: .body))
                    .foregroundColor(.black)
            }

            Text("New post")
                .font(.custom("Helvetica Neue", size: 24, relativeTo: .title))
                .fontWeight(.medium)
                .foregroundColor(.black)

            Button(action: {}) {
                Text("Post")
                    .font(.custom("Helvetica Neue", size: 14, relativeTo: .body))
                    .foregroundColor(DesignTokens.accentColor)
            }
        }
        .frame(height: DesignTokens.topBarHeight)
        .padding(.horizontal, 16)
    }
}

#Preview {
    @Previewable @State var showNewPost = true
    NewPostView(showNewPost: $showNewPost)
}
