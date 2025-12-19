import SwiftUI

struct UserProfileView: View {
    @Binding var showUserProfile: Bool
    @State private var selectedTab: ProfileTab = .posts
    @State private var isFollowing = true

    enum ProfileTab {
        case posts, saved, liked
    }

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部背景区域
                ZStack(alignment: .top) {
                    // 背景图片
                    Rectangle()
                        .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                        .frame(height: 500)
                        .clipped()
                        .blur(radius: 20)
                        .overlay(
                            Color.black.opacity(0.3)
                        )
                        .ignoresSafeArea(edges: .top)

                    VStack(spacing: 0) {
                        // MARK: - 顶部导航栏
                        HStack {
                            // 返回按钮
                            Button(action: {
                                showUserProfile = false
                            }) {
                                Image(systemName: "chevron.left")
                                    .frame(width: 24, height: 24)
                                    .foregroundColor(.white)
                            }

                            Spacer()

                            // 分享按钮
                            Button(action: {
                                // 分享操作
                            }) {
                                Image(systemName: "square.and.arrow.up")
                                    .frame(width: 24, height: 24)
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 60)
                        .padding(.bottom, 20)

                        // MARK: - 认证徽章
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(Typography.regular20)
                                .foregroundColor(.blue)

                            Text("Verified Icered Partner")
                                .font(Typography.regular13)
                                .foregroundColor(.white)
                        }
                        .padding(.bottom, 16)

                        // MARK: - 用户信息区域
                        VStack(spacing: 12) {
                            // 头像
                            ZStack {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 110, height: 110)

                                Circle()
                                    .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                                    .frame(width: 100, height: 100)
                            }

                            // 用户名
                            Text("Eli")
                                .font(Typography.bold20)
                                .foregroundColor(.white)

                            // 位置
                            Text("China")
                                .font(Typography.regular12)
                                .foregroundColor(.white)

                            // 职位
                            Text("Illustrator / Junior Illustrator")
                                .font(.system(size: 12, weight: .light))
                                .foregroundColor(.white.opacity(0.9))

                            // MARK: - 统计数据
                            HStack(spacing: 0) {
                                // Following
                                VStack(spacing: 4) {
                                    Text("Following")
                                        .font(Typography.regular16)
                                        .foregroundColor(.white)
                                    Text("592")
                                        .font(Typography.regular16)
                                        .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity)

                                // 分隔线
                                Rectangle()
                                    .fill(.white)
                                    .frame(width: 1, height: 30)

                                // Followers
                                VStack(spacing: 4) {
                                    Text("Followers")
                                        .font(Typography.regular16)
                                        .foregroundColor(.white)
                                    Text("1449")
                                        .font(Typography.regular16)
                                        .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity)

                                // 分隔线
                                Rectangle()
                                    .fill(.white)
                                    .frame(width: 1, height: 30)

                                // Likes
                                VStack(spacing: 4) {
                                    Text("Likes")
                                        .font(Typography.regular16)
                                        .foregroundColor(.white)
                                    Text("452")
                                        .font(Typography.regular16)
                                        .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .padding(.horizontal, 40)
                            .padding(.top, 10)

                            // MARK: - 操作按钮
                            HStack(spacing: 10) {
                                // Following 按钮
                                Button(action: {
                                    isFollowing.toggle()
                                }) {
                                    Text(isFollowing ? "Following" : "Follow")
                                        .font(Typography.regular12)
                                        .foregroundColor(.white)
                                        .frame(width: 105, height: 34)
                                        .background(Color(red: 0.87, green: 0.11, blue: 0.26))
                                        .cornerRadius(57)
                                }

                                // Add friends 按钮
                                Button(action: {
                                    // Add friends 操作
                                }) {
                                    Text("Add friends")
                                        .font(Typography.regular12)
                                        .foregroundColor(.white)
                                        .frame(width: 105, height: 34)
                                        .cornerRadius(57)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 57)
                                                .stroke(Color(red: 0.91, green: 0.91, blue: 0.91), lineWidth: 0.5)
                                        )
                                }

                                // Message 按钮
                                Button(action: {
                                    // Message 操作
                                }) {
                                    Text("Message")
                                        .font(Typography.regular12)
                                        .foregroundColor(.white)
                                        .frame(width: 105, height: 34)
                                        .cornerRadius(57)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 57)
                                                .stroke(Color(red: 0.91, green: 0.91, blue: 0.91), lineWidth: 0.5)
                                        )
                                }
                            }
                            .padding(.top, 8)
                        }
                        .padding(.bottom, 30)
                    }
                }
                .frame(height: 500)

                // MARK: - 标签栏
                VStack(spacing: 0) {
                    HStack {
                        Spacer()

                        HStack(spacing: 40) {
                            Button(action: {
                                selectedTab = .posts
                            }) {
                                Text("Posts")
                                    .font(Typography.semibold16)
                                    .foregroundColor(selectedTab == .posts ? Color(red: 0.82, green: 0.11, blue: 0.26) : .black)
                            }

                            Button(action: {
                                selectedTab = .saved
                            }) {
                                Text("Saved")
                                    .font(Typography.semibold16)
                                    .foregroundColor(selectedTab == .saved ? Color(red: 0.82, green: 0.11, blue: 0.26) : .black)
                            }

                            Button(action: {
                                selectedTab = .liked
                            }) {
                                Text("Liked")
                                    .font(Typography.semibold16)
                                    .foregroundColor(selectedTab == .liked ? Color(red: 0.82, green: 0.11, blue: 0.26) : .black)
                            }
                        }

                        Spacer()

                        Button(action: {
                            // 搜索操作
                        }) {
                            Image(systemName: "magnifyingglass")
                                .font(Typography.regular20)
                                .foregroundColor(.black)
                        }
                        .padding(.trailing, 20)
                    }
                    .padding(.vertical, 16)
                    .background(.white)

                    // 分隔线
                    Rectangle()
                        .fill(Color(red: 0.74, green: 0.74, blue: 0.74))
                        .frame(height: 0.5)
                }

                // MARK: - 帖子网格
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(0..<4, id: \.self) { index in
                            UserPostGridCard()
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)

                    Color.clear
                        .frame(height: 20)
                }
                .background(Color(red: 0.96, green: 0.96, blue: 0.96))
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - 用户帖子卡片组件
struct UserPostGridCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部用户信息
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Simone Carter")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black)

                    Text("1d")
                        .font(Typography.regular10)
                        .foregroundColor(.gray)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            // 图片占位符
            Rectangle()
                .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                .frame(height: 200)
                .cornerRadius(8)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            // 文字描述
            Text("kyleegigstead Cyborg dreams...")
                .font(Typography.semibold13)
                .foregroundColor(.black)
                .lineLimit(2)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
        .background(.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }
}

#Preview {
    UserProfileView(showUserProfile: .constant(true))
}
