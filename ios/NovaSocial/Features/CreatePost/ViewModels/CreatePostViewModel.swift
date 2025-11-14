import Foundation
import SwiftUI

// MARK: - Create Post View Model

@MainActor
class CreatePostViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var content: String = ""
    @Published var selectedImages: [Data] = []
    @Published var isUploading = false
    @Published var uploadProgress: Double = 0.0
    @Published var errorMessage: String?

    // MARK: - Services

    private let contentService = ContentService()
    private let mediaService = MediaService()

    // MARK: - Computed Properties

    var canPost: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Actions

    func addImage(_ imageData: Data) {
        selectedImages.append(imageData)
    }

    func removeImage(at index: Int) {
        selectedImages.remove(at: index)
    }

    func createPost(userId: String) async -> Bool {
        guard canPost else { return false }

        isUploading = true
        errorMessage = nil

        do {
            // TODO: Upload images first if any
            // TODO: Create post with content
            let post = try await contentService.createPost(creatorId: userId, content: content)

            // Reset form
            content = ""
            selectedImages = []
            isUploading = false
            return true
        } catch {
            errorMessage = "Failed to create post: \(error.localizedDescription)"
            isUploading = false
            return false
        }
    }

    func cancel() {
        content = ""
        selectedImages = []
        errorMessage = nil
    }
}
