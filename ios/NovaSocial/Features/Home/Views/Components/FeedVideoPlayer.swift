import SwiftUI
import AVKit
import Network

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
    @State private var userPaused = false  // Track if user manually paused
    
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
            
            // Play/Pause overlay - only show when user manually paused
            if userPaused {
                playPauseOverlay
            }
            

            
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
        GeometryReader { geometry in
            Group {
                if let thumbnailUrl = thumbnailUrl {
                    // 使用 CachedAsyncImage 替代 AsyncImage 以获得缓存和更快加载
                    CachedAsyncImage(
                        url: thumbnailUrl,
                        targetSize: CGSize(width: geometry.size.width * 2, height: height * 2),
                        enableProgressiveLoading: true,
                        priority: .high
                    ) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        placeholderView
                    }
                } else {
                    placeholderView
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()
        }
    }
    
    private var placeholderView: some View {
        Rectangle()
            .fill(Color(red: 0.1, green: 0.1, blue: 0.1))
            .overlay(
                Image(systemName: "video.fill")
                    .font(.system(size: 40.f))
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
                    Image(systemName: "play.fill")
                        .font(.system(size: 24.f))
                        .foregroundColor(.white)
                        .offset(x: 2)
                )
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: userPaused)
    }
    
    private var durationBadge: some View {
        Group {
            if viewModel.duration > 0 {
                Text(formatDuration(viewModel.duration - viewModel.currentTime))
                    .font(Font.custom("SFProDisplay-Medium", size: 12.f))
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
                        .font(Font.custom("SFProDisplay-Regular", size: 14.f))
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
            togglePlayPause()
        }
    }
    
    private func togglePlayPause() {
        if viewModel.isPlaying {
            viewModel.pause()
            userPaused = true
        } else {
            viewModel.play()
            userPaused = false
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
    @Published private(set) var isCached = false

    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var prefetchTask: Task<Void, Never>?
    private var loopObserver: NSObjectProtocol?  // NotificationCenter observer for video loop

    // Network monitoring for prefetch priority (nonisolated for cross-actor access)
    nonisolated(unsafe) private static let networkMonitor = NWPathMonitor()
    nonisolated(unsafe) private static let networkQueue = DispatchQueue(label: "com.icered.networkMonitor")
    nonisolated(unsafe) private static var _isOnWiFi: Bool = true
    nonisolated(unsafe) private static var networkMonitorStarted = false

    /// Thread-safe access to WiFi status (used for prefetch priority optimization)
    nonisolated static var isOnWiFi: Bool { _isOnWiFi }

    init(url: URL, autoPlay: Bool = true, isMuted: Bool = true) {
        self.url = url
        self.autoPlay = autoPlay
        self.isMuted = isMuted

        // Start network monitoring once
        Self.startNetworkMonitoringIfNeeded()
    }

    nonisolated private static func startNetworkMonitoringIfNeeded() {
        guard !Self.networkMonitorStarted else { return }
        Self.networkMonitorStarted = true

        Self.networkMonitor.pathUpdateHandler = { path in
            // Check if using WiFi (not cellular)
            Self._isOnWiFi = !path.usesInterfaceType(.cellular)
        }
        Self.networkMonitor.start(queue: Self.networkQueue)
    }

    func prepare() {
        guard player == nil else { return }

        // Check video cache first for faster loading
        Task {
            let videoURL = await getVideoURL()
            await setupPlayer(with: videoURL)
        }
    }

    private func getVideoURL() async -> URL {
        let urlString = url.absoluteString

        // Check if video is cached
        if let cachedURL = await VideoCacheService.shared.getCachedVideoURL(for: urlString) {
            isCached = true
            return cachedURL
        }

        // OPTIMIZATION: Delayed prefetch with network-aware priority
        // Delay prefetch by 0.5 seconds to avoid wasted bandwidth if user scrolls past
        prefetchTask = Task.detached(priority: .utility) { [urlString] in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay

            // Check if task was cancelled (user scrolled away)
            guard !Task.isCancelled else { return }

            // Use lower priority on cellular to save bandwidth/battery
            let priority: VideoLoadPriority = FeedVideoPlayerViewModel.isOnWiFi ? .high : .low
            await VideoCacheService.shared.prefetchVideo(urlString: urlString, priority: priority)
        }

        // Return remote URL for now (AVPlayer will stream it)
        return url
    }
    
    private func setupPlayer(with videoURL: URL) async {
        let playerItem = AVPlayerItem(url: videoURL)
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
        
        // Loop video - store observer reference for cleanup
        loopObserver = NotificationCenter.default.addObserver(
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
        prefetchTask?.cancel()
        prefetchTask = nil
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        timeObserver = nil
        statusObserver?.invalidate()
        statusObserver = nil
        // Remove NotificationCenter observer to prevent memory leak
        if let loopObserver = loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
        }
        loopObserver = nil
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

// MARK: - Previews

#Preview("FeedVideoPlayer - Default") {
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

#Preview("FeedVideoPlayer - Dark Mode") {
    ScrollView {
        VStack(spacing: 20) {
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
    .preferredColorScheme(.dark)
}
