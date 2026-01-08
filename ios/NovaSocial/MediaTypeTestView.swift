import SwiftUI
import PhotosUI

/// 快速测试视图 - 验证系统是否正确识别 Live Photo、静态照片和视频
/// ⚠️ 注意：生产环境中应该分开选择照片和视频
struct MediaTypeTestView: View {
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var detectedTypes: [String] = []
    @State private var isProcessing = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 标题说明
                VStack(spacing: 8) {
                    Text("媒体类型识别测试")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("从相册选择照片/视频，系统会自动识别类型")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)

                    Text("⚠️ 仅用于测试，生产环境应分开选择")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .padding(.top, 4)
                }
                .padding(.top, 20)

                // 选择按钮
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 10,
                    matching: .any(of: [.images, .livePhotos, .videos])
                ) {
                    HStack {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text("从相册选择媒体（测试用）")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                .onChange(of: selectedItems) { items in
                    processSelectedItems(items)
                }

                // 处理状态
                if isProcessing {
                    ProgressView("正在识别...")
                        .padding()
                }

                // 识别结果
                if !detectedTypes.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("识别结果 (\(detectedTypes.count) 项)")
                            .font(.headline)
                            .padding(.horizontal)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(detectedTypes.enumerated()), id: \.offset) { index, type in
                                    HStack {
                                        // 类型图标
                                        iconForType(type)
                                            .font(.system(size: 24))

                                        VStack(alignment: .leading) {
                                            Text("媒体 \(index + 1)")
                                                .font(.caption)
                                                .foregroundColor(.gray)

                                            Text(type)
                                                .font(.body)
                                                .fontWeight(.medium)
                                        }

                                        Spacer()

                                        // 状态标记
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                    .padding()
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                } else if !isProcessing && selectedItems.isEmpty {
                    // 空状态
                    VStack(spacing: 12) {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)

                        Text("还没有选择任何媒体")
                            .font(.headline)
                            .foregroundColor(.gray)

                        Text("点击上方按钮从相册选择")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .frame(maxHeight: .infinity)
                }

                Spacer()

                // 说明卡片
                VStack(alignment: .leading, spacing: 8) {
                    Text("支持的类型：")
                        .font(.caption)
                        .fontWeight(.semibold)

                    HStack(spacing: 16) {
                        typeExplanation(icon: "livephoto", label: "Live Photo", color: .blue)
                        typeExplanation(icon: "photo", label: "静态照片", color: .green)
                        typeExplanation(icon: "video.fill", label: "视频", color: .orange)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - 处理选中的媒体

    private func processSelectedItems(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else {
            detectedTypes = []
            return
        }

        isProcessing = true
        detectedTypes = []

        Task {
            let livePhotoManager = LivePhotoManager.shared

            do {
                // 并行加载所有选中的媒体
                let mediaItems = try await livePhotoManager.loadMedia(
                    from: items,
                    maxCount: 10
                )

                // 提取类型信息
                let types = mediaItems.map { item -> String in
                    switch item {
                    case .livePhoto(_, let metadata):
                        var info = "📸 Live Photo (实况照片)"
                        if let location = metadata.locationName {
                            info += "\n📍 \(location)"
                        }
                        if let date = metadata.formattedDate {
                            info += "\n📅 \(date)"
                        }
                        return info

                    case .image(_, let metadata):
                        var info = "🖼️ Static Photo (静态照片)"
                        if let location = metadata.locationName {
                            info += "\n📍 \(location)"
                        }
                        if let date = metadata.formattedDate {
                            info += "\n📅 \(date)"
                        }
                        return info

                    case .video(let videoData, let metadata):
                        var info = "🎥 Video (视频)"
                        info += "\n⏱️ 时长: \(formatDuration(videoData.duration))"
                        if let location = metadata.locationName {
                            info += "\n📍 \(location)"
                        }
                        return info
                    }
                }

                await MainActor.run {
                    detectedTypes = types
                    isProcessing = false
                }

                #if DEBUG
                print("[MediaTypeTest] Successfully loaded \(mediaItems.count) items")
                for (index, item) in mediaItems.enumerated() {
                    print("  [\(index + 1)] \(types[index])")
                }
                #endif

            } catch {
                await MainActor.run {
                    isProcessing = false
                    detectedTypes = ["❌ 加载失败: \(error.localizedDescription)"]
                }

                #if DEBUG
                print("[MediaTypeTest] Failed to load media: \(error)")
                #endif
            }
        }
    }

    // MARK: - 辅助方法

    @ViewBuilder
    private func iconForType(_ type: String) -> some View {
        if type.contains("Live Photo") {
            Image(systemName: "livephoto")
                .foregroundColor(.blue)
        } else if type.contains("Static Photo") {
            Image(systemName: "photo")
                .foregroundColor(.green)
        } else if type.contains("Video") {
            Image(systemName: "video.fill")
                .foregroundColor(.orange)
        } else {
            Image(systemName: "questionmark.circle")
                .foregroundColor(.gray)
        }
    }

    @ViewBuilder
    private func typeExplanation(icon: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Preview

#Preview {
    MediaTypeTestView()
}

// MARK: - 如何在你的 App 中测试

/*

 使用方法：

 1. 在 Xcode 中将此文件添加到项目
 2. 在任意地方添加导航按钮：

 ```swift
 NavigationLink("测试媒体类型") {
     MediaTypeTestView()
 }
 ```

 3. 运行 App，点击按钮
 4. 从相册选择不同类型的媒体
 5. 查看识别结果

 预期结果：
 ✅ Live Photo → 显示 "📸 Live Photo (实况照片)"
 ✅ 静态照片 → 显示 "🖼️ Static Photo (静态照片)"
 ✅ 视频 → 显示 "🎥 Video (视频)" + 时长

 ✅ 如果照片有位置信息 → 显示地点
 ✅ 如果照片有拍摄时间 → 显示日期

 */
