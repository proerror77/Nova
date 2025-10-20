import SwiftUI
import PhotosUI

/// 图片选择器包装 - 支持单选和多选
///
/// Linus 风格：简单接口，清晰的回调
/// - 单张选择
/// - 多张批量选择
/// - 相机拍照
struct ImagePickerWrapper: View {
    @Binding var selectedImages: [UIImage]
    let maxSelection: Int
    let allowCamera: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var showSourcePicker = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false

    init(
        selectedImages: Binding<[UIImage]>,
        maxSelection: Int = 1,
        allowCamera: Bool = true
    ) {
        self._selectedImages = selectedImages
        self.maxSelection = maxSelection
        self.allowCamera = allowCamera
    }

    var body: some View {
        if allowCamera && maxSelection == 1 {
            // 显示来源选择器
            sourcePickerView
                .sheet(isPresented: $showPhotoPicker) {
                    PhotoPickerView(
                        selectedImages: $selectedImages,
                        maxSelection: maxSelection
                    )
                }
                .fullScreenCover(isPresented: $showCamera) {
                    CameraView(selectedImage: Binding(
                        get: { selectedImages.first },
                        set: { if let image = $0 { selectedImages = [image] } }
                    ))
                }
        } else {
            // 直接显示照片选择器
            PhotoPickerView(
                selectedImages: $selectedImages,
                maxSelection: maxSelection
            )
        }
    }

    // MARK: - Source Picker

    private var sourcePickerView: some View {
        VStack(spacing: 20) {
            Text("Choose Source")
                .font(.headline)

            Button {
                showCamera = true
            } label: {
                Label("Camera", systemImage: "camera")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }

            Button {
                showPhotoPicker = true
            } label: {
                Label("Photo Library", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }

            Button("Cancel") {
                dismiss()
            }
            .foregroundColor(.secondary)
        }
        .padding()
    }
}

// MARK: - Photo Picker View

struct PhotoPickerView: UIViewControllerRepresentable {
    @Binding var selectedImages: [UIImage]
    let maxSelection: Int

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = maxSelection

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPickerView

        init(_ parent: PhotoPickerView) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()

            guard !results.isEmpty else { return }

            var images: [UIImage] = []
            let group = DispatchGroup()

            for result in results {
                group.enter()

                result.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                    defer { group.leave() }

                    if let image = object as? UIImage {
                        images.append(image)
                    }
                }
            }

            group.notify(queue: .main) {
                self.parent.selectedImages = images
            }
        }
    }
}

// MARK: - Camera View

struct CameraView: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
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
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - 便捷扩展

extension View {
    /// 显示图片选择器
    func imagePicker(
        isPresented: Binding<Bool>,
        selectedImages: Binding<[UIImage]>,
        maxSelection: Int = 1,
        allowCamera: Bool = true
    ) -> some View {
        sheet(isPresented: isPresented) {
            ImagePickerWrapper(
                selectedImages: selectedImages,
                maxSelection: maxSelection,
                allowCamera: allowCamera
            )
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var images: [UIImage] = []
        @State private var showPicker = false

        var body: some View {
            VStack {
                if images.isEmpty {
                    Text("No images selected")
                } else {
                    ScrollView {
                        ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 200)
                        }
                    }
                }

                Button("Select Images") {
                    showPicker = true
                }
                .buttonStyle(.borderedProminent)
            }
            .imagePicker(
                isPresented: $showPicker,
                selectedImages: $images,
                maxSelection: 5
            )
        }
    }

    return PreviewWrapper()
}
