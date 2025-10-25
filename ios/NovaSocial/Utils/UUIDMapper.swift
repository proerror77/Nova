import Foundation
import CryptoKit

enum UUIDMapper {
    /// 將任意使用者字串 ID 轉為 UUID：
    /// - 若本身為合法 UUID，直接返回
    /// - 若非 UUID 且開關允許，透過 SHA256 將字串穩定映射為一個 UUID（固定版本/變體位）
    /// - 否則返回 nil
    static func userStringToUUID(_ raw: String?) -> UUID? {
        guard let raw, !raw.isEmpty else { return nil }
        if let direct = UUID(uuidString: raw) { return direct }
        guard FeatureFlags.enableNonUUIDUserIdMapping else { return nil }
        // Hash to 16 bytes
        let digest = SHA256.hash(data: Data(raw.utf8))
        var bytes = Array(digest)[0..<16]
        // Set version (0100 for v4) and variant (10xx)
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let t = uuid_t(bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
        return UUID(uuid: t)
    }
}

