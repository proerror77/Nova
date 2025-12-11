import SwiftUI
import PhotosUI
import AVKit

// MARK: - Live Photo View

/// A view that displays and plays Live Photos with press-to-play interaction
struct LivePhotoView: View {
    let livePhotoData: LivePhotoData
    let size: CGSize
    var showBadge: Bool = true
    var autoPlay: Bool = false
    
    @State private var isPlaying = false
    @State private var player: AVPlayer?
    
    var body: some View {
        ZStack {
            // Still image (always shown as base)
            Image(uiImage: livePhotoData.stillImage)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
            
            // Video overlay (shown when playing)
            if isPlaying, let player = player {
                VideoPlayerLayer(player: player)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .transition(.opacity)
            }
            
            // Live Photo badge
            if showBadge && !isPlaying {
                VStack {
                    HStack {
                        LivePhotoBadge()
                        Spacer()
                    }
                    Spacer()
                }
                .padding(8)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.1, pressing: { pressing in
            if pressing {
                startPlaying()
            } else {
                stopPlaying()
            }
        }, perform: {})
        .onAppear {
            if autoPlay {
                startPlaying()
            }
        }
        .onDisappear {
            stopPlaying()
        }
    }
    
    private func startPlaying() {
        guard !isPlaying else { return }
        
        // Create player if needed
        if player == nil {
            player = AVPlayer(url: livePhotoData.videoURL)
        }
        
        // Reset to beginning and play
        player?.seek(to: .zero)
        player?.play()
        
        withAnimation(.easeInOut(duration: 0.15)) {
            isPlaying = true
        }
        
        // Add observer for end of playback
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { _ in
            stopPlaying()
        }
    }
    
    private func stopPlaying() {
        player?.pause()
        withAnimation(.easeInOut(duration: 0.15)) {
            isPlaying = false
        }
    }
}

// MARK: - Live Photo Badge

/// Badge indicator showing "LIVE" label
struct LivePhotoBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            // Concentric circles icon (like iOS)
            Image(systemName: "livephoto")
                .font(.system(size: 10, weight: .semibold))
            
            Text("LIVE")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.5))
        )
    }
}

// MARK: - Live Photo Preview Card (for NewPostView)

/// Preview card for Live Photo in post creation
struct LivePhotoPreviewCard: View {
    let livePhotoData: LivePhotoData
    let onDelete: () -> Void
    
    @State private var isPlaying = false
    @State private var player: AVPlayer?
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Live Photo content
            ZStack {
                // Still image
                Image(uiImage: livePhotoData.stillImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 239, height: 290)
                    .clipped()
                
                // Video overlay when playing
                if isPlaying, let player = player {
                    VideoPlayerLayer(player: player)
                        .frame(width: 239, height: 290)
                        .clipped()
                }
                
                // Live badge
                VStack {
                    HStack {
                        LivePhotoBadge()
                        Spacer()
                    }
                    Spacer()
                    
                    // Hint text
                    if !isPlaying {
                        Text("Press and hold to play")
                            .font(.system(size: 11))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(4)
                            .padding(.bottom, 8)
                    }
                }
                .padding(8)
            }
            .frame(width: 239, height: 290)
            .cornerRadius(10)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.1, pressing: { pressing in
                if pressing {
                    startPlaying()
                } else {
                    stopPlaying()
                }
            }, perform: {})
            
            // Delete button
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.5))
                            .frame(width: 20, height: 20)
                    )
            }
            .padding(4)
        }
        .onDisappear {
            stopPlaying()
            player = nil
        }
    }
    
    private func startPlaying() {
        guard !isPlaying else { return }
        
        if player == nil {
            player = AVPlayer(url: livePhotoData.videoURL)
        }
        
        player?.seek(to: .zero)
        player?.play()
        
        withAnimation(.easeInOut(duration: 0.15)) {
            isPlaying = true
        }
        
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { _ in
            stopPlaying()
        }
    }
    
    private func stopPlaying() {
        player?.pause()
        withAnimation(.easeInOut(duration: 0.15)) {
            isPlaying = false
        }
    }
}

// MARK: - Feed Live Photo Player

/// Live Photo player for feed display (in FeedPostCard)
struct FeedLivePhotoPlayer: View {
    let imageUrl: String
    let videoUrl: String
    let height: CGFloat
    
    @State private var isPlaying = false
    @State private var player: AVPlayer?
    @State private var stillImage: UIImage?
    
    var body: some View {
        ZStack {
            // Still image (loaded from URL)
            AsyncImage(url: URL(string: imageUrl)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty, .failure:
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()
            
            // Video overlay when playing
            if isPlaying, let player = player {
                VideoPlayerLayer(player: player)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipped()
                    .transition(.opacity)
            }
            
            // Live badge
            VStack {
                HStack {
                    LivePhotoBadge()
                    Spacer()
                }
                Spacer()
            }
            .padding(12)
            .opacity(isPlaying ? 0 : 1)
        }
        .frame(height: height)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.1, pressing: { pressing in
            if pressing {
                startPlaying()
            } else {
                stopPlaying()
            }
        }, perform: {})
        .onDisappear {
            stopPlaying()
        }
    }
    
    private func startPlaying() {
        guard !isPlaying, let url = URL(string: videoUrl) else { return }
        
        if player == nil {
            player = AVPlayer(url: url)
        }
        
        player?.seek(to: .zero)
        player?.play()
        
        withAnimation(.easeInOut(duration: 0.15)) {
            isPlaying = true
        }
        
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { _ in
            stopPlaying()
        }
    }
    
    private func stopPlaying() {
        player?.pause()
        withAnimation(.easeInOut(duration: 0.15)) {
            isPlaying = false
        }
    }
}

// MARK: - Preview

#Preview("Live Photo Badge") {
    ZStack {
        Color.gray
        LivePhotoBadge()
    }
    .frame(width: 200, height: 200)
}
