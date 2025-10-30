import SwiftUI
import PhotosUI

struct CreatePostView: View {
    @StateObject private var viewModel = CreatePostViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showSuccessAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: 20) {
                        // Image Count Display
                        if !viewModel.selectedImages.isEmpty {
                            HStack {
                                Text("Images Selected")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)

                                Spacer()

                                Text(viewModel.imageCountDisplay)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Image Grid
                        if !viewModel.selectedImages.isEmpty {
                            let columns = [
                                GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)
                            ]

                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(Array(viewModel.selectedImages.enumerated()), id: \.offset) { index, image in
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(minHeight: 100)
                                            .clipped()
                                            .cornerRadius(8)

                                        // Remove Button
                                        Button {
                                            viewModel.removeImage(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.title2)
                                                .foregroundColor(.white)
                                                .background(Color.black.opacity(0.6))
                                                .clipShape(Circle())
                                        }
                                        .padding(4)
                                    }
                                }

                                // Add More Button (if limit not reached)
                                if viewModel.canAddMoreImages {
                                    Button {
                                        viewModel.showImagePicker = true
                                    } label: {
                                        VStack(spacing: 8) {
                                            Image(systemName: "plus")
                                                .font(.title2)
                                                .foregroundColor(.gray)

                                            Text("Add")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .frame(minHeight: 100)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(8)
                                    }
                                }
                            }
                        } else {
                            // Image Picker Button (empty state)
                            Button {
                                viewModel.showImagePicker = true
                            } label: {
                                VStack(spacing: 16) {
                                    Image(systemName: "photo.on.rectangle.angled")
                                        .font(.system(size: 60))
                                        .foregroundColor(.gray)

                                    Text("Select Photos")
                                        .font(.headline)
                                        .foregroundColor(.primary)

                                    Text("Up to 9 images")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 300)
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            }
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
            .sheet(isPresented: $viewModel.showImagePicker) {
                MultiImagePicker(
                    images: $viewModel.selectedImages,
                    maxSelectable: CreatePostViewModel.maxImagesPerPost
                )
            }
            .alert("Success", isPresented: $showSuccessAlert) {
                Button("OK") {
                    // Could navigate back or reset
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
}

// MARK: - Multi Image Picker

struct MultiImagePicker: UIViewControllerRepresentable {
    @Binding var images: [UIImage]
    let maxSelectable: Int
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = maxSelectable
        config.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: MultiImagePicker

        init(_ parent: MultiImagePicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()

            let dispatchGroup = DispatchGroup()
            var selectedImages: [UIImage] = []
            var loadedCount = 0

            for result in results {
                dispatchGroup.enter()

                if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                    result.itemProvider.loadObject(ofClass: UIImage.self) { image, _ in
                        if let uiImage = image as? UIImage {
                            selectedImages.append(uiImage)
                        }
                        loadedCount += 1
                        dispatchGroup.leave()
                    }
                } else {
                    dispatchGroup.leave()
                }
            }

            dispatchGroup.notify(queue: .main) {
                self.parent.images = selectedImages
            }
        }
    }
}

#Preview {
    CreatePostView()
}
