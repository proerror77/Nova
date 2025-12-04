import Foundation

// MARK: - Sync State (数据同步状态)

/// 同步状态枚举
enum SyncState: String, Codable {
    case synced         // 已同步
    case localOnly      // 仅本地（未上传到服务器）
    case localModified  // 本地已修改（待同步）
    case conflict       // 冲突（本地和服务器都有修改）
}

// MARK: - Syncable Protocol

/// 可同步协议（所有本地模型的基础协议）
protocol Syncable {
    var id: String { get }
    var syncState: SyncState { get set }
    var localModifiedAt: Date? { get set }
}
