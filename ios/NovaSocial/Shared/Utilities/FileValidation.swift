import Foundation
import UIKit

// MARK: - File Validation

/// 文件驗證工具 - 檢查上傳文件的大小和類型
enum FileValidation {

    // MARK: - Configuration

    /// 最大文件大小配置
    enum FileSizeLimit {
        /// 圖片最大 10MB
        static let image: Int64 = 10 * 1024 * 1024
        /// 視頻最大 100MB
        static let video: Int64 = 100 * 1024 * 1024
        /// 音頻最大 25MB
        static let audio: Int64 = 25 * 1024 * 1024
        /// 一般文件最大 50MB
        static let document: Int64 = 50 * 1024 * 1024
    }

    /// 消息內容長度限制
    enum MessageLimit {
        /// 文字消息最大 5000 字符
        static let textLength: Int = 5000
    }

    /// 允許的文件類型
    enum AllowedMimeTypes {
        static let images = [
            "image/jpeg",
            "image/png",
            "image/gif",
            "image/webp",
            "image/heic",
            "image/heif"
        ]

        static let videos = [
            "video/mp4",
            "video/quicktime",
            "video/x-m4v",
            "video/mpeg"
        ]

        static let audio = [
            "audio/mpeg",
            "audio/mp4",
            "audio/m4a",
            "audio/x-m4a",
            "audio/wav",
            "audio/aac",
            "audio/ogg"
        ]

        static let documents = [
            "application/pdf",
            "application/msword",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "application/vnd.ms-excel",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "application/vnd.ms-powerpoint",
            "application/vnd.openxmlformats-officedocument.presentationml.presentation",
            "text/plain",
            "application/zip",
            "application/x-zip-compressed"
        ]

        static var all: [String] {
            images + videos + audio + documents
        }
    }

    // MARK: - Validation Errors

    enum ValidationError: LocalizedError {
        case fileTooLarge(maxSize: String, actualSize: String)
        case unsupportedFileType(mimeType: String)
        case emptyFile
        case messageTooLong(maxLength: Int, actualLength: Int)
        case invalidImage

        var errorDescription: String? {
            switch self {
            case .fileTooLarge(let maxSize, let actualSize):
                return "文件太大（\(actualSize)），最大允許 \(maxSize)"
            case .unsupportedFileType(let mimeType):
                return "不支援的文件類型：\(mimeType)"
            case .emptyFile:
                return "文件為空"
            case .messageTooLong(let maxLength, let actualLength):
                return "消息太長（\(actualLength) 字符），最大允許 \(maxLength) 字符"
            case .invalidImage:
                return "無效的圖片格式"
            }
        }
    }

    // MARK: - Validation Methods

    /// 驗證文件數據
    /// - Parameters:
    ///   - data: 文件數據
    ///   - mimeType: MIME 類型
    /// - Returns: 驗證結果
    static func validate(data: Data, mimeType: String) -> Result<Void, ValidationError> {
        // 檢查空文件
        guard !data.isEmpty else {
            return .failure(.emptyFile)
        }

        // 檢查文件類型
        guard AllowedMimeTypes.all.contains(mimeType.lowercased()) else {
            return .failure(.unsupportedFileType(mimeType: mimeType))
        }

        // 獲取文件大小限制
        let sizeLimit = getSizeLimit(for: mimeType)
        let fileSize = Int64(data.count)

        // 檢查文件大小
        guard fileSize <= sizeLimit else {
            return .failure(.fileTooLarge(
                maxSize: formatBytes(sizeLimit),
                actualSize: formatBytes(fileSize)
            ))
        }

        return .success(())
    }

    /// 驗證圖片
    /// - Parameters:
    ///   - image: UIImage 對象
    ///   - compressionQuality: 壓縮質量 (0.0-1.0)
    /// - Returns: 驗證結果，成功時返回壓縮後的數據
    static func validateImage(_ image: UIImage, compressionQuality: CGFloat = 0.8) -> Result<Data, ValidationError> {
        guard let data = image.jpegData(compressionQuality: compressionQuality) else {
            return .failure(.invalidImage)
        }

        let fileSize = Int64(data.count)

        guard fileSize <= FileSizeLimit.image else {
            return .failure(.fileTooLarge(
                maxSize: formatBytes(FileSizeLimit.image),
                actualSize: formatBytes(fileSize)
            ))
        }

        return .success(data)
    }

    /// 驗證消息文字長度
    /// - Parameter text: 消息文字
    /// - Returns: 驗證結果
    static func validateMessageText(_ text: String) -> Result<Void, ValidationError> {
        let length = text.count

        guard length <= MessageLimit.textLength else {
            return .failure(.messageTooLong(
                maxLength: MessageLimit.textLength,
                actualLength: length
            ))
        }

        return .success(())
    }

    // MARK: - Helper Methods

    /// 根據 MIME 類型獲取大小限制
    private static func getSizeLimit(for mimeType: String) -> Int64 {
        let type = mimeType.lowercased()

        if AllowedMimeTypes.images.contains(type) {
            return FileSizeLimit.image
        } else if AllowedMimeTypes.videos.contains(type) {
            return FileSizeLimit.video
        } else if AllowedMimeTypes.audio.contains(type) {
            return FileSizeLimit.audio
        } else {
            return FileSizeLimit.document
        }
    }

    /// 格式化字節數為可讀字符串
    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// 從文件擴展名推斷 MIME 類型
    static func mimeType(for fileExtension: String) -> String {
        let ext = fileExtension.lowercased()

        switch ext {
        // Images
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "heif": return "image/heif"

        // Videos
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "m4v": return "video/x-m4v"

        // Audio
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/m4a"
        case "wav": return "audio/wav"
        case "aac": return "audio/aac"

        // Documents
        case "pdf": return "application/pdf"
        case "doc": return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls": return "application/vnd.ms-excel"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "ppt": return "application/vnd.ms-powerpoint"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "txt": return "text/plain"
        case "zip": return "application/zip"

        default: return "application/octet-stream"
        }
    }
}
