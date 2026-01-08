import SwiftUI
import PhotosUI

// MARK: - 正确的实现：照片和视频分开选择

/// 推荐方案：提供两个独立的选择器
/// - 照片选择器：支持静态照片 + Live Photo
/// - 视频选择器：仅支持视频
struct SeparateMediaPickerExample: View {
    // 照片（包括 Live Photo）
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var photoMediaItems: [PostMediaItem] = []

    // 视频（独立）
    @State private var selectedVideoItems: [PhotosPickerItem] = []
    @State private var videoMediaItems: [PostMediaItem] = []

    @StateObject private var livePhotoManager = LivePhotoManager.shared

    // 当前选择的媒体类型
    @State private var currentMediaType: MediaSelectionType = .none

    enum MediaSelectionType {
        case none
        case photos  // 照片 + Live Photo
        case video   // 视频
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 标题
                Text("创建帖子")
                    .font(.title2)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                // 选择按钮区域
                VStack(spacing: 12) {
                    // 📸 照片选择器（包括 Live Photo）
                    PhotosPicker(
                        selection: $selectedPhotoItems,
                        maxSelectionCount: 5,
                        matching: .any(of: [.images, .livePhotos])  // ← 只选照片和 Live Photo
                    ) {
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text("添加照片")
                            Spacer()
                            if !photoMediaItems.isEmpty {
                                Text("\(photoMediaItems.count)")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue)
                                    .cornerRadius(12)
                            }
                        }
                        .font(.headline)
                        .foregroundColor(currentMediaType == .video ? .gray : .blue)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .disabled(currentMediaType == .video)  // 如果选了视频，禁用照片选择
                    .onChange(of: selectedPhotoItems) { items in
                        loadPhotos(items)
                    }

                    // 🎥 视频选择器（独立）
                    PhotosPicker(
                        selection: $selectedVideoItems,
                        maxSelectionCount: 1,  // 通常视频只选一个
                        matching: .videos  // ← 只选视频
                    ) {
                        HStack {
                            Image(systemName: "video.fill")
                            Text("添加视频")
                            Spacer()
                            if !videoMediaItems.isEmpty {
                                Text("1")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange)
                                    .cornerRadius(12)
                            }
                        }
                        .font(.headline)
                        .foregroundColor(currentMediaType == .photos ? .gray : .orange)
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .disabled(currentMediaType == .photos)  // 如果选了照片，禁用视频选择
                    .onChange(of: selectedVideoItems) { items in
                        loadVideos(items)
                    }
                }
                .padding(.horizontal)

                // 提示信息
                if currentMediaType != .none {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text(currentMediaType == .photos
                             ? "已选择照片模式，无法添加视频"
                             : "已选择视频模式，无法添加照片")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal)
                }

                // 显示选中的照片
                if !photoMediaItems.isEmpty {
                    photoPreviewSection
                }

                // 显示选中的视频
                if !videoMediaItems.isEmpty {
                    videoPreviewSection
                }

                Spacer(minLength: 40)
            }
            .padding(.top)
        }
    }

    // MARK: - 照片预览区

    private var photoPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("照片 (\(photoMediaItems.count))")
                    .font(.headline)
                Spacer()
                Button("清空") {
                    clearPhotos()
                }
                .font(.caption)
                .foregroundColor(.red)
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(photoMediaItems) { item in
                        photoPreviewCard(item)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    @ViewBuilder
    private func photoPreviewCard(_ item: PostMediaItem) -> some View {
        ZStack(alignment: .topTrailing) {
            switch item {
            case .livePhoto(let data, let metadata):
                VStack {
                    LivePhotoPreviewCard(
                        livePhotoData: data,
                        onDelete: {
                            removePhoto(item)
                        }
                    )

                    // 元数据显示
                    if let location = metadata.locationName {
                        Text("📍 \(location)")
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }

            case .image(let image, let metadata):
                VStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 239, height: 290)
                        .clipped()
                        .cornerRadius(10)
                        .overlay(alignment: .topTrailing) {
                            deleteButton {
                                removePhoto(item)
                            }
                        }

                    if let location = metadata.locationName {
                        Text("📍 \(location)")
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }

            case .video:
                EmptyView()  // 不应该出现在这里
            }
        }
    }

    // MARK: - 视频预览区

    private var videoPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("视频")
                    .font(.headline)
                Spacer()
                Button("清空") {
                    clearVideos()
                }
                .font(.caption)
                .foregroundColor(.red)
            }
            .padding(.horizontal)

            ForEach(videoMediaItems) { item in
                if case .video(let data, let metadata) = item {
                    VStack(alignment: .leading) {
                        ZStack {
                            // 视频缩略图
                            Image(uiImage: data.thumbnail)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 300)
                                .clipped()
                                .cornerRadius(12)

                            // 播放按钮
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 64))
                                .foregroundColor(.white)
                                .shadow(radius: 4)

                            // 时长标签
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Text(formatDuration(data.duration))
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.black.opacity(0.7))
                                        .cornerRadius(6)
                                        .padding(8)
                                }
                            }

                            // 删除按钮
                            VStack {
                                HStack {
                                    Spacer()
                                    deleteButton {
                                        removeVideo(item)
                                    }
                                }
                                Spacer()
                            }
                        }

                        if let location = metadata.locationName {
                            Text("📍 \(location)")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    // MARK: - 辅助视图

    @ViewBuilder
    private func deleteButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(.white)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: 24, height: 24)
                )
        }
        .padding(8)
    }

    // MARK: - 加载逻辑

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else {
            photoMediaItems = []
            updateMediaType()
            return
        }

        Task {
            do {
                let mediaItems = try await livePhotoManager.loadMedia(
                    from: items,
                    maxCount: 5
                )

                // ⚠️ 过滤掉视频（理论上不会出现，但保险起见）
                let filteredItems = mediaItems.filter { item in
                    if case .video = item {
                        return false
                    }
                    return true
                }

                photoMediaItems = filteredItems
                updateMediaType()

                #if DEBUG
                print("[SeparateMediaPicker] Loaded \(filteredItems.count) photos")
                #endif
            } catch {
                print("Failed to load photos: \(error)")
            }
        }
    }

    private func loadVideos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else {
            videoMediaItems = []
            updateMediaType()
            return
        }

        Task {
            do {
                let mediaItems = try await livePhotoManager.loadMedia(
                    from: items,
                    maxCount: 1
                )

                // ⚠️ 只保留视频
                let filteredItems = mediaItems.filter { item in
                    if case .video = item {
                        return true
                    }
                    return false
                }

                videoMediaItems = filteredItems
                updateMediaType()

                #if DEBUG
                print("[SeparateMediaPicker] Loaded \(filteredItems.count) videos")
                #endif
            } catch {
                print("Failed to load videos: \(error)")
            }
        }
    }

    // MARK: - 删除和清空

    private func removePhoto(_ item: PostMediaItem) {
        photoMediaItems.removeAll { $0.id == item.id }
        if photoMediaItems.isEmpty {
            selectedPhotoItems = []
        }
        updateMediaType()
    }

    private func removeVideo(_ item: PostMediaItem) {
        videoMediaItems.removeAll { $0.id == item.id }
        if videoMediaItems.isEmpty {
            selectedVideoItems = []
        }
        updateMediaType()
    }

    private func clearPhotos() {
        photoMediaItems = []
        selectedPhotoItems = []
        updateMediaType()
    }

    private func clearVideos() {
        videoMediaItems = []
        selectedVideoItems = []
        updateMediaType()
    }

    private func updateMediaType() {
        if !photoMediaItems.isEmpty {
            currentMediaType = .photos
        } else if !videoMediaItems.isEmpty {
            currentMediaType = .video
        } else {
            currentMediaType = .none
        }
    }

    // MARK: - 工具方法

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - 方式 2: 单选择器 + 自动过滤

/// 备选方案：单个选择器，但自动过滤不兼容的类型
struct AutoFilterMediaPickerExample: View {
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var mediaItems: [PostMediaItem] = []
    @StateObject private var livePhotoManager = LivePhotoManager.shared

    @State private var showAlert = false
    @State private var alertMessage = ""

    var body: some View {
        VStack(spacing: 20) {
            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: 5,
                matching: .any(of: [.images, .livePhotos, .videos])
            ) {
                Text("选择媒体")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .onChange(of: selectedItems) { items in
                loadAndFilterMedia(items)
            }

            if !mediaItems.isEmpty {
                Text("已选择 \(mediaItems.count) 项")
                    .font(.headline)
            }
        }
        .padding()
        .alert("提示", isPresented: $showAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private func loadAndFilterMedia(_ items: [PhotosPickerItem]) {
        Task {
            do {
                let loadedItems = try await livePhotoManager.loadMedia(
                    from: items,
                    maxCount: 5
                )

                // 检测类型
                let hasPhotos = loadedItems.contains { item in
                    if case .image = item { return true }
                    if case .livePhoto = item { return true }
                    return false
                }

                let hasVideos = loadedItems.contains { item in
                    if case .video = item { return true }
                    return false
                }

                // 如果同时有照片和视频，只保留第一个类型
                if hasPhotos && hasVideos {
                    let firstItem = loadedItems.first!
                    if case .video = firstItem {
                        // 保留视频，移除照片
                        mediaItems = loadedItems.filter { item in
                            if case .video = item { return true }
                            return false
                        }
                        alertMessage = "已自动移除照片，只保留视频"
                    } else {
                        // 保留照片，移除视频
                        mediaItems = loadedItems.filter { item in
                            if case .video = item { return false }
                            return true
                        }
                        alertMessage = "已自动移除视频，只保留照片"
                    }
                    showAlert = true
                } else {
                    mediaItems = loadedItems
                }
            } catch {
                print("Failed to load media: \(error)")
            }
        }
    }
}

// MARK: - Preview

#Preview("分离选择器（推荐）") {
    SeparateMediaPickerExample()
}

#Preview("自动过滤") {
    AutoFilterMediaPickerExample()
}
