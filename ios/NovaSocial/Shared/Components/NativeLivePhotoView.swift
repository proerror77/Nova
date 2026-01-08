import SwiftUI
import PhotosUI

// MARK: - Native PHLivePhotoView Wrapper

/// SwiftUI wrapper for UIKit's PHLivePhotoView - provides native Live Photo experience
/// Use this for displaying Live Photos downloaded from server after rebuilding with PHLivePhoto.request
struct NativeLivePhotoView: UIViewRepresentable {
    let livePhoto: PHLivePhoto?
    var isMuted: Bool = true
    var autoPlay: Bool = false
    var contentMode: UIView.ContentMode = .scaleAspectFill

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = contentMode
        view.isMuted = isMuted
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        uiView.livePhoto = livePhoto
        uiView.isMuted = isMuted
        uiView.contentMode = contentMode

        // Auto-play if requested
        if autoPlay, livePhoto != nil {
            uiView.startPlayback(with: .full)
        }
    }
}

// MARK: - Interactive Live Photo Card

/// Interactive Live Photo card with native PHLivePhotoView and badge
struct NativeLivePhotoCard: View {
    let livePhoto: PHLivePhoto?
    var size: CGSize = CGSize(width: 320, height: 400)
    var showBadge: Bool = true
    var autoPlay: Bool = false
    var onTap: (() -> Void)? = nil

    @State private var isPlaying = false

    var body: some View {
        ZStack {
            if let livePhoto = livePhoto {
                NativeLivePhotoView(
                    livePhoto: livePhoto,
                    isMuted: true,
                    autoPlay: autoPlay
                )
                .frame(width: size.width, height: size.height)
                .clipped()
            } else {
                // Placeholder while loading
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: size.width, height: size.height)
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    )
            }

            // Live Photo badge (top-left)
            if showBadge && !isPlaying {
                VStack {
                    HStack {
                        LivePhotoBadge()
                        Spacer()
                    }
                    Spacer()
                }
                .padding(12)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }
}

// MARK: - Feed Native Live Photo Player

/// Native Live Photo player for feed display using PHLivePhotoView
/// Replaces the custom video-based player for true iOS Live Photo experience
struct FeedNativeLivePhotoPlayer: View {
    let imageUrl: String
    let videoUrl: String
    let height: CGFloat
    var onTap: (() -> Void)? = nil

    @StateObject private var loader = LivePhotoLoader()
    @State private var isPlaying = false

    var body: some View {
        ZStack {
            if let livePhoto = loader.livePhoto {
                // Native Live Photo view
                NativeLivePhotoView(
                    livePhoto: livePhoto,
                    isMuted: true,
                    contentMode: .scaleAspectFill
                )
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipped()

                // Live badge overlay
                VStack {
                    HStack {
                        LivePhotoBadge()
                        Spacer()
                    }
                    Spacer()
                }
                .padding(12)
                .opacity(isPlaying ? 0 : 1)

            } else {
                // Fallback: show still image while Live Photo loads
                AsyncImage(url: URL(string: imageUrl)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .overlay(
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            )
                    case .failure:
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.white.opacity(0.5))
                            )
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipped()

                // Show loading indicator if loader is working
                if loader.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            }
        }
        .frame(height: height)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .task {
            // Load Live Photo when view appears
            await loader.loadLivePhoto(imageUrl: imageUrl, videoUrl: videoUrl)
        }
    }
}

// MARK: - Preview Provider

#Preview("NativeLivePhotoCard - Loading") {
    NativeLivePhotoCard(
        livePhoto: nil,
        size: CGSize(width: 320, height: 400),
        showBadge: true
    )
}

#Preview("FeedNativeLivePhotoPlayer - Placeholder") {
    FeedNativeLivePhotoPlayer(
        imageUrl: "https://example.com/image.jpg",
        videoUrl: "https://example.com/video.mov",
        height: 400
    )
    .background(Color.black)
}
