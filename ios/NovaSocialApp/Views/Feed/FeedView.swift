import SwiftUI

struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @State private var selectedPost: Post?
    @State private var scrollPosition: UUID?
    @State private var scrollProxy: ScrollViewProxy?
    @State private var showScrollToTopButton = false
    @State private var lastScrollOffset: CGFloat = 0
    // Chat launcher
    @State private var showChatLauncher = false
    @State private var launchPeerId: UUID? = nil
    @State private var launchConversationId: UUID? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.isLoading && viewModel.posts.isEmpty {
                    // 骨架屏加载状态（更优雅）
                    ScrollView {
                        SkeletonPostList(count: 3)
                    }
                } else if viewModel.posts.isEmpty {
                    EmptyStateView(
                        icon: "photo.on.rectangle.angled",
                        title: "No Posts Yet",
                        message: "Start following people to see their posts here"
                    )
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                // 顶部锚点（用于快速返回顶部）
                                Color.clear
                                    .frame(height: 0)
                                    .id("top")

                                ForEach(viewModel.posts) { post in
                                    PostCell(
                                        post: post,
                                        onLike: {
                                            viewModel.toggleLike(for: post)
                                        },
                                        onTap: {
                                            // 保存滚动位置
                                            scrollPosition = post.id
                                            selectedPost = post
                                        }
                                    )
                                    .id(post.id) // 用于滚动位置恢复
                                    .onAppear {
                                        // 智能预加载
                                        Task {
                                            await viewModel.loadMoreIfNeeded(currentPost: post)
                                        }

                                        // 检测是否需要显示"返回顶部"按钮
                                        if let firstPost = viewModel.posts.first,
                                           post.id != firstPost.id {
                                            showScrollToTopButton = true
                                        }
                                    }
                                    .onDisappear {
                                        // 如果第一个帖子不可见，显示返回顶部按钮
                                        if let firstPost = viewModel.posts.first,
                                           post.id == firstPost.id {
                                            showScrollToTopButton = false
                                        }
                                    }

                                    Divider()
                                }

                                // 分页加载指示器
                                if viewModel.isLoadingMore {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Loading more...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding()
                                    .transition(.opacity)
                                }
                            }
                        }
                        .refreshable {
                            // 下拉刷新时触觉反馈
                            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                            impactFeedback.impactOccurred()

                            await viewModel.refreshFeed()
                        }
                        .onAppear {
                            // 保存 proxy 引用
                            scrollProxy = proxy

                            // 恢复滚动位置
                            if let position = scrollPosition {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    withAnimation(.easeInOut) {
                                        proxy.scrollTo(position, anchor: .top)
                                    }
                                }
                            }
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        // 快速返回顶部按钮
                        if showScrollToTopButton {
                            Button {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                    scrollProxy?.scrollTo("top", anchor: .top)
                                }

                                // 触觉反馈
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()

                                // 隐藏按钮
                                showScrollToTopButton = false
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 50, height: 50)
                                        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)

                                    Image(systemName: "arrow.up")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(.trailing, 20)
                            .padding(.bottom, 20)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
            }
            .navigationTitle("Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        // 点击 Logo 快速返回顶部
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            scrollProxy?.scrollTo("top", anchor: .top)
                        }

                        // 触觉反馈
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                    } label: {
                        Text("Nova")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showChatLauncher = true
                    } label: {
                        Image(systemName: "paperplane")
                    }
                }
            }
            .sheet(isPresented: $showChatLauncher, onDismiss: {
                // Reset for next time
                launchPeerId = nil
                launchConversationId = nil
            }) {
                if let convo = launchConversationId, let peer = launchPeerId {
                    NavigationStack { ChatView(conversationId: convo, peerUserId: peer) }
                } else {
                    StartChatSheetView { peer in
                        Task {
                            do {
                                let convo = try await MessagingRepository().createDirectConversation(with: peer)
                                await MainActor.run {
                                    launchPeerId = peer
                                    launchConversationId = convo
                                }
                            } catch {
                                // You can surface an error toast here via existing ErrorMessageView pattern
                                print("Failed to create conversation: \(error)")
                            }
                        }
                    }
                }
            }
            .navigationDestination(item: $selectedPost) { post in
                PostDetailView(post: post)
            }
            .task {
                if viewModel.posts.isEmpty {
                    await viewModel.loadInitialFeed()
                }
            }
            .errorAlert(
                isPresented: $viewModel.showError,
                message: viewModel.errorMessage
            )
        }
    }
}

#Preview {
    FeedView()
}
