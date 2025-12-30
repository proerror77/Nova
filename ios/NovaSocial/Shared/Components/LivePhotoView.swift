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
    @State private var playbackObserver: NSObjectProtocol?

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

        // Remove any existing observer before adding new one
        if let observer = playbackObserver {
            NotificationCenter.default.removeObserver(observer)
            playbackObserver = nil
        }

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

        // Add observer for end of playback - store reference for cleanup
        playbackObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { [self] _ in
            stopPlaying()
        }
    }

    private func stopPlaying() {
        player?.pause()
        // Remove observer to prevent memory leak
        if let observer = playbackObserver {
            NotificationCenter.default.removeObserver(observer)
            playbackObserver = nil
        }
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
    @State private var playbackObserver: NSObjectProtocol?

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

        // Remove any existing observer before adding new one
        if let observer = playbackObserver {
            NotificationCenter.default.removeObserver(observer)
            playbackObserver = nil
        }

        if player == nil {
            player = AVPlayer(url: livePhotoData.videoURL)
        }

        player?.seek(to: .zero)
        player?.play()

        withAnimation(.easeInOut(duration: 0.15)) {
            isPlaying = true
        }

        // Store observer reference for cleanup
        playbackObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { [self] _ in
            stopPlaying()
        }
    }

    private func stopPlaying() {
        player?.pause()
        // Remove observer to prevent memory leak
        if let observer = playbackObserver {
            NotificationCenter.default.removeObserver(observer)
            playbackObserver = nil
        }
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
    @State private var playbackObserver: NSObjectProtocol?

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

        // Remove any existing observer before adding new one
        if let observer = playbackObserver {
            NotificationCenter.default.removeObserver(observer)
            playbackObserver = nil
        }

        if player == nil {
            player = AVPlayer(url: url)
        }

        player?.seek(to: .zero)
        player?.play()

        withAnimation(.easeInOut(duration: 0.15)) {
            isPlaying = true
        }

        // Store observer reference for cleanup
        playbackObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { [self] _ in
            stopPlaying()
        }
    }

    private func stopPlaying() {
        player?.pause()
        // Remove observer to prevent memory leak
        if let observer = playbackObserver {
            NotificationCenter.default.removeObserver(observer)
            playbackObserver = nil
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            isPlaying = false
        }
    }
}

// MARK: - Previews

#Preview("LivePhotoBadge - Default") {
    ZStack {
        Color.gray
        LivePhotoBadge()
    }
    .frame(width: 200, height: 200)
}

#Preview("LivePhotoBadge - Dark Mode") {
    ZStack {
        Color.gray
        LivePhotoBadge()
    }
    .frame(width: 200, height: 200)
    .preferredColorScheme(.dark)
}

// MARK: - Media Preview View

/// 全屏媒体预览视图 - 支持普通图片和 Live Photo
/// 可复用于 NewPost、Feed、Chat 等场景
struct MediaPreviewView: View {
    let mediaItem: PostMediaItem
    @Binding var isPresented: Bool
    var onDelete: (() -> Void)? = nil

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    // Live Photo 播放状态
    @State private var isPlayingLivePhoto = false
    @State private var player: AVPlayer?
    @State private var playbackObserver: NSObjectProtocol?

    var body: some View {
        ZStack {
            // 背景
            Color.black
                .ignoresSafeArea()
                .onTapGesture {
                    dismissPreview()
                }

            // 媒体内容
            GeometryReader { geometry in
                ZStack {
                    switch mediaItem {
                    case .image(let image, _):
                        imagePreview(image: image, geometry: geometry)

                    case .livePhoto(let data, _):
                        livePhotoPreview(data: data, geometry: geometry)

                    case .video(let data, _):
                        videoPreview(data: data, geometry: geometry)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // 顶部导航栏
            VStack {
                topBar
                Spacer()

                // 底部提示（Live Photo）
                if case .livePhoto = mediaItem {
                    bottomHint
                }
            }
        }
        .statusBar(hidden: true)
        .onDisappear {
            stopLivePhotoPlayback()
        }
    }

    // MARK: - Image Preview

    private func imagePreview(image: UIImage, geometry: GeometryProxy) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let delta = value / lastScale
                        lastScale = value
                        scale = min(max(scale * delta, 1), 4)
                    }
                    .onEnded { _ in
                        lastScale = 1.0
                        if scale < 1 {
                            withAnimation(.spring()) {
                                scale = 1
                                offset = .zero
                            }
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        if scale > 1 {
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        } else {
                            // 下滑关闭
                            if value.translation.height > 0 {
                                offset = CGSize(width: 0, height: value.translation.height)
                            }
                        }
                    }
                    .onEnded { value in
                        if scale > 1 {
                            lastOffset = offset
                        } else {
                            // 下滑超过 100 则关闭
                            if value.translation.height > 100 {
                                dismissPreview()
                            } else {
                                withAnimation(.spring()) {
                                    offset = .zero
                                }
                            }
                        }
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring()) {
                    if scale > 1 {
                        scale = 1
                        offset = .zero
                        lastOffset = .zero
                    } else {
                        scale = 2
                    }
                }
            }
    }

    // MARK: - Live Photo Preview

    private func livePhotoPreview(data: LivePhotoData, geometry: GeometryProxy) -> some View {
        ZStack {
            // 静态图片
            Image(uiImage: data.stillImage)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)

            // 视频播放层
            if isPlayingLivePhoto, let player = player {
                VideoPlayerLayer(player: player)
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
            }

            // Live Photo 徽章
            if !isPlayingLivePhoto {
                VStack {
                    HStack {
                        LivePhotoBadge()
                        Spacer()
                    }
                    Spacer()
                }
                .padding(16)
            }
        }
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    let delta = value / lastScale
                    lastScale = value
                    scale = min(max(scale * delta, 1), 4)
                }
                .onEnded { _ in
                    lastScale = 1.0
                    if scale < 1 {
                        withAnimation(.spring()) {
                            scale = 1
                            offset = .zero
                        }
                    }
                }
        )
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    if scale > 1 {
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    } else {
                        if value.translation.height > 0 {
                            offset = CGSize(width: 0, height: value.translation.height)
                        }
                    }
                }
                .onEnded { value in
                    if scale > 1 {
                        lastOffset = offset
                    } else {
                        if value.translation.height > 100 {
                            dismissPreview()
                        } else {
                            withAnimation(.spring()) {
                                offset = .zero
                            }
                        }
                    }
                }
        )
        .onLongPressGesture(minimumDuration: 0.1, pressing: { pressing in
            if pressing {
                startLivePhotoPlayback(data: data)
            } else {
                stopLivePhotoPlayback()
            }
        }, perform: {})
        .onTapGesture(count: 2) {
            withAnimation(.spring()) {
                if scale > 1 {
                    scale = 1
                    offset = .zero
                    lastOffset = .zero
                } else {
                    scale = 2
                }
            }
        }
    }

    // MARK: - Video Preview

    private func videoPreview(data: VideoData, geometry: GeometryProxy) -> some View {
        ZStack {
            // Video thumbnail as background
            Image(uiImage: data.thumbnail)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)

            // Video player
            if let player = player {
                VideoPlayerLayer(player: player)
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
            }

            // Play/Pause button overlay
            if !isPlayingLivePhoto {
                Button(action: {
                    if player == nil {
                        let videoPlayer = AVPlayer(url: data.url)
                        player = videoPlayer
                        videoPlayer.play()
                        isPlayingLivePhoto = true
                    }
                }) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.white.opacity(0.9))
                }
            }

            // Duration badge
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(formatVideoDuration(data.duration))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(4)
                }
                .padding(16)
            }
        }
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    let delta = value / lastScale
                    lastScale = value
                    scale = min(max(scale * delta, 1), 4)
                }
                .onEnded { _ in
                    lastScale = 1.0
                    if scale < 1 {
                        withAnimation(.spring()) {
                            scale = 1
                            offset = .zero
                        }
                    }
                }
        )
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    if scale > 1 {
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    } else {
                        if value.translation.height > 0 {
                            offset = CGSize(width: 0, height: value.translation.height)
                        }
                    }
                }
                .onEnded { value in
                    if scale > 1 {
                        lastOffset = offset
                    } else {
                        if value.translation.height > 100 {
                            dismissPreview()
                        } else {
                            withAnimation(.spring()) {
                                offset = .zero
                            }
                        }
                    }
                }
        )
        .onTapGesture {
            if isPlayingLivePhoto {
                player?.pause()
                isPlayingLivePhoto = false
            } else if player != nil {
                player?.play()
                isPlayingLivePhoto = true
            }
        }
        .onTapGesture(count: 2) {
            withAnimation(.spring()) {
                if scale > 1 {
                    scale = 1
                    offset = .zero
                    lastOffset = .zero
                } else {
                    scale = 2
                }
            }
        }
    }

    private func formatVideoDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // 关闭按钮
            Button(action: {
                dismissPreview()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }

            Spacer()

            // 删除按钮（如果提供了回调）
            if let onDelete = onDelete {
                Button(action: {
                    onDelete()
                    dismissPreview()
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.red.opacity(0.8))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Bottom Hint

    private var bottomHint: some View {
        HStack {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 14))
            Text("Long press to play Live Photo")
                .font(.system(size: 14))
        }
        .foregroundColor(.white.opacity(0.8))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.5))
        .cornerRadius(20)
        .padding(.bottom, 40)
    }

    // MARK: - Live Photo Playback

    private func startLivePhotoPlayback(data: LivePhotoData) {
        guard !isPlayingLivePhoto else { return }

        // Remove any existing observer before adding new one
        if let observer = playbackObserver {
            NotificationCenter.default.removeObserver(observer)
            playbackObserver = nil
        }

        if player == nil {
            player = AVPlayer(url: data.videoURL)
        }

        player?.seek(to: .zero)
        player?.play()

        withAnimation(.easeInOut(duration: 0.15)) {
            isPlayingLivePhoto = true
        }

        // Store observer reference for cleanup
        playbackObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { [self] _ in
            stopLivePhotoPlayback()
        }
    }

    private func stopLivePhotoPlayback() {
        player?.pause()
        // Remove observer to prevent memory leak
        if let observer = playbackObserver {
            NotificationCenter.default.removeObserver(observer)
            playbackObserver = nil
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            isPlayingLivePhoto = false
        }
    }

    // MARK: - Dismiss

    private func dismissPreview() {
        stopLivePhotoPlayback()
        withAnimation(.easeOut(duration: 0.2)) {
            isPresented = false
        }
    }
}

// MARK: - Media Preview Previews

#Preview("MediaPreview - Image") {
    MediaPreviewView(
        mediaItem: .image(UIImage(systemName: "photo")!, .empty),
        isPresented: .constant(true)
    )
}

#Preview("MediaPreview - With Delete") {
    MediaPreviewView(
        mediaItem: .image(UIImage(systemName: "photo")!, .empty),
        isPresented: .constant(true),
        onDelete: {
            print("Delete tapped")
        }
    )
}
