import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.isAuthenticated {
                MainTabView()
            } else {
                AuthenticationView()
            }
        }
        .animation(.easeInOut, value: appState.isAuthenticated)
    }
}

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var showCreateSheet = false
    @State private var showMediaPicker = false
    @State private var showCameraView = false
    @State private var selectedImage: UIImage?
    @State private var selectedVideoURL: URL?

    var body: some View {
        TabView(selection: $selectedTab) {
            FeedView()
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Home")
                }
                .tag(0)

            ExploreView()
                .tabItem {
                    Image(systemName: "magnifyingglass")
                    Text("Explore")
                }
                .tag(1)

            // "Create" Tab - 显示底部菜单
            ZStack {
                Color.clear

                VStack {
                    Spacer()

                    VStack(spacing: 16) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)

                        Text("Create")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Share your photo or video")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    Spacer()
                }
            }
            .tabItem {
                Image(systemName: "plus.square.fill")
                Text("Create")
            }
            .tag(2)
            .onTapGesture {
                showCreateSheet = true
            }

            NotificationView()
                .tabItem {
                    Image(systemName: "bell.fill")
                    Text("Notifications")
                }
                .tag(3)

            ProfileView()
                .tabItem {
                    Image(systemName: "person.fill")
                    Text("Profile")
                }
                .tag(4)
        }
        // 底部菜单
        .sheet(isPresented: $showCreateSheet) {
            CreateMediaBottomSheet(
                onSelectMedia: {
                    showMediaPicker = true
                },
                onOpenCamera: {
                    showCameraView = true
                },
                onCreateReel: {
                    // 暂时不实现
                }
            )
        }
        // 相册选择
        .sheet(isPresented: $showMediaPicker) {
            MediaPickerView(
                image: $selectedImage,
                videoURL: $selectedVideoURL,
                onImageSelected: { image in
                    selectedImage = image
                    showMediaPicker = false
                    showCreatePost(withImage: image)
                },
                onVideoSelected: { url in
                    selectedVideoURL = url
                    showMediaPicker = false
                    showCreatePost(withVideoURL: url)
                }
            )
        }
        // 相机拍摄
        .sheet(isPresented: $showCameraView) {
            CameraView(
                onPhotoCaptured: { image in
                    selectedImage = image
                    showCameraView = false
                    showCreatePost(withImage: image)
                },
                onVideoCaptured: { url in
                    selectedVideoURL = url
                    showCameraView = false
                    showCreatePost(withVideoURL: url)
                }
            )
        }
    }

    private func showCreatePost(withImage image: UIImage) {
        // 导航到创建帖子页面（传递图片）
        // 这里使用 NavigationStack 或其他导航方式
    }

    private func showCreatePost(withVideoURL url: URL) {
        // 导航到创建帖子页面（传递视频）
        // 这里使用 NavigationStack 或其他导航方式
    }
}
