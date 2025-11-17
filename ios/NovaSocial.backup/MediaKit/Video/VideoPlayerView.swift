import SwiftUI
import AVKit

/// 视频播放器 - 基础版本，支持播放控制
///
/// Linus 风格：简单够用，不过度设计
/// - 播放/暂停
/// - 进度条
/// - 音量控制
/// - 全屏支持
struct VideoPlayerView: View {
    let url: URL
    let autoPlay: Bool

    @StateObject private var playerViewModel: VideoPlayerViewModel

    init(url: URL, autoPlay: Bool = false) {
        self.url = url
        self.autoPlay = autoPlay
        _playerViewModel = StateObject(wrappedValue: VideoPlayerViewModel(url: url, autoPlay: autoPlay))
    }

    var body: some View {
        ZStack {
            // 视频播放层
            VideoPlayer(player: playerViewModel.player)
                .onAppear {
                    playerViewModel.prepare()
                }
                .onDisappear {
                    playerViewModel.cleanup()
                }

            // 自定义控制层（可选）
            if !playerViewModel.isPlaying {
                PlayButton {
                    playerViewModel.play()
                }
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
    }
}

// MARK: - Video Player ViewModel

@MainActor
final class VideoPlayerViewModel: ObservableObject {
    let url: URL
    let autoPlay: Bool

    @Published private(set) var player: AVPlayer?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0

    private var timeObserver: Any?

    init(url: URL, autoPlay: Bool = false) {
        self.url = url
        self.autoPlay = autoPlay
    }

    func prepare() {
        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)

        // 添加时间观察者
        addPeriodicTimeObserver()

        // 监听播放完成
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )

        if autoPlay {
            play()
        }
    }

    func play() {
        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime)
    }

    func cleanup() {
        pause()
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        player = nil
    }

    // MARK: - Private Helpers

    private func addPeriodicTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            self?.currentTime = CMTimeGetSeconds(time)
            if let duration = self?.player?.currentItem?.duration {
                self?.duration = CMTimeGetSeconds(duration)
            }
        }
    }

    @objc private func playerDidFinishPlaying() {
        isPlaying = false
        seek(to: 0)  // 重置到开始
    }

    deinit {
        cleanup()
    }
}

// MARK: - Play Button

struct PlayButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.white)
                .shadow(radius: 10)
        }
    }
}

// MARK: - Custom Video Player (with controls)

struct CustomVideoPlayerView: View {
    let url: URL

    @StateObject private var viewModel: VideoPlayerViewModel
    @State private var showControls = true

    init(url: URL, autoPlay: Bool = false) {
        self.url = url
        _viewModel = StateObject(wrappedValue: VideoPlayerViewModel(url: url, autoPlay: autoPlay))
    }

    var body: some View {
        ZStack {
            Color.black

            // 视频层
            if let player = viewModel.player {
                VideoPlayerLayer(player: player)
            }

            // 控制层
            if showControls {
                VStack {
                    Spacer()
                    controlsOverlay
                }
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
        .onTapGesture {
            withAnimation {
                showControls.toggle()
            }
        }
        .onAppear {
            viewModel.prepare()
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }

    // MARK: - Controls Overlay

    private var controlsOverlay: some View {
        VStack(spacing: 12) {
            // 进度条
            Slider(
                value: Binding(
                    get: { viewModel.currentTime },
                    set: { viewModel.seek(to: $0) }
                ),
                in: 0...max(viewModel.duration, 1)
            )
            .accentColor(.white)

            HStack {
                // 播放/暂停按钮
                Button {
                    if viewModel.isPlaying {
                        viewModel.pause()
                    } else {
                        viewModel.play()
                    }
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                        .foregroundColor(.white)
                }

                // 时间显示
                Text("\(formatTime(viewModel.currentTime)) / \(formatTime(viewModel.duration))")
                    .font(.caption)
                    .foregroundColor(.white)

                Spacer()
            }
        }
        .padding()
        .background(
            LinearGradient(
                gradient: Gradient(colors: [.clear, .black.opacity(0.7)]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Video Player Layer

struct VideoPlayerLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        view.layer.addSublayer(playerLayer)
        context.coordinator.playerLayer = playerLayer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.playerLayer?.frame = uiView.bounds
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var playerLayer: AVPlayerLayer?
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // 简单播放器
        VideoPlayerView(
            url: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!,
            autoPlay: false
        )

        // 自定义控制播放器
        CustomVideoPlayerView(
            url: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!,
            autoPlay: false
        )
    }
    .padding()
}
