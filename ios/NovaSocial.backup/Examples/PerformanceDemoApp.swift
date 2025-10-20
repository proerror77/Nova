import SwiftUI

/// 性能优化系统演示应用
/// 展示如何集成和使用所有性能优化组件
@main
struct PerformanceDemoApp: App {
    init() {
        // ⚡️ 一键配置性能优化系统
        PerformanceKit.configure(enableDebug: true)
    }

    var body: some Scene {
        WindowGroup {
            PerformanceDemoView()
        }
    }
}

// MARK: - Main Demo View

struct PerformanceDemoView: View {
    @StateObject private var viewModel = PerformanceDemoViewModel()

    var body: some View {
        NavigationView {
            List {
                // Section 1: 缓存演示
                Section("Cache Demo") {
                    Button("Test Cache Performance") {
                        Task {
                            await viewModel.testCachePerformance()
                        }
                    }

                    Button("Test TTL Expiration") {
                        Task {
                            await viewModel.testTTLExpiration()
                        }
                    }
                }

                // Section 2: 请求去重演示
                Section("Request Deduplication") {
                    Button("Test Concurrent Requests") {
                        Task {
                            await viewModel.testConcurrentRequests()
                        }
                    }

                    Button("Test Sequential Requests") {
                        Task {
                            await viewModel.testSequentialRequests()
                        }
                    }
                }

                // Section 3: Feed 性能演示
                Section("Feed Performance") {
                    NavigationLink("Feed with Cache") {
                        OptimizedFeedView()
                    }

                    NavigationLink("Feed without Cache") {
                        UnoptimizedFeedView()
                    }
                }

                // Section 4: 网络监听
                Section("Network Monitoring") {
                    HStack {
                        Text("Network Status:")
                        Spacer()
                        NetworkStatusIndicator()
                    }

                    Button("Toggle Network (Simulator)") {
                        // 在真机上需要手动切换网络
                        print("Switch to Airplane Mode to test")
                    }
                }

                // Section 5: 性能统计
                Section("Performance Stats") {
                    Button("Show Stats") {
                        PerformanceDebugView.printStats()
                    }

                    Button("Show Slow Requests") {
                        PerformanceDebugView.printSlowRequests()
                    }

                    Button("Show Recommendations") {
                        PerformanceRecommendations.printRecommendations()
                    }

                    Button("Reset All Stats") {
                        Task {
                            await PerformanceKit.reset()
                        }
                    }
                }

                // Section 6: 测试结果
                Section("Test Results") {
                    if let result = viewModel.lastTestResult {
                        Text(result)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Performance Demo")
        }
    }
}

// MARK: - Demo ViewModel

@MainActor
final class PerformanceDemoViewModel: ObservableObject {
    @Published var lastTestResult: String?

    func testCachePerformance() async {
        let cache = CacheManager(defaultTTL: 300)
        let testData = (1...100).map { "test_value_\($0)" }

        let start = Date()

        // 写入测试
        for (index, value) in testData.enumerated() {
            await cache.set(value, forKey: "key_\(index)")
        }

        let writeTime = Date().timeIntervalSince(start)

        // 读取测试
        let readStart = Date()
        for index in 0..<100 {
            let _: String? = await cache.get(forKey: "key_\(index)")
        }
        let readTime = Date().timeIntervalSince(readStart)

        lastTestResult = """
        ✅ Cache Performance Test
        Write: 100 entries in \(Int(writeTime * 1000))ms
        Read: 100 entries in \(Int(readTime * 1000))ms
        """
        print(lastTestResult!)
    }

    func testTTLExpiration() async {
        let cache = CacheManager(defaultTTL: 300)

        // 设置 1 秒过期
        await cache.set("short_lived", forKey: "test_ttl", ttl: 1.0)

        // 立即读取
        let value1: String? = await cache.get(forKey: "test_ttl")

        // 等待 2 秒
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        // 过期后读取
        let value2: String? = await cache.get(forKey: "test_ttl")

        lastTestResult = """
        ✅ TTL Expiration Test
        Before expiration: \(value1 ?? "nil")
        After expiration: \(value2 ?? "nil")
        """
        print(lastTestResult!)
    }

    func testConcurrentRequests() async {
        let deduplicator = RequestDeduplicator()
        var requestCount = 0

        func slowRequest() async throws -> String {
            requestCount += 1
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 秒
            return "result"
        }

        let start = Date()

        // 并发发起 5 个相同请求
        let results = try? await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    try await deduplicator.deduplicate(key: "test") {
                        try await slowRequest()
                    }
                }
            }

            var results: [String] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }

        let duration = Date().timeIntervalSince(start)

        lastTestResult = """
        ✅ Concurrent Request Test
        Requested: 5 times
        Executed: \(requestCount) time(s)
        Duration: \(Int(duration * 1000))ms
        Results: \(results?.count ?? 0)
        """
        print(lastTestResult!)
    }

    func testSequentialRequests() async {
        let deduplicator = RequestDeduplicator()
        var requestCount = 0

        func request() async throws -> String {
            requestCount += 1
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 秒
            return "result"
        }

        let start = Date()

        // 顺序发起 3 个请求
        for _ in 0..<3 {
            _ = try? await deduplicator.deduplicate(key: "test_\(requestCount)") {
                try await request()
            }
        }

        let duration = Date().timeIntervalSince(start)

        lastTestResult = """
        ✅ Sequential Request Test
        Requested: 3 times
        Executed: \(requestCount) times
        Duration: \(Int(duration * 1000))ms
        """
        print(lastTestResult!)
    }
}

// MARK: - Network Status Indicator

struct NetworkStatusIndicator: View {
    @State private var isConnected = true
    @State private var connectionType: ConnectionType = .wifi

    var body: some View {
        HStack {
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(isConnected ? connectionType.rawValue : "Offline")
                .font(.caption)
        }
        .onAppear {
            updateNetworkStatus()
            setupNetworkMonitoring()
        }
    }

    private func updateNetworkStatus() {
        isConnected = NetworkMonitor.shared.isConnected
        connectionType = NetworkMonitor.shared.connectionType
    }

    private func setupNetworkMonitoring() {
        NetworkMonitor.shared.onConnectionChanged = { [self] connected, type in
            DispatchQueue.main.async {
                self.isConnected = connected
                self.connectionType = type
            }
        }
    }
}

// MARK: - Optimized Feed View

struct OptimizedFeedView: View {
    @StateObject private var viewModel = OptimizedFeedViewModel()

    var body: some View {
        List {
            ForEach(viewModel.posts, id: \.id) { post in
                PostRowView(post: post)
            }

            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Optimized Feed")
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.loadFeed()
        }
    }
}

@MainActor
final class OptimizedFeedViewModel: ObservableObject {
    @Published var posts: [DemoPost] = []
    @Published var isLoading = false

    private let cache = CacheManager.shared
    private let deduplicator = RequestDeduplicator.shared

    func loadFeed() async {
        isLoading = true
        defer { isLoading = false }

        let cacheKey = "demo_feed"

        // 先查缓存
        if let cached: [DemoPost] = await cache.get(forKey: cacheKey) {
            posts = cached
            print("✅ Loaded from cache")
            return
        }

        // 网络请求（带去重）
        do {
            posts = try await deduplicator.deduplicate(key: cacheKey) {
                let timer = PerformanceTimer(path: "/demo/feed")

                // 模拟网络延迟
                try await Task.sleep(nanoseconds: 500_000_000)

                let mockPosts = Self.generateMockPosts()

                // 缓存结果
                await self.cache.set(mockPosts, forKey: cacheKey, ttl: 60)

                timer.stop(statusCode: 200)

                return mockPosts
            }
            print("✅ Loaded from network")
        } catch {
            print("❌ Load failed: \(error)")
        }
    }

    func refresh() async {
        await cache.remove(forKey: "demo_feed")
        await loadFeed()
    }

    private static func generateMockPosts() -> [DemoPost] {
        (1...20).map { i in
            DemoPost(
                id: "\(i)",
                content: "Demo post #\(i)",
                timestamp: Date()
            )
        }
    }
}

// MARK: - Unoptimized Feed View (for comparison)

struct UnoptimizedFeedView: View {
    @StateObject private var viewModel = UnoptimizedFeedViewModel()

    var body: some View {
        List {
            ForEach(viewModel.posts, id: \.id) { post in
                PostRowView(post: post)
            }

            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Unoptimized Feed")
        .refreshable {
            await viewModel.loadFeed()
        }
        .task {
            await viewModel.loadFeed()
        }
    }
}

@MainActor
final class UnoptimizedFeedViewModel: ObservableObject {
    @Published var posts: [DemoPost] = []
    @Published var isLoading = false

    func loadFeed() async {
        isLoading = true
        defer { isLoading = false }

        // 每次都从网络加载（无缓存，无去重）
        do {
            try await Task.sleep(nanoseconds: 500_000_000)
            posts = (1...20).map { i in
                DemoPost(
                    id: "\(i)",
                    content: "Demo post #\(i)",
                    timestamp: Date()
                )
            }
            print("✅ Loaded from network (no cache)")
        } catch {
            print("❌ Load failed: \(error)")
        }
    }
}

// MARK: - Post Row View

struct PostRowView: View {
    let post: DemoPost

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(post.content)
                .font(.body)

            Text(timeAgo(from: post.timestamp))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func timeAgo(from date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 {
            return "just now"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60))m ago"
        } else {
            return "\(Int(seconds / 3600))h ago"
        }
    }
}

// MARK: - Demo Models

struct DemoPost: Codable, Identifiable {
    let id: String
    let content: String
    let timestamp: Date
}
