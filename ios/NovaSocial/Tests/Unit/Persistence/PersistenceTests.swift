import XCTest
import SwiftData
@testable import NovaSocial

/// PersistenceTests - 数据持久化系统完整测试
/// 覆盖范围：
/// 1. 缓存保存和读取
/// 2. 过期数据自动删除
/// 3. 冲突解决（Last Write Wins）
/// 4. 草稿自动保存
/// 5. 状态恢复
/// 6. 并发安全
/// 7. 大数据测试
final class PersistenceTests: XCTestCase {

    var storage: LocalStorageManager!
    var syncManager: SyncManager!
    var draftManager: DraftManager!

    override func setUp() async throws {
        try await super.setUp()
        storage = LocalStorageManager.shared
        syncManager = SyncManager.shared
        draftManager = DraftManager.shared

        // 清空测试数据
        try await storage.clearAll()
    }

    override func tearDown() async throws {
        try await storage.clearAll()
        try await super.tearDown()
    }

    // MARK: - Test 1: 缓存保存和读取

    func testCacheSaveAndFetch() async throws {
        // Given: 创建测试 Posts
        let posts = createTestPosts(count: 10)
        let localPosts = posts.map { LocalPost.from($0) }

        // When: 保存到本地
        try await storage.save(localPosts)

        // Then: 验证可以读取
        let fetchedPosts = try await storage.fetchAll(LocalPost.self)
        XCTAssertEqual(fetchedPosts.count, 10, "应该保存并读取到 10 条 Posts")

        // 验证内容正确性
        let firstFetched = fetchedPosts.first!
        let firstOriginal = posts.first!
        XCTAssertEqual(firstFetched.id, firstOriginal.id.uuidString)
        XCTAssertEqual(firstFetched.caption, firstOriginal.caption)
        XCTAssertEqual(firstFetched.likeCount, firstOriginal.likeCount)
    }

    // MARK: - Test 2: 过期数据自动删除

    func testExpiredDataDeletion() async throws {
        // Given: 创建过期和新鲜的数据
        let oldDate = Date().addingTimeInterval(-31 * 24 * 3600) // 31 天前
        let recentDate = Date()

        let oldPost = LocalPost(
            id: UUID().uuidString,
            userId: UUID().uuidString,
            imageUrl: "https://example.com/old.jpg",
            createdAt: oldDate
        )

        let recentPost = LocalPost(
            id: UUID().uuidString,
            userId: UUID().uuidString,
            imageUrl: "https://example.com/recent.jpg",
            createdAt: recentDate
        )

        try await storage.save([oldPost, recentPost])

        // When: 删除过期数据
        try await storage.deleteExpired()

        // Then: 验证只保留新鲜数据
        let remainingPosts = try await storage.fetchAll(LocalPost.self)
        XCTAssertEqual(remainingPosts.count, 1, "应该只保留 1 条新鲜数据")
        XCTAssertEqual(remainingPosts.first?.id, recentPost.id)
    }

    // MARK: - Test 3: 冲突解决（Last Write Wins）

    func testConflictResolution_LastWriteWins() async throws {
        // Given: 本地修改的 Post
        let postId = UUID()
        let localModifiedTime = Date()

        let localPost = LocalPost(
            id: postId.uuidString,
            userId: UUID().uuidString,
            caption: "Local version",
            imageUrl: "https://example.com/local.jpg",
            likeCount: 10,
            syncState: .localModified,
            localModifiedAt: localModifiedTime
        )

        try await storage.save(localPost)

        // Case 1: 远程更新时间更晚 - 应该使用远程版本
        let remotePostNewer = Post(
            id: postId,
            userId: UUID(),
            imageUrl: "https://example.com/remote.jpg",
            thumbnailUrl: nil,
            caption: "Remote version (newer)",
            likeCount: 20,
            commentCount: 5,
            isLiked: false,
            createdAt: localModifiedTime.addingTimeInterval(10), // 10 秒后
            user: nil
        )

        try await syncManager.syncPosts([remotePostNewer])

        let syncedPost1 = try await storage.fetchFirst(
            LocalPost.self,
            predicate: #Predicate { $0.id == postId.uuidString }
        )

        XCTAssertEqual(syncedPost1?.caption, "Remote version (newer)")
        XCTAssertEqual(syncedPost1?.likeCount, 20)
        XCTAssertEqual(syncedPost1?.syncState, .synced)

        // Case 2: 本地更新时间更晚 - 应该保留本地版本
        localPost.localModifiedAt = Date().addingTimeInterval(20)
        localPost.syncState = .localModified
        try await storage.update(localPost)

        let remotePostOlder = Post(
            id: postId,
            userId: UUID(),
            imageUrl: "https://example.com/remote2.jpg",
            thumbnailUrl: nil,
            caption: "Remote version (older)",
            likeCount: 30,
            commentCount: 10,
            isLiked: false,
            createdAt: Date(),
            user: nil
        )

        try await syncManager.syncPosts([remotePostOlder])

        let syncedPost2 = try await storage.fetchFirst(
            LocalPost.self,
            predicate: #Predicate { $0.id == postId.uuidString }
        )

        XCTAssertEqual(syncedPost2?.syncState, .conflict, "应该标记为冲突状态")
    }

    // MARK: - Test 4: 草稿自动保存（每 10 秒）

    func testDraftAutoSave() async throws {
        // Given: 创建草稿
        let text = "Test draft content"
        let images: [UIImage] = [] // 简化测试，不测试图片

        // When: 首次保存
        try await draftManager.saveDraft(text: text, images: images)

        // Then: 验证草稿已保存
        let draft1 = try await draftManager.getDraft()
        XCTAssertNotNil(draft1)
        XCTAssertEqual(draft1?.text, text)

        // When: 更新文本（模拟用户输入）
        let updatedText = "Updated draft content"
        try await draftManager.autoSave(text: updatedText)

        // Then: 验证草稿已更新
        let draft2 = try await draftManager.getDraft()
        XCTAssertEqual(draft2?.text, updatedText)

        // When: 删除草稿
        try await draftManager.deleteDraft()

        // Then: 验证草稿已删除
        let draft3 = try await draftManager.getDraft()
        XCTAssertNil(draft3)
    }

    // MARK: - Test 5: 状态恢复（滚动位置）

    func testScrollPositionRestore() async throws {
        // Given: 保存滚动位置
        let postId = "post-123"
        let stateManager = ViewStateManager.shared

        // When: 保存位置
        await stateManager.saveScrollPosition(postId, for: .feed)

        // Then: 验证可以恢复
        let restoredPosition = await stateManager.getScrollPosition(for: .feed)
        XCTAssertEqual(restoredPosition, postId)

        // When: 清除位置
        await stateManager.clearScrollPosition(for: .feed)

        // Then: 验证已清除
        let clearedPosition = await stateManager.getScrollPosition(for: .feed)
        XCTAssertNil(clearedPosition)
    }

    // MARK: - Test 6: 并发安全（多个写入同时进行）

    func testConcurrentWrites() async throws {
        // Given: 准备并发写入
        let taskCount = 100

        // When: 并发写入
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<taskCount {
                group.addTask {
                    let post = LocalPost(
                        id: UUID().uuidString,
                        userId: UUID().uuidString,
                        caption: "Concurrent post \(i)",
                        imageUrl: "https://example.com/\(i).jpg"
                    )

                    do {
                        try await self.storage.save(post)
                    } catch {
                        XCTFail("Concurrent write failed: \(error)")
                    }
                }
            }
        }

        // Then: 验证所有数据都已保存
        let allPosts = try await storage.fetchAll(LocalPost.self)
        XCTAssertEqual(allPosts.count, taskCount, "所有并发写入应该成功")
    }

    // MARK: - Test 7: 大数据测试（1000 条帖子）

    func testLargeDataSet() async throws {
        // Given: 创建 1000 条测试数据
        let largeCount = 1000
        let posts = createTestPosts(count: largeCount)
        let localPosts = posts.map { LocalPost.from($0) }

        // When: 保存大量数据
        let startTime = Date()
        try await storage.save(localPosts)
        let saveTime = Date().timeIntervalSince(startTime)

        print("✅ Saved \(largeCount) posts in \(saveTime) seconds")

        // Then: 验证读取性能
        let readStartTime = Date()
        let fetchedPosts = try await storage.fetchAll(LocalPost.self)
        let readTime = Date().timeIntervalSince(readStartTime)

        print("✅ Fetched \(largeCount) posts in \(readTime) seconds")

        XCTAssertEqual(fetchedPosts.count, largeCount)
        XCTAssertLessThan(saveTime, 5.0, "保存 1000 条数据应该在 5 秒内完成")
        XCTAssertLessThan(readTime, 1.0, "读取 1000 条数据应该在 1 秒内完成")

        // When: 测试 truncate（保留最新的 100 条）
        try await storage.truncate(LocalPost.self, maxCount: 100)

        // Then: 验证只保留 100 条
        let truncatedPosts = try await storage.fetchAll(LocalPost.self)
        XCTAssertEqual(truncatedPosts.count, 100)
    }

    // MARK: - Helper Methods

    private func createTestPosts(count: Int) -> [Post] {
        var posts: [Post] = []

        for i in 0..<count {
            let post = Post(
                id: UUID(),
                userId: UUID(),
                imageUrl: "https://example.com/post\(i).jpg",
                thumbnailUrl: "https://example.com/thumb\(i).jpg",
                caption: "Test post \(i)",
                likeCount: i * 10,
                commentCount: i * 2,
                isLiked: i % 2 == 0,
                createdAt: Date().addingTimeInterval(TimeInterval(-i * 3600)),
                user: nil
            )
            posts.append(post)
        }

        return posts
    }
}

// MARK: - Performance Benchmarks

extension PersistenceTests {
    /// 性能基准测试
    func testPerformanceBenchmarks() async throws {
        // 测试 1: 批量插入性能
        measure {
            Task {
                let posts = self.createTestPosts(count: 100)
                let localPosts = posts.map { LocalPost.from($0) }
                try await self.storage.save(localPosts)
            }
        }

        // 测试 2: 查询性能
        let posts = createTestPosts(count: 500)
        let localPosts = posts.map { LocalPost.from($0) }
        try await storage.save(localPosts)

        measure {
            Task {
                _ = try await self.storage.fetchAll(LocalPost.self)
            }
        }
    }
}
