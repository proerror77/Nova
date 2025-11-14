import Foundation
import SwiftUI
import AVFoundation

// MARK: - Media View Model

@MainActor
class MediaViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var selectedImage: UIImage?
    @Published var selectedVideo: URL?
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var cameraPosition: CameraPosition = .back
    @Published var flashMode: FlashMode = .off
    @Published var errorMessage: String?

    // MARK: - Enums

    enum CameraPosition {
        case front
        case back
    }

    enum FlashMode {
        case on
        case off
        case auto
    }

    enum MediaType {
        case photo
        case video
    }

    // MARK: - Services

    private let mediaService = MediaService()

    // MARK: - Camera Actions

    func toggleCamera() {
        cameraPosition = cameraPosition == .front ? .back : .front
    }

    func toggleFlash() {
        switch flashMode {
        case .off: flashMode = .on
        case .on: flashMode = .auto
        case .auto: flashMode = .off
        }
    }

    func capturePhoto() {
        // TODO: Implement photo capture
    }

    func startRecording() {
        isRecording = true
        // TODO: Implement video recording start
    }

    func stopRecording() {
        isRecording = false
        // TODO: Implement video recording stop
    }

    // MARK: - Upload

    func uploadMedia(userId: String) async -> String? {
        guard let image = selectedImage,
              let imageData = image.jpegData(compressionQuality: 0.8) else {
            return nil
        }

        do {
            let url = try await mediaService.uploadImage(image: imageData, userId: userId)
            return url
        } catch {
            errorMessage = "Upload failed: \(error.localizedDescription)"
            return nil
        }
    }
}
