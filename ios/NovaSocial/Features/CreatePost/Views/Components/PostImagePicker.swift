import SwiftUI
import AVFoundation
import MobileCoreServices
import UniformTypeIdentifiers

/// Media picker for camera capture in post creation
/// Supports photos and videos
struct PostImagePicker: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType
    @Binding var selectedImage: UIImage?
    var onVideoSelected: ((URL) -> Void)? = nil
    var allowsVideo: Bool = false
    @Environment(\.presentationMode) private var presentationMode

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator

        // Configure media types based on what's allowed
        if allowsVideo && sourceType == .camera {
            picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
            picker.videoMaximumDuration = 60  // 60 seconds max
            picker.videoQuality = .typeHigh
        }

        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: PostImagePicker

        init(_ parent: PostImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            // Check if it's a video
            if let mediaType = info[.mediaType] as? String,
               mediaType == UTType.movie.identifier,
               let videoURL = info[.mediaURL] as? URL {
                // Copy video to temp directory
                let tempDir = FileManager.default.temporaryDirectory
                let fileName = "camera_video_\(UUID().uuidString).mov"
                let destURL = tempDir.appendingPathComponent(fileName)

                do {
                    try FileManager.default.copyItem(at: videoURL, to: destURL)
                    parent.onVideoSelected?(destURL)
                } catch {
                    #if DEBUG
                    print("[PostImagePicker] Failed to copy video: \(error)")
                    #endif
                }
            }
            // Check if it's an image
            else if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }

            parent.presentationMode.wrappedValue.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

// Type alias for backward compatibility
typealias ImagePicker = PostImagePicker
