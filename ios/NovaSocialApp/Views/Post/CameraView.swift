import SwiftUI
import AVFoundation

/// 相机拍摄 View
/// 支持照片和视频拍摄
struct CameraView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    var onPhotoCaptured: (UIImage) -> Void
    var onVideoCaptured: (URL) -> Void
    var mode: CameraMode = .both // 照片、视频或两者

    enum CameraMode {
        case photo
        case video
        case both
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator

        // 根据模式设置媒体类型
        switch mode {
        case .photo:
            picker.mediaTypes = ["public.image"]
            picker.cameraCaptureMode = .photo
        case .video:
            picker.mediaTypes = ["public.movie"]
            picker.cameraCaptureMode = .video
            picker.videoQuality = .typeHigh
        case .both:
            picker.mediaTypes = ["public.image", "public.movie"]
        }

        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView

        init(_ parent: CameraView) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.dismiss()

            // 检查是否是照片
            if let image = info[.originalImage] as? UIImage {
                parent.onPhotoCaptured(image)
            }
            // 检查是否是视频
            else if let videoURL = info[.mediaURL] as? URL {
                parent.onVideoCaptured(videoURL)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    CameraView(
        onPhotoCaptured: { _ in },
        onVideoCaptured: { _ in }
    )
}
