import Foundation
import SwiftUI
import PhotosUI

@MainActor
final class CreatePostViewModel: ObservableObject {
    // MARK: - Constants
    static let maxImagesPerPost = 9

    // MARK: - Published Properties
    @Published var selectedImages: [UIImage] = []
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
        !selectedImages.isEmpty && !isUploading
    }

    var canAddMoreImages: Bool {
        selectedImages.count < Self.maxImagesPerPost
    }

    var imageCountDisplay: String {
        "\(selectedImages.count)/\(Self.maxImagesPerPost)"
    }

    // MARK: - Initialization
    init(postRepository: PostRepository = PostRepository()) {
        self.postRepository = postRepository
    }

    // MARK: - Public Methods

    func createPost() async -> Bool {
        guard !selectedImages.isEmpty else {
            showErrorMessage("Please select at least one image")
            return false
        }

        isUploading = true
        uploadProgress = 0
        errorMessage = nil

        do {
            var uploadedImageIds: [String] = []
            let totalImages = selectedImages.count
            let progressPerImage = 0.8 / Double(totalImages)

            // Upload each image
            for (index, image) in selectedImages.enumerated() {
                // 1. Get upload URL
                let uploadInfo = try await postRepository.getUploadURL(
                    contentType: "image/jpeg"
                )

                // 2. Upload image
                guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                    throw NSError(domain: "ImageError", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Failed to convert image to data"
                    ])
                }

                try await postRepository.uploadImage(
                    data: imageData,
                    to: uploadInfo.uploadUrl
                )

                uploadedImageIds.append(uploadInfo.fileKey)
                uploadProgress = 0.2 + (Double(index + 1) * progressPerImage)
            }

            uploadProgress = 0.8

            // 3. Create post with all images
            _ = try await postRepository.createPost(
                fileKey: uploadedImageIds.first ?? "",
                caption: caption.isEmpty ? nil : caption,
                imageIds: uploadedImageIds
            )

            uploadProgress = 1.0
            isUploading = false

            // Reset form
            selectedImages = []
            caption = ""

            return true
        } catch {
            showErrorMessage(error.localizedDescription)
            isUploading = false
            return false
        }
    }

    func addImages(_ images: [UIImage]) {
        let availableSlots = Self.maxImagesPerPost - selectedImages.count
        let imagesToAdd = Array(images.prefix(availableSlots))
        selectedImages.append(contentsOf: imagesToAdd)

        if images.count > availableSlots {
            showErrorMessage("Only \(availableSlots) more image(s) can be added (max \(Self.maxImagesPerPost) total)")
        }
    }

    func removeImage(at index: Int) {
        guard index >= 0 && index < selectedImages.count else { return }
        selectedImages.remove(at: index)
    }

    func removeAllImages() {
        selectedImages.removeAll()
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
