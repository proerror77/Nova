import Foundation
import SwiftData

// MARK: - LocalDraft (草稿)

@Model
final class LocalDraft {
    @Attribute(.unique) var id: String
    var text: String
    var imagePaths: [String] // 本地图片路径（Documents 目录）
    var createdAt: Date
    var lastAutoSaveAt: Date

    init(
        id: String = UUID().uuidString,
        text: String = "",
        imagePaths: [String] = [],
        createdAt: Date = Date(),
        lastAutoSaveAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.imagePaths = imagePaths
        self.createdAt = createdAt
        self.lastAutoSaveAt = lastAutoSaveAt
    }
}

// MARK: - Helper Methods

extension LocalDraft {
    /// 是否为空草稿
    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && imagePaths.isEmpty
    }

    /// 是否过期（24小时）
    var isExpired: Bool {
        Date().timeIntervalSince(createdAt) > 24 * 3600
    }

    /// 自动保存间隔是否满足（10秒）
    func shouldAutoSave() -> Bool {
        Date().timeIntervalSince(lastAutoSaveAt) >= 10
    }
}
