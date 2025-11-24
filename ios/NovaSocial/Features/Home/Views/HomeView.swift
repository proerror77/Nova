import SwiftUI
import PhotosUI

struct HomeView: View {
    @Binding var currentPage: AppPage
    @Environment(\.dismiss) var dismiss
    @State private var showReportView = false
    @State private var showThankYouView = false
    @State private var showNewPost = false
    @State private var showSearch = false
    @State private var showNotification = false
    @State private var showPhotoOptions = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showGenerateImage = false

    var body: some View {
        ZStack {
            // 条件渲染：根据状态即时切换视图
            if showNotification {
                NotificationView(showNotification: $showNotification)
                    .transition(.identity)
            } else if showSearch {
                SearchView(showSearch: $showSearch)
                    .transition(.identity)
            } else if showNewPost {
                NewPostView(showNewPost: $showNewPost)
                    .transition(.identity)
            } else {
                homeContent
            }

            // MARK: - 照片选项弹窗
            if showPhotoOptions {
                photoOptionsModal
            }
        }
        .animation(.none, value: showNotification)
        .animation(.none, value: showSearch)
        .animation(.none, value: showNewPost)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showReportView) {
            ReportModal(isPresented: $showReportView, showThankYouView: $showThankYouView)
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(isPresented: $showCamera)
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showGenerateImage) {
            GenerateImage01View(showGenerateImage: $showGenerateImage)
        }
    }

    var homeContent: some View {
        ZStack {
            // 背景色 - 动态跟随主题
            DesignTokens.background
                .ignoresSafeArea()

            NavigationStack {
                VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack {
                    Button(action: { showSearch = true }) {
                        Image("Back-icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                    }
                    Spacer()
                    Image("ICERED-icon")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 18)
                    Spacer()
                    Button(action: { showNotification = true }) {
                        Image("Notice-icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                    }
                }
                .frame(height: DesignTokens.topBarHeight)
                .padding(.horizontal, 16)
                .background(DesignTokens.card)

                Divider()
                    .background(DesignTokens.divider)

                // MARK: - 可滚动内容区
                ScrollView {
                    VStack(spacing: 20) {
                        // MARK: - 评论卡片 1
                        CommentCardItem(imageAssetName: "post-image", showReportView: $showReportView)

                        // MARK: - 评论卡片 2
                        CommentCardItem(imageAssetName: "post-image-2", showReportView: $showReportView)

                        // MARK: - 评论卡片 3 (特殊版本)
                        CommentCardItem(hasExtraField: true, imageAssetName: "post-image-3", showReportView: $showReportView)

                        // MARK: - 标题部分
                        VStack(spacing: 8) {
                            Text("Hottest Banker in H.K.")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(DesignTokens.text)

                            Text("Corporate Poll")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(DesignTokens.textLight)
                        }
                        .frame(maxWidth: .infinity)

                        // MARK: - 轮播卡片容器 (水平滚动)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 20) {
                                // 卡片 1
                                CarouselCardItem(
                                    rankNumber: "1",
                                    name: "Lucy Liu",
                                    company: "Morgan Stanley",
                                    votes: "2293",
                                    isActive: true,
                                    imageAssetName: "PollCard-1"
                                )

                                // 卡片 2
                                CarouselCardItem(
                                    rankNumber: "2",
                                    name: "Lucy Liu",
                                    company: "Morgan Stanley",
                                    votes: "2293",
                                    isActive: false,
                                    imageAssetName: "PollCard-2"
                                )

                                // 卡片 3
                                CarouselCardItem(
                                    rankNumber: "3",
                                    name: "Lucy Liu",
                                    company: "Morgan Stanley",
                                    votes: "2293",
                                    isActive: false,
                                    imageAssetName: "PollCard-3"
                                )

                                // 卡片 4
                                CarouselCardItem(
                                    rankNumber: "4",
                                    name: "Lucy Liu",
                                    company: "Morgan Stanley",
                                    votes: "2293",
                                    isActive: false,
                                    imageAssetName: "PollCard-4"
                                )

                                // 卡片 5
                                CarouselCardItem(
                                    rankNumber: "5",
                                    name: "Lucy Liu",
                                    company: "Morgan Stanley",
                                    votes: "2293",
                                    isActive: false,
                                    imageAssetName: "PollCard-5"
                                )
                            }
                            .padding(.horizontal)
                        }
                        .frame(height: 320)

                        // MARK: - 分页指示点
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(red: 0.82, green: 0.11, blue: 0.26))
                                .frame(width: 6, height: 6)

                            ForEach(0..<4, id: \.self) { _ in
                                Circle()
                                    .fill(DesignTokens.textLight.opacity(0.5))
                                    .frame(width: 6, height: 6)
                            }
                        }

                        // MARK: - View more 按钮
                        HStack(spacing: 8) {
                            Text("view more")
                                .font(.system(size: 13))
                                .foregroundColor(Color(red: 0.81, green: 0.13, blue: 0.25))

                            Rectangle()
                                .stroke(Color(red: 0.81, green: 0.13, blue: 0.25), lineWidth: 0.5)
                                .frame(height: 1)
                                .frame(width: 50)
                        }
                        .padding(.top, 10)
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity)
                    .background(DesignTokens.background)
                }
                .padding(.bottom, -43)
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 0)
                }

                // MARK: - 底部导航栏
                HStack(spacing: -20) {
                    // Home
                    VStack(spacing: 2) {
                        Image("home-icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 22)
                        Text("Home")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                    }
                     .frame(maxWidth: .infinity)

                    // Message
                    VStack(spacing: 4) {
                        Image("Message-icon-black")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                        Text("Message")
                            .font(.system(size: 9))
                            .foregroundColor(DesignTokens.text)
                    }
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        currentPage = .message
                    }

                    // New Post
                    NewPostButtonComponent(showNewPost: $showPhotoOptions)

                    // Alice
                    VStack(spacing: -12) {
                        Image("alice-icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                        Text("")
                            .font(.system(size: 9))
                    }
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        currentPage = .alice
                    }

                    // Account
                    VStack(spacing: 4) {
                        Image("Account-icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                        Text("Account")
                            .font(.system(size: 9))
                            .foregroundColor(DesignTokens.text)
                    }
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        currentPage = .account
                    }
                }
                .frame(height: 60)
                .padding(.bottom, 20)
                .background(DesignTokens.card)
                .border(DesignTokens.border, width: 0.5)
                .offset(y: 35)
                }
            }
        }
    }

    // MARK: - 照片选项弹窗
    private var photoOptionsModal: some View {
        ZStack {
            // 半透明背景遮罩
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    showPhotoOptions = false
                }

            // 弹窗内容
            VStack {
                Spacer()

                ZStack() {
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 375, height: 270)
                        .background(.white)
                        .cornerRadius(11)
                        .offset(x: 0, y: 0)
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 56, height: 7)
                        .background(Color(red: 0.82, green: 0.11, blue: 0.26))
                        .cornerRadius(3.50)
                        .offset(x: -0.50, y: -120.50)

                    // Choose Photo
                    Button(action: {
                        showPhotoOptions = false
                        showPhotoPicker = true
                    }) {
                        Text("Choose Photo")
                            .font(Font.custom("Helvetica Neue", size: 18).weight(.medium))
                            .foregroundColor(Color(red: 0.18, green: 0.18, blue: 0.18))
                    }
                    .offset(x: 0, y: -79)

                    // Take Photo
                    Button(action: {
                        showPhotoOptions = false
                        showCamera = true
                    }) {
                        Text("Take Photo")
                            .font(Font.custom("Helvetica Neue", size: 18).weight(.medium))
                            .foregroundColor(Color(red: 0.18, green: 0.18, blue: 0.18))
                    }
                    .offset(x: 0.50, y: -21)

                    // Generate image
                    Button(action: {
                        showPhotoOptions = false
                        showGenerateImage = true
                    }) {
                        Text("Generate image")
                            .font(Font.custom("Helvetica Neue", size: 18).weight(.medium))
                            .foregroundColor(Color(red: 0.18, green: 0.18, blue: 0.18))
                    }
                    .offset(x: 0, y: 37)

                    // Cancel
                    Button(action: {
                        showPhotoOptions = false
                    }) {
                        Text("Cancel")
                            .font(Font.custom("Helvetica Neue", size: 18).weight(.medium))
                            .lineSpacing(20)
                            .foregroundColor(.black)
                    }
                    .offset(x: -0.50, y: 105)

                    // 分隔线
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 375, height: 0)
                        .overlay(
                            Rectangle()
                                .stroke(Color(red: 0.93, green: 0.93, blue: 0.93), lineWidth: 3)
                        )
                        .offset(x: 0, y: 75)
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 375, height: 0)
                        .overlay(
                            Rectangle()
                                .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.20)
                        )
                        .offset(x: 0, y: -50)
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 375, height: 0)
                        .overlay(
                            Rectangle()
                                .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.20)
                        )
                        .offset(x: 0, y: 8)
                }
                .frame(width: 375, height: 270)
                .padding(.bottom, 50)
            }
        }
    }
}

// MARK: - 轮播卡片组件
struct CarouselCardItem: View {
    let rankNumber: String
    let name: String
    let company: String
    let votes: String
    let isActive: Bool
    let imageAssetName: String  // ✅ 新增参数：图片资源名称

    var body: some View {
        VStack(spacing: 16) {
            // 图片区域
            Image(imageAssetName)  // ✅ 使用参数，支持动态图片名称
                .resizable()
                .scaledToFill()
                .frame(height: 250)
                .clipped()
                .cornerRadius(15)

            // 排名和信息
            HStack(spacing: 12) {
                Text(rankNumber)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 35, height: 35)
                    .background(Color(red: 0.82, green: 0.11, blue: 0.26))
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DesignTokens.text)

                    Text(company)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignTokens.textLight)
                }

                Spacer()

                Text(votes)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DesignTokens.textLight)
            }
        }
        .padding()
        .background(DesignTokens.card)
        .cornerRadius(12)
        .frame(width: 310)
    }
}

// MARK: - 评论卡片组件
struct CommentCardItem: View {
    var hasExtraField: Bool = false
    let imageAssetName: String
    @Binding var showReportView: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - 用户信息头（顶部）
            HStack(spacing: 10) {
                // 头像
                Circle()
                    .fill(DesignTokens.placeholder)
                    .frame(width: 40, height: 40)

                // 用户信息
                VStack(alignment: .leading, spacing: 2) {
                    Text("Simone Carter")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DesignTokens.text)

                    Text("1d")
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.textLight)
                }

                Spacer()

                // 菜单按钮 - 点击跳转到 ReportModal
                Button(action: {
                    showReportView = true
                }) {
                    Image(systemName: "ellipsis")
                        .foregroundColor(DesignTokens.text)
                        .font(.system(size: 14))
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // MARK: - 主图片区域（中间）
            Image(imageAssetName)  // ✅ 使用参数，支持动态图片名称
                .resizable()
                .scaledToFill()  // 改为 scaledToFill() 填满容器，多余部分裁剪
                .frame(maxWidth: .infinity, minHeight: 200)  // 固定宽度，最小高度 200
                .clipped()
                .cornerRadius(12)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            // MARK: - 分页指示点
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(red: 0.81, green: 0.13, blue: 0.25))
                    .frame(width: 6, height: 6)

                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Color(red: 0.85, green: 0.85, blue: 0.85))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 160)
            .padding(.vertical, 6)

            // MARK: - 评论文本（下部）
            HStack(spacing: 4) {
                Text("kyleegigstead Cyborg dreams...")
                    .font(.system(size: 13))
                    .foregroundColor(DesignTokens.text)

                Text("up")
                    .font(.system(size: 11))
                    .foregroundColor(DesignTokens.textLight)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // MARK: - 交互按钮
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.system(size: 10))
                        .foregroundColor(DesignTokens.text)
                    Text("0")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(DesignTokens.text)
                }

                HStack(spacing: 6) {
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 10))
                        .foregroundColor(DesignTokens.text)
                    Text("0")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(DesignTokens.text)
                }

                HStack(spacing: 6) {
                    Image(systemName: "bubble.right")
                        .font(.system(size: 10))
                        .foregroundColor(DesignTokens.text)
                    Text("0")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(DesignTokens.text)
                }

                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 10))
                        .foregroundColor(DesignTokens.text)
                    Text("Share")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(DesignTokens.text)
                }

                Spacer()

                Image(systemName: "bookmark")
                    .font(.system(size: 12))
                    .foregroundColor(DesignTokens.text)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(DesignTokens.card)
        .cornerRadius(12)
    }
}

// MARK: - New Post Button Component
struct NewPostButtonComponent: View {
    @State private var isPressed = false
    @Binding var showNewPost: Bool

    var body: some View {
        VStack(spacing: -10) {
            Image("Newpost-icon")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .opacity(isPressed ? 0.5 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isPressed)
            Text("")
                .font(.system(size: 9))
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            // 点击时淡出动画
            isPressed = true

            // 动画结束后即时切换（无过渡动画）
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                showNewPost = true
            }

            // 重置状态
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isPressed = false
            }
        }
    }
}

#Preview {
    HomeView(currentPage: .constant(.home))
}
