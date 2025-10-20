import SwiftUI
import PhotosUI
import AVFoundation

struct CreatePostView: View {
    @StateObject private var viewModel = CreatePostViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showSuccessAlert = false
    @State private var showMediaPicker = false
    @State private var pickerSelection: PhotosPickerItem?
    @State private var selectedVideos: [URL] = []

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: 20) {
                        // Media Selection
                        if let image = viewModel.selectedImage {
                            // 图片预览
                            mediaImagePreview(image)
                        } else if viewModel.selectedVideoURL != nil {
                            // 视频预览
                            videoPreview
                        } else {
                            // 媒体选择按钮
                            mediaSelectionButtons
                        }

                        // Caption Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Caption")
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            TextEditor(text: $viewModel.caption)
                                .frame(height: 100)
                                .padding(8)
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                        }

                        // Upload Progress
                        if viewModel.isUploading {
                            VStack(spacing: 8) {
                                ProgressView(value: viewModel.uploadProgress)

                                Text("Uploading... \(Int(viewModel.uploadProgress * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }

                        // Error Message
                        if let errorMessage = viewModel.errorMessage {
                            ErrorMessageView(message: errorMessage)
                        }

                        // Post Button
                        Button {
                            Task {
                                let success = await viewModel.createPost()
                                if success {
                                    showSuccessAlert = true
                                }
                            }
                        } label: {
                            if viewModel.isUploading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Share Post")
                                    .fontWeight(.semibold)
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!viewModel.canPost)
                    }
                    .padding()
                }

                if viewModel.isUploading {
                    LoadingOverlay()
                }
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showMediaPicker) {
                MediaPickerView(
                    image: $viewModel.selectedImage,
                    videoURL: $viewModel.selectedVideoURL,
                    onImageSelected: { image in
                        viewModel.selectImage(image)
                        showMediaPicker = false
                    },
                    onVideoSelected: { url in
                        viewModel.selectVideo(url)
                        showMediaPicker = false
                    }
                )
            }
            .alert("Success", isPresented: $showSuccessAlert) {
                Button("OK") {
                    showSuccessAlert = false
                }
            } message: {
                Text("Your post has been shared!")
            }
            .errorAlert(
                isPresented: $viewModel.showError,
                message: viewModel.errorMessage
            )
        }
    }

    // MARK: - Subviews

    private var mediaSelectionButtons: some View {
        VStack(spacing: 12) {
            // 选择图片
            Button {
                showMediaPicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Add Photo")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("Select from your library")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }

            // 选择视频
            Button {
                showMediaPicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.red)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Add Video")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("Select from your library")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }

            Text("Caption is required")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func mediaImagePreview(_ image: UIImage) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(1, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()
                .cornerRadius(12)

            // Remove Button
            Button {
                viewModel.removeMedia()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundColor(.white)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .padding(8)

            // Badge
            VStack(alignment: .leading) {
                HStack(spacing: 4) {
                    Image(systemName: "photo.fill")
                        .font(.caption)
                    Text("PHOTO")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .padding(6)
                .background(Color.blue.opacity(0.9))
                .foregroundColor(.white)
                .cornerRadius(6)
                .padding(8)

                Spacer()
            }
        }
    }

    private var videoPreview: some View {
        ZStack(alignment: .topTrailing) {
            VStack {
                if let thumbnail = viewModel.videoThumbnail {
                    ZStack(alignment: .center) {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(16 / 9, contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .clipped()

                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                    }
                } else {
                    // 加载中
                    Rectangle()
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .foregroundColor(Color(.systemGray6))
                        .overlay {
                            ProgressView()
                        }
                }

                // 视频信息
                VStack(alignment: .leading, spacing: 4) {
                    Text("Duration: \(viewModel.videoDuration)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Size: \(viewModel.videoFileSize)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .cornerRadius(12)

            // Remove Button
            Button {
                viewModel.removeMedia()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundColor(.white)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .padding(8)

            // Badge
            VStack(alignment: .leading) {
                HStack(spacing: 4) {
                    Image(systemName: "video.fill")
                        .font(.caption)
                    Text("VIDEO")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .padding(6)
                .background(Color.red.opacity(0.9))
                .foregroundColor(.white)
                .cornerRadius(6)
                .padding(8)

                Spacer()
            }
        }
    }
}

// MARK: - Media Picker

struct MediaPickerView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Binding var videoURL: URL?
    @Environment(\.dismiss) private var dismiss

    var onImageSelected: (UIImage) -> Void
    var onVideoSelected: (URL) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIImagePickerController()
        controller.delegate = context.coordinator
        controller.mediaTypes = ["public.image", "public.movie"]
        controller.sourceType = .photoLibrary
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: MediaPickerView

        init(_ parent: MediaPickerView) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.dismiss()

            // 检查选择的是图片还是视频
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
                parent.onImageSelected(image)
            } else if let videoURL = info[.mediaURL] as? URL {
                parent.videoURL = videoURL
                parent.onVideoSelected(videoURL)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    CreatePostView()
}
