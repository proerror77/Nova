import SwiftUI
import AVKit

// MARK: - Video Constants

/// Video duration limits (similar to Instagram Reels)
enum VideoConstants {
    /// Maximum video duration for feed posts (60 seconds like IG)
    static let maxFeedVideoDuration: TimeInterval = 60
    
    /// Maximum video duration for stories (15 seconds)
    static let maxStoryVideoDuration: TimeInterval = 15
    
    /// Maximum video duration for reels (90 seconds)
    static let maxReelVideoDuration: TimeInterval = 90
}

// MARK: - Feed Video Player

/// Inline video player for feed posts
/// - Auto-plays when visible (muted by default)
/// - Shows play/pause overlay on tap
/// - Displays video duration badge
struct FeedVideoPlayer: View {
    let url: URL
    let thumbnailUrl: URL?
    let autoPlay: Bool
    let isMuted: Bool
    let height: CGFloat
    
    @StateObject private var viewModel: FeedVideoPlayerViewModel
    @State private var showControls = false
    @State private var controlsTimer: Timer?
    
    init(
        url: URL,
        thumbnailUrl: URL? = nil,
        autoPlay: Bool = true,
        isMuted: Bool = true,
        height: CGFloat = 500
    ) {
        self.url = url
        self.thumbnailUrl = thumbnailUrl
        self.autoPlay = autoPlay
        self.isMuted = isMuted
        self.height = height
        _viewModel = StateObject(wrappedValue: FeedVideoPlayerViewModel(url: url, autoPlay: autoPlay, isMuted: isMuted))
    }
    
    var body: some View {
        ZStack {
            // Video or Thumbnail
            if viewModel.isReady, let player = viewModel.player {
                VideoPlayerLayer(player: player)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipped()
            } else {
                // Show thumbnail while loading
                thumbnailView
            }
            
            // Loading indicator
            if viewModel.isLoading {
                ProgressView()
                    .tint(.white)
            }
            
            // Play/Pause overlay
            if showControls || !viewModel.isPlaying {
                playPauseOverlay
            }
            
            // Duration badge (top right)
            VStack {
                HStack {
                    Spacer()
                    durationBadge
                }
                Spacer()
            }
            .padding(12)
            
            // Mute indicator (bottom right)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    muteButton
                }
            }
            .padding(12)
            
            // Progress bar (bottom)
            VStack {
                Spacer()
                progressBar
            }
        }
        .frame(height: height)
        .background(Color.black)
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap()
        }
        .onAppear {
            viewModel.prepare()
        }
        .onDisappear {
            viewModel.pause()
        }
    }
    
    // MARK: - Subviews
    
    private var thumbnailView: some View {
        Group {
            if let thumbnailUrl = thumbnailUrl {
                AsyncImage(url: thumbnailUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure, .empty:
                        placeholderView
                    @unknown default:
                        placeholderView
                    }
                }
            } else {
                placeholderView
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
    }
    
    private var placeholderView: some View {
        Rectangle()
            .fill(Color(red: 0.1, green: 0.1, blue: 0.1))
            .overlay(
                Image(systemName: "video.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.white.opacity(0.3))
            )
    }
    
    private var playPauseOverlay: some View {
        Button {
            togglePlayPause()
        } label: {
            Circle()
                .fill(Color.black.opacity(0.5))
                .frame(width: 60, height: 60)
                .overlay(
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .offset(x: viewModel.isPlaying ? 0 : 2)
                )
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: showControls)
    }
    
    private var durationBadge: some View {
        Group {
            if viewModel.duration > 0 {
                Text(formatDuration(viewModel.duration - viewModel.currentTime))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(4)
            }
        }
    }
    
    private var muteButton: some View {
        Button {
            viewModel.toggleMute()
        } label: {
            Circle()
                .fill(Color.black.opacity(0.6))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                )
        }
    }
    
    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 3)
                
                // Progress
                Rectangle()
                    .fill(Color.white)
                    .frame(width: progressWidth(geometry: geometry), height: 3)
            }
        }
        .frame(height: 3)
    }
    
    // MARK: - Helpers
    
    private func progressWidth(geometry: GeometryProxy) -> CGFloat {
        guard viewModel.duration > 0 else { return 0 }
        let progress = viewModel.currentTime / viewModel.duration
        return geometry.size.width * CGFloat(progress)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    private func handleTap() {
        withAnimation {
            showControls = true
        }
        
        // Hide controls after 2 seconds
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            withAnimation {
                showControls = false
            }
        }
    }
    
    private func togglePlayPause() {
        if viewModel.isPlaying {
            viewModel.pause()
        } else {
            viewModel.play()
        }
    }
}

// MARK: - Feed Video Player ViewModel

@MainActor
final class FeedVideoPlayerViewModel: ObservableObject {
    let url: URL
    let autoPlay: Bool
    
    @Published private(set) var player: AVPlayer?
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = true
    @Published private(set) var isReady = false
    @Published private(set) var isMuted: Bool
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    
    init(url: URL, autoPlay: Bool = true, isMuted: Bool = true) {
        self.url = url
        self.autoPlay = autoPlay
        self.isMuted = isMuted
    }
    
    func prepare() {
        guard player == nil else { return }
        
        let playerItem = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: playerItem)
        avPlayer.isMuted = isMuted
        
        // Observe player status
        statusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    self?.isReady = true
                    self?.isLoading = false
                    self?.duration = CMTimeGetSeconds(item.duration)
                    if self?.autoPlay == true {
                        self?.play()
                    }
                case .failed:
                    self?.isLoading = false
                default:
                    break
                }
            }
        }
        
        // Add time observer
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = CMTimeGetSeconds(time)
            }
        }
        
        // Loop video
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.player?.seek(to: .zero)
                self?.player?.play()
            }
        }
        
        self.player = avPlayer
    }
    
    func play() {
        player?.play()
        isPlaying = true
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
    }
    
    func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
    }
    
    func cleanup() {
        pause()
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        statusObserver?.invalidate()
        player = nil
    }
    
}

// MARK: - Video Player Layer (UIViewRepresentable)

struct VideoPlayerLayer: UIViewRepresentable {
    let player: AVPlayer
    
    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.player = player
        return view
    }
    
    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.player = player
    }
}

final class PlayerUIView: UIView {
    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }
    
    private var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
    
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspectFill
        backgroundColor = .black
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            // Sample video
            FeedVideoPlayer(
                url: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4")!,
                autoPlay: true,
                isMuted: true
            )
            .cornerRadius(12)
            
            Text("Video Player Preview")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    .background(Color.gray.opacity(0.1))
}
