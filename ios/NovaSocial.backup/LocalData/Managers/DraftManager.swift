import Foundation
import UIKit

// MARK: - DraftManager (草稿管理器)

/// 草稿管理器 - 处理帖子草稿的自动保存和过期清理
/// Linus 原则：简单直接，解决真实问题（防止用户丢失内容）
actor DraftManager {
    static let shared = DraftManager()

    private let storage = LocalStorageManager.shared
    private let autoSaveInterval: TimeInterval = 10 // 10 秒
    private let draftExpiry: TimeInterval = 24 * 3600 // 24 小时

    // 草稿 ID（固定使用同一个草稿）
    private let draftId = "current_draft"

    private init() {}

    // MARK: - Public API

    /// 保存草稿
    func saveDraft(text: String, images: [UIImage]) async throws {
        // 1. 保存图片到本地
        let imagePaths = try await saveImagesToLocal(images)

        // 2. 获取或创建草稿
        let draft = try await getOrCreateDraft()

        // 3. 更新草稿内容
        draft.text = text
        draft.imagePaths = imagePaths
        draft.lastAutoSaveAt = Date()

        try await storage.update(draft)
        print("✅ Draft saved: \(text.prefix(30))...")
    }

    /// 自动保存草稿（每 10 秒调用一次）
    func autoSave(text: String) async throws {
        let draft = try await getOrCreateDraft()

        // 检查是否需要自动保存（距离上次保存超过 10 秒）
        guard draft.shouldAutoSave() else {
            return
        }

        draft.text = text
        draft.lastAutoSaveAt = Date()

        try await storage.update(draft)
        print("💾 Auto-saved draft: \(text.prefix(30))...")
    }

    /// 获取草稿
    func getDraft() async throws -> (text: String, images: [UIImage])? {
        guard let draft = try await fetchDraft() else {
            return nil
        }

        // 检查是否过期
        if draft.isExpired {
            try await deleteDraft()
            print("🗑️ Draft expired and deleted")
            return nil
        }

        // 加载本地图片
        let images = await loadImagesFromLocal(draft.imagePaths)

        return (draft.text, images)
    }

    /// 删除草稿（发送成功后调用）
    func deleteDraft() async throws {
        guard let draft = try await fetchDraft() else {
            return
        }

        // 删除本地图片
        await deleteImagesFromLocal(draft.imagePaths)

        // 删除草稿记录
        try await storage.delete(draft)
        print("✅ Draft deleted")
    }

    /// 清理过期草稿（定期调用）
    func cleanupExpiredDrafts() async throws {
        let allDrafts = try await storage.fetchAll(LocalDraft.self)

        var deletedCount = 0
        for draft in allDrafts {
            if draft.isExpired {
                await deleteImagesFromLocal(draft.imagePaths)
                try await storage.delete(draft)
                deletedCount += 1
            }
        }

        if deletedCount > 0 {
            print("✅ Cleaned up \(deletedCount) expired drafts")
        }
    }

    // MARK: - Private Helpers

    private func getOrCreateDraft() async throws -> LocalDraft {
        if let existingDraft = try await fetchDraft() {
            return existingDraft
        }

        let newDraft = LocalDraft(id: draftId)
        try await storage.save(newDraft)
        return newDraft
    }

    private func fetchDraft() async throws -> LocalDraft? {
        try await storage.fetchFirst(
            LocalDraft.self,
            predicate: #Predicate { $0.id == draftId }
        )
    }

    // MARK: - Image Persistence

    private func saveImagesToLocal(_ images: [UIImage]) async throws -> [String] {
        var imagePaths: [String] = []

        for (index, image) in images.enumerated() {
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                continue
            }

            let filename = "draft_image_\(index)_\(UUID().uuidString).jpg"
            let fileURL = getDraftsDirectory().appendingPathComponent(filename)

            try imageData.write(to: fileURL)
            imagePaths.append(filename)
        }

        return imagePaths
    }

    private func loadImagesFromLocal(_ imagePaths: [String]) async -> [UIImage] {
        var images: [UIImage] = []

        for path in imagePaths {
            let fileURL = getDraftsDirectory().appendingPathComponent(path)

            if let imageData = try? Data(contentsOf: fileURL),
               let image = UIImage(data: imageData) {
                images.append(image)
            }
        }

        return images
    }

    private func deleteImagesFromLocal(_ imagePaths: [String]) async {
        for path in imagePaths {
            let fileURL = getDraftsDirectory().appendingPathComponent(path)
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func getDraftsDirectory() -> URL {
        let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!

        let draftsDirectory = documentsDirectory.appendingPathComponent("Drafts")

        // 创建目录（如果不存在）
        if !FileManager.default.fileExists(atPath: draftsDirectory.path) {
            try? FileManager.default.createDirectory(
                at: draftsDirectory,
                withIntermediateDirectories: true
            )
        }

        return draftsDirectory
    }
}
