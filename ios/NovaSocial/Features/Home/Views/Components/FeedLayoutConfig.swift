import SwiftUI

// MARK: - Feed Layout Configuration
/// Feed 布局配置，控制内容的显示顺序和插入规则
/// 修改这里的配置即可调整 Feed 中各组件的显示顺序

struct FeedLayoutConfig {
    /// 每隔多少个 PostCard 后插入一个轮播图区域
    /// 设置为 4 表示：4个帖子 -> 轮播图 -> 4个帖子 -> 轮播图 ...
    /// 设置为 0 或负数表示不插入轮播图
    static let postsBeforeCarousel: Int = 4

    /// 是否在 Feed 开始时先显示轮播图
    static let showCarouselFirst: Bool = false

    /// 是否启用轮播图插入
    static let carouselEnabled: Bool = true

    /// 是否只显示一次轮播图（4个帖子后显示一次，之后全是帖子）
    static let showCarouselOnlyOnce: Bool = true
}

// MARK: - Feed Item Type
/// Feed 中可显示的内容类型
enum FeedItemType: Identifiable {
    case post(index: Int, post: FeedPost)
    case carousel(id: Int)

    var id: String {
        switch self {
        case .post(let index, let post):
            return "post-\(index)-\(post.id)"
        case .carousel(let id):
            return "carousel-\(id)"
        }
    }
}

// MARK: - Feed Layout Builder
/// 根据配置生成 Feed 内容顺序
struct FeedLayoutBuilder {
    /// 根据帖子列表生成带轮播图的 Feed 内容顺序
    /// - Parameter posts: 帖子列表
    /// - Returns: 排列好的 Feed 内容项
    static func buildFeedItems(from posts: [FeedPost]) -> [FeedItemType] {
        guard FeedLayoutConfig.carouselEnabled,
              FeedLayoutConfig.postsBeforeCarousel > 0 else {
            // 不插入轮播图，直接返回所有帖子
            return posts.enumerated().map { FeedItemType.post(index: $0.offset, post: $0.element) }
        }

        var items: [FeedItemType] = []
        var carouselId = 0
        var hasInsertedCarousel = false

        // 是否先显示轮播图
        if FeedLayoutConfig.showCarouselFirst {
            items.append(.carousel(id: carouselId))
            carouselId += 1
            hasInsertedCarousel = true
        }

        // 遍历帖子，每 N 个帖子后插入轮播图
        for (index, post) in posts.enumerated() {
            items.append(.post(index: index, post: post))

            // 检查是否需要插入轮播图 (每 N 个帖子后)
            let postNumber = index + 1
            if postNumber % FeedLayoutConfig.postsBeforeCarousel == 0 {
                // 如果只显示一次轮播图，检查是否已经插入过
                if FeedLayoutConfig.showCarouselOnlyOnce && hasInsertedCarousel {
                    continue
                }
                items.append(.carousel(id: carouselId))
                carouselId += 1
                hasInsertedCarousel = true
            }
        }

        return items
    }
}
