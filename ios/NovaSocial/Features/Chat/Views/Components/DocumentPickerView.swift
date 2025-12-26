import SwiftUI
import UniformTypeIdentifiers

/// Document picker view - reads file data immediately in callback to avoid permission issues
struct DocumentPickerView: UIViewControllerRepresentable {
    let onDocumentPicked: (Data, String, String) -> Void  // (data, filename, mimeType)
    var onError: ((Error) -> Void)?

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [
            .pdf,
            .plainText,
            .image,
            .audio,
            .video,
            .data,
            .spreadsheet,
            .presentation,
            .item
        ])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerView

        init(_ parent: DocumentPickerView) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }

            // 立即開始安全範圍訪問（在回調中我們仍有隱式權限）
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let filename = url.lastPathComponent
            let mimeType = getMimeType(for: url)

            do {
                let data = try Data(contentsOf: url)
                parent.onDocumentPicked(data, filename, mimeType)
            } catch {
                // 如果是圖片類型，嘗試使用 UIImage 載入（處理編輯過的照片）
                if let image = UIImage(contentsOfFile: url.path),
                   let imageData = image.jpegData(compressionQuality: 0.8) {
                    let imageFilename = filename.hasSuffix(".jpg") || filename.hasSuffix(".jpeg")
                        ? filename
                        : "\(UUID().uuidString).jpg"
                    parent.onDocumentPicked(imageData, imageFilename, "image/jpeg")
                } else {
                    parent.onError?(error)
                }
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            // User cancelled - no action needed
        }

        /// 獲取檔案的 MIME 類型
        private func getMimeType(for url: URL) -> String {
            let pathExtension = url.pathExtension.lowercased()
            switch pathExtension {
            case "pdf":
                return "application/pdf"
            case "jpg", "jpeg":
                return "image/jpeg"
            case "png":
                return "image/png"
            case "gif":
                return "image/gif"
            case "heic", "heif":
                return "image/heic"
            case "mp4", "m4v":
                return "video/mp4"
            case "mov":
                return "video/quicktime"
            case "mp3":
                return "audio/mpeg"
            case "m4a":
                return "audio/mp4"
            case "wav":
                return "audio/wav"
            case "txt":
                return "text/plain"
            case "doc":
                return "application/msword"
            case "docx":
                return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            case "xls":
                return "application/vnd.ms-excel"
            case "xlsx":
                return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            case "ppt":
                return "application/vnd.ms-powerpoint"
            case "pptx":
                return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
            default:
                return "application/octet-stream"
            }
        }
    }
}
