//
//  DeepLinkRouter.swift
//  NovaSocial
//
//  深层链接路由器 - Linus 式简洁设计
//  100 行代码搞定全部路由,不需要什么"路由引擎"
//

import SwiftUI
import Foundation

// MARK: - 深层链接路由器

/// 深层链接路由器
/// 支持:
/// - novassocial://user/{userId}
/// - novassocial://post/{postId}
/// - novassocial://search?q={query}
/// - novassocial://notifications
/// - novassocial://auth/verify?token={token}
/// - https://nova.social/user/{userId} (Universal Links)
@MainActor
final class DeepLinkRouter: ObservableObject {
    // MARK: - 导航状态

    @Published var activeRoute: DeepLinkRoute?

    // MARK: - 单例

    static let shared = DeepLinkRouter()

    private init() {}

    // MARK: - 路由处理

    /// 处理深层链接 URL
    func handle(_ url: URL) {
        guard let route = parse(url) else {
            print("❌ [DeepLink] 无法解析 URL: \(url)")
            return
        }

        print("✅ [DeepLink] 解析成功: \(route)")
        activeRoute = route

        // 可选:记录分析事件
        logDeepLinkEvent(route)
    }

    /// 解析 URL 为路由
    private func parse(_ url: URL) -> DeepLinkRoute? {
        // 支持自定义 scheme (novassocial://) 和 Universal Links (https://nova.social)
        let path = url.path
        let query = parseQuery(url.query)

        // 路由匹配 (从最具体到最通用)
        if path.hasPrefix("/user/"), let userId = extractId(from: path, prefix: "/user/") {
            return .userProfile(userId: userId)
        }

        if path.hasPrefix("/post/"), let postId = extractId(from: path, prefix: "/post/") {
            return .postDetail(postId: postId)
        }

        if path.hasPrefix("/search"), let searchQuery = query["q"] {
            return .search(query: searchQuery)
        }

        if path.hasPrefix("/notifications") {
            return .notifications
        }

        if path.hasPrefix("/auth/verify"), let token = query["token"] {
            return .emailVerification(token: token)
        }

        if path.hasPrefix("/explore") {
            return .explore
        }

        if path == "/" || path.isEmpty {
            return .home
        }

        return nil
    }

    /// 提取路径参数 (如 /user/123 提取出 123)
    private func extractId(from path: String, prefix: String) -> String? {
        guard path.hasPrefix(prefix) else { return nil }
        let id = path.replacingOccurrences(of: prefix, with: "")
        return id.isEmpty ? nil : id
    }

    /// 解析 URL 查询参数
    private func parseQuery(_ query: String?) -> [String: String] {
        guard let query = query else { return [:] }
        var params: [String: String] = [:]

        for component in query.components(separatedBy: "&") {
            let parts = component.components(separatedBy: "=")
            guard parts.count == 2 else { continue }
            let key = parts[0].removingPercentEncoding ?? parts[0]
            let value = parts[1].removingPercentEncoding ?? parts[1]
            params[key] = value
        }

        return params
    }

    /// 记录深层链接事件 (可选)
    private func logDeepLinkEvent(_ route: DeepLinkRoute) {
        // TODO: 集成分析工具 (Firebase, Mixpanel 等)
        print("📊 [Analytics] DeepLink: \(route)")
    }

    // MARK: - 编程式导航

    /// 导航到用户资料
    func navigateToUser(_ userId: String) {
        activeRoute = .userProfile(userId: userId)
    }

    /// 导航到帖子详情
    func navigateToPost(_ postId: String) {
        activeRoute = .postDetail(postId: postId)
    }

    /// 导航到搜索
    func navigateToSearch(query: String) {
        activeRoute = .search(query: query)
    }

    /// 清除当前路由
    func clearRoute() {
        activeRoute = nil
    }
}

// MARK: - 路由枚举

enum DeepLinkRoute: Equatable {
    case home
    case userProfile(userId: String)
    case postDetail(postId: String)
    case search(query: String)
    case notifications
    case explore
    case emailVerification(token: String)

    var description: String {
        switch self {
        case .home:
            return "首页"
        case .userProfile(let userId):
            return "用户资料: \(userId)"
        case .postDetail(let postId):
            return "帖子详情: \(postId)"
        case .search(let query):
            return "搜索: \(query)"
        case .notifications:
            return "通知"
        case .explore:
            return "探索"
        case .emailVerification(let token):
            return "邮件验证: \(token)"
        }
    }
}

// MARK: - 深层链接生成器

extension DeepLinkRoute {
    /// 生成分享链接 (Universal Link)
    var shareURL: URL? {
        let baseURL = "https://nova.social"

        switch self {
        case .home:
            return URL(string: baseURL)
        case .userProfile(let userId):
            return URL(string: "\(baseURL)/user/\(userId)")
        case .postDetail(let postId):
            return URL(string: "\(baseURL)/post/\(postId)")
        case .search(let query):
            let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            return URL(string: "\(baseURL)/search?q=\(encodedQuery)")
        case .notifications:
            return URL(string: "\(baseURL)/notifications")
        case .explore:
            return URL(string: "\(baseURL)/explore")
        case .emailVerification(let token):
            return URL(string: "\(baseURL)/auth/verify?token=\(token)")
        }
    }

    /// 生成自定义 scheme 链接
    var customSchemeURL: URL? {
        let scheme = "novassocial"

        switch self {
        case .home:
            return URL(string: "\(scheme)://")
        case .userProfile(let userId):
            return URL(string: "\(scheme)://user/\(userId)")
        case .postDetail(let postId):
            return URL(string: "\(scheme)://post/\(postId)")
        case .search(let query):
            let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            return URL(string: "\(scheme)://search?q=\(encodedQuery)")
        case .notifications:
            return URL(string: "\(scheme)://notifications")
        case .explore:
            return URL(string: "\(scheme)://explore")
        case .emailVerification(let token):
            return URL(string: "\(scheme)://auth/verify?token=\(token)")
        }
    }
}

// MARK: - SwiftUI 集成

extension View {
    /// 处理深层链接导航
    func handleDeepLinks(router: DeepLinkRouter) -> some View {
        self.sheet(item: Binding(
            get: { router.activeRoute },
            set: { router.activeRoute = $0 }
        )) { route in
            DeepLinkDestinationView(route: route)
        }
    }
}

// MARK: - 深层链接目标视图

struct DeepLinkDestinationView: View {
    let route: DeepLinkRoute
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            Group {
                switch route {
                case .userProfile(let userId):
                    ProfileView(userId: userId)

                case .postDetail(let postId):
                    PostDetailView(postId: postId)

                case .search(let query):
                    SearchResultsView(query: query)

                case .notifications:
                    NotificationView()

                case .explore:
                    ExploreView()

                case .emailVerification(let token):
                    EmailVerificationView(token: token)

                case .home:
                    FeedView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 临时视图 (待实现)

private struct SearchResultsView: View {
    let query: String

    var body: some View {
        VStack {
            Text("搜索: \(query)")
                .font(.title)
            Text("搜索功能即将推出")
                .foregroundColor(.secondary)
        }
        .navigationTitle("搜索")
    }
}

private struct EmailVerificationView: View {
    let token: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text("邮箱验证成功")
                .font(.title)

            Text("验证令牌: \(token)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .navigationTitle("邮箱验证")
    }
}

// MARK: - 分享扩展

extension DeepLinkRoute {
    /// 分享到系统分享面板
    func share(from view: UIView) {
        guard let url = shareURL else { return }

        let activityVC = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )

        // iPad 支持
        if let popoverController = activityVC.popoverPresentationController {
            popoverController.sourceView = view
            popoverController.sourceRect = view.bounds
        }

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - 使用示例

#if DEBUG
struct DeepLinkExamples {
    static func examples() {
        let router = DeepLinkRouter.shared

        // 处理用户点击深层链接
        let userURL = URL(string: "novassocial://user/123")!
        router.handle(userURL)

        // 处理 Universal Link
        let universalURL = URL(string: "https://nova.social/post/456")!
        router.handle(universalURL)

        // 编程式导航
        router.navigateToUser("789")

        // 生成分享链接
        let route = DeepLinkRoute.userProfile(userId: "123")
        let shareURL = route.shareURL
        print("分享链接: \(shareURL?.absoluteString ?? "无")")
    }
}
#endif
