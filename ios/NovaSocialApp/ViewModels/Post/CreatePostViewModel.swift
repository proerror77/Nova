import Foundation
import SwiftUI
import PhotosUI

@MainActor
final class CreatePostViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var selectedImage: UIImage?
    @Published var caption = ""
    @Published var isUploading = false
    @Published var uploadProgress: Double = 0
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var showImagePicker = false

    // MARK: - Dependencies
    private let postRepository: PostRepository

    // MARK: - Computed Properties
    var canPost: Bool {
        selectedImage != nil && !isUploading
    }

    // MARK: - Initialization
    init(postRepository: PostRepository = PostRepository()) {
        self.postRepository = postRepository
    }

    // MARK: - Public Methods

    func createPost() async -> Bool {
        guard let image = selectedImage else {
            showErrorMessage("Please select an image")
            return false
        }

        isUploading = true
        uploadProgress = 0
        errorMessage = nil

        do {
            // 1. Get upload URL
            uploadProgress = 0.2
            let uploadInfo = try await postRepository.getUploadURL(
                contentType: "image/jpeg"
            )

            // 2. Upload image
            uploadProgress = 0.4
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                throw NSError(domain: "ImageError", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to convert image to data"
                ])
            }

            try await postRepository.uploadImage(
                data: imageData,
                to: uploadInfo.uploadUrl
            )

            uploadProgress = 0.7

            // 3. Create post
            _ = try await postRepository.createPost(
                fileKey: uploadInfo.fileKey,
                caption: caption.isEmpty ? nil : caption
            )

            uploadProgress = 1.0
            isUploading = false

            // Reset form
            selectedImage = nil
            caption = ""

            return true
        } catch {
            showErrorMessage(error.localizedDescription)
            isUploading = false
            return false
        }
    }

    func selectImage(_ image: UIImage) {
        selectedImage = image
    }

    func removeImage() {
        selectedImage = nil
    }

    func clearError() {
        errorMessage = nil
        showError = false
    }

    // MARK: - Private Helpers

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
}
