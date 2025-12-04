import SwiftUI

/// MediaKit 使用示例
///
/// 展示如何在实际场景中使用 MediaKit

// MARK: - Example 1: Image Loading

struct ImageLoadingExample: View {
    let imageURL = "https://picsum.photos/400/400"

    var body: some View {
        VStack(spacing: 20) {
            Text("Image Loading Examples")
                .font(.headline)

            // 1. 基础加载
            KFImageView(url: imageURL)
                .frame(width: 200, height: 200)
                .cornerRadius(12)

            // 2. 带处理器
            KFImageView(url: imageURL)
                .roundedCorners(20)
                .frame(width: 200, height: 200)

            // 3. 自定义占位符
            KFImageView(
                url: imageURL,
                placeholder: Image(systemName: "person.circle")
            )
            .frame(width: 200, height: 200)
            .cornerRadius(100)
        }
        .padding()
    }
}

// MARK: - Example 2: Image Upload

struct ImageUploadExample: View {
    @StateObject private var viewModel = UploadExampleViewModel()
    @State private var selectedImages: [UIImage] = []
    @State private var showPicker = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Image Upload Example")
                .font(.headline)

            // 选择的图片
            if selectedImages.isEmpty {
                Text("No images selected")
                    .foregroundColor(.secondary)
            } else {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(Array(selectedImages.enumerated()), id: \.offset) { _, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .cornerRadius(8)
                        }
                    }
                }
            }

            // 选择按钮
            Button("Select Images") {
                showPicker = true
            }
            .buttonStyle(.borderedProminent)

            // 上传按钮
            if !selectedImages.isEmpty {
                Button("Upload Images") {
                    Task {
                        await viewModel.uploadImages(selectedImages)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isUploading)
            }

            // 上传进度
            if viewModel.isUploading {
                VStack {
                    ProgressView(value: viewModel.uploadProgress)
                    Text("Uploading... \(Int(viewModel.uploadProgress * 100))%")
                        .font(.caption)
                }
            }

            // 上传队列
            if !viewModel.uploadQueue.isEmpty {
                List(viewModel.uploadQueue) { task in
                    HStack {
                        Image(uiImage: task.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 50, height: 50)
                            .cornerRadius(4)

                        VStack(alignment: .leading) {
                            Text(task.state.description)
                                .font(.caption)

                            if task.state == .uploading {
                                ProgressView(value: task.progress)
                            }
                        }

                        Spacer()

                        if task.state == .uploading {
                            Button("Pause") {
                                ImageUploadManager.shared.pauseUpload(taskId: task.id)
                            }
                            .font(.caption)
                        }
                    }
                }
                .frame(height: 200)
            }
        }
        .padding()
        .imagePicker(
            isPresented: $showPicker,
            selectedImages: $selectedImages,
            maxSelection: 5
        )
    }
}

@MainActor
class UploadExampleViewModel: ObservableObject {
    @Published var isUploading = false
    @Published var uploadProgress: Double = 0
    @Published var uploadQueue: [UploadTask] = []

    private let uploadManager = ImageUploadManager.shared

    func uploadImages(_ images: [UIImage]) async {
        isUploading = true

        for image in images {
            // 实际项目中，需要先从后端获取上传 URL
            let mockURL = URL(string: "https://example.com/upload")!
            uploadManager.uploadImage(image, to: mockURL)
        }

        // 观察上传队列
        uploadQueue = uploadManager.uploadQueue

        isUploading = false
    }
}

// MARK: - Example 3: Image Viewer

struct ImageViewerExample: View {
    let sampleImages = [
        "https://picsum.photos/400/600",
        "https://picsum.photos/600/400",
        "https://picsum.photos/500/500"
    ]

    @State private var showViewer = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Image Viewer Example")
                .font(.headline)

            // 缩略图网格
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                ForEach(Array(sampleImages.enumerated()), id: \.offset) { index, url in
                    KFImageView(url: url)
                        .frame(width: 100, height: 100)
                        .cornerRadius(8)
                        .onTapGesture {
                            showViewer = true
                        }
                }
            }
        }
        .padding()
        .fullScreenCover(isPresented: $showViewer) {
            ImageViewerView(images: sampleImages, initialIndex: 0)
        }
    }
}

// MARK: - Example 4: Video Player

struct VideoPlayerExample: View {
    let videoURL = URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!

    @State private var videoInfo: VideoInfo?

    var body: some View {
        VStack(spacing: 20) {
            Text("Video Player Example")
                .font(.headline)

            // 视频播放器
            CustomVideoPlayerView(url: videoURL)
                .frame(height: 250)
                .cornerRadius(12)

            // 视频信息
            if let info = videoInfo {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Video Information")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    HStack {
                        Text("Duration:")
                        Spacer()
                        Text(info.durationFormatted)
                    }

                    HStack {
                        Text("Size:")
                        Spacer()
                        Text("\(Int(info.size.width))x\(Int(info.size.height))")
                    }

                    HStack {
                        Text("File Size:")
                        Spacer()
                        Text(info.fileSizeFormatted)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }

            Button("Get Video Info") {
                Task {
                    videoInfo = try? await VideoManager.shared.getVideoInfo(from: videoURL)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

// MARK: - Example 5: Performance Monitoring

struct PerformanceMonitoringExample: View {
    @StateObject private var metrics = MediaMetrics.shared

    var body: some View {
        NavigationView {
            List {
                Section("Quick Stats") {
                    StatRow(
                        title: "Cache Hit Rate",
                        value: String(format: "%.1f%%", metrics.cacheMetrics.hitRate * 100),
                        color: metrics.cacheMetrics.hitRate > 0.7 ? .green : .orange
                    )

                    StatRow(
                        title: "Avg Load Time",
                        value: String(format: "%.0fms", metrics.imageLoadMetrics.averageLoadTime * 1000)
                    )

                    StatRow(
                        title: "Network Traffic",
                        value: String(format: "%.2f MB", metrics.networkMetrics.downloadedMB)
                    )
                }

                Section {
                    NavigationLink("Full Performance Report") {
                        MediaPerformanceDebugView()
                    }
                }
            }
            .navigationTitle("Performance")
        }
    }
}

struct StatRow: View {
    let title: String
    let value: String
    var color: Color = .primary

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(color)
                .bold()
        }
    }
}

// MARK: - Main Examples View

struct MediaKitExamplesView: View {
    var body: some View {
        NavigationView {
            List {
                NavigationLink("Image Loading") {
                    ImageLoadingExample()
                }

                NavigationLink("Image Upload") {
                    ImageUploadExample()
                }

                NavigationLink("Image Viewer") {
                    ImageViewerExample()
                }

                NavigationLink("Video Player") {
                    VideoPlayerExample()
                }

                NavigationLink("Performance Monitoring") {
                    PerformanceMonitoringExample()
                }
            }
            .navigationTitle("MediaKit Examples")
        }
    }
}

// MARK: - Extension for UploadTask.State

extension UploadTask.State {
    var description: String {
        switch self {
        case .pending: return "Pending"
        case .uploading: return "Uploading"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }
}

// MARK: - Preview

#Preview {
    MediaKitExamplesView()
}
